extends SceneTree
## 生命周期模块测试：真实 Runtime + 内存存档 + 替身服务端确认通道，不联网、不读玩家存档。
const Runtime = preload("res://scripts/kernel/runtime.gd")
const Memory = preload("res://scripts/kernel/adapters/memory_persistence.gd")
const Result = preload("res://scripts/kernel/result.gd")
var _assertions: int = 0
var _failures: Array[String] = []
var _runtime: RefCounted
var _module: RefCounted
var _authority_calls: Array = []
var _version: int = 10
var _confirms: Dictionary = {}
var _deny: bool = false
var _changes: int = 0

func _init() -> void:
	call_deferred("_run")

func expect(condition: bool, description: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(description)
		printerr("FAIL: ", description)

## 替身服务端：飞升需要两次确认，其余一次；deny 模式模拟家属拒绝。
func _fake_authority(operation: String, payload: Dictionary) -> Dictionary:
	_authority_calls.append(operation)
	if _deny:
		return Result.failure("FORBIDDEN", "家属确认未通过")
	var cultivator_id: String = payload.cultivator_id
	match operation:
		"request_change":
			return Result.success({"confirmation_token": "token-" + cultivator_id})
		"confirm_change":
			var needed: int = 2 if payload.target_state == "ascended" else 1
			_confirms[cultivator_id] = int(_confirms.get(cultivator_id, 0)) + 1
			if _confirms[cultivator_id] < needed:
				return Result.success({"complete": false, "remaining": needed - _confirms[cultivator_id], "state": payload.target_state})
			_confirms[cultivator_id] = 0
			_version += 1
			return Result.success({"complete": true, "state": payload.target_state, "version": _version})
		"update_stage":
			_version += 1
			return Result.success({"version": _version})
	return Result.failure("UNKNOWN_OPERATION", "未知操作")

func _on_changed(_payload: Dictionary) -> void:
	_changes += 1

func _dispatch(command: String, payload: Dictionary) -> Dictionary:
	return await _runtime.dispatch(command, payload)

func _entry(cultivator_id: String) -> Dictionary:
	return _module.snapshot().cultivators.get(cultivator_id, {})

func _run() -> void:
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/kernel/contracts.json"))
	_runtime = Runtime.new()
	var started: Dictionary = _runtime.start(contract, Memory.new())
	expect(started.ok, "runtime boots")
	if not started.ok:
		quit(1)
		return
	_module = _runtime._modules["lifecycle"]
	_runtime.services.events.subscribe("lifecycle.changed", _on_changed)
	await _test_guards()
	await _test_tribulation_flow()
	await _test_denied_and_ascension()
	_test_sync_and_validation()
	_runtime.shutdown()
	print("LIFECYCLE_MODULE_TEST: %d assertions; %d failures" % [_assertions, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _test_guards() -> void:
	var missing: Dictionary = await _dispatch("lifecycle.request_change", {"cultivator_id": "c_001", "target_state": "tribulation"})
	expect(missing.code == "NOT_FOUND", "unknown cultivator has no lifecycle projection")
	expect(_module.apply_authoritative("c_001", "cultivating", 1).ok, "server state sync accepted")
	expect(_module.apply_authoritative("c_001", "dead", 2).code == "INVALID_STATE", "sync rejects unknown state")
	expect(_module.allows_combat("c_001") and not _module.allows_combat("nobody"), "combat gate reads lifecycle state")
	var jump: Dictionary = await _dispatch("lifecycle.request_change", {"cultivator_id": "c_001", "target_state": "ascended"})
	expect(jump.code == "INVALID_TRANSITION", "cultivating cannot jump to ascension")
	var unknown: Dictionary = await _dispatch("lifecycle.request_change", {"cultivator_id": "c_001", "target_state": "dead"})
	expect(unknown.code == "INVALID_STATE", "unknown target rejected")
	var offline: Dictionary = await _dispatch("lifecycle.request_change", {"cultivator_id": "c_001", "target_state": "tribulation"})
	expect(offline.code == "BACKEND_UNAVAILABLE" and _entry("c_001").state == "cultivating", "no authority means no local confirmation")
	expect(_entry("c_001").pending_target == "", "failed request leaves no pending change")
	var before: int = _authority_calls.size()
	_module.set_authority(Callable(self, "_fake_authority"))
	await _dispatch("lifecycle.request_change", {"cultivator_id": "c_001", "target_state": "seclusion"})
	expect(_authority_calls.size() == before, "illegal transitions never reach the authority")

func _test_tribulation_flow() -> void:
	var requested: Dictionary = await _dispatch("lifecycle.request_change", {"cultivator_id": "c_001", "target_state": "tribulation"})
	expect(requested.ok and requested.data.confirmations_required == 1, "request issued by authority")
	expect(requested.data.confirmation_token == "token-c_001", "token returned to caller")
	expect(_entry("c_001").state == "cultivating" and _entry("c_001").pending_target == "tribulation", "request alone does not change state")
	expect(not JSON.stringify(_module.snapshot()).contains("token-c_001"), "token is never persisted")
	var changes: int = _changes
	var confirmed: Dictionary = await _dispatch("lifecycle.confirm_change", {"cultivator_id": "c_001", "confirmation_token": "token-c_001", "request_id": "req_1"})
	expect(confirmed.ok and confirmed.data.complete and not confirmed.data.replayed, "confirmation completes the change")
	expect(_entry("c_001").state == "tribulation" and _entry("c_001").version > 1, "state moves to tribulation with server version")
	expect(_changes == changes + 1, "one lifecycle.changed event per change")
	expect(not _module.allows_combat("c_001"), "tribulation blocks combat")
	var calls: int = _authority_calls.size()
	var replay: Dictionary = await _dispatch("lifecycle.confirm_change", {"cultivator_id": "c_001", "confirmation_token": "token-c_001", "request_id": "req_1"})
	expect(replay.ok and replay.data.replayed and _changes == changes + 1 and _authority_calls.size() == calls, "replayed request is idempotent")
	var no_pending: Dictionary = await _dispatch("lifecycle.confirm_change", {"cultivator_id": "c_001", "confirmation_token": "token-c_001", "request_id": "req_2"})
	expect(no_pending.code == "NO_PENDING_REQUEST", "confirmation needs a pending request")
	var stage: Dictionary = await _stage("c_001", "cardio.emergency")
	expect(stage.code == "INVALID_STAGE", "first stage must be admission")
	expect((await _stage("c_001", "cardio.admission")).ok and _entry("c_001").stage_index == 0, "admission starts tribulation")
	expect((await _stage("c_001", "cardio.emergency")).ok and _entry("c_001").stage_index == 1, "stage advances")
	expect((await _stage("c_001", "cardio.emergency")).code == "INVALID_STAGE", "repeated stage rejected")
	expect((await _stage("c_001", "fracture.surgery")).code == "INVALID_STAGE", "template cannot change mid-tribulation")
	expect((await _stage("c_001", "cardio.nothing")).code == "INVALID_STAGE", "unknown stage rejected")
	expect((await _stage("c_001", "cardio.admission")).ok and _entry("c_001").stage_index == 0, "stage may regress")
	var final: Dictionary = await _stage("c_001", "cardio.discharge")
	expect(final.ok and final.data.final, "discharge stage reported as final")
	expect(_entry("c_001").state == "tribulation", "reaching discharge never settles the tribulation automatically")
	_module.apply_authoritative("c_004", "cultivating", 1)
	expect((await _stage("c_004", "cardio.admission")).code == "NOT_IN_TRIBULATION", "stage update needs tribulation")

func _stage(cultivator_id: String, stage_id: String) -> Dictionary:
	return await _dispatch("lifecycle.update_stage", {"cultivator_id": cultivator_id, "stage_id": stage_id, "confirmation_token": "token-" + cultivator_id})

func _test_denied_and_ascension() -> void:
	_module.apply_authoritative("c_002", "cultivating", 1)
	await _dispatch("lifecycle.request_change", {"cultivator_id": "c_002", "target_state": "tribulation"})
	_deny = true
	var denied: Dictionary = await _dispatch("lifecycle.confirm_change", {"cultivator_id": "c_002", "confirmation_token": "token-c_002", "request_id": "req_d"})
	_deny = false
	expect(denied.code == "FORBIDDEN", "authority refusal is surfaced")
	expect(_entry("c_002").state == "cultivating" and _entry("c_002").pending_target == "tribulation", "refusal keeps state and pending request")
	expect(_entry("c_002").last_request_id == "", "refused request is not recorded as applied")
	_module.apply_authoritative("c_003", "seclusion", 1)
	var requested: Dictionary = await _dispatch("lifecycle.request_change", {"cultivator_id": "c_003", "target_state": "ascended"})
	expect(requested.ok and requested.data.confirmations_required == 2, "ascension reports two confirmations")
	var changes: int = _changes
	var first: Dictionary = await _dispatch("lifecycle.confirm_change", {"cultivator_id": "c_003", "confirmation_token": "token-c_003", "request_id": "req_a1"})
	expect(first.ok and not first.data.complete and first.data.remaining == 1, "first ascension confirmation is not enough")
	expect(_entry("c_003").state == "seclusion" and _changes == changes, "state unchanged after first confirmation")
	var second: Dictionary = await _dispatch("lifecycle.confirm_change", {"cultivator_id": "c_003", "confirmation_token": "token-c_003", "request_id": "req_a2"})
	expect(second.ok and second.data.complete and _entry("c_003").state == "ascended", "second confirmation completes ascension")
	var after: Dictionary = await _dispatch("lifecycle.request_change", {"cultivator_id": "c_003", "target_state": "cultivating"})
	expect(after.code == "INVALID_TRANSITION", "ascended is terminal")

func _test_sync_and_validation() -> void:
	expect(_module.apply_authoritative("c_001", "tribulation", 0, "cardio", 2).code == "STALE_VERSION", "older server version rejected")
	expect(_runtime.save().ok, "lifecycle section saves with the rest")
	var good: Dictionary = {"revision": 1, "cultivators": {"c_9": {"state": "tribulation", "version": 3, "template_id": "cardio", "stage_index": 2, "pending_target": "", "last_request_id": ""}}}
	expect(_module.validate_state(good), "well-formed tribulation entry validates")
	var bad_stage: Dictionary = good.duplicate(true)
	bad_stage.cultivators.c_9.stage_index = 9
	expect(not _module.validate_state(bad_stage), "out-of-range stage rejected")
	var bad_state: Dictionary = good.duplicate(true)
	bad_state.cultivators.c_9.state = "cultivating"
	expect(not _module.validate_state(bad_state), "stage data outside tribulation rejected")
	var bad_pending: Dictionary = good.duplicate(true)
	bad_pending.cultivators.c_9.pending_target = "tribulation"
	expect(not _module.validate_state(bad_pending), "illegal pending transition rejected")
	var extra: Dictionary = good.duplicate(true)
	extra.cultivators.c_9.token = "leak"
	expect(not _module.validate_state(extra), "unknown fields rejected so tokens cannot be stored")
	expect(_module.validate_state(_module.initial_state()), "initial state validates")
