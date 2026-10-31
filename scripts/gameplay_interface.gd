extends "res://scripts/pixel_interface.gd"

const Assets = preload("res://scripts/pixel_assets.gd")
const TrialCatalogue = preload("res://scripts/trial_catalogue.gd")
const Combat = preload("res://scripts/combat_view.gd")
var start_screen: ColorRect
var selected_avatar: String = "male"
var avatar_buttons: Array[Button] = []
var nickname_input: LineEdit
var combat: Control
var corridor: Control
var corridor_position = Vector2(180, 715)
var corridor_camera: float = 0
var menu_hidden_controls: Array[Control] = []
var profile_file_dialog: FileDialog
var health_entry: Control
var treasure: Control
var family_panel: Control
var account_panel: Control
var return_to_health_entry = false
var companion_panel: Control
var companion_button: Button

func _ready() -> void:
	super._ready()
	game.account_api.completed.connect(on_account_result)
	game.account_api.progress.connect(on_account_progress)
	var menu_button = button(self, "我的家人 / 切换角色", open_family)
	menu_button.position = Vector2(16, 324)
	menu_button.size.x = 276
	var profile_button = button(self, "健康档案 / 五项属性", open_home, true)
	profile_button.position = Vector2(16, 382)
	profile_button.size.x = 276
	companion_button = button(self, "选择你的灵宠  →", open_companion)
	companion_button.position = Vector2(16, 440)
	companion_button.size = Vector2(276, 59)
	companion_button.expand_icon = true
	companion_button.add_theme_constant_override("icon_max_width", 39)
	refresh_companion_button()
	var args = OS.get_cmdline_user_args()
	if "--skip-intro" not in args and "--preview" not in args:
		open_game_entry.call_deferred()

func refresh() -> void:
	super.refresh()
	refresh_companion_button()
	if is_instance_valid(hud_avatar_image):
		hud_avatar_image.texture = game.portrait
		hud_name_label.text = game.state.player_name
		game.player_name_label.text = game.state.player_name
	var medication = "已确认" if game.state.task_done("medication") else "待记录"
	if not game.state.longterm_enabled or not game.state.medication_required:
		medication = "无用药计划"
	var recovery = {"not_started": "未开启", "active": "进行中", "recovered": "已确认结束"}.get(game.state.recovery_status, "未开启")
	daily_label.text = "服药：%s\n计划：%s\n恢复篇章：%s" % [medication, "已确认" if game.state.task_done("planned_record") else "待记录", recovery]

func refresh_companion_button() -> void:
	if not is_instance_valid(companion_button):
		return
	var catalogue = preload("res://scripts/companion_catalogue.gd")
	var pet = game.family.companion
	var chosen = catalogue.valid(str(pet.id)) and game.account_ready
	companion_button.text = "灵宠相伴 · " + catalogue.nickname(pet) if chosen else "选择你的灵宠  →"
	companion_button.icon = catalogue.texture(pet.id) if chosen else null

func open_companion(choose: bool = false) -> void:
	if require_family() or not can_change_family():
		return
	close_modal()
	modal_open = true
	game.player.blocked = true
	game.player.route.clear()
	companion_panel = Control.new()
	companion_panel.set_script(preload("res://scripts/companion_panel.gd"))
	companion_panel.game = game
	companion_panel.ui = self
	companion_panel.choose_mode = choose
	add_child(companion_panel)

func close_modal(force: bool = false) -> void:
	if is_instance_valid(account_panel) and not game.account_ready and not force:
		return
	if is_instance_valid(account_panel):
		account_panel.clear_passwords()
		account_panel.queue_free()
	account_panel = null
	if is_instance_valid(start_screen):
		return
	if is_instance_valid(companion_panel):
		companion_panel.shutdown()
		companion_panel.queue_free()
	companion_panel = null
	if is_instance_valid(health_entry):
		health_entry.shutdown()
		health_entry.queue_free()
	health_entry = null
	if is_instance_valid(treasure):
		treasure.finish_reveal()
		treasure.queue_free()
	treasure = null
	if is_instance_valid(family_panel):
		family_panel.queue_free()
	family_panel = null
	if is_instance_valid(corridor):
		corridor_position = corridor.player_position
		corridor_camera = corridor.camera_x
		corridor.set_process(false)
		corridor.set_process_input(false)
		corridor.queue_free()
	corridor = null
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
	if not game.state.family_member_id.is_empty():
		subtitle = ("本人角色：" if game.state.family_member_id == "self" else "当前家人：") + game.state.member_label() + "  ·  " + subtitle
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

func open_game_entry() -> void:
	open_login()

func show_start() -> void:
	if is_instance_valid(start_screen):
		return
	return_to_health_entry = is_instance_valid(health_entry)
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
		var name_label = label_into(candidate, "男修 · 松风" if i == 0 else "女修 · 清岚", 24)
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
	var note = label_into(start_screen, "为当前家人选择修仙形象；家人姓名与角色称号分别保存。", 16, Color("d9c6a7"))
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
	var needs_state_creation = return_to_health_entry or game.state.health_profile_id == ""
	return_to_health_entry = false
	game.apply_avatar(selected_avatar, nickname_input.text)
	continue_game()
	if needs_state_creation:
		open_health_entry()

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
	if return_to_health_entry:
		return_to_health_entry = false
		open_health_entry()
		return
	toast("欢迎回到仙村，" + game.state.player_name)

func open_record() -> void:
	if require_family():
		return
	var state = game.state
	var content = _dialog("每日修行 · 家人健康计划", state.member_label() + "  ·  " + state.today() + "  ·  以下为本地模拟记录")
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
	paragraph(content, "每项每天只记录一次；两项共用每日奖励：修为 +10、灵印 +1、灵气 +100。七天可积攒一次十连，漏记不清零。", 15)
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

func open_health_entry() -> void:
	close_modal()
	modal_open = true
	game.player.blocked = true
	game.player.route.clear()
	health_entry = Control.new()
	health_entry.set_script(load("res://scripts/health_entry_panel.gd"))
	health_entry.game = game
	health_entry.ui = self
	add_child(health_entry)

func open_home() -> void:
	if require_family():
		return
	var state = game.state
	var content = _dialog(state.player_name + "档案 · 健康与修行", "健康档案形成五项属性；新的评估结果会更新下一场战斗的角色能力。")
	content.add_theme_constant_override("separation", 8)
	var columns = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	content.add_child(columns)
	var left = VBoxContainer.new()
	left.custom_minimum_size.x = 370
	left.add_theme_constant_override("separation", 8)
	columns.add_child(left)
	label_into(left, state.player_name + "  ·  " + state.realm(), 25)
	label_into(left, "初始战斗属性 · 已确认" if not state.health_baseline.is_empty() else "五项健康属性 / 0—100", 17)
	for key in state.ATTRIBUTE_KEYS:
		var row = HBoxContainer.new()
		left.add_child(row)
		var name_label = label_into(row, state.ATTRIBUTE_LABELS[key], 19)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label_into(row, ("%d HP" if key == "life" else "%d") % state.health_attributes[key] if not state.health_baseline.is_empty() else "%d / 100" % state.health_attributes[key], 19)
		var bar = ProgressBar.new()
		bar.custom_minimum_size = Vector2(360, 10)
		bar.show_percentage = false
		bar.max_value = maxf(100, float(state.health_attributes[key]))
		bar.value = state.health_attributes[key]
		left.add_child(bar)
	var stats = state.battle_stats()
	line(left)
	paragraph(left, "含装备的战斗属性\n生命上限 %d    普攻伤害 %d\n灵力上限 %d    体力上限 %d\n云罡护盾 %d    伤害减免 %d%%" % [stats.max_hp, stats.attack, stats.max_mp, stats.max_stamina, stats.shield, roundi((1.0 - stats.damage_multiplier) * 100)], 17, BROWN)
	var right = VBoxContainer.new()
	right.custom_minimum_size.x = 420
	right.add_theme_constant_override("separation", 12)
	columns.add_child(right)
	label_into(right, "档案来源", 23)
	paragraph(right, state.health_source + (" · 模拟" if state.health_simulated else " · 外部评估档案"), 17, BROWN)
	button(right, "补充报告 · 重新生成属性" if not state.health_baseline.is_empty() else "上传健康报告 · 生成初始属性", open_health_entry, true)
	if not state.health_baseline.is_empty():
		paragraph(right, "这份初始档案已锁定。可补充报告后确认新档案，原有通关和技能解锁会保留。", 17)
		paragraph(right, "守护准备度 %d / 100" % state.health_baseline.readiness, 16)
	else:
		button(right, "导入已评估档案（JSON）", choose_profile_file, true)
		label_into(right, "选择一份模拟初始档案", 18)
		var presets = HBoxContainer.new()
		right.add_child(presets)
		for score in [20, 40, 60]:
			var value: int = score
			var preset = button(presets, "攻击 %d" % score, func(): use_mock_profile(value))
			preset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button(right, "模拟健康改善 · 五项各 +10", improve_mock_profile)
	paragraph(right, "更新档案不清空已通关记录。战斗受伤、技能消耗也不会修改这五项属性。", 16)
	line(right)
	label_into(right, "技能解锁  %d / 4" % (4 if state.heal_unlocked() else 3), 21)
	paragraph(right, "听风剑诀 · 踏云步 · 云罡护体\n" + ("饕餮归元 · 已解锁" if state.heal_unlocked() else "饕餮归元 · 首通两个不同关卡解锁"), 16, BROWN)
	line(content)
	var actions = HBoxContainer.new()
	content.add_child(actions)
	button(actions, "进入属性闯关", open_boss, true)
	button(actions, "前往演武台", open_battle)
	button(actions, "记录今日计划", open_record)
	button(actions, "行囊与装备", func(): open_treasure("bag"))

func use_mock_profile(score: int) -> void:
	var payload = game.state.HealthProfile.mock(score, game.state.health_revision + 1)
	payload.attributes.life = mini(100, score + 5)
	payload.attributes.defense = maxi(0, score - 5)
	payload.attributes.spirit = mini(100, score + 10)
	apply_profile(payload)

func improve_mock_profile() -> void:
	var payload = game.state.HealthProfile.mock(40, game.state.health_revision + 1)
	for key in game.state.ATTRIBUTE_KEYS:
		payload.attributes[key] = mini(100, int(game.state.health_attributes[key]) + 10)
	payload.source = "模拟健康改善"
	apply_profile(payload)

func apply_profile(payload: Dictionary) -> void:
	var result = game.state.save_health_profile(payload)
	if not result.ok:
		toast(result.message)
		return
	refresh()
	open_home()
	toast(result.message)

func choose_profile_file() -> void:
	if is_instance_valid(profile_file_dialog):
		profile_file_dialog.queue_free()
	profile_file_dialog = FileDialog.new()
	profile_file_dialog.title = "导入健康属性档案"
	profile_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	profile_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	profile_file_dialog.filters = PackedStringArray(["*.json ; 健康属性档案"])
	add_child(profile_file_dialog)
	profile_file_dialog.file_selected.connect(func(path: String):
		var payload = JSON.parse_string(FileAccess.get_file_as_string(path))
		profile_file_dialog.queue_free()
		if not payload is Dictionary:
			toast("无法读取档案，请选择有效的 JSON 属性档案。")
			return
		apply_profile(payload)
	)
	profile_file_dialog.canceled.connect(profile_file_dialog.queue_free)
	profile_file_dialog.popup_centered(Vector2i(900, 620))

func open_battle() -> void:
	var content = _dialog("演武台 · 四式初习", "练习沿用当前属性，可自由重试，不结算闯关首通。")
	label_into(content, "普攻回灵，踏云回气，四式相辅", 27)
	paragraph(content, "普攻 [J]：靠近目标命中后，恢复 5 灵力。\n听风剑诀 [1]：18 灵力，剑气穿过路径上的目标。\n踏云步 [2 / 空格]：24 体力，快速位移并短暂闪避。\n云罡护体 [3 / K]：24 灵力，护盾强度随防御提升。\n饕餮归元 [4 / R]：45 灵力，短暂吐纳后恢复生命。", 20, BROWN)
	line(content)
	paragraph(content, "体力会自动恢复。归元吐纳时移动变慢，受到实际伤害会中断。每次进入训练或挑战，生命、灵力与体力重新补满。", 18)
	paragraph(content, "饕餮归元：" + ("已解锁" if game.state.heal_unlocked() else "首通两个不同关卡后解锁"), 18)
	button(content, "开始技能练习", start_battle, true)
	button(content, "查看五项属性", open_home)

func start_battle() -> void:
	_open_combat("practice")

func open_boss() -> void:
	if require_family():
		return
	close_modal()
	modal_open = true
	game.player.blocked = true
	game.player.route.clear()
	corridor = load("res://scenes/boss_corridor.tscn").instantiate()
	corridor.game = game
	corridor.ui = self
	add_child(corridor)
	corridor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func start_corridor_boss(id: String) -> void:
	var result = game.state.begin_named_boss(id)
	if not result.ok:
		toast(result.message)
		return
	close_modal()
	modal_open = true
	game.player.blocked = true
	game.player.route.clear()
	game.state.save_game()
	combat = load(TrialCatalogue.scene_path(id)).instantiate()
	combat.game = game
	combat.ui = self
	add_child(combat)
	combat.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	refresh()

func select_track(track: String) -> void:
	game.state.selected_track = track
	game.state.selected_tier = game.state.next_tier(track)
	game.state.save_game()
	open_boss()

func start_boss(use_support: bool = false, tier: int = 0, track: String = "") -> void:
	if tier == 0 and track == "":
		start_corridor_boss(game.state.selected_boss_id)
		return
	var result = game.state.begin_boss(use_support, tier, track)
	if not result.ok:
		toast(result.message)
		return
	game.state.save_game()
	_open_combat("boss")

func open_reward(message: String) -> void:
	var content = _dialog("今日修行已记下", "计划完成的积累已保存；健康属性由单独的评估档案更新。")
	paragraph(content, message, 23, BROWN)
	line(content)
	paragraph(content, "灵气已存入聚宝阁钱包，每日 +100；单抽 70、十连 700，十连至少一件史诗。装备加成在下一场战斗生效。", 18)
	button(content, "前往聚宝阁", open_treasure, true)
	button(content, "查看健康档案", open_home)
	button(content, "进入属性闯关", open_boss)
	button(content, "回到仙村", close_modal)

func _open_combat(kind: String, bonus: int = 0) -> void:
	if require_family():
		return
	close_modal()
	modal_open = true
	game.player.blocked = true
	game.player.route.clear()
	combat = Control.new()
	combat.set_script(Combat)
	combat.game = game
	combat.ui = self
	combat.mode = kind
	combat.support = bonus
	add_child(combat)
	combat.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	refresh()


func open_site(id: String) -> void:
	if id == "gacha":
		open_treasure()
	else:
		super.open_site(id)

func open_treasure(view: String = "wish") -> void:
	if require_family():
		return
	close_modal()
	modal_open = true
	game.player.blocked = true
	game.player.route.clear()
	treasure = Control.new()
	treasure.set_script(preload("res://scripts/treasure_panel.gd"))
	treasure.game = game
	treasure.ui = self
	treasure.tab = view
	add_child(treasure)


func require_family() -> bool:
	if not game.account_ready:
		open_login()
		return true
	return false

func can_change_family() -> bool:
	if is_instance_valid(combat):
		toast("请先结束或退出当前战斗，再切换家人。")
		return false
	if is_instance_valid(health_entry) and health_entry.busy:
		health_entry.status.text = "资料正在处理中，请等待完成，或先返回取消处理。"
		toast("资料正在处理中，请等待完成，或先返回取消处理。")
		return false
	return true

func open_family() -> void:
	if require_family():
		return
	if not can_change_family():
		return
	close_modal()
	modal_open = true
	game.player.blocked = true
	game.player.route.clear()
	family_panel = Control.new()
	family_panel.set_script(preload("res://scripts/family_panel.gd"))
	family_panel.game = game
	family_panel.ui = self
	add_child(family_panel)

func activate_family(id: String, fill_health: bool = false) -> bool:
	if not can_change_family():
		return false
	var result = game.family.select_member(id)
	if not result.ok:
		if is_instance_valid(family_panel) and is_instance_valid(family_panel.status_label):
			family_panel.status_label.text = result.message
		else:
			toast(result.message)
		return false
	close_modal()
	game.state = game.family.state_for(id)
	game.sync_avatar_from_state()
	game.player.position = game.SPAWN
	game.player.route.clear()
	game.player.destination_site = ""
	corridor_position = Vector2(180, 715)
	corridor_camera = 0
	refresh()
	if fill_health or (id != "self" and game.state.health_profile_id.is_empty()):
		open_health_entry()
	else:
		toast(("正在操作本人角色：" if id == "self" else "正在照顾：") + game.state.member_label())
	return true


func open_login() -> void:
	close_modal(true)
	modal_open = true
	game.player.blocked = true
	game.player.route.clear()
	account_panel = Control.new()
	account_panel.set_script(preload("res://scripts/account_panel.gd"))
	account_panel.game = game
	account_panel.ui = self
	add_child(account_panel)

func on_account_progress(message: String) -> void:
	if is_instance_valid(account_panel):
		account_panel.status_label.text = message

func on_account_result(action: String, result: Dictionary) -> void:
	if is_instance_valid(account_panel):
		account_panel.submit_button.disabled = false
	if not result.get("ok", false):
		if is_instance_valid(account_panel):
			account_panel.status_label.text = str(result.get("message", "操作失败，请重试。"))
		else:
			toast(str(result.get("message", "操作失败，请重试。")))
		return
	if action == "logout":
		reset_logged_out()
		return
	if action == "claim-legacy":
		finish_account_setup(true)
		return
	if action not in ["register", "login"]:
		return
	if is_instance_valid(account_panel):
		account_panel.clear_passwords()
	var roster = game.FamilyRoster.new()
	roster.cache_root_override = game.account_cache_root_override
	roster.legacy_source_override = game.account_legacy_source_override
	var prepared = roster.open_account(result.account)
	if not prepared.ok:
		roster.dispose()
		account_panel.status_label.text = prepared.message
		return
	game.pending_account_roster = roster
	if prepared.needs_import:
		account_panel.migration_mode = true
		account_panel.build()
	else:
		finish_account_setup(false)

func import_old_account() -> void:
	if game.pending_account_roster == null or game.account_api.busy:
		return
	var source = game.pending_account_roster.legacy_snapshot()
	if not source.ok:
		account_panel.status_label.text = source.message
		return
	var fingerprint = source.fingerprint
	account_panel.submit_button.disabled = true
	game.account_api.claim_legacy(fingerprint)

func finish_account_setup(import_old: bool) -> void:
	var roster = game.pending_account_roster
	if roster == null:
		return
	if not import_old:
		roster.legacy_choice_made = true
	if not (roster.import_legacy() if import_old else roster.save_game()):
		account_panel.status_label.text = roster.last_error
		return
	close_modal(true)
	game.family.dispose()
	game.family = roster
	game.pending_account_roster = null
	game.account_ready = true
	game.state = roster.active_state()
	game.companion_api.reset_session()
	game.sync_avatar_from_state()
	refresh()
	if game.family.companion.id.is_empty() and "--skip-intro" not in OS.get_cmdline_user_args():
		open_companion(true)
	else:
		open_family()

func logout_account() -> void:
	if not can_change_family() or game.account_api.busy:
		return
	if game.account_ready and not game.family.save_game():
		toast("当前进度保存失败，请重试后再退出。")
		return
	game.account_api.logout()

func reset_logged_out() -> void:
	close_modal(true)
	game.companion_api.reset_session()
	game.family.dispose()
	if game.pending_account_roster != null:
		game.pending_account_roster.dispose()
		game.pending_account_roster = null
	game.family = game.FamilyRoster.new()
	game.family.persist_enabled = false
	game.state = game.family.owner_state
	game.account_ready = false
	game.sync_avatar_from_state()
	refresh()
	open_login()
