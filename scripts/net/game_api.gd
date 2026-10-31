extends Node
## 游戏域 HTTP 边界；系统可 await invoke 后消费 Result。
## 对接 C 的本地服务；地址不配置时明确失败，不回退到本地发奖。
## 健康报告上传应使用独立健康域客户端，不能从这里转发原始健康 payload。
const Result = preload("res://scripts/kernel/result.gd")
const Contracts = preload("res://scripts/kernel/contracts.gd")
const Router = preload("res://scripts/kernel/command_router.gd")
signal session_changed
var _session_generation: int = 0
var base_url: String = "":
	set(value):
		if value != base_url:
			base_url = value
			_session_generation += 1
			session_changed.emit()
var bearer_token: String = "":
	set(value):
		if value != bearer_token:
			bearer_token = value
			_session_generation += 1
			session_changed.emit()
var timeout_seconds: float = 10.0

func invoke(command: String, payload: Dictionary, idempotency_key: String = "") -> Dictionary:
	return await request_api("/api/v2/commands", HTTPClient.METHOD_POST,
		{"version": 1, "command": command, "payload": payload}, idempotency_key)

func register_account(username: String, password: String) -> Dictionary:
	return await request_api("/api/v2/auth/register", HTTPClient.METHOD_POST, {"username": username, "password": password})

func login(username: String, password: String) -> Dictionary:
	var result: Dictionary = await request_api("/api/v2/auth/login", HTTPClient.METHOD_POST, {"username": username, "password": password})
	if result.ok:
		if not result.data.get("token") is String or result.data.token.is_empty():
			return Result.failure("INVALID_RESPONSE", "登录响应缺少会话令牌")
		bearer_token = result.data.token
	return result

func logout(all_sessions: bool = false) -> Dictionary:
	var path: String = "/api/v2/auth/logout-all" if all_sessions else "/api/v2/auth/logout"
	var result: Dictionary = await request_api(path, HTTPClient.METHOD_POST)
	if result.ok or result.code == "UNAUTHORIZED":
		bearer_token = ""
	return result

func fetch_snapshot() -> Dictionary:
	return await request_api("/api/v2/snapshot")

## 只允许游戏侧接口；D 的服务凭证和内部接口不能通过此适配器访问。
## 超时后的写操作由调用者使用原幂等键重试，不自动生成新键。
func request_api(path: String, method: int = HTTPClient.METHOD_GET, payload: Dictionary = {}, idempotency_key: String = "") -> Dictionary:
	if base_url.is_empty():
		return Result.failure("BACKEND_UNAVAILABLE", "尚未配置游戏后端")
	if not is_inside_tree():
		return Result.failure("NOT_READY", "HTTP 适配器需要挂在场景树中")
	if not Contracts.is_json(payload):
		return Result.failure("INVALID_PAYLOAD", "请求必须是 JSON 数据")
	if not path.begins_with("/api/v2/") or ".." in path or "\n" in path or "\r" in path:
		return Result.failure("INVALID_PATH", "只允许游戏域接口")
	if "\n" in idempotency_key or "\r" in idempotency_key or idempotency_key.length() > 128:
		return Result.failure("INVALID_PAYLOAD", "幂等键无效")
	var generation: int = _session_generation
	var request := HTTPRequest.new()
	request.timeout = timeout_seconds
	request.body_size_limit = 1048576
	add_child(request)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not bearer_token.is_empty():
		headers.append("Authorization: Bearer " + bearer_token)
	if not idempotency_key.is_empty():
		headers.append("Idempotency-Key: " + idempotency_key)
	var body: String = "" if method == HTTPClient.METHOD_GET else JSON.stringify(payload)
	var started: Error = request.request(base_url.trim_suffix("/") + path, headers, method, body)
	if started != OK:
		request.queue_free()
		return Result.failure("NETWORK_ERROR", "无法启动 HTTP 请求")
	var completed: Array = await request.request_completed
	request.queue_free()
	if generation != _session_generation:
		return Result.failure("SESSION_CHANGED", "请求期间账号或服务地址发生变化，请重新读取快照")
	if completed[0] != HTTPRequest.RESULT_SUCCESS:
		return Result.failure("NETWORK_ERROR", "连接失败或请求超时")
	var parser := JSON.new()
	var parsed: Error = parser.parse(completed[3].get_string_from_utf8())
	if parsed != OK or not Router.valid_result(parser.data):
		return Result.failure("INVALID_RESPONSE", "服务端响应不符合 Result 契约")
	var response: Dictionary = parser.data
	if (completed[1] < 200 or completed[1] >= 300) and response.ok:
		return Result.failure("HTTP_ERROR", "服务端状态码与结果不一致")
	return response.duplicate(true)
