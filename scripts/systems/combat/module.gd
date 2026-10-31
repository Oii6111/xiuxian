extends "res://scripts/kernel/system_module.gd"
## 战斗：接收属性与装备快照，管理会话并上报战果；即时战斗实体放 scripts/combat/。
## 只允许修行状态出战；战果不能改变渡劫结果，奖励由服务端结算。
## 出战资格通过注入的 gate 查询生命周期，属性快照通过注入的 provider 获取：
## combat 不读取其他系统的状态分区，未接入时明确拒绝，不默认放行、不本地编造属性。
## gate 签名：func(cultivator_id: String) -> bool。
## provider 签名：func(cultivator_id: String, encounter_id: String) -> Dictionary（Result，可 await），
## data 为 {"player": 属性快照, "enemy": 属性快照}，字段见 combat_rules.gd 的 valid_snapshot。
const Router = preload("res://scripts/kernel/command_router.gd")
const Rules = preload("res://scripts/systems/combat/combat_rules.gd")
const SESSION_KEYS: Array = ["cultivator_id", "encounter_id", "finished", "won", "duration_seconds"]
const MAX_SESSIONS: int = 50
var _gate: Callable = Callable()
var _provider: Callable = Callable()
var _gateway: Callable = Callable()
var _outcomes: Dictionary = {}

func _init() -> void:
	super("combat")

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
	return {"revision": 0, "next_session": 1, "sessions": {}}

func validate_state(state: Dictionary) -> bool:
	if state.size() != 3 or not _is_whole(state.get("revision")) or int(state.revision) < 0:
		return false
	if not _is_whole(state.get("next_session")) or int(state.next_session) < 1 or not state.get("sessions") is Dictionary:
		return false
	if state.sessions.size() > MAX_SESSIONS:
		return false
	for session_id in state.sessions:
		if not session_id is String or session_id.is_empty() or not _valid_session(state.sessions[session_id]):
			return false
	return true

func _valid_session(session: Variant) -> bool:
	if not session is Dictionary or session.size() != SESSION_KEYS.size():
		return false
	for key in SESSION_KEYS:
		if not session.has(key):
			return false
	if not session["cultivator_id"] is String or session["cultivator_id"] == "" or not session["encounter_id"] is String or session["encounter_id"] == "":
		return false
	if not session["finished"] is bool or not session["won"] is bool:
		return false
	if not (session["duration_seconds"] is int or session["duration_seconds"] is float) or not is_finite(float(session["duration_seconds"])) or float(session["duration_seconds"]) < 0.0:
		return false
	# 未结束的会话不能带战果。
	return session["finished"] or (not session["won"] and float(session["duration_seconds"]) == 0.0)

func _is_whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

func set_gate(gate: Callable) -> void:
	_gate = gate

func set_provider(provider: Callable) -> void:
	_provider = provider

## 正式装配必须注入 C 的 invoke(command, payload)，会话和战果由服务端接受后才提交投影。
func set_gateway(gateway: Callable) -> void:
	_gateway = gateway

func execute(command: String, payload: Dictionary) -> Dictionary:
	match command:
		"combat.start":
			return await _start(payload)
		"combat.finish":
			return await _finish(payload)
	return Result.failure("NOT_IMPLEMENTED", "该命令尚未实现：" + command)

func _start(payload: Dictionary) -> Dictionary:
	var cultivator_id: String = payload.cultivator_id
	var encounter_id: String = payload.encounter_id
	if not _gate.is_valid():
		return Result.failure("BACKEND_UNAVAILABLE", "尚未接入生命周期状态；无法确认可以出战")
	if not _gate.call(cultivator_id):
		return Result.failure("NOT_ALLOWED", "只有修行状态的修仙者可以出战")
	if _active_session(cultivator_id) != "":
		return Result.failure("SESSION_ACTIVE", "该修仙者已有进行中的战斗")
	if not _provider.is_valid():
		return Result.failure("BACKEND_UNAVAILABLE", "尚未接入属性快照；无法开始战斗")
	var response: Variant = await _provider.call(cultivator_id, encounter_id)
	if not response is Dictionary or not response.get("ok") is bool or not response.get("data") is Dictionary:
		return Result.failure("INVALID_RESULT", "属性快照返回值不符合 Result 契约")
	if not response["ok"]:
		var code: String = str(response.get("code", ""))
		return Result.failure(code if not code.is_empty() else "REJECTED", str(response.get("message", "")))
	var data: Dictionary = response["data"]
	if not data.get("player") is Dictionary or not data.get("enemy") is Dictionary or not Rules.valid_snapshot(data["player"]) or not Rules.valid_snapshot(data["enemy"]):
		return Result.failure("INVALID_SNAPSHOT", "属性快照缺失或不合法")
	# await 之后重新核对：期间可能已进入渡劫，或同一修仙者已开了另一局。
	if not _gate.is_valid() or not _gate.call(cultivator_id):
		return Result.failure("NOT_ALLOWED", "等待属性快照期间状态已变化，无法出战")
	if _active_session(cultivator_id) != "":
		return Result.failure("SESSION_ACTIVE", "该修仙者已有进行中的战斗")
	var authoritative: Dictionary = {}
	if _gateway.is_valid():
		var accepted: Variant = await _call_gateway("combat.start", payload)
		if not accepted is Dictionary or not accepted.get("ok", false):
			return accepted if accepted is Dictionary else Result.failure("INVALID_RESULT", "会话响应无效")
		authoritative = accepted.get("data", {})
		if not authoritative.get("session_id") is String or str(authoritative.session_id).is_empty():
			return Result.failure("INVALID_RESULT", "服务端未签发会话")
		if not authoritative.get("player") is Dictionary or not authoritative.get("enemy") is Dictionary:
			return Result.failure("INVALID_SNAPSHOT", "服务端未返回属性快照")
		if not Rules.valid_snapshot(authoritative.player) or not Rules.valid_snapshot(authoritative.enemy):
			return Result.failure("INVALID_SNAPSHOT", "服务端属性快照无效")
		if not _gate.is_valid() or not _gate.call(cultivator_id):
			return Result.failure("NOT_ALLOWED", "等待服务端会话期间状态已变化")
		if _active_session(cultivator_id) != "":
			return Result.failure("SESSION_ACTIVE", "等待期间已开启另一局战斗")
		data = authoritative
	var state: Dictionary = snapshot()
	if state.sessions.size() >= MAX_SESSIONS:
		for old_id in state.sessions.keys():
			if state.sessions[old_id].finished:
				state.sessions.erase(old_id)
				break
	if state.sessions.size() >= MAX_SESSIONS:
		return Result.failure("SESSION_LIMIT", "战斗会话已满，请先结束或清理旧会话")
	var session_id: String = str(authoritative.get("session_id", "s_%d" % int(state.next_session)))
	if state.sessions.has(session_id):
		return Result.failure("SESSION_ACTIVE", "该会话已存在")
	state.next_session = int(state.next_session) + 1
	state.sessions[session_id] = {"cultivator_id": cultivator_id, "encounter_id": encounter_id, "finished": false, "won": false, "duration_seconds": 0.0}
	state.revision += 1
	var committed: Dictionary = commit(state)
	if not committed.ok:
		return committed
	return Result.success({"session_id": session_id, "player": data["player"].duplicate(true), "enemy": data["enemy"].duplicate(true)})

func _finish(payload: Dictionary) -> Dictionary:
	var session_id: String = payload.session_id
	var duration: float = float(payload.duration_seconds)
	if _outcomes.has(session_id) and _outcomes[session_id] != payload:
		return Result.failure("RESULT_CONFLICT", "同一会话不能改写已提交的战果")
	var state: Dictionary = snapshot()
	if not state.sessions.has(session_id):
		return Result.failure("NOT_FOUND", "没有这个战斗会话")
	var session: Dictionary = state.sessions[session_id]
	if session.finished:
		# 重复上报只返回原结果，不重复通知、不重复结算。
		return Result.success({"won": session.won, "duration_seconds": session.duration_seconds, "replayed": true})
	if duration < 0.0 or duration > 86400.0:
		return Result.failure("INVALID_PAYLOAD", "战斗时长超出合理范围")
	if _gateway.is_valid():
		_outcomes[session_id] = payload.duplicate(true)
		var accepted: Variant = await _call_gateway("combat.finish", payload)
		if not accepted is Dictionary or not accepted.get("ok", false):
			return accepted if accepted is Dictionary else Result.failure("INVALID_RESULT", "战果响应无效")
		state = snapshot()
		session = state.sessions.get(session_id, {})
		if session.is_empty():
			return Result.failure("NOT_FOUND", "等待期间会话已移除")
		if session.finished:
			return Result.success({"won": session.won, "duration_seconds": session.duration_seconds, "replayed": true})
		_outcomes.erase(session_id)
	session.finished = true
	session.won = payload.won
	session.duration_seconds = snappedf(duration, 0.01)
	state.revision += 1
	var committed: Dictionary = commit(state)
	if not committed.ok:
		return committed
	# 只通知战果，不产出资源；奖励由服务端根据战果另行结算。
	_context.events.publish("combat.finished", {"session_id": session_id, "cultivator_id": session.cultivator_id, "won": session.won})
	return Result.success({"won": session.won, "duration_seconds": session.duration_seconds, "replayed": false})

func _active_session(cultivator_id: String) -> String:
	var sessions: Dictionary = snapshot().get("sessions", {})
	for session_id in sessions:
		var session: Dictionary = sessions[session_id]
		if session.cultivator_id == cultivator_id and not session.finished:
			return session_id
	return ""

func _call_gateway(command: String, payload: Dictionary) -> Dictionary:
	var response: Variant = await _gateway.call(command, payload.duplicate(true))
	if not Router.valid_result(response):
		return Result.failure("INVALID_RESULT", "服务端响应不符合 Result 契约")
	return response.duplicate(true)
