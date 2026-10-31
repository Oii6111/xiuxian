extends "res://scripts/kernel/system_module.gd"
## 任务：任务列表与进度的投影、领奖请求。任务模板由内容表提供。
## 客户端不能确认设备真实性、计算验证倍率或突破每日上限；这些属于服务端规则。
## 完成状态来自 D 核验后 C 的结算；本模块只读投影，不构造可信事件。

func _init() -> void:
	super("quests")

var _session: int = 0

func state_version() -> int:
	return 2

func initial_state() -> Dictionary:
	return {"revision": 0, "business_date": "", "account_revision": -1, "members": []}

func validate_state(state: Dictionary) -> bool:
	if state.size() != 4 or not Contracts.is_json(state) or not state.get("members") is Array or not state.get("business_date") is String:
		return false
	return Contracts.matches(state.get("revision"), "integer") and state.revision >= 0 and Contracts.matches(state.get("account_revision"), "integer")

func migrate_state(from_version: int, state: Dictionary) -> Dictionary:
	if from_version != 1 or not Contracts.validate(state, {"revision": "integer"}).ok or state.revision < 0:
		return Result.failure("MIGRATION_REQUIRED", "任务旧状态不合法")
	var migrated: Dictionary = initial_state()
	migrated.revision = state.revision
	return Result.success({"state": migrated})

func on_backend_changed() -> void:
	_session += 1
	if _context != null:
		var state: Dictionary = initial_state()
		state.revision = snapshot().revision + 1
		commit(state)

func execute(command: String, payload: Dictionary) -> Dictionary:
	var session: int = _session
	var result: Dictionary = await request_backend(command, payload)
	if not result.ok:
		return result
	if _context == null or session != _session:
		return Result.failure("SESSION_CHANGED", "请求期间账号已切换，结果未写入当前投影")
	if command != "quests.family_today":
		return result
	var data: Dictionary = result.data
	if not data.get("members") is Array or not Contracts.matches(data.get("revision"), "integer") or data.get("business_date") != payload.date:
		return Result.failure("INVALID_RESPONSE", "任务快照不符合契约")
	var state: Dictionary = snapshot()
	if state.business_date == data.business_date and int(data.revision) < int(state.account_revision):
		return Result.success(state)
	state.members = data.members.duplicate(true)
	state.business_date = data.business_date
	state.account_revision = int(data.revision)
	state.revision = int(state.revision) + 1
	var committed: Dictionary = commit(state)
	if not committed.ok:
		return committed
	return Result.success(data)
