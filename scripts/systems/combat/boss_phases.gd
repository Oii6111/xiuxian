extends RefCounted
## Boss 三阶段纯规则（设计文档 v2 第 11.5 节）：阶段由剩余血量决定，每阶段切换五行属性。
## 阶段一：普通攻击和冲锋；阶段二：召唤小怪与地面范围；阶段三：狂暴，出招更快更重。
## 无节点、无文件、无网络，可单测。只描述一局游戏内的数值，不产出资源。
const Rules = preload("res://scripts/systems/combat/combat_rules.gd")
const INTERVALS: Array = [2.0, 1.6, 1.0]
const POWERS: Array = [1.0, 1.2, 1.5]
const SUMMONS: Array = [0, 2, 3]

## 配置为三个阶段的五行属性，例如 ["wood", "fire", "metal"]。
static func valid_config(elements: Array) -> bool:
	if elements.size() != 3:
		return false
	for element in elements:
		if not Rules.is_element(element):
			return false
	return true

## 用整数比较避免浮点误差：血量高于 2/3 为阶段一，高于 1/3 为阶段二，其余为阶段三。
static func phase_index(hp: int, max_hp: int) -> int:
	if max_hp <= 0:
		return 0
	if hp * 3 > max_hp * 2:
		return 0
	if hp * 3 > max_hp:
		return 1
	return 2

static func element_for(elements: Array, index: int) -> String:
	if not valid_config(elements):
		return ""
	return elements[clampi(index, 0, 2)]

static func attack_interval(index: int) -> float:
	return INTERVALS[clampi(index, 0, 2)]

static func power(index: int) -> float:
	return POWERS[clampi(index, 0, 2)]

static func summon_count(index: int) -> int:
	return SUMMONS[clampi(index, 0, 2)]
