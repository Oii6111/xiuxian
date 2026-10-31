extends SceneTree
## 组队 Boss 战集成测试：AI 队友与 Boss、小怪的配合。只加载规则脚本。
const BossFight = preload("res://scripts/systems/combat/boss_fight.gd")
const PartyAi = preload("res://scripts/systems/combat/party_ai.gd")
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
	return {"hp": 200, "attack": 20, "defense": 4, "crit_rate": 0.0, "element": "fire"}

func _boss(hp: int) -> Dictionary:
	return {"hp": hp, "attack": 10, "defense": 0, "crit_rate": 0.0, "element": "earth"}

func _seeded() -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = 3
	return generator

func _run() -> void:
	# 没有队友：行为与单人一致。
	var solo = BossFight.new(_player(), _boss(90), _seeded(), ["water", "metal", "wood"])
	expect(solo.valid and solo.allies == null and solo.ally_strikes().is_empty(), "no party means no ally strikes")
	# 有队友：火 + 水，相生加成只在存在相生对时出现；火生土不在队内，所以无加成。
	var party = PartyAi.new()
	expect(party.add_ally("water", 12), "ally joins")
	var boss = BossFight.new(_player(), _boss(90), _seeded(), ["water", "metal", "wood"], [], party)
	expect(boss.valid and boss.allies == party, "boss fight accepts a party")
	expect(boss.ally_strikes().is_empty(), "allies wait for their first interval")
	boss.step(1.2)
	var first: Array = boss.ally_strikes()
	# 水对 Boss 当前属性水：无克制，伤害 12。
	expect(first.size() == 1 and first[0].target == "boss" and first[0].damage == 12, "ally hits the boss for its damage")
	expect(boss.fight.enemy_hp == 78, "ally damage reduces boss hp")
	expect(boss.ally_strikes().is_empty(), "ally cooldown resets after a strike")
	# 队友把 Boss 打进阶段二，召唤小怪；下一次队友出手先打小怪。
	boss.fight.enemy_hp = 61
	boss.step(1.2)
	var push: Array = boss.ally_strikes()
	expect(push.size() == 1 and boss.phase == 1 and boss.minions.alive() == 2, "ally damage advances the phase and summons minions")
	boss.step(1.2)
	var on_minion: Array = boss.ally_strikes()
	expect(on_minion.size() == 1 and on_minion[0].target == "minion" and boss.fight.enemy_hp == 61 - push[0].damage, "allies hit minions first and spare the boss")
	# 队友击杀 Boss 判胜，之后不再出手。
	var finisher = BossFight.new(_player(), _boss(10), _seeded(), ["water", "metal", "wood"], [], PartyAi.new())
	finisher.allies.add_ally("water", 30)
	finisher.step(1.2)
	var kill: Array = finisher.ally_strikes()
	expect(kill.size() == 1 and finisher.finished() and finisher.fight.won, "an ally can land the winning blow")
	finisher.step(5.0)
	expect(finisher.ally_strikes().is_empty(), "no ally strikes after the fight ends")
	expect(finisher.result().get("won") == true and finisher.result().keys().size() == 2, "result keeps the combat.finish shape")
	# 相生加成：火 + 土有相生对，玩家攻击提高 5%。
	var bonus_party = PartyAi.new()
	bonus_party.add_ally("earth", 12)
	var bonus = BossFight.new(_player(), _boss(500), _seeded(), ["water", "metal", "wood"], [], bonus_party)
	var plain = BossFight.new(_player(), _boss(500), _seeded(), ["water", "metal", "wood"])
	var with_bonus: int = bonus.player_attack().damage
	var without_bonus: int = plain.player_attack().damage
	expect(with_bonus >= 1 and without_bonus >= 1, "both fights deal damage")
	expect(is_equal_approx(bonus.fight._party_bonus, 0.05) and is_equal_approx(plain.fight._party_bonus, 0.0), "party elements feed the generation bonus")
	print("BOSS_PARTY_TEST: %d assertions; %d failures" % [_assertions, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
