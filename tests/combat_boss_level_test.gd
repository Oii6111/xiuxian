extends SceneTree
## Boss 模式关卡测试：无界面实例化 level.tscn，只调用其公开接口，不读玩家存档、不联网。
const LevelScene = preload("res://scenes/combat/level.tscn")
var _assertions: int = 0
var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func expect(condition: bool, description: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(description)
		printerr("FAIL: ", description)

func _make(boss_mode: bool, elements: Array = ["fire", "metal", "wood"]) -> Control:
	var level: Control = LevelScene.instantiate()
	level.boss_mode = boss_mode
	level.boss_elements = elements
	root.add_child(level)
	return level

func _run() -> void:
	await _test_default_mode()
	await _test_boss_mode()
	await _test_invalid_config()
	print("COMBAT_BOSS_LEVEL_TEST: %d assertions; %d failures" % [_assertions, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _test_default_mode() -> void:
	var level: Control = _make(false)
	await process_frame
	expect(level.boss == null and level.fight != null and level.fight.valid, "default mode keeps the single-enemy fight")
	level.queue_free()
	await process_frame

func _test_boss_mode() -> void:
	var level: Control = _make(true)
	await process_frame
	expect(level.boss != null and level.boss.valid and level.fight.enemy.element == "fire", "boss mode starts with the first element")
	level.player_pos = level.enemy_pos - Vector2(100, 0)
	var saw_phase_two: bool = false
	var saw_phase_three: bool = false
	var swings: int = 0
	while not level.ended and swings < 80:
		level.attack()
		if level.message.contains("第2阶段") and level.message.contains("金"):
			saw_phase_two = true
		if level.message.contains("第3阶段") and level.message.contains("木"):
			saw_phase_three = true
		level.fight.step(0.6)
		swings += 1
	expect(saw_phase_two and saw_phase_three, "phase changes are announced with the new element")
	expect(level.ended and level.fight.won and swings < 80, "boss can be defeated in boss mode")
	expect(level.boss.phase_changes == [1, 2], "phases advanced in order")
	level.queue_free()
	await process_frame

func _test_invalid_config() -> void:
	var level: Control = _make(true, ["fire"])
	await process_frame
	expect(level.ended and level.fight == null, "invalid phase config cannot start a fight")
	expect(level.message.contains("无效"), "invalid config is surfaced to the player")
	level.attack()
	expect(level.ended, "actions are ignored after a failed start")
	level.queue_free()
	await process_frame
