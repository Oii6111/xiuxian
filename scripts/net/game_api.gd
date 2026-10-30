extends Node
## 游戏域 HTTP 边界；系统可 await invoke 后消费 Result。
## 这里只负责传输，服务器路由尚待实现。地址不配置时明确失败，不回退到本地发奖。
## 健康报告上传应使用独立健康域客户端，不能从这里转发原始健康 payload。
const Result = preload("res://scripts/kernel/result.gd")
const Contracts = preload("res://scripts/kernel/contracts.gd")
const Router = preload("res://scripts/kernel/command_router.gd")
var base_url: String = ""
var bearer_token: String = ""
var timeout_seconds: float = 10.0

func invoke(command: String, payload: Dictionary) -> Dictionary:
	if base_url.is_empty():
		return Result.failure("BACKEND_UNAVAILABLE", "尚未配置游戏后端")
	if not is_inside_tree():
		return Result.failure("NOT_READY", "HTTP 适配器需要挂在场景树中")
	if not Contracts.is_json(payload):
		return Result.failure("INVALID_PAYLOAD", "请求必须是 JSON 数据")
	var request := HTTPRequest.new()
	request.timeout = timeout_seconds
	request.body_size_limit = 1048576
	add_child(request)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not bearer_token.is_empty():
		headers.append("Authorization: Bearer " + bearer_token)
	var body: String = JSON.stringify({"version": 1, "command": command, "payload": payload})
	var started: Error = request.request(base_url.trim_suffix("/") + "/api/v2/commands", headers, HTTPClient.METHOD_POST, body)
	if started != OK:
		request.queue_free()
		return Result.failure("NETWORK_ERROR", "无法启动 HTTP 请求")
	var completed: Array = await request.request_completed
	request.queue_free()
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
