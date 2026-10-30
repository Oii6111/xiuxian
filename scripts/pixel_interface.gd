extends "res://scripts/interface.gd"

const BROWN = Color("422e24")
const PARCHMENT = Color("efdbb5")
const BRASS = Color("b5884a")
const WOOD = Color("342922")
var counters: Array[Label] = []
var hud_avatar_image: TextureRect
var hud_name_label: Label

class FrameTrim extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
	func _draw() -> void:
		var r = Rect2(Vector2(5, 5), size - Vector2(10, 10))
		draw_rect(r, Color("b78c51"), false, 1)
		draw_line(Vector2(9, 8), Vector2(size.x - 9, 8), Color(1, 0.88, 0.61, 0.3), 1)
		for p in [Vector2(5, 5), Vector2(size.x - 5, 5), Vector2(5, size.y - 5), Vector2(size.x - 5, size.y - 5)]:
			draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), Color("6b4a2d"))
			draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color("eac27a"))

class ResourceIcon extends Control:
	var kind: int = 0
	func _draw() -> void:
		if kind == 0:
			draw_colored_polygon(PackedVector2Array([Vector2(15, 1), Vector2(13, 11), Vector2(20, 7), Vector2(24, 17), Vector2(21, 25), Vector2(8, 26), Vector2(4, 19), Vector2(8, 9), Vector2(10, 16)]), Color("4b94e7"))
			draw_colored_polygon(PackedVector2Array([Vector2(14, 10), Vector2(18, 17), Vector2(16, 23), Vector2(10, 22), Vector2(9, 18)]), Color("b4f4ff"))
		elif kind == 1:
			draw_colored_polygon(PackedVector2Array([Vector2(14, 1), Vector2(24, 8), Vector2(19, 24), Vector2(8, 27), Vector2(4, 17), Vector2(8, 5)]), Color("459ac6"))
			draw_colored_polygon(PackedVector2Array([Vector2(14, 3), Vector2(18, 8), Vector2(13, 23), Vector2(7, 19), Vector2(10, 7)]), Color("81dce7"))
		elif kind == 2:
			draw_rect(Rect2(6, 1, 17, 27), Color("674024"))
			draw_rect(Rect2(8, 3, 13, 23), Color("f1c46b"))
			for i in range(4):
				draw_line(Vector2(11, 7 + i * 4), Vector2(18 - i % 2 * 3, 7 + i * 4), Color("9f4d29"), 2)
		else:
			draw_rect(Rect2(4, 4, 22, 22), Color("bf9257"))
			draw_rect(Rect2(7, 7, 16, 16), Color("e8cc8c"))
			draw_rect(Rect2(12, 10, 5, 10), Color("98704a"))

func _warm(color: Color) -> Color:
	if color == INK or color == Color("345f52"):
		return BROWN
	if color == MUTED or color == Color("607566") or color == Color("6f8878"):
		return Color("80694d")
	if color == JADE or color == Color("3a6b59"):
		return Color("715035")
	if color == GOLD:
		return Color("9f6e32")
	if color == PAPER:
		return PARCHMENT
	if color == Color("eef0e2") or color == Color("eef0df"):
		return Color("e4cca0")
	return color

func style(color: Color = PAPER, _border: Color = Color("dce1ce"), _radius: int = 18) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = _warm(color)
	s.border_color = BRASS
	s.set_border_width_all(3)
	s.set_corner_radius_all(0)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	s.shadow_color = Color(0.12, 0.08, 0.06, 0.42)
	s.shadow_size = 5
	s.shadow_offset = Vector2(2, 3)
	return s

func card(rect: Rect2, parent: Node = self, color: Color = PAPER) -> VBoxContainer:
	var content = super.card(rect, parent, color)
	var trim = FrameTrim.new()
	# Node2D keeps the decorative border out of the PanelContainer's content layout.
	var overlay = Node2D.new()
	var panel = content.get_parent()
	panel.add_child(overlay)
	overlay.add_child(trim)
	trim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trim.size = panel.size
	panel.resized.connect(func(): trim.size = panel.size)
	return content

func label_into(parent: Node, text: String, size: int = 17, color: Color = INK) -> Label:
	return super.label_into(parent, text, size, _warm(color))

func button(parent: Node, text: String, callback: Callable, primary: bool = false) -> Button:
	var b = super.button(parent, text, callback, primary)
	b.add_theme_stylebox_override("normal", style(Color("725037") if primary else Color("e4cda3")))
	b.add_theme_stylebox_override("hover", style(Color("90643e") if primary else Color("f6e2b7")))
	b.add_theme_stylebox_override("pressed", style(Color("4b3428")))
	b.add_theme_stylebox_override("disabled", style(Color("d1c0a0")))
	b.add_theme_color_override("font_color", Color("fff0cb") if primary else BROWN)
	b.add_theme_color_override("font_hover_color", Color("fff0cb") if primary else BROWN)
	b.add_theme_color_override("font_pressed_color", Color("fff0cb"))
	b.add_theme_color_override("font_disabled_color", Color("87765a"))
	return b

func _build_hud() -> void:
	var title = card(Rect2(16, 14, 294, 65), self, WOOD)
	var name_label = label_into(title, "家族修真录", 34, Color("f3d19a"))
	name_label.add_theme_font_override("font", game.title_font)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var resources = card(Rect2(326, 14, 655, 62), self, Color("302b28"))
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 17)
	resources.add_child(row)
	for i in range(4):
		var group = HBoxContainer.new()
		group.add_theme_constant_override("separation", 5)
		group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(group)
		var icon = ResourceIcon.new()
		icon.kind = i
		icon.custom_minimum_size = Vector2(29, 28)
		group.add_child(icon)
		counters.append(label_into(group, "", 19, Color("fff0d0")))
	var profile = card(Rect2(16, 94, 276, 151))
	var body = HBoxContainer.new()
	body.add_theme_constant_override("separation", 13)
	profile.add_child(body)
	var portrait_box = PanelContainer.new()
	var portrait_style = style(Color("d2bd97"))
	portrait_style.content_margin_left = 3
	portrait_style.content_margin_right = 3
	portrait_style.content_margin_top = 3
	portrait_style.content_margin_bottom = 3
	portrait_box.add_theme_stylebox_override("panel", portrait_style)
	portrait_box.custom_minimum_size = Vector2(85, 115)
	body.add_child(portrait_box)
	var image = TextureRect.new()
	hud_avatar_image = image
	image.texture = game.portrait
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait_box.add_child(image)
	var details = VBoxContainer.new()
	details.add_theme_constant_override("separation", 8)
	body.add_child(details)
	var character_name = label_into(details, game.state.player_name, 22)
	hud_name_label = character_name
	character_name.clip_text = true
	character_name.custom_minimum_size.x = 124
	character_name.add_theme_font_override("font", game.title_font)
	realm_label = label_into(details, "", 17, Color("eee2c1"))
	var realm_style = style(Color("697f81"))
	realm_style.content_margin_top = 2
	realm_style.content_margin_bottom = 2
	realm_style.content_margin_left = 8
	realm_style.content_margin_right = 8
	realm_label.add_theme_stylebox_override("normal", realm_style)
	day_label = label_into(details, "", 16)
	label_into(details, "家人：青松真人", 12, MUTED)
	var tasks = card(Rect2(1160, 14, 264, 217))
	var task_title = label_into(tasks, "今日修行", 25)
	task_title.add_theme_font_override("font", game.title_font)
	task_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	daily_label = label_into(tasks, "", 16)
	button(tasks, "记下一次坚持  +", open_record, true)
	label_into(tasks, "模拟记录 · 确认后领取奖励", 12, MUTED)
	var utility = HBoxContainer.new()
	utility.position = Vector2(16, 258)
	utility.add_theme_constant_override("separation", 8)
	add_child(utility)
	button(utility, "风格画册", open_gallery)
	button(utility, "重置演示", reset_demo)
	var tips = card(Rect2(16, 818, 452, 63), self, WOOD)
	tips.add_theme_constant_override("separation", 4)
	var tip_style = style(WOOD)
	tip_style.content_margin_top = 8
	tip_style.content_margin_bottom = 8
	tips.get_parent().add_theme_stylebox_override("panel", tip_style)
	label_into(tips, "W A S D  移动   ·   Shift 奔跑   ·   E 交互", 16, Color("fae6bd"))
	label_into(tips, "点击地点自动前往 · 点击村民交谈 · Esc 关闭", 12, Color("c2aa88"))
	var navigation = HBoxContainer.new()
	navigation.position = Vector2(677, 831)
	navigation.add_theme_constant_override("separation", 8)
	add_child(navigation)
	for entry in [["家族洞府", "home"], ["渡劫试炼", "battle"], ["世界首领", "boss"], ["天机碑", "records"]]:
		var id: String = entry[1]
		button(navigation, entry[0], func(): game.travel_to(id))
	hint = label_into(self, "", 17, Color("ffe7a4"))
	hint.position = Vector2(470, 771)
	hint.size = Vector2(500, 34)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_outline_color", Color("382e25"))
	hint.add_theme_constant_override("outline_size", 6)
	toast_label = label_into(self, "", 18, Color("fff0cf"))
	toast_label.position = Vector2(391, 91)
	toast_label.size = Vector2(658, 46)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_label.add_theme_stylebox_override("normal", style(WOOD))
	toast_label.hide()
	var footer = label_into(self, "本地像素试玩 · 健康记录与世界首领均为模拟", 11, Color("f4e5ca"))
	footer.position = Vector2(1135, 883)
	footer.add_theme_color_override("font_outline_color", Color("2e2c23"))
	footer.add_theme_constant_override("outline_size", 4)

func refresh() -> void:
	var state = game.state
	var values = [state.cultivation, state.qi, state.charms, state.seals]
	for i in range(counters.size()):
		counters[i].text = ["修为", "灵气", "守护符", "灵印"][i] + " " + str(values[i])
	realm_label.text = state.realm()
	day_label.text = "修行 %d 天" % state.days
	daily_label.text = "✓  个人计划已确认\n✓  今日奖励已领取" if state.today() in state.rewarded_days else "□  按计划完成记录\n□  确认后领取奖励"

func update_proximity(id: String) -> void:
	var names = {"home": "家族洞府", "battle": "渡劫台", "boss": "世界首领", "records": "天机碑"}
	hint.text = "E  进入「%s」" % names[id] if names.has(id) else "走近建筑按 E，或点击下方地点前往"

func reset_demo() -> void:
	close_modal()
	game.state.reset_demo()
	game.player.position = game.SPAWN
	game.player.route.clear()
	game.player.destination_site = ""
	refresh()
	toast("已恢复初始修行资源")

func close_modal() -> void:
	super.close_modal()
	if is_instance_valid(game.player):
		game.player.route.clear()
		game.player.destination_site = ""

func begin_modal(title: String, subtitle: String = "") -> VBoxContainer:
	var content = super.begin_modal(title, subtitle)
	modal.color = Color(0.12, 0.08, 0.06, 0.65)
	return content

func open_npc(index: int) -> void:
	var names = ["云游药师", "花间同修", "守碑书生"]
	var content = begin_modal(names[index], "仙村小叙 · 今日也有值得珍藏的小事")
	var image = TextureRect.new()
	image.texture = game.npc_sprites[index].texture
	image.custom_minimum_size = Vector2(110, 150)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content.add_child(image)
	var words = ["修行贵在适合自己，也贵在长久。\n家人依个人计划完成的一次记录，确认后便可化为你的守护。", "家宅门前的花，每天只长一点点。\n一同坚持的日子也是如此，慢慢就有了值得纪念的模样。", "碑上记的是家族共同的坚持。\n你可以在这里看游戏贡献与成就，不必拿家人的健康相互比较。"]
	paragraph(content, words[index], 21, INK)
	line(content)
	button(content, ["查看今日计划", "看看家族洞府", "阅读家族修行簿"][index], [open_record, open_home, open_records][index], true)
