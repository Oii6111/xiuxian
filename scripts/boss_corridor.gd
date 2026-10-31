extends Control
## An actual lateral 2D hall: independent avatar, manual camera and twenty portals.
const Catalogue = preload("res://scripts/trial_catalogue.gd")
const Assets = preload("res://scripts/pixel_assets.gd")
const FIRST_GATE = 470.0
const GATE_SPACING = 480.0
const HALL_WIDTH = FIRST_GATE + 19 * GATE_SPACING + 380.0
var game: Node2D
var ui: Control
var world: Node2D
var hero: Sprite2D
var player_position = Vector2(180, 715)
var camera_x: float = 0
var browsing: bool = false
var clock: float = 0
var frame_clock: float = 0
var facing: int = 2
var nearest_index: int = 0
var portal_buttons: Array[Button] = []
var status_labels: Array[Label] = []
var jump_buttons: Array[Button] = []
var progress_label: Label
var focus_label: Label
var player_shadow: Polygon2D

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	player_position = ui.corridor_position
	camera_x = ui.corridor_camera
	browsing = true
	world = Node2D.new()
	add_child(world)
	var texture = Assets.texture("res://assets/gameplay/trial-corridor.png")
	for i in range(int(ceil(HALL_WIDTH / 1440.0))):
		var tile = Sprite2D.new()
		tile.texture = texture
		tile.centered = false
		tile.position.x = i * 1440
		tile.scale = Vector2(1440, 900) / texture.get_size()
		world.add_child(tile)
	for entry in Catalogue.all():
		_build_gate(entry)
	_build_player()
	_build_hud()
	refresh()
	_update_camera()

func gate_x(index: int) -> float:
	return FIRST_GATE + index * GATE_SPACING

func _text(parent: Node, text: String, rect: Rect2, font_size: int, color: Color, heading: bool = false) -> Label:
	var label = ui.label_into(parent, text, font_size, color)
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_outline_color", Color("342922"))
	label.add_theme_constant_override("outline_size", 3)
	if heading:
		label.add_theme_font_override("font", game.title_font)
	return label

func _build_gate(entry: Dictionary) -> void:
	var index: int = entry.index
	var center = gate_x(index)
	var accent = Color(entry.color)
	var panel = Panel.new()
	panel.position = Vector2(center - 163, 262)
	panel.size = Vector2(326, 333)
	var frame = StyleBoxFlat.new()
	frame.bg_color = Color("262b28")
	frame.border_color = Color("aa8855")
	frame.set_border_width_all(9)
	frame.shadow_color = Color(0.08, 0.06, 0.04, 0.65)
	frame.shadow_size = 9
	panel.add_theme_stylebox_override("panel", frame)
	world.add_child(panel)
	var portal_window = Control.new()
	portal_window.position = Vector2(10, 10)
	portal_window.size = Vector2(306, 313)
	portal_window.clip_contents = true
	portal_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(portal_window)
	var landscape = TextureRect.new()
	landscape.texture = Assets.texture(entry.background)
	landscape.position = Vector2.ZERO
	landscape.size = Vector2(306, 313)
	landscape.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	landscape.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	landscape.modulate = Color(0.7, 0.7, 0.7)
	landscape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	landscape.clip_contents = true
	portal_window.add_child(landscape)
	var top = Panel.new()
	top.position = Vector2(center - 179, 198)
	top.size = Vector2(358, 61)
	var plaque = StyleBoxFlat.new()
	plaque.bg_color = Color("342922")
	plaque.border_color = accent.darkened(0.15)
	plaque.set_border_width_all(3)
	top.add_theme_stylebox_override("panel", plaque)
	world.add_child(top)
	_text(top, "%02d · %s" % [index + 1, entry.name], Rect2(0, 5, 358, 44), 32, Color("f8dfaa"), true)
	var body = Sprite2D.new()
	body.texture = Catalogue.boss_texture(entry.id)
	body.position = Vector2(center, 550)
	body.offset.y = -body.texture.get_height() * 0.5
	body.scale = Vector2.ONE * 226 / body.texture.get_height()
	world.add_child(body)
	var enter = Button.new()
	enter.position = Vector2(center - 165, 263)
	enter.size = Vector2(330, 334)
	enter.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	enter.tooltip_text = entry.name + " · " + entry.arena + "\n点击进入战斗，建议培养 " + str(entry.tier) + " 档"
	var transparent = StyleBoxFlat.new()
	transparent.bg_color = Color(0, 0, 0, 0)
	var hover = transparent.duplicate()
	hover.border_color = accent.lightened(0.2)
	hover.set_border_width_all(5)
	hover.bg_color = Color(1, 0.92, 0.7, 0.08)
	enter.add_theme_stylebox_override("normal", transparent)
	enter.add_theme_stylebox_override("hover", hover)
	enter.add_theme_stylebox_override("pressed", hover)
	var id: String = entry.id
	enter.pressed.connect(func(): enter_boss(id))
	world.add_child(enter)
	portal_buttons.append(enter)
	_text(world, entry.arena, Rect2(center - 150, 277, 300, 30), 18, Color("ffe8c1"))
	var status = _text(world, "", Rect2(center - 150, 561, 300, 30), 17, Color("e8d6ae"))
	status_labels.append(status)


func _build_player() -> void:
	player_shadow = Polygon2D.new()
	var points = PackedVector2Array()
	for i in range(20):
		var a = i * TAU / 20
		points.append(Vector2(cos(a) * 29, sin(a) * 9))
	player_shadow.polygon = points
	player_shadow.color = Color(0.05, 0.05, 0.04, 0.45)
	player_shadow.z_index = 100
	world.add_child(player_shadow)
	hero = Sprite2D.new()
	hero.texture = game.walk_textures[8]
	hero.offset.y = -hero.texture.get_height() * 0.5
	hero.scale = Vector2.ONE * 115 / hero.texture.get_height()
	hero.z_index = 101
	world.add_child(hero)

func _build_hud() -> void:
	var header = ui.card(Rect2(20, 18, 1400, 137), self, Color("342922"))
	header.add_theme_constant_override("separation", 6)
	var row = HBoxContainer.new()
	header.add_child(row)
	var title = ui.label_into(row, "问道长廊 · 二十祟兽", 32, Color("f3d19a"))
	title.add_theme_font_override("font", game.title_font)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.button(row, "前往下一位", focus_next_boss)
	ui.button(row, "返回仙村 ×", ui.close_modal)
	progress_label = ui.label_into(header, "", 17, Color("eee0c4"))
	var regions = HBoxContainer.new()
	regions.add_theme_constant_override("separation", 8)
	header.add_child(regions)
	for item in [["初门", 0], ["苍梧 · 木", 1], ["丹霞 · 火", 4], ["稷野 · 土", 7], ["白羽 · 金", 10], ["玄泽 · 水", 13], ["归衡", 16]]:
		var index: int = item[1]
		var b = ui.button(regions, item[0], func(): focus_boss(index))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 35
		for state_name in ["normal", "hover", "pressed"]:
			var compact = b.get_theme_stylebox(state_name).duplicate()
			compact.content_margin_top = 4
			compact.content_margin_bottom = 4
			b.add_theme_stylebox_override(state_name, compact)
	var footer = ui.card(Rect2(20, 797, 1400, 87), self, Color("342922"))
	footer.add_theme_constant_override("separation", 5)
	focus_label = ui.label_into(footer, "", 17, Color("ffe4ae"))
	ui.label_into(footer, "A / D 行走  ·  W / S 调整站位  ·  Shift 加速  ·  E 进入最近的门  ·  滚轮浏览长廊  ·  点击 Boss 直接开战", 15, Color("d7c5a8"))
	var numbers = HBoxContainer.new()
	numbers.position = Vector2(175, 739)
	numbers.add_theme_constant_override("separation", 7)
	add_child(numbers)
	for i in range(20):
		var index: int = i
		var b = ui.button(numbers, "%02d" % (i + 1), func(): focus_boss(index))
		b.custom_minimum_size = Vector2(47, 38)
		b.add_theme_font_size_override("font_size", 15)
		for state_name in ["normal", "hover", "pressed", "disabled"]:
			var compact = b.get_theme_stylebox(state_name).duplicate()
			compact.content_margin_left = 8
			compact.content_margin_right = 8
			compact.content_margin_top = 5
			compact.content_margin_bottom = 5
			b.add_theme_stylebox_override(state_name, compact)
		jump_buttons.append(b)

func refresh() -> void:
	for entry in Catalogue.all():
		var cleared = game.state.boss_cleared(entry.id)
		status_labels[int(entry.index)].text = ("✓ 已通关" if cleared else "尚未挑战") + "  ·  建议 %d 档" % entry.tier
		var best: Dictionary = game.state.best_boss_record(entry.id)
		if not best.is_empty(): status_labels[int(entry.index)].text += " · 最快 %.1f秒" % float(best.time)
		jump_buttons[int(entry.index)].text = "%02d" % (entry.index + 1)
	progress_label.text = "%s  ·  %s  ·  首通 %d / 20  ·  关卡依次增强 · 每扇门通往独立战场" % [game.state.player_name, game.state.realm(), game.state.cleared_bosses.size()]

func focus_boss(index: int) -> void:
	var selected = clampi(index, 0, 19)
	player_position.x = maxf(140, gate_x(selected) - 185)
	camera_x = clampf(gate_x(selected) - 620, 0, HALL_WIDTH - 1440)
	browsing = true
	_update_camera()

func focus_next_boss() -> void:
	for row in Catalogue.all():
		if not game.state.boss_cleared(row.id):
			focus_boss(row.index)
			return
	focus_boss(19)

func enter_boss(id: String) -> void:
	ui.start_corridor_boss(id)

func _update_camera() -> void:
	camera_x = clampf(camera_x, 0, HALL_WIDTH - 1440)
	world.position.x = -camera_x
	hero.position = player_position
	player_shadow.position = player_position
	nearest_index = clampi(roundi((player_position.x - FIRST_GATE) / GATE_SPACING), 0, 19)
	var entry = Catalogue.at(nearest_index)
	focus_label.text = "附近：%02d · %s  /  %s    %s" % [nearest_index + 1, entry.name, entry.arena, "按 E 进入" if absf(player_position.x - gate_x(nearest_index)) < 220 else "继续沿长廊前行"]

func _process(delta: float) -> void:
	clock += delta
	var direction = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if direction.length() > 0:
		browsing = false
		player_position += direction * (490 if Input.is_action_pressed("sprint") else 290) * delta
		player_position.x = clampf(player_position.x, 120, HALL_WIDTH - 120)
		player_position.y = clampf(player_position.y, 688, 729)
		frame_clock += delta * 9
		if absf(direction.x) >= absf(direction.y):
			facing = 2 if direction.x > 0 else 1
		else:
			facing = 0 if direction.y > 0 else 3
	else:
		frame_clock = 0
	hero.texture = game.walk_textures[facing * 4 + int(frame_clock) % 4]
	hero.offset.y = -hero.texture.get_height() * 0.5
	hero.scale = Vector2.ONE * 115 / hero.texture.get_height()
	if not browsing:
		camera_x = move_toward(camera_x, clampf(player_position.x - 480, 0, HALL_WIDTH - 1440), delta * 850)
	_update_camera()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			browsing = true
			camera_x += 280 * (1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
			_update_camera()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			ui.close_modal()
		elif event.keycode == KEY_E and absf(player_position.x - gate_x(nearest_index)) < 220:
			enter_boss(Catalogue.at(nearest_index).id)
		else:
			return
		get_viewport().set_input_as_handled()
