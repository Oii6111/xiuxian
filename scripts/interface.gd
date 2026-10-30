extends Control

const INK = Color("264f46")
const MUTED = Color("77877a")
const PAPER = Color("faf7eb")
const JADE = Color("427e69")
const GOLD = Color("b79658")
var game: Node
var modal_open: bool = false
var modal: ColorRect
var toast_label: Label
var toast_time: float = 0.0
var resource_label: Label
var realm_label: Label
var day_label: Label
var daily_label: Label
var hint: Label
var fight_round: int = 0
var fight_enemy: int = 240
var fight_hp: int = 260
var fight_shield: int = 0
var fight_guarded: bool = false
var fight_active: bool = false
var fight_log: String = ""
var fight_status: Label
var enemy_bar: ProgressBar
var skill_buttons: Array[Button] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme_resource = Theme.new()
	theme_resource.default_font = game.font
	theme_resource.default_font_size = 17
	theme = theme_resource
	_build_hud()
	refresh()

func style(color: Color = PAPER, border: Color = Color("dce1ce"), radius: int = 18) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 20
	s.content_margin_right = 20
	s.content_margin_top = 18
	s.content_margin_bottom = 18
	s.shadow_color = Color(0.12, 0.25, 0.2, 0.09)
	s.shadow_size = 12
	return s

func card(rect: Rect2, parent: Node = self, color: Color = PAPER) -> VBoxContainer:
	var panel = PanelContainer.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.add_theme_stylebox_override("panel", style(color))
	parent.add_child(panel)
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)
	return content

func label_into(parent: Node, text: String, size: int = 17, color: Color = INK) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func paragraph(parent: Node, text: String, size: int = 17, color: Color = MUTED) -> Label:
	var label = label_into(parent, text, size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func line(parent: Node) -> void:
	var separator = HSeparator.new()
	separator.modulate = Color("d8ddc9")
	parent.add_child(separator)

func button(parent: Node, text: String, callback: Callable, primary: bool = false) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size.y = 44
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal = style(JADE if primary else Color("efefdf"), JADE if primary else Color("dde1d0"), 10)
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.shadow_size = 0
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", style(Color("5d947e") if primary else Color("e2e9d8"), Color("8da88e"), 10))
	b.add_theme_stylebox_override("pressed", style(Color("345f52"), JADE, 10))
	b.add_theme_stylebox_override("disabled", style(Color("e2e5d7"), Color("d9dece"), 10))
	b.add_theme_color_override("font_color", PAPER if primary else INK)
	b.add_theme_color_override("font_hover_color", PAPER if primary else INK)
	b.add_theme_color_override("font_pressed_color", PAPER)
	b.add_theme_color_override("font_disabled_color", Color("7a8876"))
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

func _build_hud() -> void:
	var title = label_into(self, "家族修真录", 36)
	title.position = Vector2(32, 25)
	var subtitle = label_into(self, "仙岛初见  /  把每一份坚持，养成家族的力量", 15, Color("5e7a6b"))
	subtitle.position = Vector2(34, 76)
	var badge = label_into(self, "GODOT  ·  可玩原型", 15, Color("5e7a6b"))
	badge.position = Vector2(1206, 36)
	var resources = card(Rect2(480, 28, 620, 57))
	resources.get_parent().add_theme_stylebox_override("panel", style(Color("f4f3e5"), Color("d5decb"), 28))
	resource_label = label_into(resources, "", 19)
	resource_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var profile = card(Rect2(28, 132, 252, 324))
	label_into(profile, "家 族 档 案", 13, GOLD)
	label_into(profile, "青松真人", 29)
	label_into(profile, "父亲的角色 · 由你守护", 14, MUTED)
	realm_label = label_into(profile, "", 19, JADE)
	line(profile)
	day_label = label_into(profile, "", 18)
	var progress = ProgressBar.new()
	progress.custom_minimum_size.y = 7
	progress.show_percentage = false
	progress.value = 80
	var track = style(Color("e4e8d5"), Color("e4e8d5"), 4)
	var fill = style(Color("83a88a"), Color("83a88a"), 4)
	for part in [track, fill]:
		part.content_margin_top = 0
		part.content_margin_bottom = 0
	progress.add_theme_stylebox_override("background", track)
	progress.add_theme_stylebox_override("fill", fill)
	progress.name = "CultivationBar"
	profile.add_child(progress)
	label_into(profile, "下一境界  ·  100 修为", 13, MUTED)
	button(profile, "查看家族洞府  →", func(): open_site("home"))
	var guide = card(Rect2(28, 479, 252, 209), self, Color("eef0df"))
	label_into(guide, "一起，慢慢修行", 20)
	paragraph(guide, "家人按计划完成健康行为，\n确认后化作修为与守护符。\n你来探索仙岛、选择策略。", 15, Color("607566"))
	line(guide)
	label_into(guide, "WASD / 方向键  移动\nShift 奔跑    E 交互\n右键拖动视角 · 滚轮缩放", 14, MUTED)
	var tasks = card(Rect2(1160, 132, 252, 314))
	label_into(tasks, "今 日 修 行", 13, GOLD)
	label_into(tasks, "一份小小的坚持", 22)
	daily_label = paragraph(tasks, "", 15, Color("607566"))
	line(tasks)
	label_into(tasks, "01   查看演示计划记录\n02   家庭确认，领取守护\n03   带上资源，前往渡劫台", 15)
	button(tasks, "模拟健康记录  +", open_record, true)
	label_into(tasks, "模拟数据 · 今日主行为仅奖励一次", 12, MUTED)
	var gallery = card(Rect2(1160, 468, 252, 169), self, Color("eef0df"))
	label_into(gallery, "另一种仙境？", 21)
	paragraph(gallery, "对比像素、国风仙侠与\n温暖低多边形三种概念。", 14)
	button(gallery, "打开风格画册  ↗", open_gallery)
	var island_name = label_into(self, "云 栖 仙 岛", 24, Color("456e5e"))
	island_name.position = Vector2(634, 680)
	var island_note = label_into(self, "家人在人间修行，你在此间守护", 14, Color("6c8978"))
	island_note.position = Vector2(575, 719)
	hint = label_into(self, "靠近建筑按 E，或点击下方入口", 17, INK)
	hint.position = Vector2(500, 750)
	hint.size.x = 440
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var navigation = card(Rect2(330, 796, 780, 70))
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	navigation.add_child(row)
	for entry in [["家族洞府", "home"], ["渡劫试炼", "battle"], ["万象灵阵", "boss"], ["天机碑", "records"]]:
		var site_id: String = entry[1]
		var b = button(row, entry[0], func(): open_site(site_id))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var footer = label_into(self, "体验版  ·  所有健康事件、识别结果与社群数据均为模拟；游戏结果不代表现实健康结论。", 12, Color("6f8878"))
	footer.position = Vector2(32, 875)
	var reset = button(self, "重置演示", reset_demo)
	reset.position = Vector2(1274, 815)
	reset.custom_minimum_size.y = 34
	toast_label = label_into(self, "", 20, PAPER)
	toast_label.position = Vector2(400, 103)
	toast_label.size = Vector2(640, 55)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_stylebox_override("normal", style(Color("3a6b59"), JADE, 14))
	toast_label.hide()

func refresh() -> void:
	var state = game.state
	resource_label.text = "修为  %d       灵气  %d       守护符  %d       灵印  %d" % [state.cultivation, state.qi, state.charms, state.seals]
	realm_label.text = "◇  " + state.realm()
	day_label.text = "已积累修行  %d 天" % state.days
	var bar = find_child("CultivationBar", true, false)
	if bar:
		bar.value = mini(100, state.cultivation)
	daily_label.text = "今日计划已确认，奖励已领取。\n继续探索，或来一场策略试炼。" if state.today() in state.rewarded_days else "今日计划等待你的确认。\n每一份坚持，都值得被看见。"

func update_proximity(id: String) -> void:
	var names = {"home": "家族洞府", "battle": "渡劫台", "boss": "万象灵阵", "records": "天机碑"}
	hint.text = "按 E 进入「%s」" % names[id] if names.has(id) else "靠近建筑按 E，或点击下方入口"

func _process(delta: float) -> void:
	if toast_time > 0:
		toast_time -= delta
		if toast_time <= 0:
			toast_label.hide()

func toast(text: String) -> void:
	toast_label.text = text
	toast_label.show()
	toast_time = 3.5

func begin_modal(title: String, subtitle: String = "") -> VBoxContainer:
	close_modal()
	modal_open = true
	game.player.blocked = true
	modal = ColorRect.new()
	modal.color = Color(0.09, 0.19, 0.16, 0.52)
	add_child(modal)
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var content = card(Rect2(375, 138, 690, 620), modal)
	var heading = HBoxContainer.new()
	content.add_child(heading)
	var title_label = label_into(heading, title, 29)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(heading, "关闭 ×", close_modal)
	if subtitle != "":
		paragraph(content, subtitle, 15)
	line(content)
	return content

func close_modal() -> void:
	if is_instance_valid(modal):
		modal.queue_free()
	modal = null
	modal_open = false
	game.player.blocked = false
	if fight_active:
		fight_active = false
		game.state.save_game()

func open_site(id: String) -> void:
	match id:
		"home": open_home()
		"battle": open_battle()
		"boss": open_boss()
		"records": open_records()

func open_record() -> void:
	var content = begin_modal("把坚持，存入修行簿", "预置记录 → 展示结构化草稿 → 家庭确认 → 领取游戏资源")
	var example = PanelContainer.new()
	example.add_theme_stylebox_override("panel", style(Color("eef0e2"), Color("dce1ce"), 12))
	content.add_child(example)
	var data = VBoxContainer.new()
	data.add_theme_constant_override("separation", 9)
	example.add_child(data)
	label_into(data, "演示计划记录  /  预设解析结果", 20)
	label_into(data, "家族成员     青松真人（父亲）", 17)
	label_into(data, "计划项目     按个人计划完成一次记录", 17)
	label_into(data, "记录日期     " + game.state.today(), 17)
	label_into(data, "事件来源     模拟设备 · 不含真实医学读数", 17)
	label_into(data, "审核状态     待家庭确认", 17, GOLD)
	paragraph(content, "此处用预置草稿演示拍照/硬件事件进入游戏的流程。尚未接入相机、OCR 或真实设备。", 15)
	var consent = CheckBox.new()
	consent.text = "我已了解这是模拟记录，同意用于本次家族游戏演示"
	consent.add_theme_font_size_override("font_size", 16)
	consent.add_theme_color_override("font_color", INK)
	consent.add_theme_color_override("font_hover_color", JADE)
	consent.add_theme_color_override("font_pressed_color", JADE)
	content.add_child(consent)
	var confirm = button(content, "确认记录 · 领取修行资源", func():
		var result = game.state.confirm_event({"event_id": "demo_" + game.state.today(), "plan_id": "daily_plan", "observed_day": game.state.today(), "review_status": "confirmed", "consent_scope": "family_game", "source": "mock_device"})
		game.state.save_game()
		refresh()
		if result.ok:
			open_reward(result.message)
		else:
			toast(result.message)
	, true)
	confirm.disabled = true
	consent.toggled.connect(func(checked: bool): confirm.disabled = not checked)
	paragraph(content, "奖励依据完成个人计划，每日主行为仅计一次。无需重复上传。", 13)

func open_reward(message: String) -> void:
	var content = begin_modal("守护已抵达", "今日的坚持，成为了家族故事里的一笔。")
	label_into(content, "◇", 82, GOLD).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var text = paragraph(content, message, 23, JADE)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line(content)
	paragraph(content, "新获得的守护符可以抵挡一次试炼伤害。修为与家族灵印会留在洞府中，成为长期积累。", 18)
	button(content, "带着守护 · 前往渡劫台", open_battle, true)
	button(content, "回到仙岛", close_modal)

func open_home() -> void:
	var content = begin_modal("青松洞府", "长辈的每一份认真，都在这里留下痕迹。")
	label_into(content, "青松真人   ·   " + game.state.realm(), 26, JADE)
	label_into(content, "累计修行 %d 天    家族灵印 %d 枚" % [game.state.days, game.state.seals], 20)
	line(content)
	label_into(content, "已获得   初入修途", 22, GOLD)
	paragraph(content, "七日门匾 · 纪念第一次共同坚持。\n当前示例角色已有 28 天历史积累。", 18)
	label_into(content, "即将解锁   一月守心", 22)
	paragraph(content, "累计 30 天计划记录，点亮洞府新门匾。\n每一次确认只能增加当天的一份积累。", 18)
	line(content)
	paragraph(content, "家族档案默认仅供本地演示。成就只展示游戏积累，不公开原始健康数据。", 15)
	button(content, "为家人记下一次坚持", open_record, true)

func open_records() -> void:
	var content = begin_modal("天机碑 · 家族修行簿", "只记录游戏贡献与共同积累。")
	label_into(content, "今日计划", 24, JADE)
	paragraph(content, "已确认 · 今日主行为奖励已领取" if game.state.today() in game.state.rewarded_days else "待确认 · 按个人计划完成一次记录", 19)
	line(content)
	label_into(content, "家族同修榜  /  模拟展示", 22)
	label_into(content, "01    松风家族              同修 128 次\n02    云水人家              同修 106 次\n03    青松家族              同修 %d 次" % game.state.days, 20)
	paragraph(content, "前两行是固定演示数据；本地家族只显示游戏积累。", 14)
	line(content)
	label_into(content, "我的灵阵贡献    %d" % game.state.contribution, 22, GOLD)
	button(content, "查看今日演示记录", open_record, true)

func open_battle() -> void:
	var content = begin_modal("渡劫台 · 开始一次试炼", "这是独立的游戏策略挑战，战斗结算不表示现实康复。")
	label_into(content, "三回合，守住心中的一盏灯", 25, JADE)
	paragraph(content, "云海幻影拥有 240 点气势。你有 260 点护元，每回合幻影都会反击。\n第三回合攻势更强，提前留好守护。", 19, INK)
	line(content)
	label_into(content, "雷诀     5 灵气 · 造成 90 伤害\n镇心诀  3 灵气 · 60 伤害 + 100 护盾\n守护符  1 张符 · 70 伤害 + 抵挡本回合", 18)
	paragraph(content, "初始资源足够完成普通试炼，无需新增健康记录。中途离开会保留已经消耗的资源。", 15)
	button(content, "我已了解 · 开启游戏试炼", start_battle, true)

func start_battle() -> void:
	fight_round = 0
	fight_enemy = 240
	fight_hp = 260
	fight_shield = 0
	fight_guarded = false
	fight_log = "云海幻影聚拢。选择你的第一招。"
	var content = begin_modal("三回合 · 云海试炼", "技能即策略：进攻、蓄盾，或使用家人带来的守护。")
	fight_active = true
	enemy_bar = ProgressBar.new()
	enemy_bar.max_value = 240
	enemy_bar.value = 240
	enemy_bar.custom_minimum_size.y = 24
	enemy_bar.show_percentage = false
	enemy_bar.add_theme_stylebox_override("background", style(Color("e4e7d8"), Color("e4e7d8"), 8))
	enemy_bar.add_theme_stylebox_override("fill", style(Color("8b9eac"), Color("8b9eac"), 8))
	content.add_child(enemy_bar)
	fight_status = paragraph(content, "", 19, INK)
	fight_status.custom_minimum_size.y = 215
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	content.add_child(row)
	skill_buttons.clear()
	for index in range(3):
		var choice = index
		var b = button(row, ["雷诀 · 5 灵气", "镇心诀 · 3 灵气", "守护符 · 1 张"][index], func(): play_turn(choice), index == 0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		skill_buttons.append(b)
	_update_fight()
	button(content, "离开试炼", close_modal)

func play_turn(choice: int) -> void:
	if not fight_active:
		return
	var cost = 5 if choice == 0 else 3
	if choice < 2 and game.state.qi < cost:
		toast("灵气不足，可返回仙岛休息或重置本次演示。")
		return
	if choice == 2 and game.state.charms < 1:
		toast("暂无守护符，请选择其他功法。")
		return
	fight_round += 1
	var damage = [90, 60, 70][choice]
	if choice == 2:
		game.state.charms -= 1
		fight_guarded = true
	else:
		game.state.qi -= cost
		if choice == 1:
			fight_shield += 100
	fight_enemy = maxi(0, fight_enemy - damage)
	var retaliation = 145 if fight_round == 3 else 65
	if fight_guarded or fight_enemy == 0:
		retaliation = 0
	var absorbed = mini(fight_shield, retaliation)
	fight_shield -= absorbed
	var hurt = retaliation - absorbed
	fight_hp = maxi(0, fight_hp - hurt)
	fight_guarded = false
	fight_log = "第 %d 回合：%s造成 %d 点伤害。\n幻影反击，你受到 %d 点伤害。" % [fight_round, ["雷诀", "镇心诀", "守护符"][choice], damage, hurt]
	game.state.save_game()
	refresh()
	_update_fight()
	if fight_enemy <= 0 or fight_round >= 3 or fight_hp <= 0:
		fight_active = false
		for b in skill_buttons:
			b.disabled = true
		var victory = fight_enemy <= 0 and fight_hp > 0
		fight_status.text += "\n\n" + ("✦  破阵成功！家人的守护与你同在。" if victory else "幻影仍在，今日暂且休整。历史修为完整保留。")
		fight_status.text += "\n这是游戏试炼结果，不代表医学判断。"

func _update_fight() -> void:
	enemy_bar.value = fight_enemy
	fight_status.text = "回合 %d / 3        幻影气势 %d / 240\n护元 %d    护盾 %d\n灵气 %d    守护符 %d\n\n%s" % [fight_round, fight_enemy, fight_hp, fight_shield, game.state.qi, game.state.charms, fight_log]
	for i in range(skill_buttons.size()):
		skill_buttons[i].disabled = game.state.qi < (5 if i == 0 else 3) if i < 2 else game.state.charms < 1

func open_boss() -> void:
	var content = begin_modal("万象灵阵 · 云海巨灵", "世界 Boss 的本地模拟：没有真实服务器或在线玩家。")
	label_into(content, "同心破阵，各尽一份力量", 25, JADE)
	var hp = ProgressBar.new()
	hp.max_value = 10000
	hp.value = maxi(0, 8240 - game.state.contribution)
	hp.custom_minimum_size.y = 26
	content.add_child(hp)
	label_into(content, "模拟巨灵气势  %d / 10,000" % maxi(0, 8240 - game.state.contribution), 20)
	paragraph(content, "本次基础贡献 = 80 × 1.2 = 96\n可选守护符加成 +20，占本次伤害约 17%。\n其余贡献来自角色积累与游戏策略。", 19, INK)
	line(content)
	if game.state.boss_day != game.state.today():
		game.state.boss_attempts = 0
		game.state.boss_day = game.state.today()
	label_into(content, "你的累计贡献  %d   ·   今日出战 %d / 3" % [game.state.contribution, game.state.boss_attempts], 20, GOLD)
	var basic = button(content, "普通出战 · 贡献 96（不消耗健康支援）", func(): contribute(false), true)
	var support = button(content, "使用守护符 · 贡献 116（消耗 1 张）", func(): contribute(true))
	basic.disabled = game.state.boss_attempts >= 3
	support.disabled = game.state.boss_attempts >= 3 or game.state.charms < 1

func contribute(support: bool) -> void:
	if game.state.boss_attempts >= 3 or (support and game.state.charms < 1):
		return
	game.state.boss_attempts += 1
	game.state.contribution += 116 if support else 96
	if support:
		game.state.charms -= 1
	game.state.save_game()
	refresh()
	open_boss()
	toast("灵阵亮起！贡献 +%d" % (116 if support else 96))

func open_gallery() -> void:
	var content = begin_modal("风格画册", "AI 生成的视觉方向图；当前可玩原型采用像素仙村场景。")
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	content.add_child(row)
	var image = TextureRect.new()
	image.custom_minimum_size = Vector2(640, 360)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	for i in range(3):
		var index = i
		button(row, ["01  像素仙村", "02  国风仙侠", "03  低多边形"][i], func(): _gallery_image(image, index))
	content.add_child(image)
	_gallery_image(image, 0)
	paragraph(content, "概念图用于比较氛围与美术方向，画面细节不表示已在 Demo 中实现。", 13)

func _gallery_image(image: TextureRect, index: int) -> void:
	var path = "res://concepts/" + ["01-pixel-village.png", "02-ink-cultivation.png", "03-cozy-3d-island.png"][index]
	if FileAccess.file_exists(path):
		image.texture = preload("res://scripts/pixel_assets.gd").texture(path)
	else:
		toast("风格图正在生成，完成后会保存至 concepts 文件夹。")

func reset_demo() -> void:
	close_modal()
	game.state.reset_demo()
	game.player.position = Vector3(0, 0.2, 1)
	refresh()
	toast("已恢复初始演示资源")
