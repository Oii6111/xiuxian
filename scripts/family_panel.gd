extends Control
## Family selection and delegated entry, with exactly two available elder slots.
const Assets = preload("res://scripts/pixel_assets.gd")
const CREAM = Color("f5e8d0")
const GOLD_TEXT = Color("edd096")
const MUTED_TEXT = Color("b7b0a8")
var game: Node
var ui: Control
var editing_id = ""
var form_open = false
var name_input: LineEdit
var age_input: LineEdit
var relation_input: LineEdit
var title_input: LineEdit
var sex_input: OptionButton
var avatar_input: OptionButton
var mode_input: OptionButton
var consent_input: CheckBox
var status_label: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	build()

func style(color: Color = Color("232830"), border: Color = Color("514837")) -> StyleBoxFlat:
	var result = StyleBoxFlat.new()
	result.bg_color = color
	result.border_color = border
	result.set_border_width_all(2)
	result.content_margin_left = 24
	result.content_margin_right = 24
	result.content_margin_top = 20
	result.content_margin_bottom = 20
	return result

func panel_at(rect: Rect2, border: Color = Color("514837")) -> VBoxContainer:
	var panel = PanelContainer.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.add_theme_stylebox_override("panel", style(Color("232830"), border))
	add_child(panel)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	return column

func text(parent: Node, value: String, font_size: int = 18, color: Color = CREAM) -> Label:
	var label = Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func paragraph(parent: Node, value: String, font_size: int = 17, color: Color = MUTED_TEXT) -> Label:
	var label = text(parent, value, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func action(parent: Node, value: String, callback: Callable, primary: bool = false) -> Button:
	var button = Button.new()
	button.text = value
	button.custom_minimum_size.y = 50
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var color = Color("735735") if primary else Color("303640")
		if state == "hover":
			color = color.lightened(0.12)
		if state == "disabled":
			color = Color("303036")
		var look = style(color, Color("a38350") if primary else Color("54565d"))
		look.content_margin_top = 12
		look.content_margin_bottom = 12
		button.add_theme_stylebox_override(state, look)
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", CREAM)
	button.add_theme_color_override("font_disabled_color", Color("797b81"))
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var shade = ColorRect.new()
	shade.color = Color(0.035, 0.04, 0.06, 0.88)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var background = Panel.new()
	background.position = Vector2(100, 45)
	background.size = Vector2(1240, 810)
	background.add_theme_stylebox_override("panel", style(Color("191d25"), Color("a38350")))
	add_child(background)
	var header = panel_at(Rect2(120, 62, 1200, 90))
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	header.add_child(row)
	text(row, "我的家人", 32, GOLD_TEXT)
	var summary = text(row, "%s  ·  %d / 2 位家人" % [game.family.account.name, game.family.members.size()], 18, MUTED_TEXT)
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var back = action(row, "返回家人列表" if form_open else "返回仙村 ×", func():
		if form_open:
			form_open = false
			build()
		else:
			ui.close_modal()
	)
	back.disabled = false
	if form_open:
		build_form()
	else:
		build_members()

func build_members() -> void:
	var own = game.family.owner_state
	var own_bar = panel_at(Rect2(150, 165, 1140, 130), GOLD_TEXT if game.family.active_id == "self" else Color("514837"))
	var own_row = HBoxContainer.new()
	own_row.add_theme_constant_override("separation", 22)
	own_bar.add_child(own_row)
	var portrait = TextureRect.new()
	portrait.texture = Assets.portrait(game.avatar_frames[own.avatar_id][0])
	portrait.custom_minimum_size = Vector2(80, 80)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	own_row.add_child(portrait)
	var own_text = VBoxContainer.new()
	own_text.add_theme_constant_override("separation", 6)
	own_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	own_row.add_child(own_text)
	text(own_text, "我的角色 · 本人", 24, GOLD_TEXT)
	text(own_text, own.player_name + " · " + own.realm(), 18)
	text(own_text, "不占用下方两个家人位置", 16, MUTED_TEXT)
	action(own_row, "进入我的角色", func(): ui.activate_family("self"), true)
	action(own_row, "我的资料", func(): ui.activate_family("self", true))
	action(own_row, "退出 / 换账号", ui.logout_account)
	for i in range(2):
		var member = game.family.members[i] if i < game.family.members.size() else {}
		var selected = not member.is_empty() and member.id == game.family.active_id
		var column = panel_at(Rect2(150 + i * 585, 312, 555, 458), Color("cbaa68") if selected else Color("514837"))
		column.add_theme_constant_override("separation", 8)
		if member.is_empty():
			text(column, "家人位置 %d" % (i + 1), 18, MUTED_TEXT)
			var space = Control.new()
			space.custom_minimum_size.y = 30
			column.add_child(space)
			var plus = text(column, "＋", 70, GOLD_TEXT)
			plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var invitation = text(column, "添加第一位家人" if i == 0 else "添加第二位家人", 27, GOLD_TEXT)
			invitation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			paragraph(column, "为家人建立独立的修仙化身。\n子女可以帮助填写资料、记录习惯并陪伴成长。", 18)
			action(column, "添加家人 · 帮助填写", func(): show_form(""), true).disabled = game.family.load_blocked
			continue
		var state = member.state
		var identity = state.family_identity
		text(column, "正在照顾" if selected else "家人位置 %d" % (i + 1), 18, GOLD_TEXT if selected else MUTED_TEXT)
		var identity_row = HBoxContainer.new()
		identity_row.add_theme_constant_override("separation", 20)
		column.add_child(identity_row)
		var image = TextureRect.new()
		image.texture = Assets.portrait(game.avatar_frames[state.avatar_id][0])
		image.custom_minimum_size = Vector2(90, 110)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		identity_row.add_child(image)
		var details = VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.add_theme_constant_override("separation", 4)
		identity_row.add_child(details)
		text(details, str(identity.get("name", "家人")), 24)
		var relation_label = text(details, str(identity.get("relation", "")) if not str(identity.get("relation", "")).is_empty() else "关系待完善", 18, GOLD_TEXT)
		relation_label.clip_text = true
		relation_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		text(details, state.player_name + " · " + state.realm(), 17)
		var age = int(identity.get("age", 0))
		text(details, ("%d 岁  ·  " % age if age > 0 else "年龄待填写  ·  ") + str(identity.get("sex", "未选择性别")), 16, MUTED_TEXT)
		text(column, "每日记录：" + ("老人微信反馈同步" if state.is_remote() else ("已确认 · 灵气已到账" if state.today() in state.rewarded_days else "待记录")), 18)
		text(column, "灵气 %d    装备 %d 件    首通 %d 关" % [state.equipment.qi, state.equipment.inventory.size(), state.cleared_bosses.size()], 18, GOLD_TEXT)
		var ready = not state.health_profile_id.is_empty()
		var id = str(member.id)
		action(column, "进入仙村" if ready else "代填健康资料", func(): ui.activate_family(id), true)
		var buttons = HBoxContainer.new()
		buttons.add_theme_constant_override("separation", 10)
		column.add_child(buttons)
		action(buttons, "编辑基本资料", func(): show_form(id))
		if ready:
			action(buttons, "补充健康资料", func(): ui.activate_family(id, true))
	var footer = panel_at(Rect2(150, 790, 1140, 50))
	status_label = paragraph(footer, game.family.last_error if not game.family.last_error.is_empty() else "本人角色单独保留；下方两个位置专门用于家人。每个角色的任务、灵气、装备和进度分别保存。", 17, GOLD_TEXT)

func show_form(id: String) -> void:
	editing_id = id
	form_open = true
	build()

func field(parent: Node, label: String, placeholder: String, value: String = "", limit: int = 30) -> LineEdit:
	text(parent, label, 17, MUTED_TEXT)
	var input = LineEdit.new()
	input.text = value
	input.placeholder_text = placeholder
	input.max_length = limit
	input.custom_minimum_size.y = 44
	var normal = style(Color("303640"))
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	var focus = style(Color("333a46"), GOLD_TEXT)
	focus.content_margin_top = 10
	focus.content_margin_bottom = 10
	input.add_theme_stylebox_override("normal", normal)
	input.add_theme_stylebox_override("focus", focus)
	input.add_theme_color_override("font_color", CREAM)
	input.add_theme_color_override("font_placeholder_color", MUTED_TEXT)
	parent.add_child(input)
	return input

func option(parent: Node, label: String, items: Array, index: int) -> OptionButton:
	text(parent, label, 17, MUTED_TEXT)
	var input = OptionButton.new()
	for value in items:
		input.add_item(value)
	input.select(index)
	input.custom_minimum_size.y = 44
	var look = style(Color("303640"))
	look.content_margin_top = 10
	look.content_margin_bottom = 10
	input.add_theme_stylebox_override("normal", look)
	input.add_theme_color_override("font_color", CREAM)
	parent.add_child(input)
	return input

func build_form() -> void:
	var identity = game.family.identity_for(editing_id)
	var left = panel_at(Rect2(150, 180, 700, 640))
	text(left, "添加家人" if editing_id.is_empty() else "编辑家人基本资料", 28, GOLD_TEXT)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	left.add_child(row)
	var names = VBoxContainer.new()
	names.custom_minimum_size.x = 380
	row.add_child(names)
	name_input = field(names, "家人姓名 *", "请输入家人姓名", str(identity.get("name", "")), 10)
	var ages = VBoxContainer.new()
	ages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ages)
	age_input = field(ages, "年龄 *", "1—120", str(int(identity.age)) if int(identity.get("age", 0)) > 0 else "", 3)
	row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	left.add_child(row)
	var sex = VBoxContainer.new()
	sex.custom_minimum_size.x = 200
	row.add_child(sex)
	sex_input = option(sex, "家人性别 *", ["请选择", "男", "女"], ["", "男", "女"].find(str(identity.get("sex", ""))))
	var relations = VBoxContainer.new()
	relations.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(relations)
	relation_input = field(relations, "与我的关系 *", "例如父亲、母亲", str(identity.get("relation", "")))
	row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	left.add_child(row)
	var titles = VBoxContainer.new()
	titles.custom_minimum_size.x = 380
	row.add_child(titles)
	title_input = field(titles, "修仙称号（选填）", "留空将使用家人姓名生成", str(identity.get("title", "")), 10)
	var avatars = VBoxContainer.new()
	avatars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(avatars)
	avatar_input = option(avatars, "修仙形象", ["男修 · 松风", "女修 · 清岚"], 1 if identity.get("avatar", "male") == "female" else 0)
	mode_input = option(left, "本次资料由谁填写", ["子女帮助家人填写", "老人本人填写"], 1 if identity.get("mode", "family") == "self" else 0)
	consent_input = CheckBox.new()
	consent_input.text = "本人同意，或已获得家人同意后帮助填写"
	consent_input.add_theme_color_override("font_color", CREAM)
	consent_input.button_pressed = false
	left.add_child(consent_input)
	status_label = paragraph(left, "基本资料不会发放打卡奖励，也不会修改健康属性。", 16)
	action(left, "保存家人并代填健康资料" if editing_id.is_empty() else "保存基本资料", save_form, true)
	var right = panel_at(Rect2(875, 180, 415, 640))
	text(right, "先认识家人，再开始修行", 25, GOLD_TEXT)
	paragraph(right, "① 填写家人信息\n\n② 上传报告或补充文字\n\n③ 分析后预览属性\n\n④ 确认后进入仙村", 21)
	paragraph(right, "姓名用于辨认家人，修仙称号用于游戏角色。两者分别保存，修改称号不会重置成长。", 18)
	paragraph(right, "每位老人都有独立的灵气钱包与行囊。创建、编辑档案不产生每日灵气奖励。", 18, GOLD_TEXT)

func save_form() -> void:
	var payload = {"name": name_input.text, "age": age_input.text, "sex": sex_input.get_item_text(sex_input.selected) if sex_input.selected > 0 else "", "relation": relation_input.text, "title": title_input.text, "avatar": "female" if avatar_input.selected == 1 else "male", "mode": "self" if mode_input.selected == 1 else "family", "consent": consent_input.button_pressed}
	var result: Dictionary
	if game.family.is_remote():
		var core = get_tree().root.get_node("GameKernel")
		result = await game.family.remote_add_member(payload, core) if editing_id.is_empty() else await game.family.remote_update_member(editing_id, payload, core)
	else:
		result = game.family.add_member(payload) if editing_id.is_empty() else game.family.update_member(editing_id, payload)
	if not result.ok:
		status_label.text = result.message
		return
	if editing_id.is_empty():
		ui.activate_family(result.id, true)
	else:
		game.sync_avatar_from_state()
		ui.refresh()
		form_open = false
		build()
		ui.toast(result.message)
