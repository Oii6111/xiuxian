extends SceneTree
## Boss 三阶段测试：只加载规则脚本，不依赖内核、存档或网络。
const Phases = preload("res://scripts/systems/combat/boss_phases.gd")
const BossFight = preload("res://scripts/systems/combat/boss_fight.gd")
var _assertions: int = 0
var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func expect(condition: bool, description: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(description)
		printerr("FAIL: ", description)

func _run() -> void:
	_test_phase_rules()
	_test_fight()
	_test_invalid()
	print("BOSS_FIGHT_TEST: %d assertions; %d failures" % [_assertions, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _player() -> Dictionary:
	return {"hp": 200, "attack": 20, "defense": 4, "crit_rate": 0.0, "element": "water"}

func _boss() -> Dictionary:
	return {"hp": 90, "attack": 10, "defense": 0, "crit_rate": 0.0, "element": "earth"}

func _seeded() -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = 3
	return generator

func _test_phase_rules() -> void:
	expect(Phases.phase_index(90, 90) == 0 and Phases.phase_index(61, 90) == 0, "above two thirds is phase one")
	expect(Phases.phase_index(60, 90) == 1 and Phases.phase_index(31, 90) == 1, "two thirds down to one third is phase two")
	expect(Phases.phase_index(30, 90) == 2 and Phases.phase_index(0, 90) == 2, "one third and below is phase three")
	expect(Phases.phase_index(10, 0) == 0, "zero max hp is safe")
	expect(Phases.valid_config(["wood", "fire", "metal"]), "three elements validate")
	expect(not Phases.valid_config(["wood", "fire"]) and not Phases.valid_config(["wood", "fire", "dark"]), "wrong size or element rejected")
	expect(Phases.element_for(["wood", "fire", "metal"], 1) == "fire" and Phases.element_for(["x"], 0) == "", "element lookup")
	expect(Phases.attack_interval(0) > Phases.attack_interval(1) and Phases.attack_interval(1) > Phases.attack_interval(2), "attacks get faster each phase")
	expect(Phases.power(0) < Phases.power(1) and Phases.power(1) < Phases.power(2), "attacks get heavier each phase")
	expect(Phases.summon_count(0) == 0 and Phases.summon_count(1) > 0, "summons start in phase two")
	expect(Phases.attack_interval(9) == Phases.attack_interval(2) and Phases.power(-3) == Phases.power(0), "phase index is clamped")

func _test_fight() -> void:
	var boss = BossFight.new(_player(), _boss(), _seeded(), ["fire", "metal", "wood"])
	expect(boss.valid and boss.fight.enemy.element == "fire" and boss.phase == 0, "boss starts in phase one with the first element")
	var opening: float = boss.attack_interval()
	var swings: int = 0
	var last_phase: int = 0
	var monotonic: bool = true
	while not boss.finished() and swings < 40:
		var swing: Dictionary = boss.player_attack()
		if swing.ok and swing.phase < last_phase:
			monotonic = false
		if swing.ok:
			last_phase = swing.phase
			expect(boss.fight.enemy.element == boss.elements[boss.phase], "enemy element follows the phase")
		boss.step(0.6)
		swings += 1
	expect(monotonic, "phase never goes backwards")
	expect(boss.finished() and boss.fight.won and swings < 40, "boss can be defeated")
	expect(boss.phase_changes == [1, 2], "both phase changes were recorded in order")
	expect(boss.attack_interval() < opening and boss.summon_count() > 0, "final phase is faster and summons")
	expect(boss.result().get("won") == true, "result reports the win")
	var fresh = BossFight.new(_player(), _boss(), _seeded(), ["fire", "metal", "wood"])
	var light: int = fresh.enemy_attack().damage
	var heavy = BossFight.new(_player(), _boss(), _seeded(), ["fire", "metal", "wood"])
	heavy.phase = 2
	expect(heavy.enemy_attack().damage > light, "later phases hit harder")

func _test_invalid() -> void:
	var bad_config = BossFight.new(_player(), _boss(), _seeded(), ["fire"])
	expect(not bad_config.valid and bad_config.player_attack().reason == "INVALID", "bad element config cannot fight")
	var bad_snapshot = BossFight.new({}, _boss(), _seeded(), ["fire", "metal", "wood"])
	expect(not bad_snapshot.valid and bad_snapshot.enemy_attack().reason == "INVALID", "bad snapshot cannot fight")
	expect(not bad_snapshot.finished() and bad_snapshot.result().is_empty(), "invalid boss has no result")
