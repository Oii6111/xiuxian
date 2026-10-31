extends SceneTree
## Boss 小怪纯规则测试：只加载规则脚本，不依赖内核、存档或网络。
const Minions = preload("res://scripts/systems/combat/boss_minions.gd")
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
	var pool = Minions.new()
	expect(pool.alive() == 0 and pool.chip_damage() == 0, "empty pool deals no chip damage")
	expect(pool.summon(0, "fire") == 0 and pool.summon(-1, "fire") == 0, "non-positive count spawns nothing")
	expect(pool.summon(2, "dark") == 0 and pool.alive() == 0, "unknown element spawns nothing")
	expect(pool.summon(2, "fire") == 2 and pool.alive() == 2, "summon spawns the requested count")
	expect(pool.chip_damage() == 2, "chip damage scales with living minions")
	var first: Dictionary = pool.hit_first(5)
	expect(first.id == 1 and first.hp == 7 and not first.defeated, "hit lands on the oldest living minion")
	var kill: Dictionary = pool.hit_first(100)
	expect(kill.id == 1 and kill.hp == 0 and kill.defeated, "overkill defeats exactly one minion")
	expect(pool.alive() == 1 and pool.chip_damage() == 1, "defeated minions stop dealing damage")
	expect(pool.hit_first(0).hp == 11, "hits deal at least one damage")
	pool.hit_first(100)
	expect(pool.alive() == 0 and pool.hit_first(5).is_empty(), "hitting an empty pool returns nothing")
	var crowded = Minions.new()
	expect(crowded.summon(4, "wood") == 4, "first batch fits")
	expect(crowded.summon(4, "wood") == 2 and crowded.alive() == Minions.MAX_ALIVE, "summons are capped at the alive limit")
	expect(crowded.summon(1, "wood") == 0, "no spawns while at the cap")
	crowded.hit_first(100)
	expect(crowded.summon(3, "wood") == 1, "room freed by a defeat can be refilled")
	print("BOSS_MINIONS_TEST: %d assertions; %d failures" % [_assertions, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
