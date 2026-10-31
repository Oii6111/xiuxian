extends "res://scripts/family_panel.gd"
## Login and registration are separate from the two elder slots.
var register_mode = false
var migration_mode = false
var username_input: LineEdit
var password_input: LineEdit
var repeat_input: LineEdit
var display_input: LineEdit
var register_avatar: OptionButton
var submit_button: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	build()

func build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var shade = ColorRect.new()
	shade.color = Color(0.035, 0.04, 0.06, 0.94)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var left = panel_at(Rect2(145, 105, 520, 690), GOLD_TEXT)
	text(left, "疯狂修仙，中", 42, GOLD_TEXT)
	text(left, "从自己的账号开始", 27)
	var space = Control.new()
	space.custom_minimum_size.y = 40
	left.add_child(space)
	text(left, "我的角色", 28, GOLD_TEXT)
	paragraph(left, "登录后拥有自己的昵称与修仙角色。\n原有角色进度可以单独保留。", 20)
	text(left, "两位家人", 28, GOLD_TEXT)
	paragraph(left, "两个位置都留给需要照顾的老人。\n帮助填写资料，记录每日坚持。", 20)
	text(left, "分别成长", 28, GOLD_TEXT)
	paragraph(left, "本人和两位家人的资料、灵气、装备与关卡进度分别保存。", 20)
	var right = panel_at(Rect2(700, 105, 595, 690))
	if register_mode:
		right.add_theme_constant_override("separation", 8)
	if migration_mode:
		text(right, "保留你的旧进度", 30, GOLD_TEXT)
		paragraph(right, "已登录：" + str(game.account_api.account.display_name), 20)
		paragraph(right, "发现此前的游戏存档。导入后，未标注家人关系的原角色归回“我自己”，已填写父亲、母亲等关系的家人继续保留。", 20)
		paragraph(right, "本人角色不占用两个家人位置。旧存档会先备份，导入进度只归属当前账号。", 19)
		status_label = paragraph(right, "请选择是否把旧进度保留到这个账号。", 17, GOLD_TEXT)
		submit_button = action(right, "保留旧进度到当前账号", ui.import_old_account, true)
		action(right, "使用全新的角色与两个家人位置", func(): ui.finish_account_setup(false))
		action(right, "退出并换一个账号", ui.logout_account)
		return
	var top = HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	right.add_child(top)
	action(top, "登录", func(): switch_mode(false), not register_mode)
	action(top, "注册", func(): switch_mode(true), register_mode)
	text(right, "注册子女账号" if register_mode else "欢迎回来", 30, GOLD_TEXT)
	username_input = field(right, "用户名", "3—32 位字母、数字或下划线", "", 32)
	password_input = field(right, "密码", "请输入密码（至少 12 位）", "", 128)
	password_input.secret = true
	password_input.text_submitted.connect(func(_value): submit())
	if register_mode:
		repeat_input = field(right, "确认密码", "请再次输入密码", "", 128)
		repeat_input.secret = true
		var personal = HBoxContainer.new()
		personal.add_theme_constant_override("separation", 16)
		right.add_child(personal)
		var names = VBoxContainer.new()
		names.custom_minimum_size.x = 270
		personal.add_child(names)
		display_input = field(names, "我的昵称", "自己的昵称", "", 10)
		var avatars = VBoxContainer.new()
		avatars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		personal.add_child(avatars)
		register_avatar = option(avatars, "我的形象", ["男修", "女修"], 0)
	status_label = paragraph(right, "注册或登录自己的账号后，再添加两位家人。", 16)
	submit_button = action(right, "注册并登录" if register_mode else "登录游戏", submit, true)
	paragraph(right, "游客模式无需账号，自动载入三张 GitHub 样例健康图片，直接体验完整流程。", 15, MUTED_TEXT)
	action(right, "游客模式 · 一键体验", ui.start_guest_mode)

func switch_mode(value: bool) -> void:
	if game.account_api.busy:
		return
	var username = username_input.text if is_instance_valid(username_input) else ""
	register_mode = value
	build()
	username_input.text = username

func submit() -> void:
	if game.account_api.busy:
		return
	var pattern = RegEx.new()
	pattern.compile("^[A-Za-z0-9_]{3,32}$")
	if pattern.search(username_input.text.strip_edges()) == null:
		status_label.text = "用户名请使用 3—32 位字母、数字或下划线。"
		return
	if password_input.text.length() < 12:
		status_label.text = "密码至少需要 12 位。"
		return
	var payload = {"username": username_input.text.strip_edges(), "password": password_input.text}
	if register_mode:
		if password_input.text != repeat_input.text:
			status_label.text = "两次输入的密码不一致。"
			return
		if display_input.text.strip_edges().is_empty():
			status_label.text = "请填写自己的昵称。"
			return
		payload.display_name = display_input.text.strip_edges()
		payload.avatar = "female" if register_avatar.selected == 1 else "male"
	submit_button.disabled = true
	game.account_api.authenticate("register" if register_mode else "login", payload)

func clear_passwords() -> void:
	if is_instance_valid(password_input):
		password_input.clear()
	if is_instance_valid(repeat_input):
		repeat_input.clear()

