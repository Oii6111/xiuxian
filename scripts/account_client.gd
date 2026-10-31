extends Node
## Passwords are sent only after verifying the service; tokens stay in memory.
signal completed(action: String, response: Dictionary)
signal progress(message: String)
var service_url = "http://127.0.0.1:8010"
var request: HTTPRequest
var token = ""
var account: Dictionary = {}
var busy = false
var pending_action = ""
var pending_payload: Dictionary = {}
var checking_service = false
var tried_start = false
var allow_autostart = true
var started_server_pid = -1

func _ready() -> void:
	if OS.has_environment("XIUXIAN_ACCOUNT_URL"):
		service_url = OS.get_environment("XIUXIAN_ACCOUNT_URL").trim_suffix("/")
	request = HTTPRequest.new()
	request.timeout = 8
	request.body_size_limit = 65536
	add_child(request)
	request.request_completed.connect(on_response)

func is_authenticated() -> bool:
	return not token.is_empty() and not account.is_empty()

func authenticate(action: String, payload: Dictionary) -> void:
	if busy:
		return
	if action not in ["register", "login"]:
		return
	var local_pattern = RegEx.new()
	local_pattern.compile("^http://(127\\.0\\.0\\.1|localhost):[0-9]{1,5}$")
	var local = local_pattern.search(service_url) != null
	if not local and not service_url.begins_with("https://"):
		completed.emit(action, {"ok": false, "message": "远程账号服务需要使用 HTTPS 地址。"})
		return
	busy = true
	pending_action = action
	pending_payload = payload.duplicate()
	tried_start = false
	checking_service = true
	progress.emit("正在连接账号服务…")
	check_service()

func check_service() -> void:
	var error = request.request(service_url + "/api/v1/health")
	if error != OK:
		finish({"ok": false, "message": "无法连接账号服务，请稍后重试。"})

func send_pending() -> void:
	checking_service = false
	progress.emit({"register": "正在注册账号…", "login": "正在登录…", "logout": "正在退出账号…", "claim-legacy": "正在保留旧进度…"}.get(pending_action, "正在处理…"))
	var headers = PackedStringArray(["Content-Type: application/json"])
	if not token.is_empty():
		headers.append("Authorization: Bearer " + token)
	var error = request.request(service_url + "/api/v1/auth/" + pending_action, headers, HTTPClient.METHOD_POST, JSON.stringify(pending_payload))
	if error != OK:
		finish({"ok": false, "message": "请求未能发送，请重试。"})

func claim_legacy(fingerprint: String) -> void:
	if busy or not is_authenticated():
		return
	busy = true
	pending_action = "claim-legacy"
	pending_payload = {"fingerprint": fingerprint}
	send_pending()

func logout() -> void:
	if busy:
		return
	busy = true
	pending_action = "logout"
	pending_payload = {}
	send_pending()

func on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if checking_service:
		if result != HTTPRequest.RESULT_SUCCESS:
			if not tried_start and allow_autostart and service_url.begins_with("http://127.0.0.1:"):
				tried_start = true
				var python = OS.get_environment("XIUXIAN_ACCOUNT_PYTHON")
				if python.is_empty():
					python = "python"
				var port = service_url.get_slice(":", 2)
				var server_path = ProjectSettings.globalize_path("res://server/account/server.py")
				var pid = OS.create_process(python, PackedStringArray([server_path, "--port", port]), false)
				started_server_pid = pid
				if pid > 0:
					progress.emit("正在准备账号服务…")
					await get_tree().create_timer(1.0).timeout
					if busy:
						check_service()
					return
			finish({"ok": false, "message": "账号服务未连接，可运行 server/account/server.py 后重试。"})
			return
		var health = JSON.parse_string(body.get_string_from_utf8())
		if code != 200 or not health is Dictionary or health.get("service") != "xiuxian-accounts" or int(health.get("api_version", 0)) != 1:
			finish({"ok": false, "message": "账号服务版本不匹配，请检查服务地址。"})
			return
		send_pending()
		return
	if pending_action == "logout":
		token = ""
		account.clear()
		finish({"ok": true})
		return
	var response = JSON.parse_string(body.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or not response is Dictionary:
		finish({"ok": false, "message": "连接中断或超时，请重试。注册超时后也可以尝试登录。"})
		return
	if code != 200 or response.get("ok", false) != true:
		finish({"ok": false, "message": str(response.get("message", "操作失败，请重试。"))})
		return
	if pending_action in ["register", "login"]:
		var identity = response.get("account", {})
		var id_pattern = RegEx.new()
		id_pattern.compile("^[a-f0-9]{32}$")
		if not identity is Dictionary or id_pattern.search(str(identity.get("id", ""))) == null or str(response.get("token", "")).is_empty():
			finish({"ok": false, "message": "账号响应格式不正确。"})
			return
		account = identity.duplicate(true)
		token = str(response.token)
		finish({"ok": true, "account": account.duplicate(true)})
	else:
		finish({"ok": true})

func finish(response: Dictionary) -> void:
	var action = pending_action
	pending_payload.clear()
	pending_action = ""
	busy = false
	checking_service = false
	completed.emit(action, response)

func _exit_tree() -> void:
	pending_payload.clear()
	token = ""
	account.clear()
	if is_instance_valid(request):
		request.cancel_request()
