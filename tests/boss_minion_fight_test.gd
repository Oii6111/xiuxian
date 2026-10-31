extends SceneTree
## Boss 战与小怪的集成测试：只加载规则脚本，不依赖内核、存档或网络。
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

func _player() -> Dictionary:
	return {"hp": 200, "attack": 20, "defense": 4, "crit_rate": 0.0, "element": "water"}

func _boss() -> Dictionary:
	return {"hp": 90, "attack": 10, "defense": 0, "crit_rate": 0.0, "element": "earth"}

func _seeded() -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = 3
	return generator

## 每次出手前推进时间，跨过 0.5 秒的攻击冷却。
func _swing(boss) -> Dictionary:
	boss.step(0.6)
	return boss.player_attack()

func _run() -> void:
	var boss = BossFight.new(_player(), _boss(), _seeded(), ["fire", "metal", "wood"])
	expect(boss.valid and boss.minions.alive() == 0, "no minions in phase one")
	var first: Dictionary = _swing(boss)
	expect(first.target == "boss" and boss.fight.enemy_hp == 64 and boss.phase == 0, "phase one hits the boss")
	_swing(boss)
	expect(boss.phase == 1 and boss.fight.enemy_hp == 38, "second hit enters phase two")
	expect(boss.minions.alive() == 2 and boss.minions.minions[0].element == "metal", "phase two summons minions of the new element")
	var on_minion: Dictionary = _swing(boss)
	expect(on_minion.target == "minion" and on_minion.minion_defeated, "attacks hit minions while any are alive")
	expect(boss.fight.enemy_hp == 38 and not boss.finished(), "boss hp is untouched while minions live")
	expect(boss.minions.alive() == 1 and boss.minions.chip_damage() == 1, "one minion left deals one chip damage")
	var hp_before: int = boss.fight.player_hp
	var chipped: Dictionary = boss.enemy_attack()
	expect(chipped.damage == 11 and boss.fight.player_hp == hp_before - 11, "boss hit includes the minion chip damage")
	expect(boss.player_dodge().ok, "dodge starts")
	var evaded: Dictionary = boss.enemy_attack()
	expect(evaded.evaded and evaded.damage == 0, "dodge window also blocks chip damage")
	var cleared: Dictionary = _swing(boss)
	expect(cleared.target == "minion" and boss.minions.alive() == 0, "last minion cleared")
	var plain: Dictionary = boss.enemy_attack()
	expect(plain.damage == 10, "no chip damage once the field is clear")
	var back_on_boss: Dictionary = _swing(boss)
	expect(back_on_boss.target == "boss" and boss.fight.enemy_hp == 18 and boss.phase == 2, "attacks return to the boss after clearing")
	expect(boss.minions.alive() == 3 and boss.phase_changes == [1, 2], "phase three summons three more")
	for index in range(3):
		expect(_swing(boss).target == "minion", "clearing phase three minion %d" % (index + 1))
	var last: Dictionary = _swing(boss)
	expect(last.target == "boss" and last.finished and boss.finished(), "boss falls after the minions")
	var outcome: Dictionary = boss.result()
	expect(outcome.get("won") == true and outcome.keys().size() == 2 and outcome.has("duration_seconds"), "result keeps the combat.finish shape")
	print("BOSS_MINION_FIGHT_TEST: %d assertions; %d failures" % [_assertions, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
