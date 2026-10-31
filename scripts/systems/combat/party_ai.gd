extends RefCounted
## AI 队友补位的纯规则（设计文档 v2 第 11.5 节：人数不足时用 AI 队友补位）。
## 队友有自己的灵根、攻击和出手冷却，按固定节奏自动近攻；伤害走同一套伤害公式。
## 无节点、无文件、无网络；不使用随机数，不暴击，所以不会改变玩家随机流的可复现性。
## 队友只返回伤害数值，由调用方决定扣在 Boss 还是小怪上；不产出任何资源，也不影响战果结构。
const Rules = preload("res://scripts/systems/combat/combat_rules.gd")
const MAX_ALLIES: int = 3
const ATTACK_INTERVAL: float = 1.2
var allies: Array = []

## 添加一位队友；灵根无效、数值非法或人数已满时返回 false。
func add_ally(element: String, attack: int) -> bool:
	if not Rules.is_element(element) or attack <= 0 or allies.size() >= MAX_ALLIES:
		return false
	allies.append({"element": element, "attack": attack, "cooldown": ATTACK_INTERVAL})
	return true

## 队伍灵根列表（含玩家自己的灵根），供相生加成使用。
func party_elements(player_element: String) -> Array:
	var elements: Array = [player_element]
	for ally in allies:
		elements.append(ally.element)
	return elements

func step(delta: float) -> void:
	if delta <= 0.0:
		return
	for ally in allies:
		ally.cooldown = maxf(0.0, ally.cooldown - delta)

## 返回本次已就绪的队友出手：每项为 {"index", "damage"}，并重置其冷却。
## target_element 为当前攻击目标的灵根；target_defense 为其防御。
func ready_attacks(target_element: String, target_defense: float) -> Array:
	var strikes: Array = []
	for index in range(allies.size()):
		var ally: Dictionary = allies[index]
		if ally.cooldown > 0.0:
			continue
		ally.cooldown = ATTACK_INTERVAL
		var multiplier: float = Rules.element_multiplier(ally.element, target_element)
		strikes.append({"index": index, "damage": Rules.damage(float(ally.attack), target_defense, multiplier, false)})
	return strikes
