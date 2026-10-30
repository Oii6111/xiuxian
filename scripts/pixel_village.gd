extends Node2D

const State = preload("res://scripts/game_state.gd")
const Player = preload("res://scripts/pixel_player.gd")
const Interface = preload("res://scripts/gameplay_interface.gd")
const Assets = preload("res://scripts/pixel_assets.gd")
const Effects = preload("res://scripts/pixel_effects.gd")
const SPAWN = Vector2(681, 565)
var state = State.new()
var player: CharacterBody2D
var ui: Control
var font: SystemFont
var title_font: SystemFont
var portrait: Texture2D
var walk_textures: Array[Texture2D] = []
var nearest: String = ""
var sites: Array[Dictionary] = []
var roads: Array[PackedVector2Array] = []
var navigation = AStar2D.new()
var debug_roads: bool = false
var elapsed: float = 0
var npc_sprites: Array[Sprite2D] = []
var avatar_frames: Dictionary = {}
var player_name_label: Label

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])
	title_font = SystemFont.new()
	title_font.font_names = PackedStringArray(["KaiTi", "STKaiti", "SimSun"])
	_setup_inputs()
	if not "--preview" in OS.get_cmdline_user_args():
		state.load_game()
	else:
		state.persist_enabled = false
	if "--female" in OS.get_cmdline_user_args():
		state.avatar_id = "female"
		state.player_name = "清岚"
	_build_background()
	_load_sprites()
	_build_roads()
	_build_sites()
	_build_player()
	_build_npcs()
	var layer = CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_script(Interface)
	ui.game = self
	layer.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_handle_capture.call_deferred()

func _setup_inputs() -> void:
	for action in {"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN], "move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT], "sprint": [KEY_SHIFT], "interact": [KEY_E]}:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var bindings = {"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN], "move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT], "sprint": [KEY_SHIFT], "interact": [KEY_E]}
	for action in bindings:
		for key in bindings[action]:
			var event = InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)

func _texture(path: String) -> Texture2D:
	return Assets.texture(path)

func _build_background() -> void:
	var background = Sprite2D.new()
	background.name = "PaintedVillageBackground"
	background.texture = _texture("res://assets/pixel/village-background.png")
	background.centered = false
	background.scale = Vector2(1440, 900) / background.texture.get_size()
	background.z_index = -100
	add_child(background)
	var effects = Node2D.new()
	effects.name = "LiveWaterLanternsAndRunes"
	effects.set_script(Effects)
	effects.z_index = 1
	add_child(effects)

func _load_sprites() -> void:
	avatar_frames["male"] = Assets.frames("res://assets/pixel/cultivator-walk.png", 4, 4)
	avatar_frames["female"] = Assets.frames("res://assets/gameplay/female-walk.png", 4, 4)
	walk_textures = avatar_frames[state.avatar_id]
	portrait = Assets.portrait(walk_textures[0])

func apply_avatar(id: String, nickname: String) -> void:
	state.choose_avatar(id, nickname)
	walk_textures = avatar_frames[state.avatar_id]
	portrait = Assets.portrait(walk_textures[0])
	player.walk_textures = walk_textures
	player.sprite.texture = walk_textures[0]
	player.facing = 0
	player_name_label.text = state.player_name
	state.save_game()
	ui.refresh()

func _build_roads() -> void:
	# Main plaza and house steps, measured against the clean 1440x900 background.
	roads.append(PackedVector2Array([Vector2(210, 482), Vector2(355, 425), Vector2(500, 432), Vector2(602, 421), Vector2(704, 410), Vector2(768, 425), Vector2(803, 464), Vector2(787, 524), Vector2(861, 573), Vector2(899, 620), Vector2(830, 659), Vector2(741, 625), Vector2(633, 610), Vector2(549, 650), Vector2(475, 708), Vector2(383, 753), Vector2(329, 729), Vector2(410, 655), Vector2(467, 615), Vector2(493, 573), Vector2(414, 547), Vector2(333, 532), Vector2(244, 523)]))
	# A connected route to the elevated tribulation terrace.
	roads.append(_corridor([Vector2(687, 459), Vector2(717, 413), Vector2(752, 366), Vector2(794, 316), Vector2(819, 256), Vector2(845, 206)], 30))
	roads.append(PackedVector2Array([Vector2(760, 178), Vector2(840, 147), Vector2(920, 167), Vector2(1005, 200), Vector2(956, 239), Vector2(846, 254), Vector2(784, 222)]))
	# Bridge and east bank: the stream stays impassable away from the bridge.
	roads.append(_corridor([Vector2(781, 600), Vector2(850, 632), Vector2(939, 668), Vector2(1024, 698), Vector2(1101, 670), Vector2(1167, 651)], 27))
	roads.append(_corridor([Vector2(1144, 665), Vector2(1160, 605), Vector2(1193, 560), Vector2(1222, 509), Vector2(1256, 456), Vector2(1289, 405)], 33))
	roads.append(PackedVector2Array([Vector2(1194, 375), Vector2(1255, 352), Vector2(1353, 367), Vector2(1350, 419), Vector2(1284, 450), Vector2(1224, 433)]))
	var points = [SPAWN, Vector2(530, 521), Vector2(402, 480), Vector2(717, 434), Vector2(752, 366), Vector2(794, 316), Vector2(819, 256), Vector2(857, 206), Vector2(781, 600), Vector2(850, 632), Vector2(939, 668), Vector2(1024, 698), Vector2(1144, 665), Vector2(1160, 605), Vector2(1193, 560), Vector2(1222, 509), Vector2(1256, 456), Vector2(1289, 405)]
	for i in range(points.size()):
		navigation.add_point(i, points[i])
	for edge in [[0, 1], [1, 2], [0, 3], [3, 4], [4, 5], [5, 6], [6, 7], [0, 8], [8, 9], [9, 10], [10, 11], [11, 12], [12, 13], [13, 14], [14, 15], [15, 16], [16, 17]]:
		navigation.connect_points(edge[0], edge[1])
	# A real physics obstruction along the family home's facade.
	var body = StaticBody2D.new()
	body.name = "HomeFacadeCollision"
	var polygon = CollisionPolygon2D.new()
	polygon.polygon = PackedVector2Array([Vector2(207, 397), Vector2(467, 364), Vector2(520, 403), Vector2(355, 449), Vector2(210, 474)])
	body.add_child(polygon)
	add_child(body)

func _corridor(points: Array, width: float) -> PackedVector2Array:
	var left = PackedVector2Array()
	var right = PackedVector2Array()
	for i in range(points.size()):
		var direction: Vector2
		if i == 0:
			direction = points[1] - points[0]
		elif i == points.size() - 1:
			direction = points[i] - points[i - 1]
		else:
			direction = points[i + 1] - points[i - 1]
		var normal = direction.normalized().orthogonal() * width
		left.append(points[i] + normal)
		right.append(points[i] - normal)
	right.reverse()
	left.append_array(right)
	return left

func can_walk(point: Vector2) -> bool:
	for polygon in roads:
		if Geometry2D.is_point_in_polygon(point, polygon):
			return true
	return false

func _build_sites() -> void:
	sites = [
		{"id": "home", "title": "家族洞府", "position": Vector2(402, 480), "node": 2, "label": Vector2(340, 287)},
		{"id": "battle", "title": "渡劫台", "position": Vector2(857, 206), "node": 7, "label": Vector2(934, 110)},
		{"id": "boss", "title": "世界首领", "position": Vector2(1289, 405), "node": 17, "label": Vector2(1366, 264)},
		{"id": "records", "title": "天机碑", "position": Vector2(1144, 665), "node": 12, "label": Vector2(1170, 487)}
	]
	for site in sites:
		var vertical = site.id != "home"
		var plaque = PanelContainer.new()
		plaque.position = site.label
		plaque.z_index = 1200
		var decoration = StyleBoxFlat.new()
		decoration.bg_color = Color("392a24")
		decoration.border_color = Color("b98948")
		decoration.set_border_width_all(2)
		decoration.content_margin_left = 9
		decoration.content_margin_right = 9
		decoration.content_margin_top = 8
		decoration.content_margin_bottom = 8
		plaque.add_theme_stylebox_override("panel", decoration)
		plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(plaque)
		var label = Label.new()
		label.text = "\n".join(site.title.split("")) if vertical else site.title
		label.add_theme_font_override("font", title_font)
		label.add_theme_color_override("font_color", Color("f6d694"))
		label.add_theme_font_size_override("font_size", 22 if vertical else 21)
		plaque.add_child(label)
		var area = Area2D.new()
		area.position = site.position
		area.input_pickable = true
		var hit = CollisionShape2D.new()
		var circle = CircleShape2D.new()
		circle.radius = 45
		hit.shape = circle
		area.add_child(hit)
		var id: String = site.id
		area.input_event.connect(func(_viewport, event, _shape):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not ui.modal_open:
				travel_to(id)
		)
		add_child(area)

func _build_player() -> void:
	player = CharacterBody2D.new()
	player.name = "PlayableCultivator"
	player.set_script(Player)
	player.game = self
	player.walk_textures = walk_textures
	player.position = SPAWN
	add_child(player)
	var label = Label.new()
	label.text = state.player_name
	player_name_label = label
	label.position = Vector2(-45, -105)
	label.size.x = 90
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color("ffefb1"))
	label.add_theme_color_override("font_outline_color", Color("342d28"))
	label.add_theme_constant_override("outline_size", 5)
	player.add_child(label)

func _build_npcs() -> void:
	var atlas = Assets.texture("res://assets/pixel/village-npcs.png")
	var image = atlas.get_image()
	var cell = Vector2i(image.get_width() / 3, image.get_height())
	var locations = [Vector2(851, 519), Vector2(430, 458), Vector2(1139, 633)]
	var names = ["云游药师", "花间同修", "守碑书生"]
	for i in range(3):
		var root = Node2D.new()
		root.position = locations[i]
		root.z_index = int(locations[i].y)
		root.name = names[i]
		add_child(root)
		var used = image.get_region(Rect2i(Vector2i(i * cell.x, 0), cell)).get_used_rect()
		var texture = AtlasTexture.new()
		texture.atlas = atlas
		texture.region = Rect2(Vector2i(i * cell.x, 0) + used.position, used.size)
		texture.filter_clip = true
		var sprite = Sprite2D.new()
		sprite.texture = texture
		sprite.scale = Vector2.ONE * 83 / texture.get_height()
		sprite.position.y = -41.5
		root.add_child(sprite)
		npc_sprites.append(sprite)
		var name_label = Label.new()
		name_label.text = names[i]
		name_label.position = Vector2(-43, -99)
		name_label.size.x = 86
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_override("font", font)
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.add_theme_color_override("font_color", Color("fff2d0"))
		name_label.add_theme_color_override("font_outline_color", Color("3a3329"))
		name_label.add_theme_constant_override("outline_size", 4)
		root.add_child(name_label)
		var area = Area2D.new()
		area.position.y = -35
		var shape = CollisionShape2D.new()
		var rectangle = RectangleShape2D.new()
		rectangle.size = Vector2(55, 85)
		shape.shape = rectangle
		area.add_child(shape)
		var index = i
		area.input_event.connect(func(_viewport, event, _shape):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not ui.modal_open:
				ui.open_npc(index)
		)
		root.add_child(area)

func travel_to(id: String) -> void:
	if ui.modal_open:
		return
	for site in sites:
		if site.id == id:
			var start = navigation.get_closest_point(player.position)
			player.route = navigation.get_point_path(start, site.node)
			player.destination_site = id
			ui.toast("前往「%s」· WASD 可取消自动行走" % site.title)
			return

func _process(delta: float) -> void:
	elapsed += delta
	for i in range(npc_sprites.size()):
		npc_sprites[i].position.y = -41.5 - sin(elapsed * 1.5 + i * 2) * 0.8
	nearest = ""
	var distance = 70.0
	for site in sites:
		var d = player.position.distance_to(site.position)
		if d < distance:
			distance = d
			nearest = site.id
	if is_instance_valid(ui):
		ui.update_proximity(nearest)
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(player):
		return
	if not player.route.is_empty():
		var target = player.route[-1]
		draw_arc(target, 15 + sin(elapsed * 3) * 2, 0, TAU, 20, Color(1, 0.85, 0.42, 0.8), 2)
	if debug_roads:
		for polygon in roads:
			draw_colored_polygon(polygon, Color(0.3, 1, 0.4, 0.25))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and nearest != "" and not ui.modal_open:
		player.route.clear()
		player.destination_site = ""
		ui.open_site(nearest)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			ui.close_modal()
		if event.keycode == KEY_F12:
			capture("res://output/pixel-screenshot.png")
		if event.keycode == KEY_F3:
			debug_roads = not debug_roads

func capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	print("CAPTURE ", path, " result=", get_viewport().get_texture().get_image().save_png(path))

func _handle_capture() -> void:
	var args = OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--capture="):
			await get_tree().create_timer(1.0).timeout
			if "--show-start" in args:
				ui.show_start()
			if "--show-record" in args:
				ui.open_record()
			if "--show-recovery" in args:
				state.begin_recovery(true)
				ui.open_recovery()
			if "--show-battle" in args:
				ui.start_battle()
				ui.combat.use_skill(2)
				await get_tree().create_timer(0.75).timeout
			if "--show-boss" in args:
				ui.start_boss(false)
				ui.combat.rules.phase = "windup"
				ui.combat.rules.phase_clock = 0.95
				ui.combat.rules.target_position = ui.combat.hero.position
				await get_tree().create_timer(0.2).timeout
				ui.combat.use_skill(0)
			if "--show-reward" in args:
				ui.open_reward("家人的坚持，化作你的守护。\n修为 +10  ·  灵气 +4  ·  守护符 +1  ·  灵印 +1")
			await get_tree().process_frame
			await capture(arg.trim_prefix("--capture="))
			get_tree().quit()
