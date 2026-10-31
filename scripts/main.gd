extends Node3D

const State = preload("res://scripts/game_state.gd")
const Player = preload("res://scripts/player.gd")
const Interface = preload("res://scripts/interface.gd")
var state = State.new()
var player: CharacterBody3D
var camera: Camera3D
var ui: Control
var sites: Array[Dictionary] = []
var animated: Array[Node3D] = []
var world: Node3D
var clock: float = 0.0
var nearest: String = ""
var camera_angle: float = 0.0
var font: SystemFont
var backdrop: Environment
var photo_mode: bool = false

func _ready() -> void:
	font = SystemFont.new()
	# 网页没有系统中文字体，回退到随包的 Noto Sans SC（OFL）。
	font.fallbacks = [preload("res://assets/fonts/NotoSansSC-Regular.otf")]
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])
	_setup_inputs()
	if not "--preview" in OS.get_cmdline_user_args():
		state.load_game()
	_build_world()
	_build_player()
	var layer = CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_script(Interface)
	ui.game = self
	layer.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_handle_capture.call_deferred()

func _setup_inputs() -> void:
	var bindings = {"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN], "move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT], "sprint": [KEY_SHIFT], "interact": [KEY_E]}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in bindings[action]:
			var event = InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)

func _material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.88
	mat.metallic_specular = 0.12
	if glow:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.45
	return mat

func shape(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material(color)
	node.position = pos
	parent.add_child(node)
	return node

func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh = BoxMesh.new()
	mesh.size = size
	return shape(parent, mesh, pos, color)

func cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color, top: float = -1, sides: int = 32) -> MeshInstance3D:
	var mesh = CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top < 0 else top
	mesh.height = height
	mesh.radial_segments = sides
	return shape(parent, mesh, pos, color)

func sphere(parent: Node3D, pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var mesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	mesh.radial_segments = 12
	mesh.rings = 6
	return shape(parent, mesh, pos, color)

func ring(parent: Node3D, pos: Vector3, radius: float, color: Color, width: float = 0.06) -> MeshInstance3D:
	var mesh = TorusMesh.new()
	mesh.inner_radius = radius - width
	mesh.outer_radius = radius + width
	mesh.rings = 48
	mesh.ring_segments = 8
	var node = shape(parent, mesh, pos, color)
	node.material_override = _material(color, true)
	return node

func text3d(parent: Node3D, text: String, pos: Vector3, color: Color = Color("264f49"), size: int = 42) -> Label3D:
	var label = Label3D.new()
	label.text = text
	label.font = font
	label.font_size = size
	label.pixel_size = 0.009
	label.position = pos
	label.modulate = color
	label.outline_size = 7
	label.outline_modulate = Color("fff7e5")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	parent.add_child(label)
	return label

func collider(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var body = StaticBody3D.new()
	body.position = pos
	var collision = CollisionShape3D.new()
	var mesh = BoxShape3D.new()
	mesh.size = size
	collision.shape = mesh
	body.add_child(collision)
	parent.add_child(body)

func _build_world() -> void:
	world = Node3D.new()
	add_child(world)
	backdrop = Environment.new()
	backdrop.background_mode = Environment.BG_COLOR
	backdrop.background_color = Color("cbded8")
	backdrop.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	backdrop.ambient_light_color = Color("eef1ee")
	backdrop.ambient_light_energy = 0.35
	backdrop.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var env = WorldEnvironment.new()
	env.environment = backdrop
	add_child(env)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_color = Color("fff8ed")
	sun.light_energy = 0.65
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60
	add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 24
	camera.far = 100
	camera.position = Vector3(23, 28, 32)
	add_child(camera)
	camera.look_at(Vector3(0, 0, 0))
	camera.current = true
	# Floating garden: deliberately built from native meshes, so every object is editable.
	cylinder(world, Vector3(0, -0.7, 0), 10.9, 1.1, Color("668f80"), 11.3, 64)
	cylinder(world, Vector3(0, -2.1, 0), 7.3, 2.1, Color("52766d"), 10.7, 12)
	cylinder(world, Vector3(0, -0.09, 0), 11.3, 0.24, Color("b6c9a0"), -1, 64)
	collider(world, Vector3(0, -0.28, 0), Vector3(24, 0.5, 24))
	# Pale cloud banks and distant, faceted mountains.
	for i in range(16):
		var angle = i * TAU / 16
		var cloud = sphere(world, Vector3(cos(angle) * 16, -2.8 + sin(i) * 0.3, sin(angle) * 15), 2.7, Color("e5eee4"))
		cloud.scale = Vector3(1.9, 0.25, 0.9)
	for i in range(7):
		cylinder(world, Vector3(-18 + i * 6, -5, -16 - (i % 2) * 4), 4, 9 + i % 3 * 2, Color("a7c7bd"), 0, 5)
	# A small jade pond beside the home.
	var rim = cylinder(world, Vector3(-6.5, 0.05, 0), 1.15, 0.13, Color("a6b59c"), -1, 32)
	rim.scale.z = 1.35
	var water = cylinder(world, Vector3(-6.5, 0.13, 0), 0.99, 0.025, Color("70aaa1"), -1, 32)
	water.scale.z = 1.35
	ring(world, Vector3(-6.6, 0.15, 0.2), 0.4, Color("a7d1ba"), 0.015)
	# Meandering stone walkways.
	for target in [Vector3(-5, 0, -3.2), Vector3(4.7, 0, -4.3), Vector3(5.3, 0, 4.2), Vector3(-5, 0, 4)]:
		for j in range(11):
			var pos = Vector3.ZERO.lerp(target, j / 10.0)
			var tile = box(world, pos + Vector3(0, 0.035, 0), Vector3(0.8, 0.08, 0.7), Color("e0dec2"))
			tile.rotation.y = sin(j * 4.0) * 0.13
	# Central mandala, decorative not a clinical status indicator.
	cylinder(world, Vector3(0, 0.03, 0), 2.15, 0.1, Color("d6dbbf"), -1, 48)
	ring(world, Vector3(0, 0.1, 0), 1.95, Color("fcf0c3"), 0.04)
	ring(world, Vector3(0, 0.11, 0), 1.65, Color("8eaf98"), 0.025)
	for i in range(8):
		var angle = i * TAU / 8
		box(world, Vector3(cos(angle) * 1.8, 0.13, sin(angle) * 1.8), Vector3(0.1, 0.04, 0.1), Color("fff3c7"))
	_build_house(Vector3(-5.2, 0, -3.7))
	_build_arena(Vector3(4.1, 0, -4.6))
	_build_portal(Vector3(5.3, 0, 4.1))
	_build_stele(Vector3(-5, 0, 4))
	# Trees cluster around the island perimeter, keeping the routes open.
	for i in range(22):
		var angle = i * TAU / 22
		var radius = 9.2 + sin(i * 5.0) * 0.5
		_tree(Vector3(cos(angle) * radius, 0, sin(angle) * radius), 0.75 + (i % 4) * 0.15, i % 4 == 0)
	for pos in [Vector3(-2, 0, -5.8), Vector3(7, 0, -1), Vector3(-7, 0, 1.2)]:
		_tree(pos, 0.9, false)
	for i in range(28):
		var pos = Vector3(sin(i * 7.3) * 9.3, 0.13, cos(i * 4.7) * 8.9)
		if abs(pos.x) > 2.4:
			for j in range(3):
				sphere(world, pos + Vector3(j * 0.15, 0, 0), 0.09, Color("f7d3a8") if i % 2 == 0 else Color("f4eacb"))
	# Three friendly inhabitants.
	for entry in [[Vector3(-2.8, 0, -1.3), Color("c0846c"), "云游药师"], [Vector3(2.9, 0, 2.1), Color("7795a6"), "守阵人"], [Vector3(-3.1, 0, 4.7), Color("a795b4"), "同修道友"]]:
		var npc = _character(entry[1])
		npc.position = entry[0]
		world.add_child(npc)
		text3d(world, entry[2], entry[0] + Vector3(0, 1.9, 0), Color("4e6c60"), 25)
		animated.append(npc)
	# Lanterns make the four destinations identifiable.
	for pos in [Vector3(-3.3, 0, -3), Vector3(2.4, 0, -4), Vector3(4, 0, 3.5), Vector3(-3.5, 0, 3.5)]:
		cylinder(world, pos + Vector3(0, 0.85, 0), 0.045, 1.7, Color("756b4a"), -1, 8)
		var lantern = sphere(world, pos + Vector3(0, 1.65, 0), 0.22, Color("f6cb8e"))
		lantern.material_override = _material(Color("f6cb8e"), true)

func _tree(pos: Vector3, scale_value: float, peach: bool) -> void:
	var tree = Node3D.new()
	world.add_child(tree)
	tree.position = pos
	tree.scale = Vector3.ONE * scale_value
	cylinder(tree, Vector3(0, 0.8, 0), 0.13, 1.6, Color("7f7960"), 0.08, 7)
	var color = Color("d9ad9d") if peach else Color("578e75")
	if peach:
		sphere(tree, Vector3(0, 1.9, 0), 0.9, color)
		sphere(tree, Vector3(0.55, 1.6, 0.1), 0.6, color.lightened(0.08))
	else:
		for i in range(3):
			cylinder(tree, Vector3(0, 1.2 + i * 0.5, 0), 0.95 - i * 0.2, 1.1, color.lightened(i * 0.035), 0.08, 7)

func _build_house(pos: Vector3) -> void:
	var home = Node3D.new()
	world.add_child(home)
	home.position = pos
	box(home, Vector3(0, 0.16, 0), Vector3(3.7, 0.32, 3.0), Color("ded7b9"))
	box(home, Vector3(0, 1.1, 0), Vector3(3, 1.9, 2.4), Color("eee3c4"))
	box(home, Vector3(0, 0.9, 1.23), Vector3(0.7, 1.45, 0.1), Color("806c4c"))
	for x in [-1.32, 1.32]:
		box(home, Vector3(x, 1.15, 1.25), Vector3(0.13, 2.2, 0.15), Color("8c7051"))
		box(home, Vector3(x * 0.68, 1.25, 1.23), Vector3(0.47, 0.58, 0.05), Color("83a592"))
	# Two sloped roof planes with a raised central ridge.
	for side in [-1, 1]:
		var roof = box(home, Vector3(side * 0.85, 2.35, 0), Vector3(2.0, 0.19, 3.2), Color("3d766a"))
		roof.rotation.z = -side * 0.38
		box(home, Vector3(side * 1.83, 2.04, 0), Vector3(0.22, 0.24, 3.3), Color("4b8372"))
	box(home, Vector3(0, 2.75, 0), Vector3(0.18, 0.18, 3.4), Color("d9c08d"))
	collider(world, pos + Vector3(0, 1, 0), Vector3(3.2, 2, 2.5))
	_register_site("home", "家族洞府", pos + Vector3(0, 0, 2.5), pos + Vector3(0, 3.45, 0), "修行与收藏")

func _build_arena(pos: Vector3) -> void:
	cylinder(world, pos + Vector3(0, 0.16, 0), 2.1, 0.32, Color("9cafa4"), -1, 8)
	cylinder(world, pos + Vector3(0, 0.35, 0), 1.8, 0.14, Color("dce1cf"), -1, 8)
	ring(world, pos + Vector3(0, 0.45, 0), 1.45, Color("f5d994"), 0.045)
	for i in range(5):
		var a = i * TAU / 5
		var point = pos + Vector3(cos(a) * 1.75, 0.85, sin(a) * 1.75)
		cylinder(world, point, 0.16, 1.0, Color("8caaa0"), 0.12, 6)
		sphere(world, point + Vector3(0, 0.6, 0), 0.16, Color("f6d898"))
	_register_site("battle", "渡劫台", pos + Vector3(0, 0, 2.3), pos + Vector3(0, 2.65, 0), "三回合策略试炼")

func _build_portal(pos: Vector3) -> void:
	cylinder(world, pos + Vector3(0, 0.16, 0), 1.65, 0.32, Color("a6b8a9"), -1, 12)
	var portal = ring(world, pos + Vector3(0, 1.8, 0), 1.2, Color("7de3d3"), 0.13)
	portal.rotation_degrees.x = 90
	animated.append(portal)
	for x in [-1.3, 1.3]:
		box(world, pos + Vector3(x, 1, 0), Vector3(0.3, 2, 0.4), Color("81988c"))
		cylinder(world, pos + Vector3(x, 2.05, 0), 0.28, 0.32, Color("e4d6a7"), 0.08, 4)
	_register_site("boss", "万象灵阵", pos + Vector3(0, 0, 1.9), pos + Vector3(0, 3.5, 0), "世界 Boss · 本地模拟")

func _build_stele(pos: Vector3) -> void:
	box(world, pos + Vector3(0, 0.18, 0), Vector3(2.2, 0.36, 1.6), Color("c4c9ae"))
	box(world, pos + Vector3(0, 1.2, 0), Vector3(1.35, 2, 0.55), Color("708d7c"))
	box(world, pos + Vector3(0, 2.3, 0), Vector3(1.7, 0.23, 0.85), Color("e1d4af"))
	for i in range(4):
		box(world, pos + Vector3(0, 1.8 - i * 0.35, 0.29), Vector3(0.8 - i * 0.1, 0.07, 0.025), Color("e3d6b6"))
	collider(world, pos + Vector3(0, 1, 0), Vector3(1.5, 2, 0.7))
	_register_site("records", "天机碑", pos + Vector3(0, 0, 1.5), pos + Vector3(0, 3.1, 0), "计划与家族成就")

func _register_site(id: String, title: String, pos: Vector3, label_pos: Vector3, subtitle: String) -> void:
	sites.append({"id": id, "title": title, "position": pos})
	text3d(world, title, label_pos)
	text3d(world, subtitle, label_pos - Vector3(0, 0.38, 0), Color("638477"), 22)

func _character(color: Color) -> Node3D:
	var root = Node3D.new()
	cylinder(root, Vector3(0, 0.57, 0), 0.35, 0.95, color, 0.19, 8)
	sphere(root, Vector3(0, 1.28, 0), 0.24, Color("edcfac"))
	var hair = sphere(root, Vector3(0, 1.43, -0.04), 0.24, Color("344a45"))
	hair.scale.y = 0.5
	sphere(root, Vector3(0, 1.62, -0.08), 0.1, Color("344a45"))
	box(root, Vector3(0, 0.68, 0), Vector3(0.49, 0.09, 0.43), Color("e6c693"))
	for x in [-0.31, 0.31]:
		sphere(root, Vector3(x, 0.77, 0.04), 0.12, color)
		box(root, Vector3(x * 0.5, 0.09, 0.08), Vector3(0.17, 0.18, 0.31), Color("445e55"))
	return root

func _build_player() -> void:
	player = CharacterBody3D.new()
	player.set_script(Player)
	add_child(player)
	player.position = Vector3(0, 0.15, 1)
	var collision = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.27
	capsule.height = 1.45
	collision.shape = capsule
	collision.position.y = 0.75
	player.add_child(collision)
	var model = _character(Color("eee8d3"))
	player.add_child(model)
	player.model = model
	player.camera = camera
	ring(player, Vector3(0, 0.06, 0), 0.5, Color("fff1b9"), 0.035)
	text3d(player, "你 · 家族守护者", Vector3(0, 1.95, 0), Color("345e52"), 27)

func _process(delta: float) -> void:
	clock += delta
	for i in range(animated.size()):
		var object = animated[i]
		if object is MeshInstance3D:
			object.rotation.z = sin(clock * 0.7) * 0.07
		else:
			object.rotation.y = sin(clock * 0.4 + i * 2) * 0.3
	nearest = ""
	var distance = 2.6
	for site in sites:
		var d = player.position.distance_to(site.position)
		if d < distance:
			distance = d
			nearest = site.id
	if is_instance_valid(ui):
		ui.update_proximity(nearest)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and nearest != "" and not ui.modal_open:
		ui.open_site(nearest)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			ui.close_modal()
		if event.keycode == KEY_F12:
			capture("res://output/demo-screenshot.png")
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not ui.modal_open:
		camera_angle -= event.relative.x * 0.006
		camera.position = Vector3(sin(camera_angle) * 34 + cos(camera_angle) * 23, 28, cos(camera_angle) * 32 - sin(camera_angle) * 23)
		camera.look_at(Vector3.ZERO)
	if event is InputEventMouseButton and not ui.modal_open:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.size = maxf(17, camera.size - 0.6)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.size = minf(29, camera.size + 0.6)

func capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var result = get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE ", path, " result=", result)

func _handle_capture() -> void:
	var args = OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--capture="):
			await get_tree().create_timer(1.5).timeout
			if "--show-record" in args:
				ui.open_record()
			if "--show-battle" in args:
				ui.start_battle()
			await get_tree().process_frame
			await capture(arg.trim_prefix("--capture="))
			get_tree().quit()
