extends RefCounted
## Shared pixel combat prototype. Individual boss moves are intentionally deferred.
const BOSS_POSITION = Vector2(1040, 575)
const SWORD_COST = 18
const SHIELD_COST = 24
const DODGE_COST = 24
const HEAL_COST = 45
const SWORD_RANGE = 820.0
const BASIC_RANGE = 210.0
var boss_id: String = ""
var boss_name: String = "云海妖龙"
var boss_position: Vector2 = BOSS_POSITION
var practice: bool = false
var state: RefCounted
var stats: Dictionary
var hp: int
var max_hp: int
var mp: float
var max_mp: float
var stamina: float
var max_stamina: float
var boss_hp: int
var boss_max_hp: int
var tier: int
var track: String
var windup_duration: float = 1.1
var attack_radius = Vector2(90, 55)
var attack_cd: float = 0
var sword_cd: float = 0
var shield_cd: float = 0
var dodge_cd: float = 0
var heal_cd: float = 0
var shield_time: float = 0
var shield_hp: int = 0
var dodge_time: float = 0
var stamina_delay: float = 0
var heal_cast: float = 0
var phase: String = "waiting"
var phase_clock: float = 0
var elapsed: float = 0
var target_position = Vector2(345, 630)
var bonus: int = 0
var damage_total: int = 0
var damage_taken: int = 0
var hit_count: int = 0
var dodge_count: int = 0
var finished: bool = false
var won: bool = false
var last_message: String = ""

func _init(data: RefCounted, support: int = 0, challenge_tier: int = 0, challenge_track: String = "", is_practice: bool = false, encounter: Dictionary = {}) -> void:
	state = data
	practice = is_practice
	bonus = support
	stats = state.battle_stats().duplicate(true)
	max_hp = int(stats.max_hp)
	hp = max_hp
	max_mp = float(stats.max_mp)
	mp = max_mp
	max_stamina = float(stats.max_stamina)
	stamina = max_stamina
	tier = state.selected_tier if challenge_tier == 0 else challenge_tier
	track = state.selected_track if challenge_track == "" else challenge_track
	if not encounter.is_empty():
		boss_id = str(encounter.id)
		boss_name = str(encounter.name)
		tier = int(encounter.tier)
		boss_position = Vector2(encounter.boss_position[0], encounter.boss_position[1])
	if not practice:
		# Tier 10 -> 100: shorter tells and larger ground attacks.
		# The effect renderer reads these same radii as the hit test.
		var difficulty = clampf((float(tier) - 10.0) / 90.0, 0.0, 1.0)
		windup_duration = lerpf(0.85, 0.45, difficulty)
		attack_radius = Vector2(125, 80).lerp(Vector2(230, 150), difficulty)
	boss_max_hp = 280 + tier * 28
	boss_hp = boss_max_hp

func _available(cooldown: float, cost: float = 0) -> bool:
	last_message = ""
	if finished:
		last_message = "本次挑战已结束。"
	elif heal_cast > 0:
		last_message = "正在归元吐纳，移动寻找安全位置。"
	elif cooldown > 0:
		last_message = "技能尚在冷却。"
	elif mp < cost:
		last_message = "灵力不足，靠近目标普攻命中可回灵。"
	return last_message == ""

func _deal(damage: int) -> int:
	var actual = mini(boss_hp, damage)
	boss_hp -= actual
	damage_total += actual
	if not practice:
		state.contribution += actual
	if boss_hp == 0:
		finished = true
		won = true
		heal_cast = 0
		if not practice:
			var record = {"time": elapsed, "damage_taken": damage_taken, "hits": hit_count}
			if boss_id != "":
				state.complete_boss(boss_id, record)
			else:
				state.complete_stage(track, tier, record)
	return actual

func attack(origin: Vector2 = Vector2(900, 575)) -> Dictionary:
	if not _available(attack_cd):
		return {"ok": false, "message": last_message}
	attack_cd = 0.6
	if origin.distance_to(boss_position) > BASIC_RANGE:
		return {"ok": true, "damage": 0, "message": "普攻落空，靠近目标再出剑。"}
	var damage = _deal(int(stats.attack) + bonus)
	bonus = 0
	mp = minf(max_mp, mp + 5)
	return {"ok": true, "damage": damage, "finished": finished, "message": "普攻命中 · 灵力 +5"}

static func sword_hits(origin: Vector2, direction: Vector2, targets: Array) -> Array:
	var result: Array = []
	var heading = direction.normalized()
	for target in targets:
		var offset: Vector2 = target.position - origin
		var along = offset.dot(heading)
		if along >= 0 and along <= SWORD_RANGE and absf(offset.cross(heading)) <= float(target.get("radius", 60)) + 42:
			result.append(target)
	return result

func sword(origin: Vector2, direction: Vector2, targets: Array = []) -> Dictionary:
	if not _available(sword_cd, SWORD_COST):
		return {"ok": false, "message": last_message}
	if direction.is_zero_approx():
		return {"ok": false, "message": "需要一个出剑方向。"}
	mp -= SWORD_COST
	sword_cd = 2.4
	var candidates = targets.duplicate()
	candidates.append({"id": "boss", "position": boss_position, "radius": 65})
	var hits = sword_hits(origin, direction, candidates)
	var damage = 0
	var power = int(round(float(stats.attack) * 2.1))
	for target in hits:
		if target.get("id", "") == "boss":
			damage += _deal(power)
		elif target.has("hp"):
			var actual = mini(int(target.hp), power)
			target.hp -= actual
			damage += actual
	return {"ok": true, "damage": damage, "hit_count": hits.size(), "message": "听风剑诀 · 剑气掠过路径目标" if not hits.is_empty() else "剑气未命中，调整站位再出剑。"}

func defend() -> bool:
	if not _available(shield_cd, SHIELD_COST):
		return false
	mp -= SHIELD_COST
	shield_cd = 7.0
	shield_time = 3.2
	shield_hp = int(stats.shield)
	last_message = "云罡护体 · 云纹已结成护盾"
	return true

func dodge() -> bool:
	if not _available(dodge_cd):
		return false
	if stamina < DODGE_COST:
		last_message = "体力不足，稍候回气再踏云。"
		return false
	stamina -= DODGE_COST
	stamina_delay = 0.7
	dodge_cd = 0.45
	dodge_time = 0.3
	dodge_count += 1
	last_message = "踏云步 · 位移与短暂闪避"
	return true

func heal() -> bool:
	if not state.heal_unlocked():
		last_message = "首通任意两个不同关卡后，解锁饕餮归元。"
		return false
	if not _available(heal_cd, HEAL_COST):
		return false
	if hp >= max_hp:
		last_message = "生命已满，无需归元。"
		return false
	mp -= HEAL_COST
	heal_cd = 15.0
	heal_cast = 1.1
	last_message = "饕餮归元 · 吐纳中，移动速度降低"
	return true

func receive_damage(raw_damage: int) -> Dictionary:
	if finished:
		return {}
	if dodge_time > 0:
		return {"event": "evaded"}
	var amount = maxi(1, int(round(raw_damage * float(stats.damage_multiplier))))
	var absorbed = mini(shield_hp, amount) if shield_time > 0 else 0
	shield_hp -= absorbed
	amount -= absorbed
	if amount == 0:
		return {"event": "blocked", "absorbed": absorbed}
	var actual = mini(hp, amount)
	hp -= actual
	damage_taken += actual
	hit_count += 1
	var interrupted = heal_cast > 0
	heal_cast = 0
	if hp == 0:
		finished = true
	return {"event": "hurt", "damage": actual, "absorbed": absorbed, "interrupted": interrupted}

func step(delta: float, player_position: Vector2) -> Dictionary:
	if finished or delta <= 0:
		return {}
	elapsed += delta
	attack_cd = maxf(0, attack_cd - delta)
	sword_cd = maxf(0, sword_cd - delta)
	shield_cd = maxf(0, shield_cd - delta)
	dodge_cd = maxf(0, dodge_cd - delta)
	heal_cd = maxf(0, heal_cd - delta)
	shield_time = maxf(0, shield_time - delta)
	if shield_time == 0:
		shield_hp = 0
	dodge_time = maxf(0, dodge_time - delta)
	var regeneration_time = maxf(0, delta - stamina_delay)
	stamina_delay = maxf(0, stamina_delay - delta)
	stamina = minf(max_stamina, stamina + regeneration_time * 18)
	var healed = 0
	if heal_cast > 0:
		heal_cast = maxf(0, heal_cast - delta)
		if heal_cast == 0:
			healed = mini(max_hp - hp, int(round(max_hp * 0.24)) + 12)
			hp += healed
	phase_clock += delta
	if phase == "waiting" and phase_clock >= 2.4:
		phase = "windup"
		phase_clock = 0
		target_position = player_position
		return {"event": "windup", "healed": healed}
	if phase == "windup" and phase_clock >= windup_duration:
		phase = "breath"
		phase_clock = 0
		var offset = (player_position - target_position) / attack_radius
		if offset.length() >= 1:
			return {"event": "evaded", "healed": healed}
		var result = receive_damage(25 + tier * 3)
		result["healed"] = healed
		return result
	if phase == "breath" and phase_clock >= 0.65:
		phase = "waiting"
		phase_clock = 0
	return {"healed": healed}
