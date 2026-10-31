extends RefCounted
## 一局即时战斗的纯规则状态：冷却、闪避无敌窗口、伤害结算。无节点、无文件、无网络。
## 时间由调用方用 step(delta) 推进，随机由注入的 RandomNumberGenerator 提供，同种子可复现。
## 战果只描述这一局游戏的胜负；不改变生命周期，奖励由服务端结算。
const Rules = preload("res://scripts/systems/combat/combat_rules.gd")
const ATTACK_COOLDOWN: float = 0.5
const DODGE_COOLDOWN: float = 1.5
const DODGE_WINDOW: float = 0.35
var valid: bool = false
var player: Dictionary = {}
var enemy: Dictionary = {}
var player_hp: int = 0
var enemy_hp: int = 0
var elapsed: float = 0.0
var finished: bool = false
var won: bool = false
var _party_bonus: float = 0.0
var _attack_cd: float = 0.0
var _dodge_cd: float = 0.0
var _dodge_left: float = 0.0
var skill_cd: float = 0.0
var shield: int = 0
var energy: int = 0
var slow_left: float = 0.0
var _support_clock: float = 0.0
var _support_healed: bool = false
var _rng: RandomNumberGenerator

func _init(player_snapshot: Dictionary, enemy_snapshot: Dictionary, rng: RandomNumberGenerator, party_elements: Array = []) -> void:
	_rng = rng
	if rng == null or not Rules.valid_snapshot(player_snapshot) or not Rules.valid_snapshot(enemy_snapshot):
		return
	valid = true
	player = player_snapshot.duplicate(true)
	enemy = enemy_snapshot.duplicate(true)
	player_hp = int(player.hp)
	enemy_hp = int(enemy.hp)
	_party_bonus = Rules.generation_bonus(party_elements)

func _blocked() -> String:
	if not valid:
		return "INVALID"
	if finished:
		return "FINISHED"
	return ""

## hit_boss 为 false 时照常走冷却与暴击随机并算出伤害，但不扣敌人血量、不判胜负（用于打小怪）。
func player_attack(hit_boss: bool = true) -> Dictionary:
	var blocked: String = _blocked()
	if not blocked.is_empty():
		return {"ok": false, "reason": blocked}
	if _attack_cd > 0.0:
		return {"ok": false, "reason": "COOLDOWN"}
	_attack_cd = ATTACK_COOLDOWN
	var crit: bool = _rng.randf() < float(player.crit_rate)
	var multiplier: float = Rules.element_multiplier(player.element, enemy.element)
	var amount: int = Rules.damage(float(player.attack) * (1.0 + _party_bonus), float(enemy.defense), multiplier, crit)
	energy = mini(100, energy + 16)
	if hit_boss:
		enemy_hp = maxi(0, enemy_hp - amount)
		if enemy_hp == 0:
			finished = true
			won = true
	return {"ok": true, "damage": amount, "crit": crit, "multiplier": multiplier, "finished": finished}

## 队友对敌人造成的伤害：只扣敌人血量并判胜负，不使用玩家的冷却与随机。
func apply_ally_damage(amount: int) -> Dictionary:
	var blocked: String = _blocked()
	if not blocked.is_empty() or amount <= 0:
		return {"ok": false, "reason": blocked if not blocked.is_empty() else "INVALID"}
	enemy_hp = maxi(0, enemy_hp - amount)
	if enemy_hp == 0:
		finished = true
		won = true
	return {"ok": true, "damage": amount, "finished": finished}

func player_dodge() -> Dictionary:
	var blocked: String = _blocked()
	if not blocked.is_empty():
		return {"ok": false, "reason": blocked}
	if _dodge_cd > 0.0:
		return {"ok": false, "reason": "COOLDOWN"}
	_dodge_cd = DODGE_COOLDOWN
	_dodge_left = DODGE_WINDOW
	return {"ok": true}

## power 用于放大 Boss 招式；闪避无敌窗口内伤害为 0。
## extra 为固定附加伤害（如存活小怪的骚扰），同样受闪避无敌窗口保护。
func enemy_attack(power: float = 1.0, extra: int = 0) -> Dictionary:
	var blocked: String = _blocked()
	if not blocked.is_empty():
		return {"ok": false, "reason": blocked}
	if _dodge_left > 0.0:
		return {"ok": true, "evaded": true, "damage": 0, "finished": false}
	var multiplier: float = Rules.element_multiplier(enemy.element, player.element)
	var amount: int = Rules.damage(float(enemy.attack) * power, float(player.defense), multiplier, false) + maxi(0, extra)
	var absorbed: int = mini(shield, amount)
	shield -= absorbed
	amount -= absorbed
	player_hp = maxi(0, player_hp - amount)
	if player_hp == 0:
		finished = true
		won = false
	return {"ok": true, "evaded": false, "damage": amount, "finished": finished}

func step(delta: float) -> void:
	if not valid or finished or not is_finite(delta) or delta <= 0.0:
		return
	elapsed += delta
	skill_cd = maxf(0.0, skill_cd - delta)
	slow_left = maxf(0.0, slow_left - delta)
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_dodge_cd = maxf(0.0, _dodge_cd - delta)
	_dodge_left = maxf(0.0, _dodge_left - delta)

## 只有战斗结束才有战果；结构对应 combat.finish 的 won 与 duration_seconds。
func result() -> Dictionary:
	if not finished:
		return {}
	return {"won": won, "duration_seconds": snappedf(elapsed, 0.01)}


## Q：灵根职业技能；R：满能量法宝。目标由场景选择，数值只作用于本局。
func cast_skill(ultimate: bool = false, hit_enemy: bool = true) -> Dictionary:
	var blocked: String = _blocked()
	if not blocked.is_empty():
		return {"ok": false, "reason": blocked}
	if ultimate and energy < 100:
		return {"ok": false, "reason": "ENERGY"}
	if not ultimate and skill_cd > 0.0:
		return {"ok": false, "reason": "COOLDOWN"}
	if ultimate:
		energy = 0
	else:
		skill_cd = 6.0
	var element: String = str(player.element)
	var scale: float = 3.5 if ultimate else 1.8
	var amount: int = Rules.damage(float(player.attack) * scale * (1.0 + _party_bonus), float(enemy.defense), Rules.element_multiplier(element, enemy.element), false)
	if not ultimate:
		match element:
			"wood": player_hp = mini(int(player.hp), player_hp + maxi(1, int(float(player.hp) * 0.15)))
			"earth": shield = mini(int(player.hp), shield + maxi(1, int(float(player.hp) * 0.3)))
			"fire": amount = int(amount * 1.25)
			"water": slow_left = 3.0
	if hit_enemy:
		apply_ally_damage(amount)
	return {"ok": true, "damage": amount, "crit": false, "element": element, "ultimate": ultimate}

## 童子辅助独立于医疗状态：低血量本局一次回复，周期小护盾，不改持久属性。
func companion_step(delta: float) -> void:
	if not valid or finished or not is_finite(delta) or delta <= 0:
		return
	_support_clock += delta
	if _support_clock >= 10.0:
		_support_clock = fmod(_support_clock, 10.0)
		shield = mini(int(float(player.hp) * 0.3), shield + 6)
	if not _support_healed and player_hp > 0 and float(player_hp) / float(player.hp) < 0.3:
		_support_healed = true
		player_hp = mini(int(player.hp), player_hp + maxi(1, int(float(player.hp) * 0.2)))
