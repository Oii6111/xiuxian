extends Control

var game: Node3D
var title_font: SystemFont
var body_font: SystemFont
var map_panel: PanelContainer
var site_panel: PanelContainer
var site_label: Label
var toast_label: Label
var hint: Label
var map_open := false
var toast_time := 0.0
const GREEN = Color("35594e")
const PALE = Color("f3eedf")
const MUTED = Color("778775")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_font = SystemFont.new()
	title_font.font_names = PackedStringArray(["KaiTi", "STKaiti", "Microsoft YaHei"])
	body_font = SystemFont.new()
	body_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])
	var header := VBoxContainer.new()
	header.position = Vector2(42, 30)
	header.add_theme_constant_override("separation", 7)
	add_child(header)
	var eyebrow := text("云 海 之 上   /   修 行 初 见", 12, MUTED)
	header.add_child(eyebrow)
	header.add_child(text(game.TITLES[game.scene_index], 37, GREEN, true))
	header.add_child(text("一庭松风，半卷闲云。" if game.scene_index == 0 else "五境试炼  /  " + game.REALMS[game.scene_index], 13, MUTED))
	var tag := PanelContainer.new()
	tag.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tag.position = Vector2(-228, 34)
	tag.size = Vector2(190, 53)
	tag.add_theme_stylebox_override("panel", panel_style())
	add_child(tag)
	var tag_text := text("松风  ·  炼气初行", 17, GREEN, true)
	tag_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_child(tag_text)
	var side := VBoxContainer.new()
	side.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	side.position = Vector2(-198, -110)
	side.add_theme_constant_override("separation", 12)
	add_child(side)
	for spec in [["五境图", "M", "map"], ["观衣冠", "V", "close"], ["归洞府", "Home", "home"]]:
		var button := make_button(spec[0] + "  ·  " + spec[1])
		button.custom_minimum_size = Vector2(162, 39)
		button.add_theme_font_size_override("font_size", 16)
		var action: String = spec[2]
		button.pressed.connect(func():
			if action == "map": toggle_map()
			elif action == "home": game.travel(0)
			else:
				game.close_view = not game.close_view
				game.zoom_target = 6.2 if game.close_view else (31.0 if game.scene_index == 0 else 22.0)
		)
		side.add_child(button)
	var footer := PanelContainer.new()
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	footer.position = Vector2(35, -67)
	footer.size = Vector2(640, 39)
	footer.add_theme_stylebox_override("panel", panel_style())
	add_child(footer)
	footer.add_child(text("W A S D  漫游     Shift  疾行     滚轮  远近     E  查看     Esc  收起", 12, GREEN))
	var edition := text("青绿水墨 · 场景与角色预览", 12, MUTED)
	edition.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	edition.position = Vector2(-250, -47)
	add_child(edition)
	hint = text("", 17, GREEN, true)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-240, -125)
	hint.size = Vector2(480, 35)
	add_child(hint)
	_build_map()
	site_panel = PanelContainer.new()
	site_panel.position = Vector2(40, 175)
	site_panel.custom_minimum_size = Vector2(290, 140)
	site_panel.add_theme_stylebox_override("panel", panel_style())
	site_panel.visible = false
	add_child(site_panel)
	site_label = text("", 16, GREEN, true)
	site_label.custom_minimum_size.x = 280
	site_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	site_panel.add_child(site_label)
	toast_label = text("", 15, GREEN)
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toast_label.position = Vector2(-230, 45)
	toast_label.size = Vector2(460, 40)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(toast_label)

func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.96, 0.94, 0.88, 0.92)
	style.border_color = Color("b5bea8")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 17
	style.content_margin_right = 17
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func text(content: String, size: int, color: Color, calligraphy := false) -> Label:
	var item := Label.new()
	item.text = content
	item.add_theme_font_override("font", title_font if calligraphy else body_font)
	item.add_theme_font_size_override("font_size", size)
	item.add_theme_color_override("font_color", color)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return item

func make_button(content: String) -> Button:
	var button := Button.new()
	button.text = content
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", title_font)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", GREEN)
	button.add_theme_color_override("font_hover_color", Color("244e43"))
	var normal := panel_style()
	button.add_theme_stylebox_override("normal", normal)
	var hover := panel_style()
	hover.bg_color = Color("dce5cf")
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	return button

func _build_map() -> void:
	map_panel = PanelContainer.new()
	map_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	map_panel.position = Vector2(-285, -225)
	map_panel.size = Vector2(570, 450)
	map_panel.add_theme_stylebox_override("panel", panel_style())
	map_panel.visible = false
	add_child(map_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	map_panel.add_child(column)
	column.add_child(text("五境云游图", 31, GREEN, true))
	column.add_child(text("选择一处仙境，前往漫游。", 13, MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	column.add_child(grid)
	var descriptions := ["松风小筑  /  家族主岛", "炼气  /  竹石山门", "筑基  /  碧潭玄龟", "结丹  /  丹枫狐境", "元婴  /  逐雷高台", "化神  /  五相天阙"]
	for i in range(6):
		var button := make_button(descriptions[i])
		button.custom_minimum_size = Vector2(245, 64)
		var destination := i
		button.pressed.connect(func(): game.travel(destination))
		grid.add_child(button)
	column.add_child(text("本次开放场景漫游；战斗与养成将在后续加入。", 12, MUTED))
	var close_button := make_button("收起地图  ·  M / Esc")
	close_button.pressed.connect(dismiss)
	column.add_child(close_button)

func toggle_map() -> void:
	map_open = not map_open
	map_panel.visible = map_open
	game.player.input_enabled = not map_open
	if map_open: site_panel.visible = false

func dismiss() -> void:
	map_open = false
	map_panel.visible = false
	site_panel.visible = false
	game.player.input_enabled = true

func update_site(site: String) -> void:
	hint.text = "E  ·  " + ("前往五境" if site == "五境试炼" else site) if not site.is_empty() else ""
	site_panel.visible = false

func show_site(site: String) -> void:
	var descriptions := {"家族洞府": "家族洞府\n\n竹影、暖灯与一盏清茶。\n这里将安放家族修行与角色养成。", "灵根测试": "灵根测试\n\n五色灵石，映照修行之路。\n后续在这里查看与培养五项属性。", "成就碑林": "成就碑林\n\n把每一次坚持刻进山中。\n这里将展示成就与家族故事。"}
	site_label.text = descriptions.get(site, site)
	site_panel.visible = true

func toast(message: String) -> void:
	toast_label.text = message
	toast_time = 3.0

func _process(delta: float) -> void:
	if toast_time > 0:
		toast_time -= delta
		if toast_time <= 0: toast_label.text = ""
