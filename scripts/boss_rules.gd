extends RefCounted
## PR4 四技能战斗：装备开局快照、三阶段 Boss、锁定预兆、散祟与生命状态隔离。
const BossBrain = preload("res://scripts/systems/combat/pr4_boss_brain.gd")
const Patterns = preload("res://scripts/systems/combat/pr4_patterns.gd")
const BOSS_POSITION = Vector2(1040, 575)
const SWORD_COST = 18
const SHIELD_COST = 24
const DODGE_COST = 24
const HEAL_COST = 45
const SWORD_RANGE = 820.0
const BASIC_RANGE = 210.0
var combat_rank: int = 1
var poise: float = 0
var max_poise: float = 140
var poise_delay: float = 0
var stagger_count: int = 0
var counter_time: float = 0
var perfect_dodges: int = 0
var precision_spent: bool = false
var combo_step: int = 0
var combo_time: float = 0
var brain: RefCounted
var pending_action: Dictionary = {}
var hurt_grace: float = 0
var pattern_index: int = 0
var stage_index: int = 0
var adds: Array = []
var _warning: Dictionary = {}
var _base_windup: float = 1.1
var _attack_number: int = 0
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
		pattern_index = int(encounter.get("index", 0))
		boss_id = str(encounter.id)
		boss_name = str(encounter.name)
		tier = int(encounter.tier)
		boss_position = Vector2(encounter.boss_position[0], encounter.boss_position[1])
	if not boss_id.is_empty() and not practice:
		brain = BossBrain.new(boss_id, boss_position, tier)
		combat_rank = int(brain.definition.rank)
		max_poise = float(brain.definition.poise)
	if not practice:
		# Tier 10 -> 100: shorter tells and larger ground attacks.
		# The effect renderer reads these same radii as the hit test.
		var rank_factor = clampf((float(tier) - 10.0) / 90.0, 0.0, 1.0)
		windup_duration = lerpf(0.85, 0.45, rank_factor)
		attack_radius = Vector2(125, 80).lerp(Vector2(230, 150), rank_factor)
	_base_windup = windup_duration
	boss_max_hp = 280 + tier * 28
	if brain != null:
		# Fixed content health: room for complete patterns at PR4 base DPS.
		# Never scales from the player gear snapshot; stronger equipment remains useful.
		boss_max_hp = int(brain.definition.max_hp)
	boss_hp = boss_max_hp
	if not state.allows_battle():
		finished = true
		last_message = "该角色当前不能出战，请选择修行中的家人。"

func _available(cooldown: float, cost: float = 0, can_cancel: bool = false) -> bool:
	last_message = ""
	if not state.allows_battle():
		finished = true
		last_message = "该角色当前不能出战，请切换修行中的家人。"
	elif finished:
		last_message = "本次挑战已结束。"
	elif heal_cast > 0:
		last_message = "正在归元吐纳，移动寻找安全位置。"
	elif not pending_action.is_empty() and not can_cancel:
		last_message = "正在出招，踏云可取消。"
	elif cooldown > 0:
		last_message = "技能尚在冷却。"
	elif mp < cost:
		last_message = "灵力不足，靠近目标普攻命中可回灵。"
	return last_message == ""

func _deal(damage: int) -> int:
	var actual = mini(boss_hp, damage)
	boss_hp -= actual
	damage_total += actual
	_sync_stage()
	if not practice:
		state.contribution += actual
	if boss_hp == 0:
		finished = true
		won = true
		pending_action.clear()
		if brain != null:
			brain.clear_attack()
		heal_cast = 0
		if not practice:
			var record = {"time": elapsed, "damage_taken": damage_taken, "hits": hit_count}
			if brain != null:
				record.merge({"rank":combat_rank,"ruleset":"pr4_actions_v4","precision":perfect_dodges,"staggers":stagger_count})
			if boss_id != "":
				state.complete_boss(boss_id, record)
			else:
				state.complete_stage(track, tier, record)
	return actual

func attack(origin: Vector2 = Vector2(900, 575)) -> Dictionary:
	if not _available(attack_cd):
		return {"ok": false, "message": last_message}
	attack_cd = 0.6
	return _resolve_attack(origin)

func _resolve_attack(origin: Vector2) -> Dictionary:
	for add in adds:
		if int(add.hp) > 0 and origin.distance_to(add.position) <= BASIC_RANGE:
			var damage: int = mini(int(add.hp), int(stats.attack) + bonus)
			add.hp -= damage
			bonus = 0
			_combo_hit()
			mp = minf(max_mp, mp + 5)
			return {"ok": true, "damage": damage, "target": "add", "position":add.position, "impacts":[{"position":add.position,"damage":damage,"boss":false}], "finished": false, "message": "清理散祟 · 灵力 +5"}
	if origin.distance_to(boss_position) > BASIC_RANGE:
		combo_step = 0
		combo_time = 0
		return {"ok": true, "damage": 0, "message": "普攻落空，靠近目标再出剑。"}
	var strike: Dictionary = _strike_boss(int(stats.attack)+bonus,4.0,_combo_hit())
	var damage: int = strike.damage
	bonus = 0
	mp = minf(max_mp, mp + 5)
	return {"ok": true, "damage": damage, "finished": finished, "counter":strike.counter, "combo":combo_step, "impacts":[{"position":boss_position,"damage":damage,"boss":true}], "message": "普攻命中 · 灵力 +5"}

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
	return _resolve_sword(origin,direction,targets)

func _resolve_sword(origin: Vector2, direction: Vector2, targets: Array = []) -> Dictionary:
	var candidates = targets.duplicate()
	for add in adds:
		if add.hp > 0:
			candidates.append(add)
	candidates.append({"id": "boss", "position": boss_position, "radius": 65})
	var hits = sword_hits(origin, direction, candidates)
	var damage = 0
	var impacts: Array = []
	var counter_used := false
	var power = int(round(float(stats.attack) * 2.1))
	for target in hits:
		if target.get("id", "") == "boss":
			var strike: Dictionary = _strike_boss(power,10)
			var actual: int = strike.damage
			counter_used = bool(strike.counter)
			damage += actual
			impacts.append({"position":boss_position,"damage":actual,"boss":true})
		elif target.has("hp"):
			var actual = mini(int(target.hp), power)
			target.hp -= actual
			damage += actual
			impacts.append({"position":target.position,"damage":actual,"boss":false})
	return {"ok": true, "damage": damage, "impacts":impacts, "counter":counter_used, "hit_count": hits.size(), "message": "听风剑诀 · 剑气掠过路径目标" if not hits.is_empty() else "剑气未命中，调整站位再出剑。"}

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
	if not _available(dodge_cd,0,true):
		return false
	if stamina < DODGE_COST:
		last_message = "体力不足，稍候回气再踏云。"
		return false
	stamina -= DODGE_COST
	stamina_delay = 0.7
	dodge_cd = 0.45
	dodge_time = 0.3
	precision_spent = false
	pending_action.clear()
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
	if brain != null and hurt_grace > 0:
		return {}
	if dodge_time > 0:
		if brain != null and dodge_time>=.17 and not precision_spent:
			precision_spent = true
			perfect_dodges += 1
			counter_time = 2.0
			stamina = minf(max_stamina,stamina+10)
			hurt_grace = .10
			return {"event":"perfect_evade","refund":10}
		return {"event": "evaded"}
	var amount = maxi(1, int(round(raw_damage * float(stats.damage_multiplier))))
	var absorbed = mini(shield_hp, amount) if shield_time > 0 else 0
	shield_hp -= absorbed
	amount -= absorbed
	if amount == 0:
		if brain != null:
			hurt_grace = .22
		return {"event": "blocked", "absorbed": absorbed}
	var actual = mini(hp, amount)
	hp -= actual
	damage_taken += actual
	hit_count += 1
	if brain != null:
		hurt_grace = .5
	var interrupted = heal_cast > 0
	var attack_interrupted := not pending_action.is_empty()
	pending_action.clear()
	heal_cast = 0
	if hp == 0:
		finished = true
	return {"event": "hurt", "damage": actual, "absorbed": absorbed, "interrupted": interrupted,"attack_interrupted":attack_interrupted}

## Named encounters advance in <= 1/60 s slices, including defenses and projectiles.
## This prevents a fast dash/shot tunnelling through the hero after a dropped frame.
func step(delta: float, player_position: Vector2) -> Dictionary:
	if brain == null:
		return _step_once(delta, player_position)
	if not is_finite(delta) or delta <= 0 or finished:
		return {}
	var remaining := delta
	var events: Array = []
	var healed := 0
	while remaining > .000001 and not finished:
		var slice := minf(remaining, 1.0/60)
		var result := _step_once(slice, player_position)
		healed += int(result.get("healed", 0))
		for event in result.get("events", []):
			events.append(event)
		if result.get("event", "") == "state_changed":
			events.append({"event":"state_changed"})
		remaining -= slice
	var output: Dictionary = {"healed":healed, "events":events}
	for event in events:
		if event.event in ["hurt", "blocked", "evaded", "perfect_evade", "windup", "state_changed", "stagger"]:
			output.merge(event, true)
	return output

func _step_once(delta: float, player_position: Vector2) -> Dictionary:
	if finished or delta <= 0 or not is_finite(delta):
		return {}
	if not state.allows_battle():
		finished = true
		won = false
		heal_cast = 0
		pending_action.clear()
		return {"event":"state_changed"}
	elapsed += delta
	counter_time = maxf(0,counter_time-delta)
	combo_time = maxf(0,combo_time-delta)
	if combo_time == 0: combo_step = 0
	poise_delay = maxf(0,poise_delay-delta)
	if brain != null and poise_delay == 0 and not brain.pending_stagger:
		poise = maxf(0,poise-delta*5)
	hurt_grace = maxf(0, hurt_grace - delta)
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
	if brain != null:
		var player_events: Array = _step_player_action(delta,player_position)
		if finished: return {"healed":healed,"events":player_events}
		var enemies := _step_enemies(delta,player_position,healed)
		enemies.events = player_events+enemies.events
		return enemies
	phase_clock += delta
	if phase == "waiting" and phase_clock >= (2.4 - stage_index * 0.35):
		phase = "windup"
		windup_duration = _base_windup * (1.0 - stage_index * 0.13)
		phase_clock = 0
		target_position = player_position
		_warning = Patterns.build(pattern_index, stage_index, boss_position, target_position, attack_radius) if boss_id != "" else {"kind":"circle", "origin":boss_position, "target":target_position, "radius":attack_radius, "width":32.0}
		_attack_number += 1
		return {"event": "windup", "healed": healed}
	if phase == "windup" and phase_clock >= windup_duration:
		phase = "breath"
		phase_clock = 0
		if not Patterns.hits(warning_profile(), player_position):
			return {"event": "evaded", "healed": healed}
		var result = receive_damage(25 + tier * 3 + active_adds() * 4)
		result["healed"] = healed
		return result
	if phase == "breath" and phase_clock >= 0.65:
		phase = "waiting"
		phase_clock = 0
	return {"healed": healed}

## 仅具名 Boss 使用三阶段；旧技能练习仍是单阶段，保持四技能消耗/成长规则。
func _sync_stage() -> void:
	if practice or boss_id.is_empty() or boss_hp <= 0:
		return
	var next: int = 2 if boss_hp * 3 <= boss_max_hp else (1 if boss_hp * 3 <= boss_max_hp * 2 else 0)
	if next <= stage_index:
		return
	stage_index = next
	# 已经显示的预兆不在中途缩短：新节奏从下一次蓄力生效。
	if brain != null:
		brain.stage = stage_index
	var summon_count: int = int(brain.definition.minions) if brain != null else stage_index + 1
	for i in range(summon_count):
		if active_adds() >= 4:
			break
		var slot: int = adds.size() % 4
		adds.append({"id":"add_%d" % adds.size(), "hp":36 + tier / 2, "position":BossBrain.clamp_floor(boss_position + Vector2(-100 + (slot % 2) * 170, -45 + (slot / 2) * 65)), "radius":30, "phase":"seek", "clock":-1.0-slot*.22, "target":Vector2.ZERO})

func active_adds() -> int:
	return adds.filter(func(add): return add.hp > 0).size()

func warning_profile() -> Dictionary:
	if _warning.is_empty():
		return {"kind":"circle", "origin":boss_position, "target":target_position, "radius":attack_radius, "width":32.0}
	return _warning.duplicate(true)

## AI 陪练只在 practice 中启用，沿用不结算首通/贡献的规则。
func companion_hit(amount: int) -> int:
	if not practice or finished or not state.allows_battle() or amount <= 0:
		return 0
	return _deal(amount)


func _step_enemies(delta: float, player: Vector2, healed: int) -> Dictionary:
	var events: Array = []
	brain.stage = stage_index
	for event in brain.step(delta, player):
		if event.event == "damage":
			var received := receive_damage(int(event.raw))
			if not received.is_empty():
				received["attack"] = event.attack
				received["direction"] = event.direction
				received["source"] = event.get("source","")
				events.append(received)
		else:
			if event.event == "stagger":
				poise = 0
				stagger_count += 1
			events.append(event)
	boss_position = brain.position
	phase = brain.phase
	phase_clock = brain.phase_clock
	windup_duration = brain.phase_duration if phase == "windup" else windup_duration
	if not brain.profiles.is_empty():
		_warning = brain.profiles[0].duplicate(true)
		target_position = _warning.target
	if not finished:
		_step_adds(delta, player, events)
	return {"healed":healed, "events":events}

func _step_adds(delta: float, player: Vector2, events: Array) -> void:
	for i in range(adds.size()):
		var add: Dictionary = adds[i]
		if add.hp <= 0:
			continue
		add.clock += delta
		match str(add.phase):
			"seek":
				var offset: Vector2 = player - Vector2(add.position)
				var direction := offset.normalized()
				for other in adds:
					if other != add and other.hp > 0 and Vector2(add.position).distance_to(other.position) < 55:
						direction += (Vector2(add.position) - Vector2(other.position)).normalized() * .8
				if offset.length() > 65:
					add.position = BossBrain.clamp_floor(Vector2(add.position) + direction.limit_length(1) * (85 + tier*.25) * delta)
				if add.clock >= .45 and offset.length() <= 115:
					add.phase = "windup"
					add.clock = 0.0
					add.target = player
			"windup":
				if add.clock >= .72:
					add.phase = "lunge"
					add.clock = 0.0
					add["origin"] = add.position
			"lunge":
				add.position = Vector2(add.origin).lerp(BossBrain.clamp_floor(add.target),clampf(float(add.clock)/.16,0,1))
				if add.clock >= .16:
					add.phase = "recover"
					add.clock = 0.0
					add["recover_from"] = add.position
					var profile := {"kind":"circle", "target":add.target, "radius":Vector2(49,34), "width":20.0}
					if Patterns.hits(profile, player):
						var raw := roundi(12+(combat_rank-1)*1.1)
						var received := receive_damage(raw)
						if not received.is_empty():
							received["attack"] = "散祟扑咬"
							received["direction"] = (player-Vector2(add.origin)).normalized()
							events.append(received)
			"recover":
				if add.clock < .25:
					add.position = Vector2(add.recover_from).lerp(Vector2(add.origin),clampf(float(add.clock)/.25,0,1))
				if add.clock >= 1.45:
					add.phase = "seek"
					add.clock = 0.0

func enemy_zones() -> Array:
	if brain == null or finished:
		return []
	var zones: Array = brain.zones()
	for add in adds:
		if add.hp > 0 and add.phase in ["windup","lunge"]:
			zones.append({"profile":{"kind":"circle", "target":add.target, "radius":Vector2(49,34), "width":20.0}, "progress":1.0 if add.phase == "lunge" else clampf(float(add.clock)/.72,0,1), "style":"minion", "active":false})
	return zones


## Only landed hits advance a basic chain. Misses and a long gap reset it.
func _combo_hit() -> float:
	if brain == null: return 1.0
	combo_step = combo_step%3+1 if combo_time>0 else 1
	combo_time = 1.25
	return 1.22 if combo_step == 3 else 1.0

func _strike_boss(amount: int, pressure: float, chain_multiplier: float = 1.0) -> Dictionary:
	var counter := brain != null and counter_time>0
	var multiplier := chain_multiplier
	if counter: multiplier *= 1.45
	if brain != null and brain.phase == "stagger": multiplier *= 1.20
	var actual := _deal(roundi(amount*multiplier))
	if counter: counter_time = 0
	if brain != null and not finished and brain.phase != "stagger":
		poise_delay = 2.8
		poise = minf(max_poise,poise+(pressure+(18 if counter else 0))*(1.5 if brain.phase == "breath" else 1.0))
		if poise>=max_poise:
			brain.pending_stagger = true
	return {"damage":actual,"counter":counter}


## Main-scene attacks reserve their normal cost/cooldown, then resolve on the impact frame.
## The immediate attack/sword resolvers remain available to isolated rule fixtures.
func start_action(kind: String, origin: Vector2, direction: Vector2 = Vector2.RIGHT) -> Dictionary:
	if brain == null:
		return sword(origin,direction) if kind=="sword" else attack(origin)
	if kind not in ["basic","sword"]:
		return {"ok":false,"message":"未知动作。"}
	var cooldown := sword_cd if kind=="sword" else attack_cd
	var cost := SWORD_COST if kind=="sword" else 0
	if not _available(cooldown,cost): return {"ok":false,"message":last_message}
	if kind=="sword" and direction.is_zero_approx(): return {"ok":false,"message":"需要一个出剑方向。"}
	if kind=="sword":
		mp -= SWORD_COST
		sword_cd = 2.4
	else:
		attack_cd = .6
	pending_action = {"kind":kind,"remaining":.16 if kind=="sword" else .12,"direction":direction.normalized()}
	return {"ok":true,"queued":true,"damage":0,"message":"听风剑诀 · 起剑" if kind=="sword" else "起剑 · 踏云可取消"}

func _step_player_action(delta: float, origin: Vector2) -> Array:
	if pending_action.is_empty(): return []
	pending_action.remaining -= delta
	if float(pending_action.remaining)>.00001: return []
	var action: Dictionary = pending_action.duplicate()
	pending_action.clear()
	var result: Dictionary = _resolve_sword(origin,action.direction) if action.kind=="sword" else _resolve_attack(origin)
	return [{"event":"player_hit","kind":action.kind,"result":result}]
