extends Node
## PR4 本机演示装配层：使用已登录的当前家人，复用 v2 lifecycle 命令与 FSM。
## 仅将明确家属点击后的游戏投影写进该家人存档；不冒充远程服务，UI 常驻本机演示标识。
const Runtime = preload("res://scripts/kernel/runtime.gd")
const Memory = preload("res://scripts/kernel/adapters/memory_persistence.gd")
const Result = preload("res://scripts/kernel/result.gd")
const Rules = preload("res://scripts/systems/lifecycle/lifecycle_rules.gd")
const Record = preload("res://scripts/systems/lifecycle/family_record.gd")
var runtime: RefCounted
var actor: RefCounted
var actor_id: String
var scope_provider: Callable
var _scope: String
var _serial: int = 0
var _tickets: Dictionary = {}
var _receipts: Dictionary = {}

func bind(character: RefCounted, id: String, scope: Callable) -> Dictionary:
	actor = character
	actor_id = id
	scope_provider = scope
	_scope = str(scope.call())
	if not actor.lifecycle_load_error.is_empty():
		return Result.failure("INVALID_STATE", actor.lifecycle_load_error)
	var record: Dictionary = actor.lifecycle_record()
	runtime = Runtime.new()
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/kernel/contracts.json"))
	var started: Dictionary = runtime.start(contract, Memory.new())
	if not started.ok:
		return started
	var module: RefCounted = runtime._modules.lifecycle
	module.apply_authoritative(actor_id, record.state, record.version, record.template_id if int(record.stage_index) >= 0 else "", record.stage_index)
	module.set_authority(Callable(self, "_authority"))
	return Result.success()

func _current_scope() -> bool:
	return actor != null and scope_provider.is_valid() and str(scope_provider.call()) == _scope

func snapshot(module_id: String) -> Dictionary:
	return runtime.snapshot(module_id) if runtime != null else {}

func dispatch(command: String, payload: Dictionary) -> Dictionary:
	if not _current_scope():
		return Result.failure("ROLE_CHANGED", "账号或家人已切换，请重新打开")
	if str(payload.get("cultivator_id", "")) != actor_id:
		return Result.failure("FORBIDDEN", "操作不属于当前家人")
	if runtime == null:
		return Result.failure("NOT_READY", "状态未同步")
	return await runtime.dispatch(command, payload)

func _authority(operation: String, payload: Dictionary) -> Dictionary:
	if not _current_scope():
		return Result.failure("ROLE_CHANGED", "当前家人已变化")
	var current: Dictionary = actor.lifecycle_record()
	match operation:
		"request_change":
			if int(payload.from_version) != int(current.version):
				return Result.failure("STALE_STATE", "状态已变化，请刷新")
			_serial += 1
			var token: String = "local-family-%d-%d" % [get_instance_id(), _serial]
			_tickets[token] = {"owner": actor_id, "target": payload.target_state, "version": current.version, "count": 0, "expires": Time.get_ticks_msec() + 300000}
			return Result.success({"confirmation_token": token})
		"confirm_change":
			var key: String = str(payload.request_id)
			if _receipts.has(key):
				return _receipts[key].duplicate(true)
			var ticket: Dictionary = _tickets.get(payload.confirmation_token, {})
			if ticket.is_empty() or ticket.owner != actor_id or ticket.target != payload.target_state:
				return Result.failure("FORBIDDEN", "确认令牌归属不匹配")
			if Time.get_ticks_msec() > int(ticket.expires):
				return Result.failure("TOKEN_EXPIRED", "确认已过期，请重新发起")
			if int(ticket.version) != int(current.version):
				return Result.failure("STALE_STATE", "确认期间状态已更新")
			var count: int = int(ticket.count) + 1
			var needed: int = Rules.confirmations_required(ticket.target)
			if count < needed:
				ticket.count = count
				_receipts[key] = Result.success({"complete": false, "state": ticket.target, "remaining": needed - count})
				return _receipts[key].duplicate(true)
			var updated: Dictionary = current.duplicate(true)
			updated.state = ticket.target
			updated.version += 1
			updated.template_id = current.template_id if ticket.target == "tribulation" else ""
			updated.stage_index = -1
			updated = Record.with_event(updated, key, int(Time.get_unix_time_from_system()))
			var saved: Dictionary = actor.commit_lifecycle(updated, int(current.version))
			if not saved.ok:
				return Result.failure(saved.code, saved.message)
			_tickets.erase(payload.confirmation_token)
			_receipts[key] = Result.success({"complete": true, "state": updated.state, "version": updated.version})
			return _receipts[key].duplicate(true)
		"update_stage":
			if int(payload.from_version) != int(current.version) or current.state != "tribulation":
				return Result.failure("STALE_STATE", "状态已变化，请刷新")
			var stage: Dictionary = Rules.parse_stage(payload.stage_id)
			if stage.is_empty():
				return Result.failure("INVALID_STAGE", "阶段不存在")
			var updated: Dictionary = current.duplicate(true)
			updated.template_id = stage.template_id
			updated.stage_index = stage.index
			updated.version += 1
			updated = Record.with_event(updated, "stage_%d" % updated.version, int(Time.get_unix_time_from_system()), payload.stage_id)
			var saved: Dictionary = actor.commit_lifecycle(updated, int(current.version))
			if not saved.ok:
				return Result.failure(saved.code, saved.message)
			return Result.success({"version": updated.version})
	return Result.failure("UNKNOWN_COMMAND", "未知操作")

func record_lamp(count: int) -> Dictionary:
	if not _current_scope():
		return Result.failure("ROLE_CHANGED", "账号或家人已切换")
	var current: Dictionary = actor.lifecycle_record()
	if current.state != "tribulation":
		return Result.failure("NOT_IN_TRIBULATION", "只有渡劫中才能点灯")
	var updated: Dictionary = current.duplicate(true)
	updated.lamps = clampi(count, 0, 24)
	var result: Dictionary = actor.commit_lifecycle(updated, int(current.version))
	return Result.success() if result.ok else Result.failure(result.code, result.message)

## 在开始渡劫前保存模板偏好，尚不代表医疗状态变化。
func remember_template(template_id: String) -> Dictionary:
	if not _current_scope():
		return Result.failure("ROLE_CHANGED", "家人已切换")
	var current: Dictionary = actor.lifecycle_record()
	if current.state != "cultivating" or not Rules.TEMPLATES.has(template_id):
		return Result.failure("INVALID_STATE", "仅修行时可选择下一次渡劫模板")
	var updated: Dictionary = current.duplicate(true)
	updated.template_id = template_id
	var saved: Dictionary = actor.commit_lifecycle(updated, int(current.version))
	return Result.success() if saved.ok else Result.failure(saved.code, saved.message)

func cancel_requests() -> void:
	_tickets.clear()

func _exit_tree() -> void:
	_tickets.clear()
	_receipts.clear()
	scope_provider = Callable()
	actor = null
	if runtime != null:
		runtime.shutdown()
		runtime = null
