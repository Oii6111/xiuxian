extends SceneTree
## AI 队友纯规则测试：只加载规则脚本，不依赖内核、存档或网络。
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

func _run() -> void:
	var party = PartyAi.new()
	expect(party.ready_attacks("earth", 0.0).is_empty(), "empty party never attacks")
	expect(not party.add_ally("dark", 10) and not party.add_ally("fire", 0) and not party.add_ally("fire", -3), "invalid ally rejected")
	expect(party.allies.is_empty(), "rejected allies are not added")
	expect(party.add_ally("fire", 12) and party.add_ally("water", 12) and party.add_ally("wood", 12), "up to three allies join")
	expect(not party.add_ally("metal", 12) and party.allies.size() == PartyAi.MAX_ALLIES, "party size is capped")
	expect(party.party_elements("earth") == ["earth", "fire", "water", "wood"], "party elements include the player first")
	expect(party.ready_attacks("earth", 0.0).is_empty(), "allies wait one interval before the first strike")
	party.step(0.0)
	party.step(-1.0)
	expect(party.ready_attacks("earth", 0.0).is_empty(), "non-positive time does not advance cooldowns")
	party.step(1.2)
	# 对土：木克土 15；火生土无克制 12；水被土克 9。
	var strikes: Array = party.ready_attacks("earth", 0.0)
	expect(strikes.size() == 3, "all three allies strike once the interval passes")
	expect(strikes[0].damage == 12 and strikes[1].damage == 9 and strikes[2].damage == 15, "damage follows element advantage")
	expect(strikes[0].index == 0 and strikes[2].index == 2, "strikes report the ally index")
	expect(party.ready_attacks("earth", 0.0).is_empty(), "cooldown resets after a strike")
	party.step(0.6)
	expect(party.ready_attacks("earth", 0.0).is_empty(), "half an interval is not enough")
	party.step(0.6)
	expect(party.ready_attacks("earth", 20.0).size() == 3, "allies strike again after a full interval")
	party.step(1.2)
	var armored: Array = party.ready_attacks("fire", 100.0)
	expect(armored[0].damage >= 1 and armored[1].damage >= 1, "damage is at least one against heavy armor")
	print("PARTY_AI_TEST: %d assertions; %d failures" % [_assertions, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
