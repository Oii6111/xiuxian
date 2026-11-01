extends Node2D

const State = preload("res://scripts/game_state.gd")
const FamilyRoster = preload("res://scripts/family_roster.gd")
const Player = preload("res://scripts/pixel_player.gd")
const Interface = preload("res://scripts/gameplay_interface.gd")
const Assets = preload("res://scripts/pixel_assets.gd")
const Effects = preload("res://scripts/pixel_effects.gd")
@export var interface_override: Script
const SPAWN = Vector2(681, 565)
var state = State.new()
var family = FamilyRoster.new()
var account_api: Node
var account_ready = false
var guest_mode = false
var companion_api: Node
var companion_actor: Node2D
var companion_tasks: Node
var account_cache_root_override = ""
var account_legacy_source_override = ""
var pending_account_roster: RefCounted
var player: CharacterBody2D
var ui: Control
var font: SystemFont
var title_font: SystemFont
var portrait: Texture2D
var walk_textures: Array[Texture2D] = []
var nearest: String = ""
var sites: Array[Dictionary] = []
var roads: Array[PackedVector2Array] = []
var terrain_blockers: Array[PackedVector2Array] = []
var terrain_crossings: Array[PackedVector2Array] = []
var navigation = AStar2D.new()
var debug_roads: bool = false
var elapsed: float = 0
var npc_sprites: Array[Sprite2D] = []
var avatar_frames: Dictionary = {}
var player_name_label: Label

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	font = SystemFont.new()
	# 网页没有系统中文字体，回退到随包的 Noto Sans SC（OFL）。
	font.fallbacks = [preload("res://assets/fonts/NotoSansSC-Regular.otf")]
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])
	title_font = SystemFont.new()
	# 网页没有系统中文字体，回退到随包的 Noto Sans SC（OFL）。
	title_font.fallbacks = [preload("res://assets/fonts/NotoSansSC-Regular.otf")]
	title_font.font_names = PackedStringArray(["KaiTi", "STKaiti", "SimSun"])
	_setup_inputs()
	family.persist_enabled = false
	family.save_file_override = state.save_file_override
	if not state.health_profile_id.is_empty() or state.profile_created:
		family.adopt_legacy(state)
	else:
		state = family.owner_state
	account_ready = "--preview" in OS.get_cmdline_user_args() or "--skip-intro" in OS.get_cmdline_user_args()
	account_api = Node.new()
	account_api.set_script(preload("res://scripts/net/backend_session.gd"))
	add_child(account_api)
	account_api.realtime.snapshot_received.connect(_on_backend_snapshot)
	companion_api = Node.new()
	companion_api.set_script(preload("res://scripts/companion_client.gd"))
	companion_api.game = self
	add_child(companion_api)
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
	ui.set_script(interface_override if interface_override != null else Interface)
	ui.game = self
	layer.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	companion_actor = Node2D.new()
	companion_actor.set_script(preload("res://scripts/companion_actor.gd"))
	companion_actor.game = self
	add_child(companion_actor)
	companion_tasks = Node.new()
	companion_tasks.set_script(preload("res://scripts/companion_task_client.gd"))
	companion_tasks.game = self
	add_child(companion_tasks)
	_handle_capture.call_deferred()

## C 推送新的权威快照时刷新当前账号全部角色；切换账号期间的旧快照不会写入新账号。
func _on_backend_snapshot(_snapshot: Dictionary) -> void:
	if not account_ready or not family.is_remote() or not account_api.is_authenticated():
		return
	var synced = await account_api.sync_family(family)
	if synced.ok and is_instance_valid(ui):
		state = family.active_state()
		ui.refresh()

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
	avatar_frames["male"] = Assets.frames("res://assets/pixel/cultivator-walk.png", 4, 4, 0.2)
	avatar_frames["female"] = Assets.frames("res://assets/gameplay/female-walk-v2.png", 4, 4, 0.2)
	walk_textures = avatar_frames[state.avatar_id]
	portrait = Assets.portrait(walk_textures[0])


func apply_avatar(id: String, nickname: String) -> void:
	var before_avatar = state.avatar_id
	var before_name = state.player_name
	var before_identity = state.family_identity.duplicate(true)
	var before_created = state.profile_created
	state.choose_avatar(id, nickname)
	if not state.save_game():
		state.avatar_id = before_avatar
		state.player_name = before_name
		state.family_identity = before_identity
		state.profile_created = before_created
		ui.toast("形象保存失败，已保留原来的角色。")
	sync_avatar_from_state()
	ui.refresh()

func start_guest_mode() -> void:
	# Guest play is a local, non-persistent roster. It never reuses an account session.
	account_api.reset_session()
	family.dispose()
	family = FamilyRoster.new()
	family.persist_enabled = false
	family.account = {"id": "guest-local", "name": "游客样例"}
	family.reset_owner({"display_name": "游客样例", "avatar": "male"})
	var created = family.add_member({"name": "张建国", "age": "68", "sex": "男", "relation": "爸爸", "title": "张建国的化身", "avatar": "male", "mode": "family", "consent": true})
	guest_mode = true
	account_ready = true
	if created.ok:
		state = family.state_for(created.id)
	else:
		state = family.owner_state
	state.persist_enabled = false
	# A guest gets one free ten-pull so the complete onboarding loop is playable
	# immediately after the sample health profile is confirmed.
	state.equipment.starter_ten_pulls = 1
	companion_api.reset_session()
	companion_tasks.clear_state()
	sync_avatar_from_state()
	ui.refresh()

func reset_guest_mode() -> void:
	guest_mode = false
	account_ready = false
	family.dispose()
	family = FamilyRoster.new()
	family.persist_enabled = false
	state = family.owner_state
	sync_avatar_from_state()
	ui.refresh()
func sync_avatar_from_state() -> void:
	walk_textures = avatar_frames[state.avatar_id]
	portrait = Assets.portrait(walk_textures[0])
	player.walk_textures = walk_textures
	player.sprite.texture = walk_textures[0]
	player.facing = 0
	player_name_label.text = state.player_name

func _exit_tree() -> void:
	family.dispose()
	if pending_account_roster != null:
		pending_account_roster.dispose()

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
	_build_terrain_blockers()
	var points = [SPAWN, Vector2(530, 521), Vector2(402, 480), Vector2(717, 434), Vector2(752, 366), Vector2(794, 316), Vector2(819, 256), Vector2(857, 206), Vector2(781, 600), Vector2(850, 632), Vector2(939, 668), Vector2(1024, 698), Vector2(1144, 665), Vector2(1160, 605), Vector2(1193, 560), Vector2(1222, 509), Vector2(1256, 456), Vector2(1289, 405), Vector2(275, 503)]
	for i in range(points.size()):
		navigation.add_point(i, points[i])
	for edge in [[0, 1], [1, 2], [0, 3], [3, 4], [4, 5], [5, 6], [6, 7], [0, 8], [8, 9], [9, 10], [10, 11], [11, 12], [12, 13], [13, 14], [14, 15], [15, 16], [16, 17], [2, 18]]:
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

func _build_terrain_blockers() -> void:
	# These are the visible water basins in the 1440x900 game canvas.
	# The bridge deck is a separate crossing so its stone surface remains walkable.
	terrain_blockers = [
		PackedVector2Array([
			Vector2(520, 720), Vector2(600, 710), Vector2(700, 720), Vector2(760, 760),
			Vector2(800, 830), Vector2(830, 900), Vector2(480, 900), Vector2(480, 820)
		]),
		PackedVector2Array([
			Vector2(1040, 730), Vector2(1120, 730), Vector2(1195, 760), Vector2(1210, 810),
			Vector2(1320, 850), Vector2(1440, 840), Vector2(1440, 900), Vector2(800, 900), Vector2(800, 820)
		])
	]
	terrain_crossings = [
		_corridor([Vector2(690, 650), Vector2(760, 662), Vector2(840, 685), Vector2(920, 710), Vector2(1000, 738), Vector2(1060, 720), Vector2(1100, 685)], 22)
	]
	roads.append_array(terrain_crossings)

func _terrain_contains(polygons: Array[PackedVector2Array], point: Vector2) -> bool:
	for polygon in polygons:
		if Geometry2D.is_point_in_polygon(point, polygon):
			return true
	return false

func _point_walkable(point: Vector2) -> bool:
	if _terrain_contains(terrain_blockers, point) and not _terrain_contains(terrain_crossings, point):
		return false
	for polygon in roads:
		if Geometry2D.is_point_in_polygon(point, polygon):
			return true
	return false

func can_walk(point: Vector2) -> bool:
	# Check the player's footprint, not only its center, so the sprite cannot straddle a bank or roof.
	for offset in [Vector2.ZERO, Vector2(9, 0), Vector2(-9, 0), Vector2(0, 9), Vector2(0, -9)]:
		if not _point_walkable(point + offset):
			return false
	return true

func _build_sites() -> void:
	sites = [
		{"id": "home", "title": "健康档案", "position": Vector2(402, 480), "node": 2, "label": Vector2(340, 287)},
		{"id": "battle", "title": "演武台", "position": Vector2(857, 206), "node": 7, "label": Vector2(934, 110)},
		{"id": "boss", "title": "属性试炼", "position": Vector2(1289, 405), "node": 17, "label": Vector2(1366, 264)},
		{"id": "records", "title": "天机碑", "position": Vector2(1144, 665), "node": 12, "label": Vector2(1170, 487)},
		{"id": "gacha", "title": "聚宝阁", "position": Vector2(275, 503), "node": 18, "label": Vector2(155, 451)}
	]
	var treasure_stand = Node2D.new()
	treasure_stand.name = "TreasureStand"
	treasure_stand.set_script(preload("res://scripts/treasure_stand.gd"))
	treasure_stand.position = Vector2(275, 485)
	treasure_stand.z_index = 480
	add_child(treasure_stand)
	for site in sites:
		var vertical = site.id not in ["home", "gacha"]
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
		for polygon in terrain_blockers:
			draw_colored_polygon(polygon, Color(1.0, 0.2, 0.2, 0.28))
		for polygon in terrain_crossings:
			draw_colored_polygon(polygon, Color(1.0, 0.85, 0.15, 0.35))

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
			if "--preview" in args and ("--show-family" in args or "--show-family-form" in args or "--show-family-health" in args):
				var father = family.add_member({"name": "张建国", "age": 68, "sex": "男", "relation": "父亲", "title": "青松真人", "avatar": "male", "mode": "family", "consent": true})
				var father_state = family.state_for(father.id)
				father_state.apply_health_profile(father_state.HealthProfile.mock(40, 1))
				father_state.record_task("planned_record", true)
				father_state.complete_boss("b00", {"time": 36})
				family.add_member({"name": "李秀兰", "age": 65, "sex": "女", "relation": "母亲", "title": "云霞仙子", "avatar": "female", "mode": "family", "consent": true})
				family.select_member(father.id)
				state = father_state
				sync_avatar_from_state()
				ui.refresh()
				ui.open_family()
				if "--show-family-form" in args:
					ui.family_panel.show_form(father.id)
				if "--show-family-health" in args:
					ui.activate_family(family.members[1].id, true)
			if "--show-login" in args:
				ui.open_login()
			if "--show-register" in args:
				ui.open_login()
				ui.account_panel.register_mode = true
				ui.account_panel.build()
			if "--show-family-empty" in args:
				ui.open_family()
			if "--show-start" in args:
				ui.show_start()
			if "--show-record" in args:
				ui.open_record()
			if "--show-recovery" in args:
				state.begin_recovery(true)
				ui.open_recovery()
			if "--show-health-entry" in args:
				ui.open_health_entry()
			if "--show-profile" in args:
				ui.open_home()
			if "--show-stages" in args or "--show-corridor" in args:
				ui.open_boss()
				for option in args:
					if option.begins_with("--corridor-index="):
						ui.corridor.focus_boss(int(option.trim_prefix("--corridor-index=")))
			if "--show-arena" in args:
				var requested_boss = "b00"
				for option in args:
					if option.begins_with("--boss-id="):
						requested_boss = option.trim_prefix("--boss-id=")
				ui.start_corridor_boss(requested_boss)
			if "--show-unlocked" in args:
				state.complete_stage("attack", 10)
				state.complete_stage("attack", 20)
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
			if "--show-skills" in args:
				ui.start_boss(false)
				ui.combat.hero.position = Vector2(835, 610)
				ui.combat.rules.phase = "windup"
				ui.combat.rules.target_position = Vector2(835, 610)
				ui.combat.use_skill(2)
				ui.combat.use_skill(0)
			if "--show-heal" in args:
				ui.start_boss(false)
				ui.combat.rules.hp -= 180
				ui.combat.use_skill(3)
			if "--show-treasure" in args or "--show-treasure-results" in args or "--show-equipment" in args:
				if state.health_profile_id.is_empty():
					state.apply_health_profile(state.HealthProfile.mock(40, 1))
				if "--preview" in args and ("--show-treasure-results" in args or "--show-equipment" in args):
					state.equipment.qi = 700
					state.equipment_rng.seed = 20261031
					state.draw_equipment(10, "preview-ten")
					state.equip_item(state.equipment.inventory[0].id)
				ui.open_treasure("bag" if "--show-equipment" in args else "wish")
				if "--show-equipment" in args:
					ui.treasure.selected_id = state.equipment.inventory[0].id
					ui.treasure.build()
			if "--show-companion-choice" in args:
				ui.open_companion(true)
			if "--show-companion-map" in args or "--show-companion-chat" in args:
				family.choose_companion("gourd_dragon", "团团")
				companion_actor.refresh_pet()
				ui.refresh()
				if "--show-companion-chat" in args:
					ui.open_companion()
					ui.companion_panel.send_message("下一步做什么？")
					await get_tree().process_frame
			if "--show-reward" in args:
				ui.open_reward("家人的坚持，化作你的守护。\n修为 +10  ·  灵印 +1")
			await get_tree().process_frame
			await capture(arg.trim_prefix("--capture="))
			get_tree().quit()



