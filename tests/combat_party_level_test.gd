extends SceneTree
## Party level test: the AI teammate switch is off by default and works when on.
const LevelScene = preload("res://scenes/combat/level.tscn")
const Rules = preload("res://scripts/systems/combat/combat_rules.gd")
var _assertions: int = 0
var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func expect(condition: bool, description: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(description)
		printerr("FAIL: ", description)

func _make(allies: bool) -> Control:
	var level: Control = LevelScene.instantiate()
	level.boss_mode = true
	level.allies_enabled = allies
	root.add_child(level)
	return level

func _run() -> void:
	var solo: Control = _make(false)
	await process_frame
	expect(solo.party == null and solo.boss.allies == null, "allies are off by default")
	solo.queue_free()
	await process_frame
	var team: Control = _make(true)
	await process_frame
	expect(team.party != null and team.party.allies.size() == 1 and team.boss.allies == team.party, "teammate joins when enabled")
	var before: int = team.fight.enemy_hp
	team._process(1.3)
	expect(team.message.contains("队友出手"), "teammate strike is announced")
	# 期望值由公式推导：队友水 12 攻击，Boss 当前火属性，水克火 1.3 倍，并扣除 Boss 防御的一半。
	var expected: int = Rules.damage(12.0, float(team.fight.enemy.defense), Rules.element_multiplier("water", str(team.fight.enemy.element)), false)
	expect(expected == 13, "hand-checked value: (12 - 4 * 0.5) * 1.3 floors to 13")
	expect(team.fight.enemy_hp == before - expected, "teammate damages the boss by the formula amount")
	expect(team.message.contains(str(expected)), "announcement shows the real damage")
	team.queue_free()
	await process_frame
	print("COMBAT_PARTY_LEVEL_TEST: %d assertions; %d failures" % [_assertions, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
