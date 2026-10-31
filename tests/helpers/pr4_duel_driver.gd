extends RefCounted
## Engineering collision-aware solver, not a human perception/balance benchmark.
## The gameplay renderer never exposes these private collision profiles.
const Brain = preload("res://scripts/systems/combat/pr4_boss_brain.gd")
const Patterns = preload("res://scripts/systems/combat/pr4_patterns.gd")
static func equip_progression(state: RefCounted, rank: int) -> void:
	# Authentic PR4 item templates, four slots, no invented HP or combat-only buffs.
	state.equipment.inventory.clear()
	state.equipment.equipped.clear()
	if rank<=4: return
	var quality := clampi((rank-5)/4,0,4)
	for template in [0,2,3,4]:
		var id := "gear_%06d" % (template+1)
		state.equipment.inventory.append({"id":id,"template":template,"rarity":quality})
		state.equip_item(id)
	state.equipment.next_id = 6
static func danger(point: Vector2, zones: Array) -> bool:
	for zone in zones:
		if Patterns.hits(zone.profile,point): return true
	return false
static func run(rules: RefCounted, active: bool, limit: float = 160) -> Dictionary:
	var hero := Vector2(550,638)
	var roll_left := 0.0
	var roll_direction := Vector2.RIGHT
	var cast_left := 0.0
	var attacks := 0
	var combos := 0
	var moves: Dictionary = {}
	var stages: Dictionary = {0:true}
	for frame in range(int(limit*60)):
		if rules.finished: break
		var dt := 1.0/60
		cast_left = maxf(0,cast_left-dt)
		var zones: Array = rules.enemy_zones()
		if rules.phase=="attack" and rules.brain.move.kind in ["slash","nova","beam","cross"]:
			for profile in rules.brain.profiles: zones.append({"profile":profile})
		var retreating := false
		var aim: Vector2 = rules.boss_position
		for add in rules.adds:
			if add.hp>0 and hero.distance_to(add.position)<250:
				aim = add.position
				break
		var goal: Vector2 = aim+(hero-aim).normalized()*125
		if active:
			if danger(hero,zones) or danger(goal,zones):
				retreating = true
				var best := INF
				for angle in range(20):
					var candidate := Brain.clamp_floor(hero+Vector2.from_angle(angle*TAU/20)*165)
					if not danger(candidate,zones):
						var score := hero.distance_to(candidate)+candidate.distance_to(aim)*.30
						if score<best:
							best = score
							goal = candidate
				if rules.phase=="windup" and rules.brain.progress()>.78 and danger(hero,zones) and rules.dodge():
					roll_direction = (goal-hero).normalized()
					roll_left = 145
					cast_left = 0
			for shot in rules.brain.projectiles:
				if not shot.spent and hero.distance_to(shot.position)<95:
					goal = Brain.clamp_floor(hero+Vector2(0,120 if hero.y<570 else -120))
					if hero.distance_to(shot.position)<40 and rules.dodge():
						roll_direction = (goal-hero).normalized()
						roll_left = 145
						cast_left = 0
			if rules.hp<rules.max_hp*.55 and rules.state.heal_unlocked() and rules.phase in ["breath","stagger"]: rules.heal()
			if rules.phase=="windup" and rules.brain.progress()>.75 and danger(hero,zones): rules.defend()
		if roll_left>0:
			var distance := minf(roll_left,145/.18*dt)
			hero = Brain.clamp_floor(hero+roll_direction*distance)
			roll_left -= distance
		elif hero.distance_to(goal)>8:
			hero = Brain.clamp_floor(hero+(goal-hero).limit_length(255*dt*(.3 if rules.heal_cast>0 else (.65 if cast_left>0 else 1.0))))
		if roll_left<=0 and not retreating and hero.distance_to(aim)<=210:
			var basic: Dictionary = rules.start_action("basic",hero)
			if basic.ok: cast_left = .38
		if roll_left<=0 and not retreating and hero.distance_to(rules.boss_position)<820:
			var sword: Dictionary = rules.start_action("sword",hero,rules.boss_position-hero)
			if sword.ok: cast_left = .52
		var result: Dictionary = rules.step(dt,hero)
		for event in result.get("events",[]):
			if event.event=="windup":
				attacks += 1
				moves[rules.brain.move.id] = true
			if event.event=="combo_link": combos += 1
		stages[rules.stage_index] = true
	return {"moves":moves.keys(),"stages":stages.keys(),"won":rules.won,"finished":rules.finished,"time":rules.elapsed,"hp":rules.hp,"max_hp":rules.max_hp,"damage":rules.damage_taken,"hits":rules.hit_count,"dodges":rules.dodge_count,"precision":rules.perfect_dodges,"staggers":rules.stagger_count,"attacks":attacks,"links":combos}
