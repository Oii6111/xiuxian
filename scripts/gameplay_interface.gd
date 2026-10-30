extends "res://scripts/pixel_interface.gd"

const Assets = preload("res://scripts/pixel_assets.gd")
const Combat = preload("res://scripts/combat_view.gd")
var start_screen: ColorRect
var selected_avatar: String = "male"
var avatar_buttons: Array[Button] = []
var nickname_input: LineEdit
var combat: Control
var menu_hidden_controls: Array[Control] = []

func _ready() -> void:
	super._ready()
	var menu_button = button(self, "形象 / 开始界面", show_start)
	menu_button.position = Vector2(16, 324)
	menu_button.size.x = 216
	var args = OS.get_cmdline_user_args()
	if "--skip-intro" not in args and "--preview" not in args:
		show_start.call_deferred()

func refresh() -> void:
	super.refresh()
	if is_instance_valid(hud_avatar_image):
		hud_avatar_image.texture = game.portrait
		hud_name_label.text = game.state.player_name
	var medication = "已确认" if game.state.task_done("medication") else "待记录"
	if not game.state.longterm_enabled or not game.state.medication_required:
		medication = "无用药计划"
	var recovery = {"not_started": "未开启", "active": "进行中", "recovered": "已确认结束"}.get(game.state.recovery_status, "未开启")
	daily_label.text = "服药：%s\n计划：%s\n恢复篇章：%s" % [medication, "已确认" if game.state.task_done("planned_record") else "待记录", recovery]

func close_modal() -> void:
	if is_instance_valid(start_screen):
		return
	if is_instance_valid(combat):
		combat.set_process(false)
		combat.set_process_input(false)
		combat.queue_free()
	combat = null
	super.close_modal()

func _check(parent: Node, text: String, checked: bool = false) -> CheckBox:
	var check = CheckBox.new()
	check.text = text
	check.button_pressed = checked
	check.add_theme_color_override("font_color", BROWN)
	check.add_theme_color_override("font_hover_color", Color("8d5f32"))
	check.add_theme_color_override("font_pressed_color", BROWN)
	check.add_theme_font_size_override("font_size", 16)
	parent.add_child(check)
	return check

func _dialog(title: String, subtitle: String) -> VBoxContainer:
	close_modal()
	modal_open = true
	game.player.blocked = true
	modal = ColorRect.new()
	modal.color = Color(0.12, 0.08, 0.06, 0.65)
	add_child(modal)
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var content = card(Rect2(270, 112, 900, 686), modal)
	var row = HBoxContainer.new()
	content.add_child(row)
	var title_label = label_into(row, title, 29)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(row, "关闭 ×", close_modal)
	paragraph(content, subtitle, 16)
	line(content)
	return content

func show_start() -> void:
	if is_instance_valid(start_screen):
		return
	close_modal()
	menu_hidden_controls.clear()
	for child in get_children():
		if child is Control and child.visible and not child.is_queued_for_deletion():
			menu_hidden_controls.append(child)
			child.hide()
	start_screen = ColorRect.new()
	start_screen.color = Color(0.08, 0.09, 0.1, 0.67)
	add_child(start_screen)
	start_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_open = true
	game.player.blocked = true
	game.player.route.clear()
	selected_avatar = game.state.avatar_id
	var header = card(Rect2(425, 53, 590, 102), start_screen, WOOD)
	var title = label_into(header, "家族修真录", 46, Color("f3d19a"))
	title.add_theme_font_override("font", game.title_font)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var subtitle = label_into(start_screen, "选择你的守护者，与家人一同修行", 23, Color("fff0c6"))
	subtitle.position = Vector2(445, 176)
	subtitle.size.x = 550
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	avatar_buttons.clear()
	for i in range(2):
		var id = "male" if i == 0 else "female"
		var candidate = button(start_screen, "", func(): select_avatar(id))
		candidate.position = Vector2(412 + i * 335, 243)
		candidate.size = Vector2(281, 350)
		var image = Sprite2D.new()
		image.texture = game.avatar_frames[id][0]
		image.position = Vector2(140, 275)
		image.offset.y = -image.texture.get_height() * 0.5
		image.scale = Vector2.ONE * 233 / image.texture.get_height()
		candidate.add_child(image)
		var name_label = label_into(candidate, "男修 · 云行" if i == 0 else "女修 · 清岚", 24)
		name_label.position = Vector2(12, 290)
		name_label.size.x = 257
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		avatar_buttons.append(candidate)
	var prompt = label_into(start_screen, "你的昵称", 21, Color("f4e4c1"))
	prompt.position = Vector2(444, 625)
	nickname_input = LineEdit.new()
	nickname_input.position = Vector2(573, 618)
	nickname_input.size = Vector2(422, 49)
	nickname_input.text = game.state.player_name
	nickname_input.max_length = 10
	nickname_input.add_theme_stylebox_override("normal", style(PARCHMENT))
	nickname_input.add_theme_stylebox_override("focus", style(Color("f6e5bd")))
	nickname_input.add_theme_color_override("font_color", BROWN)
	nickname_input.add_theme_color_override("caret_color", BROWN)
	start_screen.add_child(nickname_input)
	var start = button(start_screen, "保存形象并进入" if game.state.profile_created else "开始修行", start_selected, true)
	start.position = Vector2(510, 711)
	start.size = Vector2(420, 68)
	if game.state.profile_created:
		var resume = button(start_screen, "继续上次修行  →", continue_game)
		resume.position = Vector2(1163, 23)
		resume.size.x = 252
	var note = label_into(start_screen, "你操作的是年轻守护者；家人拥有独立的修真化身。", 16, Color("d9c6a7"))
	note.position = Vector2(420, 812)
	note.size.x = 600
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	select_avatar(selected_avatar)

func select_avatar(id: String) -> void:
	selected_avatar = "female" if id == "female" else "male"
	for i in range(avatar_buttons.size()):
		var chosen = (i == 1) == (selected_avatar == "female")
		var frame = style(Color("f0dbaf") if chosen else Color("cbb994"))
		frame.border_color = Color("f4c65f") if chosen else Color("8f724d")
		frame.set_border_width_all(5 if chosen else 2)
		avatar_buttons[i].add_theme_stylebox_override("normal", frame)

func start_selected() -> void:
	game.apply_avatar(selected_avatar, nickname_input.text)
	continue_game()

func continue_game() -> void:
	if is_instance_valid(start_screen):
		start_screen.queue_free()
	start_screen = null
	for item in menu_hidden_controls:
		if is_instance_valid(item):
			item.show()
	menu_hidden_controls.clear()
	modal_open = false
	game.player.blocked = false
	refresh()
	toast("欢迎回到仙村，" + game.state.player_name)

func open_record() -> void:
	var state = game.state
	var content = _dialog("每日修行 · 家人健康计划", "青松真人（父亲）  ·  " + state.today() + "  ·  以下为本地模拟记录")
	var consent = _check(content, "我已了解这是模拟记录，并由家属确认完成及同意用于家族游戏")
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	content.add_child(row)
	var portrait_column = VBoxContainer.new()
	portrait_column.custom_minimum_size.x = 215
	row.add_child(portrait_column)
	var elder_image = TextureRect.new()
	elder_image.texture = Assets.texture("res://assets/gameplay/elder-meditating.png")
	elder_image.custom_minimum_size = Vector2(215, 230)
	elder_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	elder_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait_column.add_child(elder_image)
	label_into(portrait_column, "家属确认，一同坚持", 18)
	var tasks = VBoxContainer.new()
	tasks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tasks.add_theme_constant_override("separation", 12)
	row.add_child(tasks)
	label_into(tasks, "长期管理 · 按个人计划记录", 23)
	var medication_due = state.longterm_enabled and state.medication_required
	label_into(tasks, "按医嘱用药    " + ("✓ 今日已确认" if state.task_done("medication") else ("待家属确认" if medication_due else "当前无用药计划")), 19)
	var medication = button(tasks, "确认今日服药记录", func(): confirm_task("medication", consent.button_pressed), true)
	line(tasks)
	label_into(tasks, "个人计划记录    " + ("✓ 今日已确认" if state.task_done("planned_record") else "待家属确认"), 19)
	var record = button(tasks, "确认今日计划记录", func(): confirm_task("planned_record", consent.button_pressed))
	content.move_child(consent, content.get_child_count() - 1)
	medication.disabled = true
	record.disabled = true
	consent.toggled.connect(func(checked: bool):
		medication.disabled = not checked or not medication_due or state.task_done("medication")
		record.disabled = not checked or state.task_done("planned_record")
	)
	paragraph(content, "每项任务每天只记录一次；两项共用每日一份主行为奖励。漏记不扣历史修为。", 15)
	var actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	content.add_child(actions)
	button(actions, "管理个人计划", open_plan_settings)
	button(actions, "阶段恢复篇章", open_recovery)
	button(actions, "查看家族修行簿", open_records)
	paragraph(content, "这里不识别真实服药，不给出药名或剂量；计划由家人按既有安排设置。", 13)

func confirm_task(task: String, consent: bool) -> void:
	var result = game.state.record_task(task, consent)
	if not result.ok:
		toast(result.message)
		return
	game.state.save_game()
	refresh()
	if result.rewarded:
		open_reward(result.message)
	else:
		open_record()
		toast("记录已保存 · 今日奖励已领取")

func open_plan_settings() -> void:
	var content = _dialog("个人计划设置", "只配置演示任务，不生成医疗建议。")
	paragraph(content, "长期管理与阶段恢复可以同时存在。没有用药计划的家人，可关闭服药任务。", 21, BROWN)
	var longterm = _check(content, "启用长期健康管理", game.state.longterm_enabled)
	var medication = _check(content, "个人既有计划包含每日服药记录（演示）", game.state.medication_required)
	line(content)
	button(content, "保存计划设置", func():
		game.state.longterm_enabled = longterm.button_pressed
		game.state.medication_required = medication.button_pressed and longterm.button_pressed
		game.state.save_game()
		refresh()
		open_record()
	, true)
	button(content, "查看阶段恢复篇章", open_recovery)

func open_recovery() -> void:
	var content = _dialog("阶段恢复 · 渡劫篇章", "长辈的恢复记录与年轻人的游戏试炼分别确认。")
	var status = game.state.recovery_status
	if status == "not_started":
		label_into(content, "为一次阶段恢复，开启一段守护", 26)
		paragraph(content, "家属可以在这里主动开启模拟恢复篇章。已有的长期管理计划继续保留。\n你将在渡劫台守护打坐老者，选择功法抵挡三轮天雷。", 21, BROWN)
		var confirmed = _check(content, "家属确认：在本次演示中开启阶段恢复篇章")
		var begin = button(content, "开启篇章", func():
			game.state.begin_recovery(confirmed.button_pressed)
			game.state.save_game()
			refresh()
			open_recovery()
		, true)
		begin.disabled = true
		confirmed.toggled.connect(func(value: bool): begin.disabled = not value)
	else:
		label_into(content, "篇章进行中" if status == "active" else "篇章已由家属确认结束", 26)
		paragraph(content, "游戏试炼：" + ("已完成" if game.state.trial_cleared else "可前往渡劫台挑战") + "\n长期管理：" + ("仍在进行" if game.state.longterm_enabled else "未启用"), 21, BROWN)
		button(content, "进入老者打坐 · 天雷试炼", start_battle, true)
		if status == "active":
			line(content)
			var source = _check(content, "演示：已获得可靠来源的恢复确认，并由家属核实")
			var finish = button(content, "单独确认恢复 · 结束篇章", func():
				game.state.confirm_recovery(source.button_pressed, source.button_pressed)
				game.state.save_game()
				refresh()
				open_recovery()
			)
			finish.disabled = true
			source.toggled.connect(func(value: bool): finish.disabled = not value)
	paragraph(content, "打赢雷劫只完成游戏挑战，不会自动把现实状态改成康复。", 15)

func open_battle() -> void:
	var content = _dialog("渡劫台 · 天雷守护", "长辈打坐修行，你以功法和守护符抵挡三轮天雷。")
	var image = TextureRect.new()
	image.texture = Assets.texture("res://assets/gameplay/elder-meditating.png")
	image.custom_minimum_size = Vector2(200, 180)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content.add_child(image)
	paragraph(content, "雷诀：5 灵气，消解 90 雷劫余势。\n镇心诀：3 灵气，消解 60 余势并获得 100 护盾。\n守护符：1 张，消解 70 余势并挡下本轮天雷。", 20, BROWN)
	button(content, "进入打坐天雷试炼", start_battle, true)
	if game.state.qi < 15:
		button(content, "演示补给 · 灵气补至 15", func():
			game.state.qi = 15
			game.state.save_game()
			refresh()
			open_battle()
		)
	button(content, "查看 / 开启阶段恢复篇章", open_recovery)
	paragraph(content, "无需新增健康记录也能参加普通试炼。中途离开保留已消耗资源。", 14)

func start_battle() -> void:
	_open_combat("tribulation")

func open_boss() -> void:
	game.state.refresh_boss_day()
	var content = _dialog("世界首领 · 云海妖龙", "本地实时挑战：妖龙会蓄力、预警、吐息和受击。")
	label_into(content, "看见攻击，选择你的应对", 26)
	paragraph(content, "WASD 移动，J 挥剑，K 护盾，空格闪避。\n红色范围出现后，可以移开，或把握时机展开护盾。", 21, BROWN)
	line(content)
	label_into(content, "今日出战 %d / 3    累计贡献 %d" % [game.state.boss_attempts, game.state.contribution], 22)
	paragraph(content, "进入战场即使用一次出战机会。伤害会实时记为本地贡献。\n普通攻击不消耗健康资源；可选守护符仅为首击增加 20 伤害。", 18)
	var normal = button(content, "普通出战 · 不消耗守护符", func(): start_boss(false), true)
	var support = button(content, "带上守护符 · 消耗 1 张", func(): start_boss(true))
	normal.disabled = game.state.boss_attempts >= 3
	support.disabled = game.state.boss_attempts >= 3 or game.state.charms <= 0
	paragraph(content, "暂未连接多人服务器，共享战况和其他玩家不在本次演示范围内。", 14)

func start_boss(use_support: bool = false) -> void:
	var result = game.state.begin_boss(use_support)
	if not result.ok:
		toast(result.message)
		return
	game.state.save_game()
	_open_combat("boss", result.support_damage)

func _open_combat(kind: String, bonus: int = 0) -> void:
	close_modal()
	modal_open = true
	game.player.blocked = true
	combat = Control.new()
	combat.set_script(Combat)
	combat.game = game
	combat.ui = self
	combat.mode = kind
	combat.support = bonus
	add_child(combat)
	combat.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	refresh()
