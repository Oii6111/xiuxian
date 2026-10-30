extends Node3D
const State = preload("res://scripts/campaign/state.gd")
const Catalogue = preload("res://scripts/campaign/catalogue.gd")
const Encounter = preload("res://scripts/campaign/encounter.gd")
const Art = preload("res://scripts/campaign/creatures.gd")
const Interface = preload("res://scripts/campaign/ui.gd")
var state = State.new()
var rules: RefCounted
var font: SystemFont
var stage: Node3D
var player: CharacterBody3D
var hero: Node3D
var boss: Node3D
var camera: Camera3D
var ui: CanvasLayer
var portals: Array = []
var node_visuals: Array = []
var hazard_visuals: Dictionary = {}
var townfolk: Array = []
var peaceful_minions: Array = []
var nearby_person: String = ""
var minion_visuals: Array = []
var home_decor: Node3D
var encounter_token: String = ""
var result_shown: bool = false
var clock: float = 0.0
var nearest: String = ""
var shield_visual: MeshInstance3D
var escort_visual: Node3D
var last_direction = Vector3(0,0,-1)
var debug_capture: bool = false

func _ready() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei","Noto Sans CJK SC","SimHei"])
	var args = OS.get_cmdline_user_args()
	if "--preview" in args or "--campaign-test" in args:
		state.persist_enabled = false
	else:
		state.load_game()
	_setup_input()
	_environment()
	_build_player()
	_build_town()
	ui = CanvasLayer.new()
	ui.set_script(Interface)
	ui.game = self
	add_child(ui)
	if "b00" not in state.data.clears and "--campaign-test" not in args and "--preview" not in args:
		ui.open_start.call_deferred()
	_capture_args.call_deferred()

func _setup_input() -> void:
	var bindings = {"move_forward":[KEY_W,KEY_UP],"move_back":[KEY_S,KEY_DOWN],"move_left":[KEY_A,KEY_LEFT],"move_right":[KEY_D,KEY_RIGHT],"sprint":[KEY_SHIFT]}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in bindings[action]:
			var event = InputEventKey.new()
			event.physical_keycode = key
			if not InputMap.action_has_event(action,event):
				InputMap.action_add_event(action,event)

func _environment() -> void:
	var environment = WorldEnvironment.new()
	var settings = Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("a8dce8")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("e4f6ff")
	settings.ambient_light_energy = 0.40
	settings.ambient_light_sky_contribution = 0.0
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	settings.tonemap_exposure = 0.90
	environment.environment = settings
	add_child(environment)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-30,0)
	sun.light_color = Color("fff2d7")
	sun.light_energy = 0.65
	sun.shadow_enabled = true
	add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 20.5
	camera.position = Vector3(18,23,21)
	add_child(camera)
	camera.look_at(Vector3(0,0.4,0))
	camera.current = true
	get_viewport().msaa_3d = Viewport.MSAA_2X

func _build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "QGuardian"
	add_child(player)
	var hit = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.30
	capsule.height = 1.5
	hit.shape = capsule
	hit.position.y = 0.75
	player.add_child(hit)
	hero = Art.hero(state.data.avatar)
	player.add_child(hero)
	shield_visual = Art.ball(player,Vector3(0,1,0),1.05,Color(0.35,0.9,1.0,0.26),Vector3(1,1.2,1))
	shield_visual.hide()
	player.position = Vector3(-3,0,4)

func change_avatar(kind: String) -> void:
	state.data.avatar = kind
	if is_instance_valid(hero):
		player.remove_child(hero)
		hero.queue_free()
	hero = Art.hero(kind)
	player.add_child(hero)
	state.save_game()
	if is_instance_valid(ui):
		ui.show_toast("形象已切换，修行进度保留。")

func _clear_stage() -> void:
	if is_instance_valid(stage):
		remove_child(stage)
		stage.queue_free()
	stage = Node3D.new()
	stage.name = "FiveRealmsStage"
	add_child(stage)
	portals.clear()
	node_visuals.clear()
	townfolk.clear()
	peaceful_minions.clear()
	nearby_person = ""
	minion_visuals.clear()
	hazard_visuals.clear()
	boss = null
	escort_visual = null
	home_decor = null

func _floor(color: Color, town: bool) -> void:
	if town:
		Art.cylinder(stage,Vector3(0,-0.85,0),10.8,1.3,Color("b8cfbe"))
		Art.cylinder(stage,Vector3(0,-0.12,0),10.4,0.24,color)
	else:
		Art.box(stage,Vector3(0,-0.80,0),Vector3(20.8,1.1,14.8),Color("667e8f"))
		Art.box(stage,Vector3(0,-0.08,0),Vector3(20,0.16,14),color)
		for x in range(-8,9,2):
			for z in range(-6,7,2):
				Art.box(stage,Vector3(x,0.012,z),Vector3(1.92,0.015,1.92),color.lightened(0.025 if (x+z)%4==0 else 0))
	var body = StaticBody3D.new()
	stage.add_child(body)
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(22,1,19 if town else 15)
	collision.shape = shape
	collision.position.y = -0.5
	body.add_child(collision)
	for i in range(8):
		var p = Vector3(sin(i*2.4)*19,-1.5,cos(i*2.4)*15)
		Art.cylinder(stage,p,2.1,3.8,Color("8bb9be"),0.1)
		Art.ball(stage,p+Vector3(0,2.0,0),1.3,Color("c8e5dc"),Vector3(1.1,0.4,1))

func _build_town() -> void:
	_clear_stage()
	_floor(Color("93bc9c"),true)
	Art.ring(stage,Vector3(0,0.03,0),5.0,0.55,Color("d8c69a"))
	Art.ring(stage,Vector3(0,0.04,0),2.0,0.05,Color("72bcb5"))
	# Editable Blender architecture; simple fallback keeps headless prototypes usable.
	var pavilion = Art.blender_asset("zhaosheng_pagoda")
	if pavilion != null:
		stage.add_child(pavilion)
		pavilion.position = Vector3(0,0,-4)
		pavilion.scale = Vector3.ONE * 0.78
	else:
		for y in [0.8,1.9]:
			Art.cylinder(stage,Vector3(0,y,-4),1.4,0.7,Color("f0d4a0"))
			var roof = Art.cylinder(stage,Vector3(0,y+0.55,-4),2.0,0.6,Color("579a9e"),0.18)
			roof.mesh.radial_segments = 4
			roof.rotation.y = PI*0.25
	Art.label(stage,"照生灯台",Vector3(0,3.5,-4),Color("fff8dc"),34)
	var regions = ["水","土","金","火","木"]
	var names = ["玄泽","稷野","白羽关","丹霞岭","苍梧林"]
	var colors = ["7b9eea","e8bb5e","8adbe7","ff8b65","4bc89b"]
	for i in range(5):
		var angle = -0.4 + i * TAU/5
		var p = Vector3(sin(angle)*7.6,0,cos(angle)*6.5)
		var color = Color(colors[i])
		Art.cylinder(stage,p+Vector3(0,0.15,0),1.0,0.3,color.darkened(0.1))
		var arch = Art.ring(stage,p+Vector3(0,1.65,0),1.25,0.14,color)
		arch.rotation.x = PI*0.5
		Art.ball(stage,p+Vector3(0,1.65,0),0.72,Color(color,0.22))
		var restored = regions[i] in state.data.seals
		Art.label(stage,names[i]+(" · 已复归" if restored else ""),p+Vector3(0,3.25,0),Color("fff7dd"),35)
		portals.append({"position":Vector2(p.x,p.z),"region":regions[i],"label":names[i]})
		if restored:
			var residents = Catalogue.minions_for(regions[i])
			for j in range(residents.size()):
				var resident = Art.model(residents[j],"minions")
				stage.add_child(resident)
				resident.position = p + Vector3(-1.4+float(j)*2.8,0,-1.0)
				resident.scale = Vector3.ONE * 0.72
				peaceful_minions.append(resident)
	Art.label(stage,"听雷台 · E",Vector3(-3.5,1.3,3.5),Color("fff3c2"),32)
	portals.append({"position":Vector2(-3.5,3.5),"region":"序章","label":"听雷台"})
	for i in range(7):
		var angle = -1.05 + float(i)*0.35
		var p = Vector3(sin(angle)*9.2,0,-cos(angle)*9.2)
		var tree = Art.blender_asset("sapling_tree")
		if tree != null:
			stage.add_child(tree)
			tree.position = p
			tree.rotation.y = float(i)*1.6
			tree.scale = Vector3.ONE * (0.85+float(i%3)*0.12)
		else:
			Art.cylinder(stage,p+Vector3(0,0.8,0),0.16,1.6,Color("a88765"))
			Art.ball(stage,p+Vector3(0,2,0),0.8,Color("79bf9e"))
	_build_townfolk()
	player.position = Vector3(-2,0,2.8)
	player.velocity = Vector3.ZERO
	refresh_home()

func refresh_home() -> void:
	if rules != null or not is_instance_valid(stage):
		return
	if is_instance_valid(home_decor):
		stage.remove_child(home_decor)
		home_decor.queue_free()
	home_decor = Node3D.new()
	stage.add_child(home_decor)
	for i in range(state.data.buildings.size()):
		var item: String = state.data.buildings[i]
		var p = Vector3(-4.5+i*2.5,0,-2.5)
		match item:
			"门灯":
				Art.cylinder(home_decor,p+Vector3(0,1,0),0.1,2,Color("715b51"))
				Art.ball(home_decor,p+Vector3(0,2.0,0),0.45,Color("ffe39b"))
			"石景":
				Art.ball(home_decor,p+Vector3(0,0.45,0),0.8,Color("8eafc0"),Vector3(1,0.6,0.7))
				Art.ring(home_decor,p+Vector3(0,0.04,0),1.0,0.1,Color("8dd8ea"))
			"谷亭":
				Art.box(home_decor,p+Vector3(0,0.6,0),Vector3(1.1,1.2,0.9),Color("e7c38a"))
				Art.cylinder(home_decor,p+Vector3(0,1.5,0),0.9,0.5,Color("67a8a3"),0.08)
			"风铃":
				Art.beam(home_decor,p,p+Vector3(0,2.0,0),0.08,Color("a68465"))
				Art.ball(home_decor,p+Vector3(0,1.7,0),0.22,Color("8cd6cc"))
		Art.label(home_decor,item,p+Vector3(0,2.8,0),Color("e4fbfa"),24)
	if is_instance_valid(ui):
		ui.refresh()

func start_encounter(id: String) -> bool:
	var access = state.availability(id)
	if access != "":
		ui.show_toast(access)
		return false
	if encounter_token != "":
		state.abandon(encounter_token)
	ui.close_panel()
	var begin = state.begin(id)
	if not begin.ok:
		ui.show_toast(begin.message)
		return false
	encounter_token = begin.token
	rules = Encounter.new(Catalogue.entry(id),begin.snapshot,state.data.difficulty,state.data.skill)
	result_shown = false
	_clear_stage()
	var c = Color(rules.entry.color)
	_floor(c.lightened(0.35),false)
	boss = Art.model(rules.entry,"bosses")
	stage.add_child(boss)
	boss.position = Vector3(rules.boss_position.x,0,rules.boss_position.y)
	Art.label(boss,rules.entry.name,Vector3(0,4.5,0),Color("fff8de"),44)
	player.position = Vector3(-5.8,0,3.4)
	player.velocity = Vector3.ZERO
	for node in rules.nodes:
		var root = Node3D.new()
		root.position = Vector3(node.position.x,0,node.position.y)
		stage.add_child(root)
		Art.cylinder(root,Vector3(0,0.22,0),0.45,0.44,c)
		Art.ring(root,Vector3(0,0.055,0),0.85,0.07,Color("fff0b0"))
		var text = Art.label(root,node.label+" · E",Vector3(0,1.15,0),Color("fff5c9"),29)
		node_visuals.append({"root":root,"label":text})
	if id == "b11":
		escort_visual = Node3D.new()
		stage.add_child(escort_visual)
		Art.ball(escort_visual,Vector3(0,0.55,0),0.38,Color("ffe7a1"))
		Art.label(escort_visual,"羽灯 · 靠近伴行",Vector3(0,1.5,0),Color("fff3b1"),28)
	for mob in rules.minions:
		var model = Art.model(Catalogue.minion(mob.id),"minions")
		stage.add_child(model)
		model.position = Vector3(mob.position.x,0,mob.position.y)
		var tag = Art.label(model,mob.name,Vector3(0,1.6,0),Color("fff9d7"),26)
		minion_visuals.append({"model":model,"label":tag})
	# Distinct corner props support each area's palette and scale.
	for i in range(6):
		var p = Vector3(-8.8+float(i)*3.5,0,-6.5)
		Art.cylinder(stage,p+Vector3(0,0.4,0),0.4,0.8,c.darkened(0.12))
		Art.ball(stage,p+Vector3(0,1,0),0.4,c.lightened(0.3))
	ui.refresh()
	return true

func return_town() -> void:
	if encounter_token != "":
		state.abandon(encounter_token)
	encounter_token = ""
	rules = null
	ui.close_panel()
	_build_town()
	ui.refresh()
	ui.show_toast(state.next_goal())

func combat_action(action: int) -> void:
	if rules == null or ui.modal_open or rules.finished:
		return
	var pos = Vector2(player.position.x,player.position.z)
	match action:
		0:
			var result = rules.attack(pos)
			if result.get("ok",false):
				var slash = Art.ring(stage,Vector3(player.position.x,0.7,player.position.z),1.1,0.08,Color("e8ffff"))
				var tween = slash.create_tween()
				tween.tween_property(slash,"scale",Vector3(1.5,0.3,1.5),0.18)
				tween.tween_callback(slash.queue_free)
		1:
			var result = rules.cast(pos)
			if result.get("ok",false):
				var ray = Art.beam(stage,player.position+Vector3(0,1,0),Vector3(rules.boss_position.x,1,rules.boss_position.y),0.13,Color("e7e9ff"))
				var tween = ray.create_tween()
				tween.tween_interval(0.18)
				tween.tween_callback(ray.queue_free)
		2:
			rules.guard()
		3:
			if rules.dash():
				player.velocity = last_direction * 25.0
				player.move_and_slide()
				var target = rules.clamp_position(Vector2(player.position.x,player.position.z) + Vector2(last_direction.x,last_direction.z)*2.0)
				player.position.x = target.x
				player.position.z = target.y
		4:
			rules.interact(pos)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(ui) or ui.modal_open:
		if is_instance_valid(player):
			player.velocity = Vector3.ZERO
		return
	var input = Input.get_vector("move_left","move_right","move_forward","move_back")
	var right = camera.global_basis.x
	right.y = 0
	var forward = -camera.global_basis.z
	forward.y = 0
	var direction = (right.normalized()*input.x-forward.normalized()*input.y).normalized()
	var speed = 7.1 if Input.is_action_pressed("sprint") else 5.5
	if rules != null:
		speed = 6.0
	if direction.length() > 0.1:
		last_direction = direction
		hero.rotation.y = lerp_angle(hero.rotation.y,atan2(-direction.x,-direction.z),delta*14)
	player.velocity.x = direction.x*speed
	player.velocity.z = direction.z*speed
	player.velocity.y -= 22.0*delta
	player.move_and_slide()
	var limit = rules.arena if rules != null else Rect2(-9,-8,18,16)
	player.position.x = clampf(player.position.x,limit.position.x+0.6,limit.end.x-0.6)
	player.position.z = clampf(player.position.z,limit.position.y+0.6,limit.end.y-0.6)

func _process(delta: float) -> void:
	clock += delta
	if not is_instance_valid(ui):
		return
	if is_instance_valid(shield_visual):
		shield_visual.visible = rules != null and rules.guard_time > 0
	if is_instance_valid(hero):
		var moving = player.velocity.length() > 0.5 and not ui.modal_open
		hero.position.y = absf(sin(clock*12))*0.06 if moving else sin(clock*2)*0.025
	if rules == null:
		nearest = ""
		nearby_person = ""
		var distance = 2.1
		for portal in portals:
			var d = Vector2(player.position.x,player.position.z).distance_to(portal.position)
			if d < distance:
				distance = d
				nearest = portal.region
		for person in townfolk:
			var d = Vector2(player.position.x,player.position.z).distance_to(person.position)
			if d < distance:
				distance = d
				nearby_person = person.id
		if nearby_person != "":
			ui.hint_label.text = "E 与 "+Catalogue.person(nearby_person).name+"交谈 · 了解当地散祟与主祟的来历"
		else:
			ui.hint_label.text = "E 进入 "+Catalogue.region_name(nearest)+" · 也可点击右上角山海图鉴" if nearest!="" else state.next_goal()+"  |  WASD移动 · Shift加速 · E交互"
	else:
		var pos = Vector2(player.position.x,player.position.z)
		rules.step(delta,pos)
		if is_instance_valid(boss):
			boss.position = Vector3(rules.boss_position.x,sin(clock*2.1)*0.06,rules.boss_position.y)
			boss.rotation.y = sin(clock*0.8)*0.06
		_sync_visuals()
		for event in rules.feedback:
			_feedback(event)
		rules.feedback.clear()
		if rules.finished and not result_shown:
			result_shown = true
			var settled = state.settle(encounter_token,rules.entry.id,rules.won,rules.difficulty,{"seconds":rules.elapsed,"hits":rules.hits_taken,"blocks":rules.perfect_blocks,"preset":rules.snapshot.get("status","unknown"),"skill":rules.selected_skill})
			ui.show_result(settled)
	ui.refresh()

func _sync_visuals() -> void:
	for i in range(minion_visuals.size()):
		var mob = rules.minions[i]
		minion_visuals[i].model.visible = mob.hp > 0
		minion_visuals[i].model.position = Vector3(mob.position.x,absf(sin(clock*3+i))*0.04,mob.position.y)
		minion_visuals[i].label.text = mob.name+"  "+str(maxi(0,ceili(mob.hp)))
	if is_instance_valid(escort_visual):
		escort_visual.position = Vector3(rules.escort.x,0,rules.escort.y)
	var live: Array = []
	for h in rules.hazards:
		live.append(h.id)
		if not hazard_visuals.has(h.id):
			hazard_visuals[h.id] = _hazard_mesh(h)
			if h.get("source","") == "" and is_instance_valid(boss):
				Art.play_attack(boss)
		var visual: Node3D = hazard_visuals[h.id]
		for child in visual.get_children():
			if child is MeshInstance3D:
				child.material_override = Art.material(Color("ed7659") if h.active else Color(0.96,0.71,0.30,0.63))
	for id in hazard_visuals.keys():
		if id not in live:
			hazard_visuals[id].queue_free()
			hazard_visuals.erase(id)
	for i in range(node_visuals.size()):
		var done: bool = rules.nodes[i].done
		node_visuals[i].label.text = "✓ 已复位" if done else rules.nodes[i].label+" · E"
		node_visuals[i].root.scale = Vector3.ONE * (0.65 if done else 1.0)

func _hazard_mesh(h: Dictionary) -> Node3D:
	var root = Node3D.new()
	stage.add_child(root)
	var c = Color(0.96,0.71,0.30,0.63)
	var p: Vector2 = h.position
	match h.shape:
		"circle":
			Art.cylinder(root,Vector3(p.x,0.045,p.y),h.radius,0.04,c)
			Art.ring(root,Vector3(p.x,0.09,p.y),h.radius,0.04,c)
		"ring":
			Art.ring(root,Vector3(p.x,0.09,p.y),h.radius,h.width,c)
		"line","charge":
			var end: Vector2 = h.end
			var mid = (p+end)*0.5
			var line = Art.box(root,Vector3(mid.x,0.06,mid.y),Vector3(h.width*2,0.05,p.distance_to(end)),c)
			line.rotation.y = atan2(end.x-p.x,end.y-p.y)
			Art.cylinder(root,Vector3(p.x,0.06,p.y),h.width,0.04,c)
			Art.cylinder(root,Vector3(end.x,0.06,end.y),h.width,0.04,c)
		"cone":
			var vertices = PackedVector3Array([Vector3(p.x,0.07,p.y)])
			for i in range(25):
				var a = h.angle-h.half_angle+float(i)/24*h.half_angle*2
				vertices.append(Vector3(p.x+cos(a)*h.radius,0.07,p.y+sin(a)*h.radius))
			var indices = PackedInt32Array()
			for i in range(1,25):
				indices.append_array(PackedInt32Array([0,i+1,i]))
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_INDEX] = indices
			var mesh = ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			Art.part(root,mesh,Vector3.ZERO,c)
	return root

func _feedback(event: Dictionary) -> void:
	if event.kind == "minion_defeat":
		state.record_minion(str(event.id))
	var p: Vector2 = event.position
	if p == Vector2.ZERO:
		p = Vector2(player.position.x,player.position.z)
	var text = Art.label(stage,event.text,Vector3(p.x,2.8,p.y),Color("fff7b4"),37)
	var tween = text.create_tween()
	tween.tween_property(text,"position:y",3.8,0.65)
	tween.tween_callback(text.queue_free)
	if event.kind == "block":
		ui.show_toast("守住了！趁短暂窗口反击。")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if rules != null and rules.finished:
				return_town()
			elif ui.modal_open:
				ui.close_panel()
			elif rules != null:
				ui.pause_menu()
			else:
				ui.open_atlas()
			get_viewport().set_input_as_handled()
			return
		if ui.modal_open:
			return
		if event.keycode == KEY_E:
			if rules != null:
				combat_action(4)
			elif nearby_person != "":
				ui.open_npc(nearby_person)
			elif nearest != "":
				ui.open_atlas(nearest)
		if rules != null:
			for key in {KEY_J:0,KEY_1:1,KEY_K:2,KEY_SPACE:3}:
				if event.keycode == key:
					combat_action({KEY_J:0,KEY_1:1,KEY_K:2,KEY_SPACE:3}[key])
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not ui.modal_open and rules != null:
		combat_action(0)

func _capture_args() -> void:
	var args = OS.get_cmdline_user_args()
	if "--preview" not in args:
		return
	if "--restored-town" in args:
		state.data.clears = ["b00","b03","b06","b09","b12","b15"]
		state.data.seals = ["木","火","土","金","水"]
		state.data.buildings = ["门灯","石景","谷亭","风铃"]
		_build_town()
	for arg in args:
		if arg.begins_with("--capture-boss="):
			state.data.clears = ["b00","b03","b06","b09","b12","b15"]
			state.data.seals = ["木","火","土","金","水"]
			start_encounter(arg.trim_prefix("--capture-boss="))
	var capture_positions = {"front":Vector3(0,18,26),"left":Vector3(-26,18,0),"back":Vector3(0,18,-26),"right":Vector3(26,18,0)}
	for arg in args:
		if arg.begins_with("--capture-view="):
			var view_name = arg.trim_prefix("--capture-view=")
			if capture_positions.has(view_name):
				camera.position = capture_positions[view_name]
				camera.size = 23.0
				camera.look_at(Vector3(0,0.4,0))
	if "--capture-clean" in args:
		ui.hide()
	if "--show-atlas" in args:
		ui.open_atlas()
	for arg in args:
		if arg.begins_with("--campaign-capture="):
			await get_tree().create_timer(3.2).timeout
			await RenderingServer.frame_post_draw
			var image = get_viewport().get_texture().get_image()
			var result = image.save_png(arg.trim_prefix("--campaign-capture="))
			print("CAMPAIGN_CAPTURE ",result)
			get_tree().quit()

func _build_townfolk() -> void:
	var points = [Vector3(2.2,0,2.6),Vector3(5.0,0,-1.0),Vector3(-2.0,0,4.8),Vector3(-5.0,0,0.0),Vector3(3.8,0,-4.0),Vector3(-4.4,0,-4.8)]
	var people = Catalogue.people()
	for i in range(people.size()):
		var person = people[i]
		var model = Art.model(person,"npcs")
		stage.add_child(model)
		model.position = points[i]
		model.scale = Vector3.ONE * 0.82
		Art.label(model,person.name+" · E",Vector3(0,2.7,0),Color("fff5cb"),29)
		townfolk.append({"id":person.id,"position":Vector2(points[i].x,points[i].z)})
