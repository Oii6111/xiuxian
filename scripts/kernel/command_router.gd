extends RefCounted
## Intent 单入口：严格 DTO 校验 → 系统处理 → 统一结果 → 无载荷审计。
## 这只是客户端分派，不是权限控制；账户归属、去重与奖励必须在后端检查。
const Result = preload("res://scripts/kernel/result.gd")
const Contracts = preload("res://scripts/kernel/contracts.gd")
var _routes: Dictionary = {}
var _audit: RefCounted

func _init(audit_service: RefCounted) -> void:
	_audit = audit_service

func register(command: String, fields: Dictionary, handler: Callable) -> Dictionary:
	if not Contracts.valid_fields(fields):
		return Result.failure("INVALID_CONFIG", "命令字段类型未定义")
	if command.is_empty() or _routes.has(command) or not handler.is_valid():
		return Result.failure("DUPLICATE_COMMAND", "命令为空、重复或无处理器")
	_routes[command] = {"fields": fields.duplicate(true), "handler": handler}
	return Result.success()

func dispatch(command: String, payload: Dictionary = {}) -> Dictionary:
	var result: Dictionary
	if not _routes.has(command):
		# 不把任意外部输入写入审计记录。
		result = Result.failure("UNKNOWN_COMMAND", "未声明的命令")
		_audit.record("unknown", result.code)
		return result
	var route: Dictionary = _routes[command]
	result = Contracts.validate(payload, route.fields)
	if result.ok:
		var response: Variant = await route.handler.call(command, payload.duplicate(true))
		if valid_result(response):
			result = response.duplicate(true)
		else:
			result = Result.failure("INVALID_RESULT", "系统返回值不符合 Result 契约")
	_audit.record(command, result.code)
	return result

static func valid_result(response: Variant) -> bool:
	return response is Dictionary and response.get("ok") is bool and response.get("code") is String and response.get("message") is String and response.get("data") is Dictionary and Contracts.is_json(response)

func clear() -> void:
	_routes.clear()
