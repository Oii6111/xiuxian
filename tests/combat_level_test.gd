extends SceneTree
## 关卡场景测试：无界面实例化 level.tscn，只调用其公开接口，不读玩家存档、不联网。
const LevelScene = preload("res://scenes/combat/level.tscn")
var _assertions: int = 0
var _failures: Array[String] = []
var _outcomes: Array = []

func _init() -> void:
	call_deferred("_run")

func expect(condition: bool, description: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(description)
		printerr("FAIL: ", description)

func _on_finished(result: Dictionary) -> void:
	_outcomes.append(result)

func _make(session: String = "") -> Control:
	var level: Control = LevelScene.instantiate()
	level.session_id = session
	level.finished.connect(_on_finished)
	root.add_child(level)
	return level

func _fight_to_end(level: Control) -> int:
	level.player_pos = level.enemy_pos - Vector2(100, 0)
	var swings: int = 0
	while not level.ended and swings < 40:
		level.attack()
		level.fight.step(0.6)
		swings += 1
	return swings

func _run() -> void:
	await _test_win()
	await _test_range_and_dodge()
	await _test_report_failure()
	print("COMBAT_LEVEL_TEST: %d assertions; %d failures" % [_assertions, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _test_win() -> void:
	var level: Control = _make()
	await process_frame
	expect(level.fight != null and level.fight.valid, "level builds a valid fight from demo snapshots")
	var swings: int = _fight_to_end(level)
	expect(level.ended and level.fight.won and swings < 40, "player can win by attacking in range")
	expect(_outcomes.size() == 1 and _outcomes[0].won == true, "finished emitted exactly once with the result")
	level.attack()
	level.dodge()
	expect(_outcomes.size() == 1, "no further outcome after the fight ends")
	level.queue_free()
	await process_frame

func _test_range_and_dodge() -> void:
	var level: Control = _make()
	await process_frame
	level.attack()
	expect(level.message == "距离太远" and level.fight.enemy_hp == int(level.enemy_snapshot.hp), "out-of-range attack deals no damage")
	level.dodge()
	expect(level.message == "闪避", "dodge starts")
	level.dodge()
	expect(level.message == "闪避冷却中", "dodge cooldown enforced")
	level.queue_free()
	await process_frame

func _test_report_failure() -> void:
	var level: Control = _make("s_999")
	await process_frame
	_fight_to_end(level)
	await process_frame
	await process_frame
	expect(level.ended and level.reported, "fight with a session id reports its result once")
	expect(level.message.contains("NOT_FOUND"), "unknown session is surfaced to the player, not silently dropped")
	level.queue_free()
	await process_frame
