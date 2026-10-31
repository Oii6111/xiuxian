extends RefCounted
## CombatResolver 纯规则：五行克制、相生加成、伤害公式、属性快照校验。依据设计文档 v2 第 11 节。
## 无节点、无文件、无网络，可单测。只描述一局游戏内的数值，不接触健康数据，也不产出任何资源。
const ELEMENTS: Array = ["wood", "fire", "earth", "metal", "water"]
## 相克：木克土、土克水、水克火、火克金、金克木。
const OVERCOMES: Dictionary = {"wood": "earth", "earth": "water", "water": "fire", "fire": "metal", "metal": "wood"}
## 相生：木生火、火生土、土生金、金生水、水生木。
const GENERATES: Dictionary = {"wood": "fire", "fire": "earth", "earth": "metal", "metal": "water", "water": "wood"}
const ADVANTAGE: float = 1.3
const DISADVANTAGE: float = 0.8
const CRIT_MULTIPLIER: float = 1.5
const BONUS_PER_PAIR: float = 0.05
const BONUS_CAP: float = 0.15

static func is_element(value: Variant) -> bool:
	return value is String and ELEMENTS.has(value)

## 攻击被克制的敌人 +30%，攻击克制自己的敌人 -20%，其余不变。
static func element_multiplier(attacker: String, defender: String) -> float:
	if OVERCOMES.get(attacker, "") == defender:
		return ADVANTAGE
	if OVERCOMES.get(defender, "") == attacker:
		return DISADVANTAGE
	return 1.0

## 队伍里每存在一对相生关系，全队攻击 +5%，最多 +15%；重复灵根只算一次，无效灵根忽略。
static func generation_bonus(party: Array) -> float:
	var present: Array = []
	for element in party:
		if is_element(element) and not present.has(element):
			present.append(element)
	var pairs: int = 0
	for source in present:
		if present.has(GENERATES[source]):
			pairs += 1
	return minf(BONUS_CAP, pairs * BONUS_PER_PAIR)

## 至少造成 1 点伤害，避免高防御让战斗无法结束。
static func damage(attack: float, defense: float, multiplier: float, crit: bool) -> int:
	var base: float = maxf(1.0, attack - defense * 0.5)
	var scaled: float = base * multiplier * (CRIT_MULTIPLIER if crit else 1.0)
	return maxi(1, int(floor(scaled)))

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

## 战斗属性快照：由养成系统提供的只读副本，必须字段完整、数值有限、灵根合法。
static func valid_snapshot(snapshot: Dictionary) -> bool:
	# 固定字段白名单，禁止把整份健康对象透传到游戏。
	if snapshot.size() != 5:
		return false
	for key in ["hp", "attack", "defense", "crit_rate"]:
		if not _number(snapshot.get(key)):
			return false
	if not is_element(snapshot.get("element")):
		return false
	var rate: float = float(snapshot["crit_rate"])
	return float(snapshot["hp"]) >= 1.0 and float(snapshot["hp"]) == floor(float(snapshot["hp"])) and float(snapshot["attack"]) >= 0.0 and float(snapshot["defense"]) >= 0.0 and rate >= 0.0 and rate <= 1.0
