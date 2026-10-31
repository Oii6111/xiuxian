extends "res://scripts/kernel/system_module.gd"
## 生命周期：修行/渡劫/闭关/飞升，以及渡劫阶段、庆典与纪念流程。
## 必须经家属确认；飞升需要二次确认。掉线、计时器和战斗结果都不是触发源。
## 客户端只保存服务端状态的投影，不签发也不消费确认令牌：令牌由服务端权威签发，
## 这里通过注入的 authority 回调转发；未接入时明确返回 BACKEND_UNAVAILABLE，绝不本地伪造确认。
## authority 签名：func(operation: String, payload: Dictionary) -> Result（可 await）。
const Rules = preload("res://scripts/systems/lifecycle/lifecycle_rules.gd")
const ENTRY_KEYS: Array = ["state", "version", "template_id", "stage_index", "pending_target", "last_request_id"]
var _authority: Callable = Callable()
var _responses: Dictionary = {}

func _init() -> void:
	super("lifecycle")

func state_version() -> int:
	return 2

func migrate_state(from_version: int, old: Dictionary) -> Dictionary:
	if from_version != 1:
		return Result.failure("MIGRATION_REQUIRED", "不支持的模块存档版本")
	if old.size() == 1 and old.get("revision") == 0:
		return Result.success({"state": initial_state()})
	if validate_state(old):
		return Result.success({"state": old.duplicate(true)})
	return Result.failure("INVALID_STATE", "旧模块存档无效")

func initial_state() -> Dictionary:
	return {"revision": 0, "cultivators": {}}

func validate_state(state: Dictionary) -> bool:
	if state.size() != 2 or not _is_whole(state.get("revision")) or int(state.revision) < 0 or not state.get("cultivators") is Dictionary:
		return false
	for cultivator_id in state.cultivators:
		if not cultivator_id is String or cultivator_id.is_empty() or not _valid_entry(state.cultivators[cultivator_id]):
			return false
	return true

func _valid_entry(entry: Variant) -> bool:
	if not entry is Dictionary or entry.size() != ENTRY_KEYS.size():
		return false
	for key in ENTRY_KEYS:
		if not entry.has(key):
			return false
	var current: Variant = entry["state"]
	if not current is String or not Rules.is_state(current):
		return false
	if not _is_whole(entry["version"]) or int(entry["version"]) < 0 or not _is_whole(entry["stage_index"]):
		return false
	if not entry["template_id"] is String or not entry["pending_target"] is String or not entry["last_request_id"] is String:
		return false
	var index: int = int(entry["stage_index"])
	if entry["template_id"] == "":
		if index != -1:
			return false
	elif current != "tribulation" or not Rules.TEMPLATES.has(entry["template_id"]) or index < 0 or index >= Rules.TEMPLATES[entry["template_id"]].stages.size():
		return false
	if entry["pending_target"] != "" and not Rules.can_transition(current, entry["pending_target"]):
		return false
	return true

func _is_whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

## 由装配层或联调代码注入服务端确认通道；传入空 Callable 即断开。
func set_authority(authority: Callable) -> void:
	_authority = authority

## 战斗等系统用它判断能否出战；只读，不暴露内部状态。
func allows_combat(cultivator_id: String) -> bool:
	var entry: Dictionary = _entry(cultivator_id)
	return not entry.is_empty() and Rules.allows_combat(entry.state)

## 服务端权威状态同步入口（登录、重连、快照恢复）。拒绝比本地更旧的版本。
func apply_authoritative(cultivator_id: String, state: String, version: int, template_id: String = "", stage_index: int = -1) -> Dictionary:
	if cultivator_id.is_empty() or not Rules.is_state(state):
		return Result.failure("INVALID_STATE", "修仙者或状态无效")
	var existing: Dictionary = _entry(cultivator_id)
	if not existing.is_empty() and version < int(existing.version):
		return Result.failure("STALE_VERSION", "服务端状态版本比本地更旧")
	if not existing.is_empty() and version == int(existing.version):
		if existing.state != state or existing.template_id != template_id or int(existing.stage_index) != stage_index:
			return Result.failure("STALE_VERSION", "相同版本的状态内容不一致")
		return Result.success()
	var pending: String = ""
	if not existing.is_empty() and Rules.can_transition(state, existing.pending_target):
		pending = existing.pending_target
	var entry: Dictionary = _make_entry(state, version, template_id, stage_index, pending, "")
	if not _valid_entry(entry):
		return Result.failure("INVALID_STATE", "生命周期状态组合无效")
	return _write(cultivator_id, entry)

func execute(command: String, payload: Dictionary) -> Dictionary:
	match command:
		"lifecycle.request_change":
			return await _request_change(payload)
		"lifecycle.confirm_change":
			return await _confirm_change(payload)
		"lifecycle.update_stage":
			return await _update_stage(payload)
	return Result.failure("NOT_IMPLEMENTED", "该命令尚未实现：" + command)

func _request_change(payload: Dictionary) -> Dictionary:
	var cultivator_id: String = payload.cultivator_id
	var target: String = payload.target_state
	var entry: Dictionary = _entry(cultivator_id)
	if entry.is_empty():
		return Result.failure("NOT_FOUND", "尚无该修仙者的生命周期状态，请先同步服务端状态")
	if not Rules.is_state(target):
		return Result.failure("INVALID_STATE", "未知的目标状态")
	if not Rules.can_transition(entry.state, target):
		return Result.failure("INVALID_TRANSITION", "当前状态不允许迁移到目标状态")
	var granted: Dictionary = await _authority_call("request_change", {"cultivator_id": cultivator_id, "target_state": target, "from_version": int(entry.version)})
	if not granted.ok:
		return granted
	var token: Variant = granted.data.get("confirmation_token")
	if not token is String or token.is_empty():
		return Result.failure("INVALID_RESULT", "服务端未返回确认令牌")
	var current: Dictionary = _entry(cultivator_id)
	if not _unchanged(entry, current):
		return Result.failure("STALE_STATE", "状态在等待确认期间已变化，请刷新后重试")
	# 令牌只交给调用方，不写入存档。
	current.pending_target = target
	var written: Dictionary = _write(cultivator_id, current)
	if not written.ok:
		return written
	return Result.success({"target_state": target, "confirmations_required": Rules.confirmations_required(target), "confirmation_token": token})

func _confirm_change(payload: Dictionary) -> Dictionary:
	var cultivator_id: String = payload.cultivator_id
	var request_id: String = payload.request_id
	var entry: Dictionary = _entry(cultivator_id)
	if entry.is_empty():
		return Result.failure("NOT_FOUND", "尚无该修仙者的生命周期状态，请先同步服务端状态")
	if entry.last_request_id == request_id:
		# 重试同一个请求只返回原结果，不重复迁移、不重复通知。
		return Result.success({"complete": true, "replayed": true, "state": entry.state})
	var replay_key: String = cultivator_id + ":" + request_id
	if _responses.has(replay_key):
		return Result.success(_responses[replay_key])
	var target: String = entry.pending_target
	if target.is_empty():
		return Result.failure("NO_PENDING_REQUEST", "没有待确认的状态变更")
	var granted: Dictionary = await _authority_call("confirm_change", {"cultivator_id": cultivator_id, "confirmation_token": payload.confirmation_token, "request_id": request_id, "target_state": target})
	if not granted.ok:
		return granted
	var data: Dictionary = granted.data
	var observed: Dictionary = _entry(cultivator_id)
	if not _unchanged(entry, observed) or observed.pending_target != target:
		return Result.failure("STALE_STATE", "确认期间状态已变化，请刷新")
	if not data.get("complete") is bool:
		return Result.failure("INVALID_RESULT", "确认结果缺少 complete")
	if data.get("state") != target:
		return Result.failure("INVALID_RESULT", "服务端确认的目标状态与待确认请求不一致")
	if data.get("complete", false) != true:
		# 飞升需要二次确认：第一次只记录进度，状态不变。
		if not _is_whole(data.get("remaining")) or int(data.remaining) < 1 or int(data.remaining) >= Rules.confirmations_required(target):
			return Result.failure("INVALID_RESULT", "确认次数无效")
		_responses[replay_key] = {"complete": false, "remaining": int(data.remaining), "state": entry.state}
		if _responses.size() > 64:
			_responses.erase(_responses.keys()[0])
		return Result.success(_responses[replay_key])
	var current: Dictionary = _entry(cultivator_id)
	if not _unchanged(entry, current) or current.pending_target != target:
		return Result.failure("STALE_STATE", "状态在等待确认期间已变化，请刷新后重试")
	var version: int = _server_version(data, int(entry.version))
	if version < 0:
		return Result.failure("INVALID_RESULT", "服务端未返回有效的状态版本")
	var written: Dictionary = _write(cultivator_id, _make_entry(target, version, "", -1, "", request_id))
	if not written.ok:
		return written
	return Result.success({"complete": true, "replayed": false, "state": target})

func _update_stage(payload: Dictionary) -> Dictionary:
	var cultivator_id: String = payload.cultivator_id
	var entry: Dictionary = _entry(cultivator_id)
	if entry.is_empty():
		return Result.failure("NOT_FOUND", "尚无该修仙者的生命周期状态，请先同步服务端状态")
	if entry.state != "tribulation":
		return Result.failure("NOT_IN_TRIBULATION", "只有渡劫中才能更新阶段")
	var parsed: Dictionary = Rules.parse_stage(payload.stage_id)
	if parsed.is_empty():
		return Result.failure("INVALID_STAGE", "未知的渡劫阶段")
	var template_id: String = entry.template_id
	if template_id.is_empty():
		if parsed.index != 0:
			return Result.failure("INVALID_STAGE", "渡劫必须从入院阶段开始")
	elif parsed.template_id != template_id:
		return Result.failure("INVALID_STAGE", "渡劫中不能更换阶段模板")
	elif not Rules.can_move_stage(template_id, int(entry.stage_index), parsed.index):
		return Result.failure("INVALID_STAGE", "阶段不能原地重复或越界")
	var granted: Dictionary = await _authority_call("update_stage", {"cultivator_id": cultivator_id, "stage_id": payload.stage_id, "confirmation_token": payload.confirmation_token, "from_version": int(entry.version)})
	if not granted.ok:
		return granted
	var current: Dictionary = _entry(cultivator_id)
	if not _unchanged(entry, current):
		return Result.failure("STALE_STATE", "状态在等待确认期间已变化，请刷新后重试")
	var version: int = _server_version(granted.data, int(entry.version))
	if version < 0:
		return Result.failure("INVALID_RESULT", "服务端未返回有效的状态版本")
	# 到达出院阶段不会自动改变角色状态；渡劫结算必须另行经家属确认。
	var written: Dictionary = _write(cultivator_id, _make_entry("tribulation", version, parsed.template_id, parsed.index, entry.pending_target, entry.last_request_id))
	if not written.ok:
		return written
	return Result.success({"stage_id": payload.stage_id, "final": Rules.is_final_stage(parsed.template_id, parsed.index)})

func _authority_call(operation: String, payload: Dictionary) -> Dictionary:
	if not _authority.is_valid():
		return Result.failure("BACKEND_UNAVAILABLE", "尚未接入服务端确认；客户端不会本地签发或伪造家属确认")
	var response: Variant = await _authority.call(operation, payload)
	if not response is Dictionary or not response.get("ok") is bool or not response.get("data") is Dictionary:
		return Result.failure("INVALID_RESULT", "服务端确认返回值不符合 Result 契约")
	if not response["ok"]:
		var code: String = str(response.get("code", ""))
		return Result.failure(code if not code.is_empty() else "REJECTED", str(response.get("message", "")))
	return Result.success(response["data"])

func _entry(cultivator_id: String) -> Dictionary:
	if _context == null:
		return {}
	return snapshot().get("cultivators", {}).get(cultivator_id, {})

func _make_entry(state: String, version: int, template_id: String, stage_index: int, pending: String, request_id: String) -> Dictionary:
	return {"state": state, "version": version, "template_id": template_id, "stage_index": stage_index, "pending_target": pending, "last_request_id": request_id}

## await 之后重新核对：版本和状态都没变，才允许写入，避免覆盖期间到达的同步。
func _unchanged(before: Dictionary, current: Dictionary) -> bool:
	return not current.is_empty() and int(current.version) == int(before.version) and current.state == before.state

## 服务端返回的新版本必须严格大于本地版本，否则视为无效。
func _server_version(data: Dictionary, floor_version: int) -> int:
	var value: Variant = data.get("version")
	if not _is_whole(value) or int(value) <= floor_version:
		return -1
	return int(value)

func _write(cultivator_id: String, entry: Dictionary) -> Dictionary:
	if _context == null:
		return Result.failure("NOT_READY", "生命周期系统已停止")
	var state: Dictionary = snapshot()
	state.cultivators[cultivator_id] = entry
	state.revision += 1
	var committed: Dictionary = commit(state)
	if committed.ok:
		_context.events.publish("lifecycle.changed", {"cultivator_id": cultivator_id, "state": entry.state})
	return committed
