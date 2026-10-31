extends Control
## All credentials stay at the verified game account origin. Bot tokens never enter Godot.
var game: Node
var ui: Control
var request: HTTPRequest
var status: Label
var connect_button: Button
var member_id = ""
var owner_scope = ""
var operation = ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	member_id = game.family.active_id
	owner_scope = str(game.family.account.id) + ":" + str(game.account_api.generation)
	var shade = ColorRect.new()
	shade.color = Color(0.08, 0.1, 0.08, 0.7)
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card = ui.card(Rect2(340, 180, 760, 530), self, Color("f5e8c9"))
	ui.label_into(card, "连接微信与灵宠", 29)
	ui.paragraph(card, "当前角色：" + game.state.member_label() + "\n请让这位角色对应的体验者扫码。微信安排与完成记录只同步给当前账号的这位角色。", 19)
	ui.line(card)
	status = ui.paragraph(card, "正在读取连接状态…", 18)
	status.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui.paragraph(card, "扫码后在浏览器核对角色并确认任务共享。连接成功后，在微信发送“今日任务”开始。", 16)
	connect_button = ui.button(card, "打开微信扫码窗口", func(): send("invite"), true)
	ui.button(card, "刷新连接状态", func(): send("status"))
	ui.button(card, "断开当前角色的微信", func(): send("revoke"))
	ui.button(card, "返回灵宠", ui.open_companion)
	request = HTTPRequest.new()
	request.timeout = 25
	request.max_redirects = 0
	request.body_size_limit = 65536
	request.request_completed.connect(on_response)
	add_child(request)
	send("status")

func valid_scope() -> bool:
	return game.account_ready and game.account_api.is_authenticated() and owner_scope == str(game.family.account.id) + ":" + str(game.account_api.generation) and member_id == game.family.active_id

func send(action: String) -> void:
	if not operation.is_empty() or not valid_scope():
		return
	operation = action
	connect_button.disabled = true
	var root_url = game.account_api.authenticated_service_url
	var headers = PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + game.account_api.token])
	var endpoint = "/api/v1/wechat/bindings"
	var method = HTTPClient.METHOD_GET
	var body = ""
	if action != "status":
		endpoint = "/api/v1/wechat/invitations" if action == "invite" else "/api/v1/wechat/bindings/revoke"
		method = HTTPClient.METHOD_POST
		body = JSON.stringify({"game_member_id": member_id, "label": game.state.member_label()})
	status.text = "正在打开微信连接…" if action == "invite" else "正在读取连接状态…"
	var error = request.request(root_url + endpoint, headers, method, body)
	if error != OK:
		operation = ""
		connect_button.disabled = false
		status.text = "连接服务暂未响应，请确认现场服务已启动。"

func on_response(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
	var action = operation
	operation = ""
	connect_button.disabled = false
	if not valid_scope():
		return
	var value = JSON.parse_string(bytes.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not value is Dictionary or not value.get("ok", false):
		status.text = str(value.get("message", "连接服务暂未响应，请稍后重试。")) if value is Dictionary else "连接服务暂未响应，请稍后重试。"
		return
	if action == "invite":
		var url = str(value.get("login_url", ""))
		var allowed = RegEx.new()
		allowed.compile("^http://127\\.0\\.0\\.1:[0-9]{1,5}/login/[a-f0-9]{48}/$")
		if allowed.search(url) != null:
			OS.shell_open(url)
			status.text = "扫码窗口已打开。完成手机确认后，请在浏览器核对角色并确认共享。"
		else:
			status.text = "登录地址不符合本机场景要求，请检查服务配置。"
	elif action == "revoke":
		status.text = "当前角色已断开微信，停止共享新记录。"
	else:
		var connected = false
		var channel_status = "offline"
		for binding in value.get("bindings", []):
			if binding is Dictionary and binding.get("member_id") == member_id and binding.get("status") == "active":
				connected = true
				channel_status = str(binding.get("channel_status", "offline"))
		if connected and channel_status == "active":
			status.text = "微信已连接。请在微信发送“今日任务”；任务更新会自动同步。"
		elif connected:
			status.text = "角色绑定已保存，微信收发服务尚未连接。请检查服务；登录失效时断开后重新扫码。"
		else:
			status.text = "当前角色还没有连接微信。"
	game.companion_tasks.refresh_now()
