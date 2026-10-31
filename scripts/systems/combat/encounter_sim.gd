extends RefCounted
## 本局三波即时战斗规则；不访问场景、文件、网络或健康状态。配置由装配层传入。
const Fight = preload("res://scripts/systems/combat/combat_fight.gd")
const Rules = preload("res://scripts/systems/combat/combat_rules.gd")
var fight: RefCounted
var config: Dictionary
var enemies: Array = []
var projectiles: Array = []
var player_pos := Vector2(350, 470)
var wave: int = -1
var serial: int = 0
var finished: bool = false
var won: bool = false
var message: String = ""
var paused: bool = false
var _rng := RandomNumberGenerator.new()

func _init(player: Dictionary, encounter: Dictionary, seed_value: int = 7) -> void:
	config = encounter.duplicate(true)
	_rng.seed = seed_value
	if not Rules.valid_snapshot(player) or not valid_config(config):
		return
	fight = Fight.new(player, {"hp": 1, "attack": 1, "defense": 0, "crit_rate": 0.0, "element": config.element}, _rng)
	_next_wave()

static func valid_config(value: Dictionary) -> bool:
	if not Rules.is_element(value.get("element")) or not value.get("waves") is Array or value.waves.size() != 3:
		return false
	for group in value.waves:
		if not group is Array or group.is_empty() or group.size() > 6:
			return false
		for behavior in group:
			if behavior not in ["rush", "shooter", "bomber", "summoner", "boss"]:
				return false
	return value.waves[2] == ["boss"]

func _spawn(behavior: String, position: Vector2) -> void:
	serial += 1
	var hp: int = 230 if behavior == "boss" else 48
	enemies.append({"id": serial, "behavior": behavior, "pos": position, "target": player_pos, "hp": hp, "max_hp": hp, "attack": 16 if behavior == "boss" else 10, "defense": 4.0, "element": config.element, "phase": 0, "wait": 1.4, "warning": -1.0})

func _next_wave() -> void:
	wave += 1
	projectiles.clear()
	if wave >= config.waves.size():
		finished = true
		won = true
		fight.finished = true
		fight.won = true
		message = "试炼完成 · 返回选择其他地区"
		return
	enemies.clear()
	var group: Array = config.waves[wave]
	for i in range(group.size()):
		_spawn(group[i], Vector2(920 + i * 160, 350 + i * 180))
	message = "第 %d / 3 波" % (wave + 1)

func _alive() -> Array:
	return enemies.filter(func(e: Dictionary) -> bool: return e.hp > 0)

func target_at(aim: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var distance: float = INF
	for enemy in _alive():
		var d: float = enemy.pos.distance_to(aim)
		if d < distance:
			distance = d
			best = enemy
	return best

func attack(aim: Vector2, skill_mode: int = 0, weapon: String = "sword") -> Dictionary:
	if finished or paused or fight == null:
		return {"ok": false}
	var target: Dictionary = target_at(aim)
	if target.is_empty():
		return {"ok": false}
	var reach: float = 150.0 if weapon == "sword" else 430.0
	if skill_mode == 1:
		reach = 480.0
	if skill_mode == 2:
		reach = 1500.0
	if player_pos.distance_to(target.pos) > reach:
		message = "目标超出距离，靠近后再出手"
		return {"ok": false}
	fight.enemy = {"hp": target.max_hp, "attack": target.attack, "defense": target.defense, "crit_rate": 0.0, "element": target.element}
	fight.enemy_hp = target.hp
	var hit: Dictionary = fight.player_attack(false) if skill_mode == 0 else fight.cast_skill(skill_mode == 2, false)
	if not hit.ok:
		message = "法宝能量未满" if hit.get("reason") == "ENERGY" else "技能冷却中"
		return hit
	var victims: Array = [target]
	if skill_mode == 2 or (skill_mode == 1 and fight.player.element in ["fire", "wood"]):
		victims = _alive().filter(func(e: Dictionary) -> bool: return skill_mode == 2 or e.pos.distance_to(target.pos) < 180)
	for victim in victims:
		var damage: int = int(hit.damage)
		if victim.id != target.id:
			damage = Rules.damage(float(fight.player.attack) * (3.5 if skill_mode == 2 else 1.8), victim.defense, Rules.element_multiplier(fight.player.element, victim.element), false)
		victim.hp = maxi(0, victim.hp - damage)
		_phase(victim)
	message = ("法宝" if skill_mode == 2 else ("术法" if skill_mode == 1 else "普攻")) + "命中 · %d 点伤害" % hit.damage
	if _alive().is_empty():
		_next_wave()
	return hit

func _phase(enemy: Dictionary) -> void:
	if enemy.behavior != "boss" or enemy.hp <= 0:
		return
	var phase: int = 2 if enemy.hp * 3 <= enemy.max_hp else (1 if enemy.hp * 3 <= enemy.max_hp * 2 else 0)
	if phase <= enemy.phase:
		return
	enemy.phase = phase
	var elements: Array = [config.element, Rules.GENERATES[config.element], Rules.OVERCOMES[config.element]]
	enemy.element = elements[phase]
	if _alive().size() < 6:
		_spawn("rush", enemy.pos + Vector2(-90, 60))
	message = "Boss 第 %d 阶段" % (phase + 1)

func _hurt(enemy: Dictionary, power: float = 1.0) -> void:
	fight.enemy = {"hp": enemy.max_hp, "attack": enemy.attack, "defense": enemy.defense, "element": enemy.element}
	fight.enemy_attack(power)
	if fight.finished:
		finished = true
		won = false
		message = "本局结束，可免费重试"

func step(delta: float) -> void:
	if fight == null or finished or paused or delta <= 0 or not is_finite(delta):
		return
	fight.step(delta)
	fight.companion_step(delta)
	for enemy in _alive():
		if finished:
			break
		var offset: Vector2 = player_pos - enemy.pos
		var speed: float = 90.0 if fight.slow_left <= 0 else 36.0
		if enemy.warning < 0:
			if enemy.behavior in ["rush", "bomber", "boss"] and offset.length() > 120:
				enemy.pos += offset.normalized() * speed * delta
			enemy.wait -= delta
			if enemy.wait <= 0:
				enemy.warning = 0.85
				enemy.target = player_pos
		else:
			enemy.warning -= delta
			if enemy.warning <= 0:
				enemy.warning = -1.0
				enemy.wait = 2.3 - float(enemy.phase) * 0.4
				match enemy.behavior:
					"shooter":
						projectiles.append({"pos": enemy.pos, "velocity": enemy.pos.direction_to(enemy.target) * 290, "ttl": 4.0, "owner": enemy.duplicate(true)})
					"summoner":
						if _alive().size() < 6:
							_spawn("rush", enemy.pos + Vector2(0, 80))
					"bomber":
						if player_pos.distance_to(enemy.pos) <= 150:
							_hurt(enemy, 1.6)
						enemy.hp = 0
					"boss":
						if enemy.phase == 0:
							var closest: Vector2 = Geometry2D.get_closest_point_to_segment(player_pos, enemy.pos, enemy.target)
							if player_pos.distance_to(closest) < 55:
								_hurt(enemy, 1.1)
							enemy.pos = enemy.target
						else:
							if player_pos.distance_to(enemy.target) < 155:
								_hurt(enemy, 1.3)
							if enemy.phase == 2:
								for i in range(6):
									projectiles.append({"pos": enemy.pos, "velocity": Vector2.RIGHT.rotated(i * TAU / 6) * 230, "ttl": 4.0, "owner": enemy.duplicate(true)})
					_:
						var closest: Vector2 = Geometry2D.get_closest_point_to_segment(player_pos, enemy.pos, enemy.target)
						if player_pos.distance_to(closest) < 45:
							_hurt(enemy)
						enemy.pos = enemy.target
		enemy.pos = enemy.pos.clamp(Vector2(100, 205), Vector2(1320, 715))
	for shot in projectiles.duplicate():
		if finished:
			break
		shot.ttl -= delta
		var previous: Vector2 = shot.pos
		shot.pos += shot.velocity * delta
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(player_pos, previous, shot.pos)
		if player_pos.distance_to(closest) < 30:
			_hurt(shot.owner)
			projectiles.erase(shot)
		elif shot.ttl <= 0:
			projectiles.erase(shot)
	if not finished and _alive().is_empty():
		_next_wave()
