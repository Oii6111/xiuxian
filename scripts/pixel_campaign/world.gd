extends Node2D
## Pixel exploration owns no legacy village resources or clinical state.
signal exit_to_village

const Catalogue = preload("res://scripts/pixel_campaign/catalogue.gd")
const SagaState = preload("res://scripts/pixel_campaign/state.gd")
const Art = preload("res://scripts/pixel_campaign/pixel_art.gd")
const StoryUI = preload("res://scripts/pixel_campaign/story_ui.gd")
const Battle = preload("res://scripts/pixel_campaign/battle.gd")
const REGIONS = ["序章", "木", "火", "土", "金", "水", "旁篇", "共域", "终章"]
const WALK_AREA = Rect2(280, 350, 900, 370)

var state
var origin_village: Node2D
var initial_region: String = "木"
var current_region: String = "木"
var stage_name: String = "苍梧林"
var player_position: Vector2 = Vector2(450, 650)
var player_sprite: Sprite2D
var battle
var encounter_token: String = ""
var encounter_id: String = ""
var ui
var stage: Node2D
var stage_layer: CanvasLayer
var battle_layer: CanvasLayer
var actors: Array = []
var hero_textures: Array = []
var frame_clock: float = 0.0
var facing: int = 0
var decor
var elapsed: float = 0.0
var _leaving: bool = false

class CampDecoration extends Node2D:
	var buildings: Array = []
	func _draw() -> void:
		# Tiny pixel props make the spending loop visible in the explored world.
		if "门灯" in buildings:
			draw_rect(Rect2(-6, -55, 12, 56), Color("76503d"))
			draw_rect(Rect2(-17, -67, 34, 13), Color("493a31"))
			draw_rect(Rect2(-13, -54, 26, 27), Color("efc96c"))
			draw_rect(Rect2(-8, -50, 16, 18), Color("fff0a5"))
			draw_rect(Rect2(-19, 0, 38, 7), Color("5c5145"))
		if "药圃" in buildings:
			draw_rect(Rect2(40, -10, 94, 35), Color("765440"))
			for n in range(5):
				draw_rect(Rect2(46 + n * 17, -24, 6, 40), Color("659565"))
				draw_rect(Rect2(40 + n * 17, -19, 18, 9), Color("98b978"))
				draw_rect(Rect2(44 + n * 17, -29, 10, 8), Color("c7d58b"))
		if "听雨亭" in buildings:
			draw_rect(Rect2(155, -53, 8, 71), Color("79513f"))
			draw_rect(Rect2(226, -53, 8, 71), Color("79513f"))
			draw_rect(Rect2(144, 14, 102, 10), Color("a89876"))
			draw_rect(Rect2(137, -58, 117, 10), Color("476d6b"))
			draw_rect(Rect2(151, -69, 89, 12), Color("648c7f"))
			draw_rect(Rect2(171, -78, 49, 10), Color("8ca28a"))
		if "观星台" in buildings:
			draw_rect(Rect2(274, 0, 80, 20), Color("878b86"))
			draw_rect(Rect2(282, -11, 64, 13), Color("acb4a6"))
			draw_rect(Rect2(309, -40, 10, 30), Color("6d6960"))
			draw_rect(Rect2(293, -49, 43, 12), Color("c4ac68"))
			draw_rect(Rect2(323, -54, 18, 20), Color("827b62"))

func _ready() -> void:
	if state == null:
		state = SagaState.new()
		state.load_game()
	_setup_movement()
	stage_layer = CanvasLayer.new()
	stage_layer.layer = 30
	add_child(stage_layer)
	stage = Node2D.new()
	stage_layer.add_child(stage)
	ui = StoryUI.new()
	ui.world = self
	add_child(ui)
	var first_region = initial_region if initial_region in REGIONS else "木"
	if "b00" not in state.data.clears and first_region == "木":
		first_region = "序章"
	change_region(first_region)
	if str(state.load_warning) != "":
		ui.toast(str(state.load_warning))

func _setup_movement() -> void:
	var bindings = {"saga_left": [KEY_A, KEY_LEFT], "saga_right": [KEY_D, KEY_RIGHT], "saga_up": [KEY_W, KEY_UP], "saga_down": [KEY_S, KEY_DOWN], "saga_run": [KEY_SHIFT]}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			for key in bindings[action]:
				var event = InputEventKey.new()
				event.physical_keycode = key
				InputMap.action_add_event(action, event)

func _input(event: InputEvent) -> void:
	if battle != null or _leaving:
		return
	if not event is InputEventKey:
		return
	var key = event.physical_keycode
	if key in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SHIFT, KEY_SPACE, KEY_J, KEY_K, KEY_1, KEY_E, KEY_M, KEY_TAB, KEY_ESCAPE]:
		get_viewport().set_input_as_handled()
	if not event.pressed or event.echo:
		return
	if key == KEY_ESCAPE:
		if ui.modal_open:
			ui.close_modal()
		else:
			ui.show_exit()
		return
	if ui.modal_open:
		return
	match key:
		KEY_M:
			open_map()
		KEY_TAB:
			open_atlas()
		KEY_E:
			var nearby = _nearest_actor()
			if not nearby.is_empty():
				if nearby.kind == "boss":
					open_boss(nearby.id)
				elif nearby.kind == "npc":
					open_npc(nearby.id)
				elif nearby.kind == "minion":
					ui.show_minion(nearby.id)

func _physics_process(delta: float) -> void:
	if stage == null or ui == null or battle != null or _leaving:
		return
	elapsed += delta
	if ui.modal_open:
		return
	var direction = Input.get_vector("saga_left", "saga_right", "saga_up", "saga_down")
	var speed = 275.0 if Input.is_action_pressed("saga_run") else 190.0
	player_position += direction * speed * delta
	player_position.x = clampf(player_position.x, WALK_AREA.position.x, WALK_AREA.end.x)
	player_position.y = clampf(player_position.y, WALK_AREA.position.y, WALK_AREA.end.y)
	if direction.length() > 0.01:
		frame_clock += delta * (11.0 if speed > 200 else 8.0)
		if absf(direction.x) > absf(direction.y):
			facing = 2 if direction.x > 0 else 1
		else:
			facing = 0 if direction.y > 0 else 3
	else:
		frame_clock = 0
	if is_instance_valid(player_sprite):
		player_sprite.position = player_position
		player_sprite.z_index = int(player_position.y)
		if hero_textures.size() >= 16:
			player_sprite.texture = hero_textures[facing * 4 + int(frame_clock) % 4]
			player_sprite.offset.y = -player_sprite.texture.get_height() * 0.5 - absf(sin(frame_clock * PI / 2.0)) * 1.4
	var nearby = _nearest_actor()
	var hint = "WASD / 方向键移动 · Shift 奔跑 · M 五域图 · Tab 图鉴 · Esc 菜单"
	if not nearby.is_empty():
		hint = "E · " + ("察看祟门：" if nearby.kind == "boss" else "交谈：") + str(nearby.name) + "    /    点击人物或门签也可交互"
	ui.set_hint(hint)

func _nearest_actor() -> Dictionary:
	var nearest: Dictionary = {}
	var distance = 112.0
	for actor in actors:
		var value = player_position.distance_to(actor.position)
		if value < distance:
			distance = value
			nearest = actor
	return nearest

func change_region(region: String) -> void:
	if battle != null or region not in REGIONS:
		return
	current_region = region
	stage_name = Catalogue.region_name(region)
	ui.close_modal()
	decor = null
	for child in stage.get_children():
		stage.remove_child(child)
		child.queue_free()
	actors.clear()
	ui.clear_actor_buttons()
	var background = Sprite2D.new()
	background.texture = Art.background(region)
	background.centered = false
	background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if background.texture != null:
		background.scale = Vector2(1440.0 / background.texture.get_width(), 900.0 / background.texture.get_height())
	stage.add_child(background)
	_add_region_actors()
	hero_textures = Art.hero_frames(str(state.data.avatar))
	player_position = Vector2(430, 650)
	player_sprite = Sprite2D.new()
	player_sprite.name = "SagaPlayer"
	player_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if not hero_textures.is_empty():
		player_sprite.texture = hero_textures[0]
		player_sprite.offset = Vector2(0, -player_sprite.texture.get_height() * 0.5)
		player_sprite.scale = Vector2.ONE * 94.0 / player_sprite.texture.get_height()
	player_sprite.position = player_position
	player_sprite.z_index = int(player_position.y)
	stage.add_child(player_sprite)
	var name_label = Label.new()
	name_label.text = str(state.data.name)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(-90, -112) / maxf(player_sprite.scale.x, 0.01)
	name_label.size = Vector2(180, 24)
	name_label.scale = Vector2.ONE / maxf(player_sprite.scale.x, 0.01)
	name_label.add_theme_color_override("font_color", Color("fff1cc"))
	name_label.add_theme_color_override("font_outline_color", Color("312e2b"))
	name_label.add_theme_constant_override("outline_size", 5)
	player_sprite.add_child(name_label)
	refresh_home_decor()
	ui.refresh_hud()

func _add_region_actors() -> void:
	var rows = Catalogue.all().filter(func(row): return row.region == current_region)
	var positions = [Vector2(655, 430), Vector2(900, 350), Vector2(1130, 520)]
	if rows.size() == 1:
		positions = [Vector2(925, 440)]
	elif rows.size() == 2:
		positions = [Vector2(780, 400), Vector2(1100, 500)]
	for i in range(rows.size()):
		var row = rows[i]
		var spot = positions[mini(i, positions.size() - 1)]
		var cleared = row.id in state.data.clears
		var locked = state.availability(str(row.id)) != ""
		var sprite = _actor_sprite(Art.boss_texture(str(row.id)), spot, 125)
		sprite.modulate = Color(0.54, 0.59, 0.59, 0.83) if locked else (Color(0.84, 0.96, 0.85) if cleared else Color.WHITE)
		var title = ("○ " if cleared else ("锁 · " if locked else "祟门 · ")) + str(row.name)
		ui.actor_button(title, spot + Vector2(-80, 13), Vector2(160, 35), open_boss.bind(str(row.id)))
		actors.append({"kind":"boss", "id":str(row.id), "name":str(row.name), "position":spot})
	var npc = _regional_npc()
	if not npc.is_empty():
		var spot = Vector2(330, 470)
		_actor_sprite(Art.npc_texture(str(npc.id)), spot, 100)
		ui.actor_button(str(npc.name) + " · 委托", spot + Vector2(-75, 13), Vector2(150, 35), open_npc.bind(str(npc.id)))
		actors.append({"kind":"npc", "id":str(npc.id), "name":str(npc.name), "position":spot})
	var restored = false
	for core in Catalogue.cores():
		if core in state.data.clears and Catalogue.entry(core).region == current_region:
			restored = true
	if restored:
		var residents = Catalogue.minions_for(current_region)
		for i in range(residents.size()):
			var mob = residents[i]
			var spot = Vector2(850 + i * 190, 680)
			var sprite = _actor_sprite(Art.minion_texture(str(mob.id)), spot, 65)
			sprite.modulate = Color(0.91, 1.0, 0.84)
			ui.actor_button(str(mob.name) + " · 已安居", spot + Vector2(-78, 10), Vector2(156, 32), ui.show_minion.bind(str(mob.id)))
			actors.append({"kind":"minion", "id":str(mob.id), "name":str(mob.name), "position":spot})

func _actor_sprite(texture: Texture2D, spot: Vector2, height: float) -> Sprite2D:
	var shadow = Polygon2D.new()
	var points = PackedVector2Array()
	for n in range(16):
		var angle = n * TAU / 16.0
		points.append(Vector2(cos(angle) * height * 0.28, sin(angle) * height * 0.09))
	shadow.polygon = points
	shadow.color = Color(0.12, 0.19, 0.16, 0.3)
	shadow.position = spot
	shadow.z_index = int(spot.y) - 1
	stage.add_child(shadow)
	var sprite = Sprite2D.new()
	sprite.texture = texture
	sprite.position = spot
	sprite.z_index = int(spot.y)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if texture != null:
		sprite.offset.y = -texture.get_height() * 0.5
		sprite.scale = Vector2.ONE * height / texture.get_height()
	stage.add_child(sprite)
	return sprite

func _regional_npc() -> Dictionary:
	for person in Catalogue.people():
		if str(person.region) == current_region:
			return person
	return Catalogue.person("lei")

func refresh_home_decor() -> void:
	if is_instance_valid(decor):
		stage.remove_child(decor)
		decor.queue_free()
	decor = CampDecoration.new()
	decor.buildings = state.data.buildings.duplicate()
	decor.position = Vector2(360, 720)
	decor.z_index = 770
	stage.add_child(decor)
	decor.queue_redraw()
	if ui != null:
		ui.refresh_hud()

func open_map() -> void:
	if battle == null:
		ui.show_map()

func open_atlas(region: String = "") -> void:
	if battle == null:
		ui.show_atlas(region)

func open_npc(id: String) -> void:
	if battle == null:
		ui.show_npc(id)

func open_boss(id: String) -> void:
	if battle == null:
		state.investigate(id)
		ui.show_boss(id)

func enter_boss(id: String) -> void:
	if battle != null or _leaving:
		return
	var begun = state.begin(id)
	if not begun.get("ok", false):
		ui.toast(str(begun.get("message", "尚未开放")))
		return
	encounter_token = str(begun.token)
	encounter_id = id
	ui.close_modal()
	ui.hide()
	battle_layer = CanvasLayer.new()
	battle_layer.layer = 32
	add_child(battle_layer)
	battle = Battle.new()
	battle.host = self
	battle.entry = Catalogue.entry(id)
	battle.snapshot = begun.snapshot
	battle.difficulty = str(state.data.difficulty)
	battle.selected_skill = str(state.data.skill)
	battle.avatar = str(state.data.avatar)
	battle.completed.connect(_battle_completed)
	battle.leave_requested.connect(_battle_left)
	battle.retry_requested.connect(_battle_retry)
	if battle.has_signal("minion_collected"):
		battle.connect("minion_collected", _minion_collected)
	battle_layer.add_child(battle)

func _minion_collected(id: String) -> void:
	state.record_minion(id)

func _battle_completed(won: bool, metrics: Dictionary) -> void:
	if encounter_token.is_empty():
		return
	# Consume the transaction handle before any UI or signal can re-enter.
	var token = encounter_token
	var id = encounter_id
	encounter_token = ""
	for mob_id in metrics.get("collected_minions", []):
		state.record_minion(str(mob_id))
	var result = state.settle(token, id, won, str(state.data.difficulty), metrics)
	_free_battle()
	change_region(current_region)
	ui.show_result(id, won, result)

func _battle_left() -> void:
	if encounter_token != "":
		state.abandon(encounter_token)
	encounter_token = ""
	_free_battle()
	ui.refresh_hud()
	ui.toast("已回到区域。修为与营造材没有损失，随时可以再试。")

func _battle_retry() -> void:
	var id = encounter_id
	_battle_left()
	enter_boss(id)

func _free_battle() -> void:
	battle = null
	if is_instance_valid(battle_layer):
		remove_child(battle_layer)
		battle_layer.queue_free()
	battle_layer = null
	ui.show()

func next_boss(after_id: String) -> String:
	if after_id == "b00":
		return "b01"
	var previous = Catalogue.entry(after_id)
	for row in Catalogue.all():
		if row.region == previous.get("region", "") and row.id not in state.data.clears and state.availability(str(row.id)) == "":
			return str(row.id)
	if state.data.seals.size() == 5 and "b19" not in state.data.clears:
		return "b19"
	return ""

func follow_next(after_id: String) -> void:
	var id = next_boss(after_id)
	if id == "":
		open_map()
	else:
		change_region(str(Catalogue.entry(id).region))
		open_boss(id)

func request_exit() -> void:
	if _leaving:
		return
	_leaving = true
	if encounter_token != "":
		state.abandon(encounter_token)
		encounter_token = ""
	state.save_game()
	if origin_village != null:
		exit_to_village.emit()
	else:
		get_tree().change_scene_to_file("res://scenes/main.tscn")

func _exit_tree() -> void:
	if state != null and encounter_token != "":
		state.abandon(encounter_token)
		encounter_token = ""


