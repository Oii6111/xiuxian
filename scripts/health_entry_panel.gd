extends Control
## Native report onboarding. Draft results never touch GameState before confirmation.
const Baseline = preload("res://scripts/health_baseline.gd")
const BASE_URL = "http://127.0.0.1:8001"
var service_url = BASE_URL
const ENTRY_REVISION = "1f356a0"
const GUEST_SAMPLE_PATHS = ["res://health-entry/样本体检报告.png", "res://health-entry/手写既往病史记录.png", "res://health-entry/四款药品包装展示.png"]
var ui
var game
var probe: HTTPRequest
var work: HTTPRequest
var file_dialog: FileDialog
var status: Label
var file_label: Label
var result_box: VBoxContainer
var preview: TextureRect
var report_placeholder: Label
var consent: CheckBox
var analyze_button: Button
var confirm_button: Button
var connect_button: Button
var select_button: Button
var avatar_button: Button
var chosen_path = ""
var chosen_paths: Array[String] = []
var name_input: LineEdit
var relation_input: LineEdit
var age_input: LineEdit
var sex_input: OptionButton
var history_input: TextEdit
var medication_input: TextEdit
var field_controls: Array[Control] = []
var clear_button: Button
var draft: Dictionary = {}
var record_id = ""
var submitted_inputs = ""
var configured = false
var service_verified = false
var busy = false
var phase = ""
var model_name = "qwen3-vl-plus"
var provider = "通义千问视觉"
var tried_start = false
var disposed = false
var target_state: RefCounted
var bound_member_id = ""
var bound_family: RefCounted
var bound_account_id = ""
var bound_generation = 0
var bound_health_revision = 0
var bound_health_profile_id = ""
var probe_service_url = ""
var verified_service_url = ""
var pending_service_url = ""
var committed = false
var fill_mode: OptionButton
var guest_sample_button: Button
var guest_mode = false
var guest_samples_loaded = false

func _ready() -> void:
	target_state = game.state
	# 网页版：健康入口经游戏服务同源代理，浏览器不直连其他端口。
	if OS.has_feature("web"):
		service_url = game.account_api.service_url
	bound_member_id = target_state.family_member_id
	bound_family = game.family
	bound_account_id = str(game.family.account.get("id", ""))
	bound_generation = game.account_api.generation
	bound_health_revision = target_state.health_revision
	bound_health_profile_id = target_state.health_profile_id
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade = ColorRect.new()
	shade.color = Color(0.08, 0.07, 0.06, 0.8)
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var content = ui.card(Rect2(100, 45, 1240, 810), self)
	content.add_theme_constant_override("separation", 10)
	var heading = HBoxContainer.new()
	content.add_child(heading)
	var title = ui.label_into(heading, "创建基础状态" if bound_member_id.is_empty() else ("为自己填写 · " if bound_member_id == "self" else "为家人填写 · ") + target_state.member_label(), 27)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	avatar_button = ui.button(heading, "选择形象", ui.show_start)
	ui.button(heading, "稍后填写 / 返回仙村", ui.close_modal)
	ui.label_into(content, "① 填写基础信息    →    ② 分析资料生成属性    →    ③ 确认并进入仙村    * 为必填项", 18)
	ui.line(content)
	var columns = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 26)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var left = VBoxContainer.new()
	left.custom_minimum_size.x = 365
	left.add_theme_constant_override("separation", 10)
	columns.add_child(left)
	var names = HBoxContainer.new()
	names.add_theme_constant_override("separation", 12)
	left.add_child(names)
	var name_column = VBoxContainer.new()
	name_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_child(name_column)
	ui.label_into(name_column, "显示姓名 *", 16)
	name_input = text_line(name_column, "请输入姓名")
	name_input.max_length = 10
	var age_column = VBoxContainer.new()
	names.add_child(age_column)
	ui.label_into(age_column, "年龄 *", 16)
	age_column.custom_minimum_size.x = 110
	age_input = text_line(age_column, "填写年龄")
	age_input.max_length = 3
	var required_row = HBoxContainer.new()
	required_row.add_theme_constant_override("separation", 12)
	left.add_child(required_row)
	var sex_column = VBoxContainer.new()
	sex_column.custom_minimum_size.x = 130
	required_row.add_child(sex_column)
	ui.label_into(sex_column, "性别 *", 16)
	sex_input = OptionButton.new()
	for item in ["请选择性别", "男", "女"]:
		sex_input.add_item(item)
	sex_input.add_theme_color_override("font_color", ui.BROWN)
	sex_input.add_theme_stylebox_override("normal", ui.style(Color("f6e5c4")))
	sex_input.get_popup().add_theme_color_override("font_color", ui.BROWN)
	sex_input.get_popup().add_theme_stylebox_override("panel", ui.style(Color("f6e5c4")))
	sex_column.add_child(sex_input)
	sex_input.item_selected.connect(func(_index): input_changed())
	field_controls.append(sex_input)
	var relation_column = VBoxContainer.new()
	relation_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	required_row.add_child(relation_column)
	ui.label_into(relation_column, "与家人的关系 *", 16)
	relation_input = text_line(relation_column, "请输入关系")
	relation_input.max_length = 30
	var tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_stylebox_override("panel", ui.style(ui.PARCHMENT))
	tabs.add_theme_stylebox_override("tab_selected", ui.style(Color("f6e2b7")))
	tabs.add_theme_stylebox_override("tab_unselected", ui.style(Color("d8c39b")))
	tabs.add_theme_color_override("font_selected_color", ui.BROWN)
	tabs.add_theme_color_override("font_unselected_color", ui.BROWN)
	left.add_child(tabs)
	var reports = VBoxContainer.new()
	reports.name = "报告图片"
	reports.add_theme_constant_override("separation", 8)
	tabs.add_child(reports)
	var report_frame = PanelContainer.new()
	report_frame.custom_minimum_size = Vector2(0, 170)
	report_frame.add_theme_stylebox_override("panel", ui.style(Color("f6e5c4")))
	reports.add_child(report_frame)
	preview = TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	report_frame.add_child(preview)
	report_placeholder = ui.label_into(report_frame, "上传报告照片后在此预览", 16)
	report_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	report_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	report_placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	report_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	file_label = ui.paragraph(reports, "尚未选择图片。可添加多页体检报告、病历或用药单。", 16)
	file_label.max_lines_visible = 2
	file_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var file_actions = HBoxContainer.new()
	file_actions.add_theme_constant_override("separation", 8)
	reports.add_child(file_actions)
	select_button = ui.button(file_actions, "添加报告图片", choose_file, true)
	select_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_button = ui.button(file_actions, "清空", clear_files)
	guest_sample_button = ui.button(file_actions, "游客样例 · 自动加载三张", load_guest_samples)
	ui.paragraph(reports, "PNG / JPEG / WebP · 最多 6 张
每张最多 10 MB，合计最多 30 MB", 14)
	var info = VBoxContainer.new()
	info.name = "病史与用药"
	info.add_theme_constant_override("separation", 8)
	tabs.add_child(info)
	ui.label_into(info, "已有病史（选填）", 16)
	history_input = text_area(info, "请输入已有病史")
	ui.label_into(info, "已有用药记录（选填）", 16)
	medication_input = text_area(info, "请输入已有用药记录")
	ui.paragraph(info, "可上传体检报告、病历或用药单照片。", 14)
	ui.paragraph(left, "确认后保存显示姓名和游戏属性；不保存报告图片和原文。", 14)
	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	columns.add_child(right)
	var top_row = HBoxContainer.new()
	right.add_child(top_row)
	var name_label = ui.label_into(top_row, "基础状态预览", 24)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	connect_button = ui.button(top_row, "重新连接", connect_service)
	status = ui.paragraph(right, "等待连接分析服务…", 16)
	status.custom_minimum_size.y = 58
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size.y = 310
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	result_box = VBoxContainer.new()
	result_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_box.add_theme_constant_override("separation", 8)
	scroll.add_child(result_box)
	show_placeholder()
	fill_mode = OptionButton.new()
	fill_mode.add_item("子女代填 · 已获得家人同意")
	fill_mode.add_item("老人本人填写")
	fill_mode.custom_minimum_size.y = 38
	fill_mode.add_theme_color_override("font_color", ui.BROWN)
	fill_mode.add_theme_stylebox_override("normal", ui.style(Color("f6e5c4")))
	fill_mode.item_selected.connect(func(_index): input_changed())
	right.add_child(fill_mode)
	field_controls.append(fill_mode)
	consent = ui._check(right, "本人同意或已获家人同意；含图片时发送至模型识别")
	consent.toggled.connect(func(_checked: bool): update_buttons())
	analyze_button = ui.button(right, "分析资料 · 生成初始属性", analyze, true)
	confirm_button = ui.button(right, "确认初始属性并进入仙村", confirm_draft, true)
	probe = HTTPRequest.new()
	probe.max_redirects = 0
	probe.timeout = 4
	probe.body_size_limit = 65536
	add_child(probe)
	probe.request_completed.connect(probe_completed)
	work = HTTPRequest.new()
	work.max_redirects = 0
	work.timeout = 150
	work.body_size_limit = 2 * 1024 * 1024
	add_child(work)
	work.request_completed.connect(work_completed)
	prefill_member_identity()
	update_buttons()
	if "--preview" in OS.get_cmdline_user_args():
		status.text = "请填写基础信息，上传报告或补充文字资料后开始分析。"
	else:
		connect_service()
	if guest_mode:
		call_deferred("load_guest_samples")

func text_line(parent: Node, placeholder: String, initial: String = "") -> LineEdit:
	var field = LineEdit.new()
	field.placeholder_text = placeholder
	field.text = initial
	field.custom_minimum_size.y = 40
	field.add_theme_stylebox_override("normal", ui.style(Color("f6e5c4")))
	field.add_theme_color_override("font_color", ui.BROWN)
	field.add_theme_color_override("font_placeholder_color", Color("8b755e"))
	field.add_theme_color_override("caret_color", ui.BROWN)
	parent.add_child(field)
	field.text_changed.connect(func(_text): input_changed())
	field_controls.append(field)
	return field

func text_area(parent: Node, placeholder: String) -> TextEdit:
	var field = TextEdit.new()
	field.placeholder_text = placeholder
	field.custom_minimum_size.y = 80
	field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	field.add_theme_color_override("font_color", ui.BROWN)
	field.add_theme_color_override("font_placeholder_color", Color("8b755e"))
	field.add_theme_color_override("caret_color", ui.BROWN)
	field.add_theme_stylebox_override("normal", ui.style(Color("f6e5c4")))
	parent.add_child(field)
	field.text_changed.connect(input_changed)
	field_controls.append(field)
	return field

func input_changed() -> void:
	if disposed or busy or not is_instance_valid(result_box):
		return
	if not draft.is_empty():
		draft = {}
		record_id = ""
		show_placeholder()
		status.text = "资料已修改，请重新分析后再确认。"
	update_buttons()

func profile_error() -> String:
	if name_input.text.strip_edges().is_empty():
		return "请填写姓名。"
	var age_text = age_input.text.strip_edges()
	if age_text.is_empty():
		return "请填写年龄。"
	if not age_text.is_valid_int() or int(age_text) < 1 or int(age_text) > 120:
		return "年龄请填写 1—120 之间的整数。"
	if sex_input.selected <= 0:
		return "请选择性别。"
	if relation_input.text.strip_edges().is_empty():
		return "请填写与家人的关系。"
	return ""

func current_profile() -> Dictionary:
	var age_text = age_input.text.strip_edges()
	return {"name": name_input.text.strip_edges(), "relation": relation_input.text.strip_edges(), "age": int(age_text) if age_text.is_valid_int() else 0, "sex": sex_input.get_item_text(sex_input.selected) if sex_input.selected > 0 else ""}

func show_placeholder() -> void:
	clear_result()
	ui.label_into(result_box, "等待报告分析", 26)
	ui.paragraph(result_box, "可上传体检报告、病历或用药单照片，也可补充病史与用药信息。\n\n确认授权后点击分析。分析完成后可在这里查看角色属性和基础状态。", 18)

func clear_result() -> void:
	for child in result_box.get_children():
		result_box.remove_child(child)
		child.queue_free()

func update_buttons() -> void:
	if not is_instance_valid(analyze_button):
		return
	analyze_button.disabled = busy or not service_verified or (not chosen_paths.is_empty() and not configured) or not consent.button_pressed or not profile_error().is_empty()
	confirm_button.disabled = busy or draft.is_empty() or not consent.button_pressed or not profile_error().is_empty()
	analyze_button.tooltip_text = profile_error()
	select_button.disabled = busy
	if is_instance_valid(guest_sample_button):
		guest_sample_button.disabled = busy
	avatar_button.disabled = busy
	clear_button.disabled = busy or chosen_paths.is_empty()
	for field in field_controls:
		if field is LineEdit or field is TextEdit:
			field.editable = not busy
		elif field is SpinBox:
			field.editable = not busy
		elif field is OptionButton:
			field.disabled = busy
	connect_button.disabled = busy
	consent.disabled = busy
	analyze_button.text = "正在识别，请稍候…" if busy and phase == "parse" else "分析资料 · 生成初始属性"
	confirm_button.text = "确认基础状态并进入仙村"

func connect_service() -> void:
	if busy or probe.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	configured = false
	service_verified = false
	status.text = "正在连接本地分析服务…"
	update_buttons()
	probe_service_url = service_url
	var error = probe.request(probe_service_url + "/api/v1/health")
	if error != OK:
		status.text = "无法连接服务，请运行 health-entry/start.bat 后重试。"

func probe_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if disposed or probe_service_url != service_url:
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		if not tried_start and not OS.has_feature("web"):
			tried_start = true
			var server_path = ProjectSettings.globalize_path("res://health-entry/server.py")
			var python = OS.get_environment("XIUXIAN_HEALTH_PYTHON")
			if python.is_empty():
				python = "python"
			var pid = OS.create_process(python, PackedStringArray([server_path]), false)
			status.text = "正在启动分析服务…" if pid > 0 else "启动失败，请运行 health-entry/start.bat 后重试。"
			if pid > 0:
				await get_tree().create_timer(2.0).timeout
				if not disposed:
					connect_service()
		else:
			status.text = "服务未连接。请运行 health-entry/start.bat，再点击重新连接。"
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if code != 200 or not data is Dictionary or data.get("service") != "xiuxian-health-entry" or int(data.get("api_version", 0)) < 3:
		status.text = "请关闭 8001 端口的旧服务，使用新版 health-entry/start.bat 启动后重新连接。"
		return
	if data.get("source_revision") != ENTRY_REVISION:
		status.text = "分析服务版本较旧。请重启 health-entry/start.bat 后重新连接。"
		return
	if data.get("game_projection_version") != "legacy-pixel-v1":
		status.text = "健康服务需要更新，请重新启动 health-entry/start.bat。"
		return
	service_verified = true
	verified_service_url = service_url
	configured = data.get("configured", false) == true
	model_name = str(data.get("model", "qwen3-vl-plus"))
	provider = str(data.get("provider_label", "通义千问视觉"))
	status.text = provider + " · " + model_name + "\n" + ("已连接，可选择报告进行分析。" if configured else "图片识别待配置密钥；现在也可只提交文字资料，无需调用模型。")
	update_buttons()

func choose_file() -> void:
	if is_instance_valid(file_dialog):
		file_dialog.queue_free()
	file_dialog = FileDialog.new()
	file_dialog.title = "选择健康报告图片"
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	file_dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; 健康报告图片"])
	add_child(file_dialog)
	file_dialog.files_selected.connect(func(paths): select_files(paths); file_dialog.queue_free())
	file_dialog.canceled.connect(file_dialog.queue_free)
	file_dialog.popup_centered(Vector2i(960, 650))

func load_guest_samples() -> void:
	if busy or guest_samples_loaded:
		return
	guest_samples_loaded = true
	guest_mode = true
	name_input.text = "张建国"
	age_input.text = "68"
	sex_input.select(1)
	relation_input.text = "爸爸"
	history_input.text = "高血压 10 年"
	medication_input.text = "氨氯地平 5mg 每日一次"
	fill_mode.select(0)
	var paths = PackedStringArray()
	for resource_path in GUEST_SAMPLE_PATHS:
		paths.append(ProjectSettings.globalize_path(resource_path))
	select_files(paths)
	consent.button_pressed = true
	status.text = "游客样例已加载三张原始健康图片。正在准备样例档案…"
	update_buttons()
	if service_verified and configured:
		analyze()
	else:
		load_guest_sample_baseline()

func load_guest_sample_baseline() -> void:
	var payload = JSON.parse_string(FileAccess.get_file_as_string("res://health-entry/sample-baseline.json"))
	if not payload is Dictionary:
		status.text = "无法读取游客样例档案。"
		return
	payload.baseline_id = "baseline_guest_sample"
	payload.baseline_locked = true
	payload.mapping_version = "body_system_v2"
	payload.projection_version = "legacy-pixel-v1"
	payload.recognition_mode = "sample"
	payload.display_name = name_input.text.strip_edges()
	var checked = Baseline.validate(payload)
	if not checked.ok:
		status.text = checked.message
		return
	record_id = "guest-sample"
	submitted_inputs = input_signature()
	draft = checked.baseline
	show_draft()
	status.text = "游客样例档案已生成 · 三张原始图片已载入 · 可直接确认进入仙村。"
	update_buttons()
func select_file(path: String) -> void:
	select_files(PackedStringArray([path]))

func select_files(paths: PackedStringArray) -> void:
	if busy:
		return
	var combined = chosen_paths.duplicate()
	for path in paths:
		if path not in combined:
			combined.append(path)
	if combined.size() > 6:
		status.text = "一次最多选择 6 张报告图片。"
		return
	var total = 0
	for path in combined:
		var file = FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() > 10 * 1024 * 1024 or path.get_extension().to_lower() not in ["png", "jpg", "jpeg", "webp"]:
			status.text = "请选择 10 MB 以内的 PNG、JPEG 或 WebP 报告图片。"
			return
		total += file.get_length()
		var image = Image.load_from_file(path)
		if image == null or image.is_empty() or image.get_width() * image.get_height() > 25000000:
			status.text = "无法读取图片，或分辨率过大。请重新选择。"
			return
	if total > 30 * 1024 * 1024:
		status.text = "图片合计不能超过 30 MB。"
		return
	chosen_paths.assign(combined)
	chosen_path = chosen_paths[0] if not chosen_paths.is_empty() else ""
	consent.button_pressed = false
	input_changed()
	if not chosen_path.is_empty():
		preview.texture = ImageTexture.create_from_image(Image.load_from_file(chosen_path))
	report_placeholder.visible = chosen_path.is_empty()
	var names = PackedStringArray()
	for path in chosen_paths:
		names.append(path.get_file())
	file_label.tooltip_text = "\n".join(names)
	file_label.text = "已选择 %d 张 · 合并识别\n" % chosen_paths.size() + "、".join(names).left(70)
	update_buttons()

func clear_files() -> void:
	if busy:
		return
	chosen_paths.clear()
	chosen_path = ""
	preview.texture = null
	report_placeholder.show()
	file_label.text = "未选择图片。可提交左侧填写的文字资料。"
	consent.button_pressed = false
	input_changed()
	update_buttons()

func input_signature() -> String:
	return JSON.stringify({"member_id": bound_member_id, "fill_mode": fill_mode.selected, "profile": current_profile(), "history": history_input.text, "medications": medication_input.text, "paths": chosen_paths})

func analyze() -> void:
	if busy:
		return
	var message = profile_error()
	if not message.is_empty():
		status.text = message
		update_buttons()
		return
	if not service_verified or (not chosen_paths.is_empty() and not configured) or not consent.button_pressed or not profile_error().is_empty():
		return
	if history_input.text.length() > 4000 or medication_input.text.length() > 4000:
		status.text = "病史和用药记录各最多 4000 字。"
		return
	var data_urls = []
	var total = 0
	for path in chosen_paths:
		var raw = FileAccess.get_file_as_bytes(path)
		total += raw.size()
		if raw.is_empty() or raw.size() > 10 * 1024 * 1024 or total > 30 * 1024 * 1024:
			status.text = "报告文件读取失败或过大，请重新选择。"
			return
		var ext = path.get_extension().to_lower()
		var mime = "image/jpeg" if ext in ["jpg", "jpeg"] else "image/" + ext
		data_urls.append("data:" + mime + ";base64," + Marshalls.raw_to_base64(raw))
	draft = {}
	record_id = ""
	show_placeholder()
	status.text = "正在使用 " + model_name + " 读取 %d 张图片…\n通常需要十几秒至两分钟。" % data_urls.size() if not data_urls.is_empty() else "正在根据文字资料计算初始属性…\n本次不调用大模型。"
	submitted_inputs = input_signature()
	send_request("parse", "/api/v1/game/projections/parse", {"data_urls": data_urls, "profile": current_profile(), "history_text": history_input.text.strip_edges(), "medications_text": medication_input.text.strip_edges()})

func send_request(next_phase: String, endpoint: String, payload: Dictionary) -> void:
	if not context_matches() or not service_verified or verified_service_url != service_url:
		status.text = "角色、档案或服务已变更，请重新打开资料页并连接服务。"
		return
	pending_service_url = service_url
	busy = true
	phase = next_phase
	update_buttons()
	var error = work.request(service_url + endpoint, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		busy = false
		status.text = "请求未能发送，请重新连接服务。"
		update_buttons()

func work_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if disposed:
		return
	busy = false
	if not context_matches() or (not pending_service_url.is_empty() and pending_service_url != service_url):
		status.text = "角色、档案或服务已变更，本次结果未写入任何档案。"
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or not data is Dictionary:
		status.text = "分析服务连接中断或超时。原有属性已保留，可重新分析。"
		update_buttons()
		return
	if code != 200:
		status.text = str(data.get("message", "分析失败，请重试。")).left(240)
		update_buttons()
		return
	if phase == "parse":
		var projection = data.get("game_projection")
		if not projection is Dictionary or str(data.get("record_id", "")).is_empty():
			status.text = "分析结果缺少游戏属性，请重新分析。"
			update_buttons()
			return
		if data.get("recognition_mode") not in ["live", "text"]:
			status.text = "未收到有效分析结果，请重新分析资料。"
			update_buttons()
			return
		var candidate = projection.duplicate(true)
		candidate.merge({"baseline_id": "preview", "baseline_version": "char_baseline_v1", "baseline_locked": true, "recognition_mode": data.get("recognition_mode", "live"), "mapping_version": "body_system_v2", "rules_revision": data.get("source_revision", ""), "display_name": data.get("display_name", name_input.text.strip_edges()), "projection_version": "legacy-pixel-v1"}, true)
		var checked = Baseline.validate(candidate)
		if not checked.ok:
			status.text = checked.message
			update_buttons()
			return
		record_id = str(data.record_id)
		draft = checked.baseline
		show_draft()
		status.text = ("模型分析完成" if draft.recognition_mode == "live" else "文字计算完成 · 未调用模型") + " · 请核对下方属性。\n点击确认后才会更新角色；结果保留 30 分钟。"
	elif phase == "confirm":
		var payload = data.get("baseline")
		if not payload is Dictionary or payload.get("recognition_mode") != draft.recognition_mode:
			status.text = "服务未返回已确认档案，请重试。"
			update_buttons()
			return
		commit(payload)
		return
	update_buttons()

func show_draft() -> void:
	clear_result()
	ui.label_into(result_box, "报告分析 · 待你确认" if draft.recognition_mode == "live" else "文字资料 · 待你确认", 23)
	ui.label_into(result_box, str(draft.get("display_name", target_state.player_name)) + " · 初始气血 %d HP" % target_state.HealthProfile.INITIAL_HP, 25)
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 4)
	result_box.add_child(grid)
	for item in [["攻击", "attack"], ["防御", "defense"], ["灵力", "spirit"], ["体力", "stamina"]]:
		ui.label_into(grid, "%s  %d" % [item[0], draft.character_state[item[1]]], 22)
	ui.paragraph(result_box, "洞察 %d    心志 %d    身法 %d    气运 %d" % [draft.character_state.insight, draft.character_state.mind, draft.character_state.speed, draft.character_state.luck], 15)
	ui.label_into(result_box, "守护准备度 %d / 100" % draft.readiness, 17)
	ui.paragraph(result_box, "确认后锁定此份初始档案。后续可补充资料生成新档案，通关进度会保留。", 15)

func confirm_draft() -> void:
	if busy or draft.is_empty():
		return
	if not consent.button_pressed:
		status.text = "请先确认本次资料使用，再保存基础档案。"
		return
	if not profile_error().is_empty():
		status.text = profile_error()
		update_buttons()
		return
	if input_signature() != submitted_inputs:
		input_changed()
		status.text = "资料已修改，请重新分析后再确认。"
		return
	if guest_mode and draft.recognition_mode == "sample":
		commit(draft)
		return
	if draft.recognition_mode not in ["live", "text"]:
		status.text = "请先分析你的资料，再确认基础状态。"
		return
	if not service_verified or record_id.is_empty():
		status.text = "请重新连接并分析报告。"
		return
	status.text = "正在确认并保存初始档案…"
	var body = {"record_id": record_id, "recognition_mode": draft.recognition_mode, "baseline_locked": true}
	# 正式账号：先向 C 申请该角色的一次性票据，健康服务确认后以服务身份写入 C。
	if target_state.is_remote():
		busy = true
		update_buttons()
		var ticket = await game.account_api.api.request_api("/api/v2/baselines/tickets", HTTPClient.METHOD_POST, {"cultivator_id": target_state.cultivator_id})
		busy = false
		if not ticket.ok or not context_matches():
			status.text = "无法连接游戏服务，原有属性已保留，请重试。"
			update_buttons()
			return
		body["baseline_ticket"] = ticket.data.baseline_ticket
	send_request("confirm", "/api/v1/game/projections/confirm", body)

func commit(payload: Dictionary) -> void:
	if not context_matches():
		status.text = "当前家人已切换，请为对应家人重新打开资料页。"
		return
	if not consent.button_pressed:
		status.text = "请先确认本次资料使用，再保存基础档案。"
		return
	if target_state.is_remote():
		# 服务端已确认；从 C 拉取权威投影，不在本地另写一份。
		var synced = await game.account_api.sync_family(game.family)
		if not synced.ok:
			status.text = "档案已提交，游戏同步稍后完成。"
			return
		committed = true
		ui.refresh()
		ui.close_modal()
		ui.toast("基础状态已保存，开始修行吧！")
		return
	var old = target_state.health_snapshot()
	var applied = target_state.apply_health_baseline(payload)
	if not applied.ok:
		status.text = applied.message
		update_buttons()
		return
	if not bound_member_id.is_empty():
		target_state.family_identity.merge(current_profile(), true)
		target_state.family_identity.mode = "self" if fill_mode.selected == 1 else "family"
		target_state.family_identity.consent = consent.button_pressed
	if not target_state.save_game():
		target_state.restore_health_snapshot(old)
		status.text = "存档写入失败，原有属性已保留。请检查存档目录权限后重试。"
		update_buttons()
		return
	committed = true
	ui.refresh()
	ui.close_modal()
	if game.guest_mode and int(target_state.equipment.get("starter_ten_pulls", 0)) > 0:
		ui.toast("基础状态已保存，游客赠送一次免费十连。")
		ui.call_deferred("open_treasure", "wish")
	else:
		ui.toast("基础状态已保存，开始修行吧！")

func shutdown() -> void:
	if disposed:
		return
	disposed = true
	# Raw medical inputs belong only to this health form, never to the family Store.
	draft.clear()
	record_id = ""
	submitted_inputs = ""
	chosen_path = ""
	chosen_paths.clear()
	if is_instance_valid(history_input):
		history_input.text = ""
	if is_instance_valid(medication_input):
		medication_input.text = ""
	if is_instance_valid(preview):
		preview.texture = null
	if is_instance_valid(probe):
		probe.cancel_request()
	if is_instance_valid(work):
		work.cancel_request()

func _exit_tree() -> void:
	shutdown()


func context_matches() -> bool:
	return not disposed and is_instance_valid(game) and game.state == target_state and game.family == bound_family and str(game.family.account.get("id", "")) == bound_account_id and game.account_api.generation == bound_generation and target_state.family_member_id == bound_member_id and target_state.health_revision == bound_health_revision and target_state.health_profile_id == bound_health_profile_id

func prefill_member_identity() -> void:
	if bound_member_id.is_empty():
		return
	var identity = target_state.family_identity
	name_input.text = str(identity.get("name", ""))
	age_input.text = str(int(identity.get("age", 0))) if int(identity.get("age", 0)) > 0 else ""
	relation_input.text = str(identity.get("relation", ""))
	sex_input.select(clampi(["", "男", "女"].find(str(identity.get("sex", ""))), 0, 2))
	fill_mode.select(1 if identity.get("mode", "family") == "self" else 0)
	consent.button_pressed = false
