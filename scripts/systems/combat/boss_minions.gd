extends RefCounted
## Boss 召唤小怪的纯规则：生成、受击、清场、对玩家的附加伤害。无节点、无文件、无网络。
## 小怪不产出资源，也不改变战果结构；战斗胜负仍只看 Boss 是否被击败。
const Rules = preload("res://scripts/systems/combat/combat_rules.gd")
const MAX_ALIVE: int = 6
const MINION_HP: int = 12
const CHIP_DAMAGE: int = 1
var minions: Array = []
var _next_id: int = 1

## 在阶段切换时生成最多 count 只小怪，返回实际生成的数量；总数不超过 MAX_ALIVE。
func summon(count: int, element: String) -> int:
	if count <= 0 or not Rules.is_element(element):
		return 0
	var spawned: int = 0
	while spawned < count and alive() < MAX_ALIVE:
		minions.append({"id": _next_id, "hp": MINION_HP, "element": element})
		_next_id += 1
		spawned += 1
	return spawned

func alive() -> int:
	var count: int = 0
	for minion in minions:
		if minion.hp > 0:
			count += 1
	return count

## 对最早生成且仍存活的小怪造成伤害；没有存活小怪时返回空字典。
func hit_first(amount: int) -> Dictionary:
	for minion in minions:
		if minion.hp > 0:
			minion.hp = maxi(0, minion.hp - maxi(1, amount))
			return {"id": minion.id, "hp": minion.hp, "defeated": minion.hp == 0}
	return {}

## Boss 出招时每只存活小怪额外造成固定的少量伤害。
func chip_damage() -> int:
	return alive() * CHIP_DAMAGE
