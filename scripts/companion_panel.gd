extends Control
const Catalogue = preload("res://scripts/companion_catalogue.gd")
const Context = preload("res://scripts/companion_context.gd")
var game: Node
var ui: Control
var choose_mode = false
var selected_id = "gourd_dragon"
var nickname_input: LineEdit
var status_label: Label
var choice_buttons: Dictionary = {}
var choice_caption: Label
var confirm_button: Button
var input: LineEdit
var send_button: Button
var quick_buttons: Array[Button] = []
var messages: VBoxContainer
var scroll: ScrollContainer
var thinking: Label
var mode_label: Label
var portrait: TextureRect
var portrait_clock = 0.0
var closed = false
var task_sync_label: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	game.companion_api.reply_received.connect(on_reply)
	game.companion_api.busy_changed.connect(on_busy)
	if is_instance_valid(game.companion_tasks):
		game.companion_tasks.changed.connect(on_tasks_changed)
	choose_mode = choose_mode or not Catalogue.valid(str(game.family.companion.id))
	build()

func build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	choice_buttons.clear()
	quick_buttons.clear()
	input = null
	send_button = null
	messages = null
	thinking = null
	portrait = null
	task_sync_label = null
	var shade = ColorRect.new()
	shade.color = Color(0.08, 0.1, 0.08, 0.68)
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var content = ui.card(Rect2(150, 73, 1140, 755), self, Color("f5e8c9"))
	content.add_theme_constant_override("separation", 13)
	var heading = HBoxContainer.new()
	content.add_child(heading)
	var title = ui.label_into(heading, "选择你的同行灵宠" if choose_mode else "灵宠小叙 · " + Catalogue.nickname(game.family.companion), 28)
	title.add_theme_font_override("font", game.title_font)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.button(heading, "关闭 ×", ui.close_modal)
	ui.paragraph(content, "四位伙伴，同样贴心。选一只喜欢的，陪你与家人慢慢修行。" if choose_mode else "今日任务、家人近况、下一步安排，都可以来问我。", 16)
	ui.line(content)
	if choose_mode:
		build_choices(content)
	else:
		build_chat(content)

func build_choices(content: VBoxContainer) -> void:
	var existing = Catalogue.clean(game.family.companion)
	selected_id = str(existing.id) if Catalogue.valid(existing.id) else "gourd_dragon"
	var cards = HBoxContainer.new()
	cards.add_theme_constant_override("separation", 14)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cards)
	for id in Catalogue.IDS:
		var pet = Catalogue.PETS[id]
		var candidate = ui.button(cards, "", func(): select_pet(id))
		candidate.custom_minimum_size = Vector2(254, 355)
		candidate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		candidate.tooltip_text = pet.intro
		var box = VBoxContainer.new()
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.offset_left = 14
		box.offset_right = -14
		box.offset_top = 22
		box.offset_bottom = -18
		box.add_theme_constant_override("separation", 14)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		candidate.add_child(box)
		var image = pet_image(box, id, Vector2(200, 190))
		image.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var name_label = ui.label_into(box, pet.name, 23)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var trait_label = ui.label_into(box, pet.trait, 14)
		trait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var intro = ui.paragraph(box, "“" + pet.intro + "”", 15)
		intro.custom_minimum_size = Vector2(220, 70)
		intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		choice_buttons[id] = candidate
	choice_caption = ui.label_into(content, "", 18)
	var bottom = HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 15)
	content.add_child(bottom)
	ui.label_into(bottom, "给伙伴取个昵称", 17)
	nickname_input = LineEdit.new()
	nickname_input.custom_minimum_size = Vector2(230, 45)
	nickname_input.max_length = 10
	nickname_input.text = existing.nickname if Catalogue.valid(existing.id) else Catalogue.PETS[selected_id].nickname
	nickname_input.add_theme_color_override("font_color", ui.BROWN)
	nickname_input.add_theme_color_override("caret_color", ui.BROWN)
	nickname_input.add_theme_stylebox_override("normal", ui.style(Color("fff4da")))
	nickname_input.add_theme_stylebox_override("focus", ui.style(Color("fff8e7")))
	bottom.add_child(nickname_input)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	confirm_button = ui.button(bottom, "", confirm_choice, true)
	confirm_button.custom_minimum_size.x = 270
	status_label = ui.label_into(content, "随时可以免费更换，任务与陪伴记录会一直保留。", 14)
	select_pet(selected_id, false)

func select_pet(id: String, update_nickname: bool = true) -> void:
	var old_default = Catalogue.PETS[selected_id].nickname
	selected_id = id
	if update_nickname and (nickname_input.text.strip_edges().is_empty() or nickname_input.text == old_default):
		nickname_input.text = Catalogue.PETS[id].nickname
	for key in choice_buttons:
		var selected = key == id
		var frame = ui.style(Color("f8e3b2") if selected else Color("eee1c4"))
		frame.border_color = Color("669985") if selected else Color("bda77c")
		frame.set_border_width_all(4 if selected else 2)
		choice_buttons[key].add_theme_stylebox_override("normal", frame)
	choice_caption.text = Catalogue.PETS[id].name + "：" + Catalogue.PETS[id].intro
	confirm_button.text = "与" + Catalogue.PETS[id].name + "一同出发"

func confirm_choice() -> void:
	var result = game.family.choose_companion(selected_id, nickname_input.text)
	if not result.ok:
		status_label.text = result.message
		return
	game.companion_api.cancel_pending()
	game.companion_actor.refresh_pet()
	ui.refresh()
	choose_mode = false
	build()

func pet_image(parent: Node, id: String, minimum: Vector2) -> TextureRect:
	var image = TextureRect.new()
	image.texture = Catalogue.texture(id)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.custom_minimum_size = minimum
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(image)
	return image

func build_chat(content: VBoxContainer) -> void:
	var columns = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 22)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var side = VBoxContainer.new()
	side.custom_minimum_size.x = 252
	side.add_theme_constant_override("separation", 11)
	columns.add_child(side)
	portrait = pet_image(side, game.family.companion.id, Vector2(230, 175))
	var name_label = ui.label_into(side, Catalogue.nickname(game.family.companion), 27)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_label = ui.label_into(side, "在线陪伴" if game.companion_api.online else "仙村向导", 14)
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.paragraph(side, Catalogue.PETS[game.family.companion.id].intro, 15)
	ui.line(side)
	if OS.get_environment("XIUXIAN_WECHAT_LINK_ENABLED") == "1":
		ui.button(side, "连接微信 / 查看连接", ui.open_wechat_link)
	for entry in [["今日任务", "今天的任务怎么样？"], ["家人近况", "家人今天的记录怎么样？"], ["下一步做什么", "下一步做什么？"]]:
		var question: String = entry[1]
		quick_buttons.append(ui.button(side, entry[0], func(): send_message(question)))
	var stretch = Control.new()
	stretch.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(stretch)
	ui.button(side, "更换灵宠 / 修改昵称", func():
		game.companion_api.cancel_pending()
		choose_mode = true
		build()
	)
	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 9)
	columns.add_child(right)
	var context = Context.snapshot(game)
	ui.label_into(right, context.as_of_date + "  ·  当前角色：" + Context.active(context).label, 15)
	if is_instance_valid(game.companion_tasks) and game.companion_tasks.manages(game.family.active_id):
		task_sync_label = ui.label_into(right, game.companion_tasks.status_text(), 13)
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size.y = 380
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	messages = VBoxContainer.new()
	messages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	messages.add_theme_constant_override("separation", 12)
	scroll.add_child(messages)
	thinking = ui.label_into(right, Catalogue.nickname(game.family.companion) + "正在想一想…", 14)
	thinking.visible = game.companion_api.busy
	var bottom = HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	right.add_child(bottom)
	input = LineEdit.new()
	input.placeholder_text = "问问今日任务，或聊聊接下来的安排…"
	input.max_length = 600
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size.y = 48
	input.add_theme_stylebox_override("normal", ui.style(Color("fff8e8")))
	input.add_theme_stylebox_override("focus", ui.style(Color("fffdf2")))
	input.add_theme_color_override("font_color", ui.BROWN)
	input.add_theme_color_override("font_placeholder_color", Color("9a8466"))
	input.add_theme_color_override("caret_color", ui.BROWN)
	input.text_submitted.connect(func(_text): send_message(input.text))
	bottom.add_child(input)
	send_button = ui.button(bottom, "发送", func(): send_message(input.text), true)
	send_button.custom_minimum_size.x = 88
	var record_note = "按游戏中的记录陪你安排今天；确认记录请到对应页面完成。"
	if is_instance_valid(game.companion_tasks) and game.companion_tasks.manages(game.family.active_id):
		record_note = "由老人微信反馈完成，任务状态会自动同步。"
	ui.paragraph(right, record_note, 12)
	var has_current_history = false
	for item in game.companion_api.history:
		has_current_history = has_current_history or item.scope == game.companion_api.scope()
	if not has_current_history:
		game.companion_api.append_message("assistant", "你好，我是%s。今天想先看看任务、关心一下家人，还是一起安排下一步？" % Catalogue.nickname(game.family.companion))
	render_messages()
	on_busy(game.companion_api.busy)
	input.grab_focus.call_deferred()

func render_messages() -> void:
	if not is_instance_valid(messages):
		return
	for child in messages.get_children():
		messages.remove_child(child)
		child.queue_free()
	for item in game.companion_api.history:
		if item.scope != game.companion_api.scope():
			continue
		var user = item.role == "user"
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		messages.add_child(row)
		var gap = Control.new()
		gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if user:
			row.add_child(gap)
		var panel = PanelContainer.new()
		panel.custom_minimum_size.x = 625
		var frame = ui.style(Color("e2ecd9") if user else Color("fff7e3"))
		frame.border_color = Color("9cae84") if user else Color("c8b28a")
		frame.content_margin_left = 16
		frame.content_margin_right = 16
		frame.content_margin_top = 12
		frame.content_margin_bottom = 12
		panel.add_theme_stylebox_override("panel", frame)
		row.add_child(panel)
		var box = VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		panel.add_child(box)
		ui.label_into(box, "你" if user else Catalogue.nickname(game.family.companion), 13)
		var text = ui.paragraph(box, item.text, 16, ui.BROWN)
		text.custom_minimum_size.x = 580
		if not item.actions.is_empty():
			var buttons = HBoxContainer.new()
			buttons.add_theme_constant_override("separation", 7)
			box.add_child(buttons)
			for action in item.actions:
				var id: String = action.id
				ui.button(buttons, action.label, func(): open_action(id))
		if not user:
			row.add_child(gap)
	scroll_to_bottom.call_deferred()

func scroll_to_bottom() -> void:
	if is_instance_valid(scroll):
		await get_tree().process_frame
		if is_instance_valid(scroll):
			scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)

func send_message(text: String) -> void:
	if game.companion_api.send_message(text):
		if is_instance_valid(input):
			input.clear()
		render_messages()

func on_busy(value: bool) -> void:
	if is_instance_valid(send_button):
		send_button.disabled = value
	if is_instance_valid(thinking):
		thinking.visible = value
	for candidate in quick_buttons:
		candidate.disabled = value

func on_reply(payload: Dictionary) -> void:
	if closed:
		return
	if is_instance_valid(mode_label):
		mode_label.text = "在线陪伴" if game.companion_api.online else "仙村向导"
	game.companion_actor.say("我整理好啦，来看看吧", payload.get("animation", "talk"))
	render_messages()

func open_action(id: String) -> void:
	if id not in Context.ACTIONS:
		return
	match id:
		"record": ui.open_record()
		"family": ui.open_family()
		"health": ui.open_home()
		"treasure": ui.open_treasure()
		"equipment": ui.open_treasure("bag")
		"boss": ui.open_boss()

func _process(delta: float) -> void:
	portrait_clock += delta
	if is_instance_valid(portrait):
		portrait.pivot_offset = portrait.size * 0.5
		portrait.rotation = sin(portrait_clock * 2) * 0.025

func on_tasks_changed() -> void:
	if is_instance_valid(task_sync_label):
		task_sync_label.text = game.companion_tasks.status_text()

func shutdown() -> void:
	closed = true
	if is_instance_valid(game.companion_tasks) and game.companion_tasks.changed.is_connected(on_tasks_changed):
		game.companion_tasks.changed.disconnect(on_tasks_changed)
	if game.companion_api.reply_received.is_connected(on_reply):
		game.companion_api.reply_received.disconnect(on_reply)
	if game.companion_api.busy_changed.is_connected(on_busy):
		game.companion_api.busy_changed.disconnect(on_busy)
	game.companion_api.cancel_pending()
