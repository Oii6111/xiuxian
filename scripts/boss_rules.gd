extends RefCounted
## Deterministic local action-combat rules. Cooldowns and telegraphs use elapsed game time.
var state: RefCounted
var hp: int = 300
var boss_hp: int = 1440
var attack_cd: float = 0
var shield_cd: float = 0
var dodge_cd: float = 0
var shield_time: float = 0
var dodge_time: float = 0
var phase: String = "waiting"
var phase_clock: float = 0
var target_position = Vector2(345, 630)
var bonus: int = 0
var damage_total: int = 0
var finished: bool = false
var won: bool = false

func _init(data: RefCounted, support: int = 0) -> void:
	state = data
	bonus = support

func attack() -> Dictionary:
	if finished or attack_cd > 0:
		return {"ok": false}
	attack_cd = 0.65
	var damage = mini(boss_hp, 96 + bonus)
	bonus = 0
	boss_hp -= damage
	damage_total += damage
	state.contribution += damage
	if boss_hp <= 0:
		finished = true
		won = true
	return {"ok": true, "damage": damage, "finished": finished}

func defend() -> bool:
	if finished or shield_cd > 0:
		return false
	shield_cd = 4.0
	shield_time = 1.25
	return true

func dodge() -> bool:
	if finished or dodge_cd > 0:
		return false
	dodge_cd = 2.0
	dodge_time = 0.42
	return true

func step(delta: float, player_position: Vector2) -> Dictionary:
	attack_cd = maxf(0, attack_cd - delta)
	shield_cd = maxf(0, shield_cd - delta)
	dodge_cd = maxf(0, dodge_cd - delta)
	shield_time = maxf(0, shield_time - delta)
	dodge_time = maxf(0, dodge_time - delta)
	if finished:
		return {}
	phase_clock += delta
	if phase == "waiting" and phase_clock >= 2.4:
		phase = "windup"
		phase_clock = 0
		target_position = player_position
		return {"event": "windup"}
	if phase == "windup" and phase_clock >= 1.1:
		phase = "breath"
		phase_clock = 0
		var offset = (player_position - target_position) / Vector2(90, 55)
		if offset.length() >= 1 or dodge_time > 0:
			return {"event": "evaded"}
		if shield_time > 0:
			return {"event": "blocked"}
		hp = maxi(0, hp - 80)
		if hp == 0:
			finished = true
		return {"event": "hurt", "damage": 80}
	if phase == "breath" and phase_clock >= 0.65:
		phase = "waiting"
		phase_clock = 0
	return {}
