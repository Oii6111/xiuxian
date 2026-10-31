extends SceneTree
## 战斗纯规则测试：只加载规则脚本，不依赖内核、存档或网络。
const Rules = preload("res://scripts/systems/combat/combat_rules.gd")
const Fight = preload("res://scripts/systems/combat/combat_fight.gd")
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
	_test_elements()
	_test_damage_and_snapshots()
	_test_fight()
	_test_dodge_and_defeat()
	_test_determinism_and_invalid()
	print("COMBAT_RULES_TEST: %d assertions; %d failures" % [_assertions, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _player() -> Dictionary:
	return {"hp": 100, "attack": 20, "defense": 4, "crit_rate": 0.0, "element": "wood"}

func _enemy() -> Dictionary:
	return {"hp": 40, "attack": 10, "defense": 4, "crit_rate": 0.0, "element": "earth"}

func _seeded(seed_value: int) -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = seed_value
	return generator

func _test_elements() -> void:
	for element in Rules.ELEMENTS:
		var beaten: String = Rules.OVERCOMES[element]
		expect(is_equal_approx(Rules.element_multiplier(element, beaten), 1.3), "overcoming bonus: " + element)
		expect(is_equal_approx(Rules.element_multiplier(beaten, element), 0.8), "overcome penalty: " + element)
		expect(is_equal_approx(Rules.element_multiplier(element, element), 1.0), "same element neutral: " + element)
	expect(is_equal_approx(Rules.element_multiplier("wood", "fire"), 1.0), "generating pair is neutral in damage")
	expect(is_equal_approx(Rules.element_multiplier("x", "wood"), 1.0), "unknown element is neutral")
	expect(Rules.is_element("metal") and not Rules.is_element("dark") and not Rules.is_element(3), "element vocabulary is closed")
	expect(is_equal_approx(Rules.generation_bonus(["wood"]), 0.0), "single element has no pair")
	expect(is_equal_approx(Rules.generation_bonus(["wood", "fire"]), 0.05), "one generating pair gives 5 percent")
	expect(is_equal_approx(Rules.generation_bonus(["wood", "fire", "earth"]), 0.10), "two pairs give 10 percent")
	expect(is_equal_approx(Rules.generation_bonus(["wood", "wood", "fire"]), 0.05), "duplicate elements count once")
	expect(is_equal_approx(Rules.generation_bonus(Rules.ELEMENTS), 0.15), "bonus is capped at 15 percent")
	expect(is_equal_approx(Rules.generation_bonus(["wood", "bogus", 7]), 0.0), "invalid party entries ignored")

func _test_damage_and_snapshots() -> void:
	expect(Rules.damage(10.0, 4.0, 1.0, false) == 8, "base damage subtracts half defense")
	expect(Rules.damage(10.0, 4.0, 1.0, true) == 12, "crit multiplies by 1.5")
	expect(Rules.damage(10.0, 4.0, 1.3, false) == 10, "damage rounds down after multiplier")
	expect(Rules.damage(1.0, 100.0, 0.8, false) == 1, "damage is at least 1")
	expect(Rules.valid_snapshot(_player()), "well-formed snapshot validates")
	var missing: Dictionary = _player()
	missing.erase("defense")
	expect(not Rules.valid_snapshot(missing), "missing field rejected")
	var dead: Dictionary = _player()
	dead.hp = 0
	expect(not Rules.valid_snapshot(dead), "zero hp rejected")
	var crit: Dictionary = _player()
	crit.crit_rate = 1.5
	expect(not Rules.valid_snapshot(crit), "crit rate above 1 rejected")
	var element: Dictionary = _player()
	element.element = "dark"
	expect(not Rules.valid_snapshot(element), "unknown element rejected")
	var broken: Dictionary = _player()
	broken.attack = NAN
	expect(not Rules.valid_snapshot(broken), "non-finite number rejected")

func _test_fight() -> void:
	var fight = Fight.new(_player(), _enemy(), _seeded(1))
	expect(fight.valid and fight.player_hp == 100 and fight.enemy_hp == 40, "fight starts from snapshots")
	var first: Dictionary = fight.player_attack()
	expect(first.ok and first.damage == 23 and not first.crit and is_equal_approx(first.multiplier, 1.3), "advantaged attack deals 23")
	expect(fight.enemy_hp == 17, "enemy hp reduced")
	expect(fight.player_attack().reason == "COOLDOWN", "attack cooldown enforced")
	var hit: Dictionary = fight.enemy_attack()
	expect(hit.ok and not hit.evaded and hit.damage == 6 and fight.player_hp == 94, "disadvantaged enemy attack deals 6")
	fight.step(0.5)
	var last: Dictionary = fight.player_attack()
	expect(last.ok and last.finished and fight.finished and fight.won, "killing blow wins the fight")
	expect(fight.result().won == true and is_equal_approx(fight.result().duration_seconds, 0.5), "result matches combat.finish fields")
	expect(fight.enemy_attack().reason == "FINISHED" and fight.player_dodge().reason == "FINISHED", "no actions after the fight ends")
	var frozen: float = fight.elapsed
	fight.step(1.0)
	expect(is_equal_approx(fight.elapsed, frozen), "time stops after the fight ends")
	var unfinished = Fight.new(_player(), _enemy(), _seeded(1))
	expect(unfinished.result().is_empty(), "no result before the fight ends")
	var bonus = Fight.new(_player(), _enemy(), _seeded(1), ["wood", "fire"])
	expect(bonus.player_attack().damage == 24, "generation bonus raises attack by 5 percent")

func _test_dodge_and_defeat() -> void:
	var dodger = Fight.new(_player(), _enemy(), _seeded(2))
	expect(dodger.player_dodge().ok, "dodge starts")
	expect(dodger.player_dodge().reason == "COOLDOWN", "dodge cooldown enforced")
	var evaded: Dictionary = dodger.enemy_attack()
	expect(evaded.ok and evaded.evaded and evaded.damage == 0 and dodger.player_hp == 100, "invulnerability window evades damage")
	dodger.step(0.4)
	expect(dodger.enemy_attack().damage == 6 and dodger.player_hp == 94, "invulnerability window ends")
	expect(dodger.player_dodge().reason == "COOLDOWN", "dodge cooldown outlasts the window")
	dodger.step(1.2)
	expect(dodger.player_dodge().ok, "dodge available after cooldown")
	var doomed = Fight.new(_player(), _enemy(), _seeded(3))
	var smash: Dictionary = doomed.enemy_attack(100.0)
	expect(smash.ok and smash.finished and doomed.player_hp == 0, "overwhelming hit defeats the player")
	expect(doomed.finished and not doomed.won and doomed.result().won == false, "defeat is reported as not won")

func _crit_sequence(seed_value: int) -> Array:
	var player: Dictionary = _player()
	player.crit_rate = 0.5
	var enemy: Dictionary = _enemy()
	enemy.hp = 10000
	var fight = Fight.new(player, enemy, _seeded(seed_value))
	var damages: Array = []
	for index in range(8):
		damages.append(fight.player_attack().damage)
		fight.step(0.5)
	return damages

func _test_determinism_and_invalid() -> void:
	var first: Array = _crit_sequence(5)
	expect(first == _crit_sequence(5), "same seed reproduces the same fight")
	var in_range: bool = true
	for amount in first:
		if amount != 23 and amount != 35:
			in_range = false
	expect(in_range, "damage is either normal or crit value")
	var bad = Fight.new({}, _enemy(), _seeded(1))
	expect(not bad.valid and bad.player_attack().reason == "INVALID", "invalid snapshot cannot fight")
	var no_rng = Fight.new(_player(), _enemy(), null)
	expect(not no_rng.valid and no_rng.player_dodge().reason == "INVALID", "missing random source cannot fight")
