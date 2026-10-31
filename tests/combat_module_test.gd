extends SceneTree
## 战斗模块测试：真实 Runtime + 内存存档 + 替身 gate/provider，不联网、不读玩家存档。
const Runtime = preload("res://scripts/kernel/runtime.gd")
const Memory = preload("res://scripts/kernel/adapters/memory_persistence.gd")
const Result = preload("res://scripts/kernel/result.gd")
var _assertions: int = 0
var _failures: Array[String] = []
var _runtime: RefCounted
var _module: RefCounted
var _allowed: Dictionary = {"c_001": true, "c_002": true}
var _snapshot_calls: int = 0
var _bad_snapshot: bool = false
var _provider_fail: bool = false
var _finished_events: Array = []

func _init() -> void:
	call_deferred("_run")

func expect(condition: bool, description: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(description)
		printerr("FAIL: ", description)

func _gate(cultivator_id: String) -> bool:
	return _allowed.get(cultivator_id, false)

func _provider(cultivator_id: String, _encounter_id: String) -> Dictionary:
	_snapshot_calls += 1
	if _provider_fail:
		return Result.failure("UPSTREAM_DOWN", "属性服务不可用")
	if _bad_snapshot:
		return Result.success({"player": {"hp": 0}, "enemy": {}})
	return Result.success({
		"player": {"hp": 100, "attack": 20, "defense": 4, "crit_rate": 0.1, "element": "wood"},
		"enemy": {"hp": 40, "attack": 10, "defense": 4, "crit_rate": 0.0, "element": "earth"}})

func _on_finished(payload: Dictionary) -> void:
	_finished_events.append(payload)

func _start(cultivator_id: String, encounter_id: String = "e_1") -> Dictionary:
	return await _runtime.dispatch("combat.start", {"cultivator_id": cultivator_id, "encounter_id": encounter_id})

func _finish(session_id: String, won: bool = true, duration: float = 12.5) -> Dictionary:
	return await _runtime.dispatch("combat.finish", {"session_id": session_id, "won": won, "duration_seconds": duration})

func _run() -> void:
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/kernel/contracts.json"))
	_runtime = Runtime.new()
	var started: Dictionary = _runtime.start(contract, Memory.new())
	expect(started.ok, "runtime boots")
	if not started.ok:
		quit(1)
		return
	_module = _runtime._modules["combat"]
	_runtime.services.events.subscribe("combat.finished", _on_finished)
	await _test_unwired()
	await _test_flow()
	await _test_guards()
	_test_validation()
	_runtime.shutdown()
	print("COMBAT_MODULE_TEST: %d assertions; %d failures" % [_assertions, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _test_unwired() -> void:
	var no_gate: Dictionary = await _start("c_001")
	expect(no_gate.code == "BACKEND_UNAVAILABLE", "without lifecycle gate nobody may fight")
	_module.set_gate(Callable(self, "_gate"))
	var no_provider: Dictionary = await _start("c_001")
	expect(no_provider.code == "BACKEND_UNAVAILABLE", "without snapshot provider combat cannot start")
	expect(_module.snapshot().sessions.is_empty() and _snapshot_calls == 0, "failed starts leave no session behind")
	_module.set_provider(Callable(self, "_provider"))

func _test_flow() -> void:
	var begun: Dictionary = await _start("c_001")
	expect(begun.ok and begun.data.session_id == "s_1", "first session gets a stable id")
	expect(begun.data.player.element == "wood" and begun.data.enemy.hp == 40, "start returns validated snapshots")
	var again: Dictionary = await _start("c_001", "e_2")
	expect(again.code == "SESSION_ACTIVE", "one active fight per cultivator")
	var other: Dictionary = await _start("c_002")
	expect(other.ok and other.data.session_id == "s_2", "another cultivator may fight in parallel")
	var events: int = _finished_events.size()
	var done: Dictionary = await _finish("s_1", true, 12.555)
	expect(done.ok and done.data.won and not done.data.replayed, "finish records the result")
	expect(is_equal_approx(done.data.duration_seconds, 12.56), "duration is rounded to centiseconds")
	expect(_finished_events.size() == events + 1 and _finished_events[-1].session_id == "s_1" and _finished_events[-1].won, "one finished event with the result")
	var replay: Dictionary = await _finish("s_1", false, 99.0)
	expect(replay.ok and replay.data.replayed and replay.data.won, "repeated finish returns the original result")
	expect(is_equal_approx(replay.data.duration_seconds, 12.56) and _finished_events.size() == events + 1, "repeated finish does not notify again")
	var next: Dictionary = await _start("c_001")
	expect(next.ok and next.data.session_id == "s_3", "new fight allowed after finishing")
	var lost: Dictionary = await _finish("s_3", false, 5.0)
	expect(lost.ok and not lost.data.won, "defeat is recorded as not won")
	expect(not JSON.stringify(_module.snapshot()).contains("spirit_stones"), "combat state holds no resources")

func _test_guards() -> void:
	var missing: Dictionary = await _finish("s_999")
	expect(missing.code == "NOT_FOUND", "unknown session rejected")
	_allowed["c_001"] = false
	var blocked: Dictionary = await _start("c_001")
	expect(blocked.code == "NOT_ALLOWED", "cultivator outside cultivating cannot fight")
	_allowed["c_001"] = true
	_bad_snapshot = true
	var invalid: Dictionary = await _start("c_001")
	_bad_snapshot = false
	expect(invalid.code == "INVALID_SNAPSHOT", "malformed snapshot rejected")
	_provider_fail = true
	var failed: Dictionary = await _start("c_001")
	_provider_fail = false
	expect(failed.code == "UPSTREAM_DOWN", "provider failure is surfaced")
	var sessions_before: int = _module.snapshot().sessions.size()
	await _start("c_001")
	var last: String = "s_%d" % (int(_module.snapshot().next_session) - 1)
	var negative: Dictionary = await _finish(last, true, -1.0)
	expect(negative.code == "INVALID_PAYLOAD", "negative duration rejected")
	var huge: Dictionary = await _finish(last, true, 999999.0)
	expect(huge.code == "INVALID_PAYLOAD", "implausible duration rejected")
	expect(not _module.snapshot().sessions[last].finished and _module.snapshot().sessions.size() == sessions_before + 1, "rejected finish leaves the session open")

func _test_validation() -> void:
	expect(_module.validate_state(_module.initial_state()), "initial state validates")
	var open_session: Dictionary = {"cultivator_id": "c_9", "encounter_id": "e_1", "finished": false, "won": false, "duration_seconds": 0.0}
	var good: Dictionary = {"revision": 1, "next_session": 2, "sessions": {"s_1": open_session}}
	expect(_module.validate_state(good), "open session validates")
	var fake_win: Dictionary = good.duplicate(true)
	fake_win.sessions.s_1.won = true
	expect(not _module.validate_state(fake_win), "unfinished session cannot carry a win")
	var extra: Dictionary = good.duplicate(true)
	extra.sessions.s_1.reward = 100
	expect(not _module.validate_state(extra), "unknown session fields rejected")
	var bad_counter: Dictionary = good.duplicate(true)
	bad_counter.next_session = 0
	expect(not _module.validate_state(bad_counter), "session counter must be positive")
	var crowded: Dictionary = {"revision": 1, "next_session": 100, "sessions": {}}
	for index in range(51):
		crowded.sessions["s_%d" % index] = open_session.duplicate(true)
	expect(not _module.validate_state(crowded), "session table is bounded")
