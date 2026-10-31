extends "res://scripts/kernel/system_module.gd"
## 赛季：同步当前赛季，提示体检刷新；具体切季规则由服务端负责。
## 灵根、装备、境界等永久状态保留。未体检沿用旧属性，不能清空角色。

func _init() -> void:
	super("season")

var _request_sequence: int = 0

func state_version() -> int:
	return 2

func initial_state() -> Dictionary:
	return {"revision": 0, "calendar_version": "", "current": {}, "cultivator_id": "", "checkup_status": "unknown", "checkup_reminder": ""}

func on_backend_changed() -> void:
	_request_sequence += 1
	if _context != null:
		var state: Dictionary = initial_state()
		state.revision = snapshot().revision + 1
		commit(state)

func validate_state(state: Dictionary) -> bool:
	if state.size() != 6 or not Contracts.is_json(state):
		return false
	if not Contracts.matches(state.get("revision"), "integer") or state.revision < 0 or not state.get("current") is Dictionary:
		return false
	for field in ["calendar_version", "cultivator_id", "checkup_status", "checkup_reminder"]:
		if not state.get(field) is String:
			return false
	if state.current.is_empty():
		return true
	return Contracts.validate(state.current, {"id": "string", "starts_at": "string", "ends_at": "string"}).ok

## v1 仅有 revision；迁移不访问网络、不重置其他系统的永久积累。
func migrate_state(from_version: int, state: Dictionary) -> Dictionary:
	if from_version != 1 or not Contracts.validate(state, {"revision": "integer"}).ok or state.revision < 0:
		return Result.failure("MIGRATION_REQUIRED", "赛季旧状态不合法")
	var migrated: Dictionary = initial_state()
	migrated.revision = state.revision
	return Result.success({"state": migrated})

func execute(command: String, payload: Dictionary) -> Dictionary:
	if command != "season.refresh":
		return Result.failure("UNKNOWN_COMMAND", "赛季命令不存在")
	_request_sequence += 1
	var sequence: int = _request_sequence
	var result: Dictionary = await request_backend(command, payload)
	if not result.ok:
		return result
	if _context == null or sequence != _request_sequence:
		return Result.failure("STALE_RESPONSE", "赛季请求已被更新的请求替代")
	var fields: Dictionary = {"calendar_version": "string", "current": "object", "cultivator_id": "string", "checkup_status": "string", "checkup_reminder": "string"}
	if not Contracts.validate(result.data, fields).ok or result.data.cultivator_id != payload.cultivator_id:
		return Result.failure("INVALID_RESPONSE", "赛季响应不符合契约")
	var state: Dictionary = result.data.duplicate(true)
	state["revision"] = snapshot().revision + 1
	if not validate_state(state) or state.current.is_empty():
		return Result.failure("INVALID_RESPONSE", "赛季日历响应不合法")
	var committed: Dictionary = commit(state)
	if not committed.ok:
		return committed
	_context.events.publish("season.changed", {"season_id": state.current.id})
	return Result.success(state)
