extends RefCounted
## Boss-only locomotion and attack timeline. No wallet, health facts or progression writes.
## Coordinates are foot positions. Tells, projectiles and collision use the same profiles.
const Patterns = preload("res://scripts/systems/combat/pr4_patterns.gd")
const CONFIG = preload("res://data/combat/pr4_boss_moves.json")
const FLOOR = Rect2(150, 458, 1080, 222)
var progression: Dictionary
var combo_index: int = 0
var combo_total: int = 1
var pending_stagger: bool = false
var hazards: Array = []
var player_velocity = Vector2.ZERO
var _last_player = Vector2.INF
var _last_used: Dictionary = {}
var _waves_fired: Dictionary = {}
var definition: Dictionary
var position: Vector2
var velocity = Vector2.ZERO
var facing = Vector2.LEFT
var phase = "waiting"
var phase_clock = 0.0
var phase_duration = 1.2
var move: Dictionary = {}
var profiles: Array = []
var projectiles: Array = []
var impacts: Array = []
var trail: Array = []
var stage = 0
var tier = 10
var attack_number = 0
var _previous = ""
var _start = Vector2.ZERO
var _end = Vector2.ZERO
var _landed = false
var _spent: Dictionary = {}

func _init(id: String, spawn: Vector2, rank: int) -> void:
	definition = CONFIG.data.bosses[id].duplicate(true)
	progression = definition.progression.duplicate(true)
	position = clamp_floor(spawn)
	tier = rank

static func clamp_floor(point: Vector2) -> Vector2:
	return Vector2(clampf(point.x, FLOOR.position.x, FLOOR.end.x), clampf(point.y, FLOOR.position.y, FLOOR.end.y))

func clear_attack() -> void:
	projectiles.clear()
	hazards.clear()
	profiles.clear()
	impacts.clear()
	trail.clear()
	velocity = Vector2.ZERO

func progress() -> float:
	return clampf(phase_clock / maxf(phase_duration, .001), 0, 1)

func raw_damage() -> int:
	return mini(int(CONFIG.data.max_raw_damage), roundi((float(definition.base_attack)) * float(move.get("power", 1)) * (1 + int(move.get("attack_stage",stage)) * .08)))

func step(delta: float, player: Vector2) -> Array:
	var events: Array = []
	if _last_player.is_finite():
		player_velocity = player_velocity.lerp(((player-_last_player)/delta).limit_length(255), .22)
	_last_player = player
	if pending_stagger and phase != "attack":
		pending_stagger = false
		clear_attack()
		phase = "stagger"
		phase_clock = 0
		phase_duration = 1.55
		combo_index = 0
		combo_total = 1
		events.append({"event":"stagger"})
	_step_hazards(delta,player,events)
	for pool in [impacts, trail]:
		for item in pool:
			item.life -= delta
		for i in range(pool.size() - 1, -1, -1):
			if pool[i].life <= 0:
				pool.remove_at(i)
	phase_clock += delta
	velocity = Vector2.ZERO
	match phase:
		"waiting":
			_seek(delta, player)
			if phase_clock >= phase_duration:
				_begin(player)
				events.append({"event":"windup", "attack":move.name})
		"windup":
			if phase_clock + .00001 >= phase_duration:
				phase = "attack"
				phase_clock = 0
				phase_duration = float(move.active)
				events.append({"event":"release", "kind":move.kind})
				if move.kind == "volley":
					_fire(0)
		"attack":
			_active(delta, player, events)
			if phase_clock + .00001 >= phase_duration:
				phase_clock = 0
				projectiles.clear()
				if combo_index+1 < combo_total:
					phase = "link"
					phase_duration = .42
					events.append({"event":"combo_link", "next":combo_index+2, "total":combo_total})
				else:
					phase = "breath"
					phase_duration = maxf(1.05,float(move.recover)) + (combo_total-1)*.22
					events.append({"event":"recover", "attack":move.name})
		"link":
			_seek(delta*.42,player)
			if phase_clock + .00001 >= phase_duration:
				_begin(player,true)
				events.append({"event":"windup", "attack":move.name})
		"stagger":
			if phase_clock + .00001 >= phase_duration:
				phase = "waiting"
				phase_clock = 0
				phase_duration = .75
		"breath":
			if phase_clock + .00001 >= phase_duration:
				phase = "waiting"
				phase_clock = 0
				phase_duration = float(definition.tempo) * (1 - stage * .08) * float(progression.tempo)
	return events

func _seek(delta: float, player: Vector2) -> void:
	var offset = player - position
	if offset.length() > 1:
		facing = offset.normalized()
	var spacing: float = float(definition.spacing)
	var direction = Vector2.ZERO
	if offset.length() > spacing + 20:
		direction += facing
	elif offset.length() < spacing - 30:
		direction -= facing * (.85 if definition.motion == "kite" else .35)
	if definition.motion != "pursue":
		var side = 1.0 if attack_number % 2 == 0 else -1.0
		direction += Vector2(-facing.y, facing.x * .58) * side * .65
	# Turn at edges rather than walking into a clamp indefinitely.
	if position.y < FLOOR.position.y + 18 and direction.y < 0:
		direction.y = absf(direction.y)
	if position.y > FLOOR.end.y - 18 and direction.y > 0:
		direction.y = -absf(direction.y)
	if position.x < FLOOR.position.x + 30 and direction.x < 0:
		direction.x = absf(direction.x)
	if position.x > FLOOR.end.x - 30 and direction.x > 0:
		direction.x = -absf(direction.x)
	var before = position
	position = clamp_floor(position + direction.limit_length(1) * float(definition.speed) * (1 + stage * .07) * float(progression.speed) * delta)
	if position.distance_to(player) < 65:
		position = clamp_floor(player - facing * 65)
	velocity = (position - before) / delta

func _begin(player: Vector2, linked: bool = false) -> void:
	var pool: Array = []
	for candidate in definition.moves:
		if int(candidate.min_stage) <= stage:
			pool.append(candidate)
	var chosen: Dictionary = pool[0]
	var best_score = -INF
	var distance: float = position.distance_to(player)
	for candidate in pool:
		# Aging prevents starving a signature; range and recent actions drive the choice.
		var score: float = (attack_number-int(_last_used.get(candidate.id,-2)))*12
		if candidate.id == _previous: score -= 65
		match str(candidate.kind):
			"slash": score += 30 if distance<=float(candidate.reach) else -350
			"charge", "leap": score += 25 if distance>280 else 2
			"volley", "beam": score += 14 if distance>240 else -8
			"nova": score += 18 if distance>105 and distance<300 else -12
			"eruption", "cross": score += 15 if player_velocity.length()<80 else 7
		if linked and candidate.kind in ["slash","nova"] and distance<230: score += 10
		if score>best_score:
			best_score = score
			chosen = candidate
	if linked:
		combo_index += 1
	else:
		combo_index = 0
		combo_total = int(progression.combo[stage])
	move = chosen.duplicate(true)
	move["attack_stage"] = stage
	move["waves"] = int(progression.waves[stage]) if move.kind == "volley" else 1
	_last_used[move.id] = attack_number
	_waves_fired.clear()
	_previous = str(move.id)
	attack_number += 1
	_start = position
	var target = player
	if move.kind in ["volley","beam","eruption","cross"]:
		target = clamp_floor(player+player_velocity*float(progression.lead))
	facing = (target - position).normalized()
	if facing.is_zero_approx():
		facing = Vector2.LEFT
	_end = clamp_floor(player)
	if move.kind == "charge":
		_end = clamp_floor(position + facing * minf(float(move.reach), position.distance_to(player) + 100))
	elif move.kind == "leap":
		_end = clamp_floor(position + (player - position).limit_length(float(move.reach)))
	phase = "windup"
	phase_clock = 0
	# Earliest tell stays readable even in final phase; the entire move is frozen now.
	phase_duration = maxf(float(progression.min_tell), float(move.tell) * (1 - stage * .045) * float(progression.tell))
	_landed = false
	_spent.clear()
	profiles = _build_profiles(target)
	if move.kind == "volley":
		var travel := 0.0
		for profile in profiles: travel = maxf(travel,_start.distance_to(profile.target)/float(move.speed))
		move.active = maxf(.75,travel+.34*(int(move.waves)-1)+.10)

func _shape(kind: String, center: Vector2, radius: Vector2) -> Dictionary:
	return {"kind":kind, "origin":_start, "target":center, "radius":radius, "width":float(move.width), "direction":facing, "inner":.48, "clip":FLOOR.grow(2)}

func _build_profiles(player: Vector2) -> Array:
	var radius = Vector2(move.radius[0], move.radius[1])
	match str(move.kind):
		"slash":
			var cone = _shape("cone", _start, radius)
			cone["angle"] = float(move.width)
			return [cone]
		"charge":
			return [_shape("capsule", _end, Vector2(float(move.width), float(move.width)))]
		"leap":
			return [_shape("circle", _end, radius)]
		"nova":
			return [_shape("ring", _start, radius)]
		"cross":
			return [_shape("cross", clamp_floor(player), radius)]
		"beam":
			return [_shape("capsule", _ray_end(facing,float(move.reach)), Vector2(float(move.width), float(move.width)))]
		"eruption":
			var output: Array = []
			var count: int = mini(5, int(move.count) + (1 if stage == 2 else 0))
			for i in range(count):
				var offset = Vector2((i - (count - 1) * .5) * 140, sin(i * 2.4) * 50)
				output.append(_shape("circle", clamp_floor(player + offset), radius))
			return output
		"volley":
			var output: Array = []
			var count: int = mini(7, int(move.count) + (2 if int(move.attack_stage) == 2 else 0))
			for wave in range(int(move.waves)):
				for i in range(count):
					var direction = facing.rotated((i-(count-1)*.5)*float(move.spread)+(wave%2)*.10)
					var profile = _shape("capsule",_ray_end(direction,float(move.reach)),Vector2(float(move.width),float(move.width)))
					profile["wave"] = wave
					output.append(profile)
			return output
	return []

func _fire(wave: int) -> void:
	if _waves_fired.has(wave): return
	_waves_fired[wave] = true
	for profile in profiles:
		if int(profile.get("wave",0)) != wave: continue
		var direction: Vector2 = (profile.target - _start).normalized()
		projectiles.append({"position":_start, "velocity":direction * float(move.speed), "spent":false, "radius":float(move.width), "distance":0.0})

func _contact(profile: Dictionary, key: String, player: Vector2, events: Array) -> void:
	if _spent.has(key):
		return
	if Patterns.hits(profile, player):
		_spent[key] = true
		events.append({"event":"damage", "raw":raw_damage(), "attack":move.name, "direction":(player-position).normalized(), "source":key})

func _impact(profile: Dictionary) -> void:
	impacts.append({"profile":profile.duplicate(true), "style":move.style, "life":.48})

func _active(delta: float, player: Vector2, events: Array) -> void:
	var fraction = progress()
	match str(move.kind):
		"charge":
			var before = position
			position = _start.lerp(_end, fraction)
			velocity = (position-before) / delta
			trail.append({"position":position, "life":.24})
			var sweep = _shape("capsule", position, Vector2(34, 34))
			sweep.origin = before
			sweep.width = float(move.width)
			_contact(sweep, "charge", player, events)
			if not _landed and fraction >= 1 - .0001:
				_landed = true
				_impact(_shape("circle", position, Vector2(65, 40)))
		"leap":
			position = _start.lerp(_end, smoothstep(0, 1, fraction))
			if not _landed and fraction >= 1 - .0001:
				_landed = true
				_impact(profiles[0])
				_contact(profiles[0], "landing", player, events)
				events.append({"event":"impact", "kind":"leap"})
		"volley":
			for wave in range(1,int(move.waves)):
				if phase_clock>=wave*.34 and not _waves_fired.has(wave):
					_fire(wave)
					events.append({"event":"volley_burst"})
			for i in range(projectiles.size()):
				var projectile: Dictionary = projectiles[i]
				var before: Vector2 = projectile.position
				projectile.position += projectile.velocity * delta
				projectile.distance += Vector2(projectile.velocity).length()*delta
				if projectile.spent:
					continue
				var sweep = _shape("capsule", projectile.position, Vector2(projectile.radius, projectile.radius))
				sweep.origin = before
				sweep.width = projectile.radius
				var key = "shot_%d" % i
				_contact(sweep, key, player, events)
				if _spent.has(key) or projectile.distance>=float(move.reach) or not FLOOR.grow(35).has_point(projectile.position):
					projectile.spent = true
		"eruption":
			for i in range(profiles.size()):
				var key = "eruption_%d" % i
				if phase_clock >= i * .16 and not _spent.has(key + "_fired"):
					_spent[key + "_fired"] = true
					_impact(profiles[i])
					_contact(profiles[i], key, player, events)
					if bool(progression.hazards) and int(move.attack_stage)>=1:
						hazards.append({"profile":profiles[i].duplicate(true),"style":move.style,"life":float(move.get("residue",1.5)),"clock":0.0,"tick":0,"raw":maxi(1,roundi(raw_damage()*.42)),"attack":str(move.name)+"余势"})
		_:
			if not _landed and phase_clock >= .055:
				_landed = true
				for profile in profiles:
					_impact(profile)
					_contact(profile, "strike", player, events)

func zones() -> Array:
	var output: Array = []
	for hazard in hazards:
		output.append({"profile":hazard.profile,"progress":1.0,"style":hazard.style,"active":true,"residue":true})
	if phase == "windup":
		for profile in profiles:
			output.append({"profile":profile, "progress":progress(), "style":move.style, "active":false})
	elif phase == "attack" and move.kind == "charge":
		output.append({"profile":profiles[0], "progress":1.0, "style":move.style, "active":true})
	elif phase == "attack" and move.kind == "leap" and not _landed:
		output.append({"profile":profiles[0], "progress":1.0, "style":move.style, "active":false})
	elif phase == "attack" and move.kind == "eruption":
		for i in range(profiles.size()):
			if not _spent.has("eruption_%d_fired" % i):
				output.append({"profile":profiles[i], "progress":1.0, "style":move.style, "active":false})
	return output


func _step_hazards(delta: float, player: Vector2, events: Array) -> void:
	for hazard in hazards:
		hazard.life -= delta
		hazard.clock += delta
		if hazard.life>0 and hazard.clock>=.6:
			hazard.clock -= .6
			hazard.tick += 1
			if Patterns.hits(hazard.profile,player):
				events.append({"event":"damage","raw":hazard.raw,"attack":hazard.attack,"direction":(player-Vector2(hazard.profile.target)).normalized(),"source":"residue_%d" % hazard.tick})
	for i in range(hazards.size()-1,-1,-1):
		if hazards[i].life<=0:
			hazards.remove_at(i)


func _ray_end(direction: Vector2, reach: float) -> Vector2:
	var length := reach
	var bounds := FLOOR.grow(2)
	if direction.x>.001: length = minf(length,(bounds.end.x-_start.x)/direction.x)
	elif direction.x<-.001: length = minf(length,(bounds.position.x-_start.x)/direction.x)
	if direction.y>.001: length = minf(length,(bounds.end.y-_start.y)/direction.y)
	elif direction.y<-.001: length = minf(length,(bounds.position.y-_start.y)/direction.y)
	return _start+direction*maxf(0,length)
