extends SceneTree
const State = preload("res://scripts/game_state.gd")
const Boss = preload("res://scripts/boss_rules.gd")
const Brain = preload("res://scripts/systems/combat/pr4_boss_brain.gd")
const Catalogue = preload("res://scripts/trial_catalogue.gd")
const Patterns = preload("res://scripts/systems/combat/pr4_patterns.gd")
const Signatures = preload("res://data/combat/pr4_boss_signatures.json")
var checks: int = 0
var failures: Array = []
var report: Array = []
func expect(value: bool, title: String) -> void:
	checks += 1
	if not value:
		failures.append(title)
		printerr("FAIL: ",title)
func fresh() -> RefCounted:
	var state = State.new()
	state.persist_enabled = false
	state.apply_health_profile(state.HealthProfile.mock(40,1))
	return state
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var seen_moves: Dictionary = {}
	var seen_kinds: Dictionary = {}
	for row in Catalogue.all():
		var brain = Brain.new(row.id,Vector2(row.boss_position[0],row.boss_position[1]),int(row.tier))
		expect(brain.definition.name == row.name, row.id+" authored identity matches catalogue")
		var initial: Vector2 = brain.position
		for i in range(36):
			brain.step(1.0/60,Vector2(550,620))
		expect(brain.position.distance_to(initial)>30,row.id+" actually moves before attacking")
		var visited: Dictionary = {}
		var bounded := true
		var recovery_safe := true
		var minimum_tell := 10.0
		var least_damage := 999
		var most_damage := 0
		for stage in range(3):
			brain.stage = stage
			for frame in range(2400):
				var player := Vector2(660+sin(frame*.011)*190,560+cos(frame*.017)*70)
				var before_phase: String = brain.phase
				var events: Array = brain.step(1.0/60,player)
				bounded = bounded and Brain.FLOOR.grow(.01).has_point(brain.position)
				for event in events:
					if event.event == "windup":
						visited[brain.move.id] = true
						minimum_tell = minf(minimum_tell,brain.phase_duration)
						least_damage = mini(least_damage,brain.raw_damage())
						most_damage = maxi(most_damage,brain.raw_damage())
					if before_phase == "breath" and event.event == "damage" and not str(event.get("source","")).begins_with("residue_"):
						recovery_safe = false
				if brain.phase == "breath":
					recovery_safe = recovery_safe and brain.projectiles.is_empty() and brain.phase_duration>=.9
		expect(bounded,row.id+" seek, charge and landing remain in arena")
		expect(visited.size()==3,row.id+" all three authored moves occur in real timeline")
		expect(recovery_safe,row.id+" recovery has no hidden damaging projectiles")
		expect(minimum_tell>=.66,row.id+" every phase retains a readable tell")
		expect(least_damage>0 and most_damage<=240 and most_damage>least_damage,row.id+" light and heavy damage differ within cap")
		for move in brain.definition.moves:
			expect(not seen_moves.has(move.id),"unique authored move "+move.id)
			seen_moves[move.id] = true
			seen_kinds[move.kind] = true
		report.append({"boss":row.id,"name":row.name,"moves_seen":visited.keys(),"minimum_tell":minimum_tell,"raw_damage_range":[least_damage,most_damage],"bounded":bounded,"safe_recovery":recovery_safe})
	expect(seen_moves.size()==60 and seen_kinds.size()==8,"twenty bosses cover sixty moves and eight attack mechanics")
	_locked_tell()
	_projectile_and_charge()
	_rules_checks()
	_wood_heart_checks()
	_signature_checks()
	_wind_corridor_checks()
	_wind_launch_checks()
	var output := FileAccess.open("res://work/boss-polish/design-report.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"bosses":report},"  "))
	output.close()
	print("PR4_BOSS_DESIGN_TEST: %d assertions; %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
func _locked_tell() -> void:
	for row in Catalogue.all():
		var brain = Brain.new(row.id,Vector2(950,560),int(row.tier))
		for i in range(200):
			brain.step(1.0/60,Vector2(650,580))
			if brain.phase == "windup": break
		var frozen: Array = brain.profiles.duplicate(true)
		var duration: float = brain.phase_duration
		brain.stage = 2
		brain.step(.1,Vector2(200,675))
		expect(brain.profiles==frozen and is_equal_approx(brain.phase_duration,duration),row.id+" tell never chases or accelerates after stage change")
		for profile in frozen:
			for x in range(200,1200,100):
				var point := Vector2(x,580)
				var drawn := false
				for polygon in Patterns.polygons(profile):
					drawn = drawn or Geometry2D.is_point_in_polygon(point,polygon)
				expect(Patterns.hits(profile,point)==drawn,"shared visible / damage geometry")
func _projectile_and_charge() -> void:
	var brain = Brain.new("b01",Vector2(950,575),10)
	# Far target selects the gap closer. A charge can hurt at most once per execution.
	var player := Vector2(550,575)
	var contacts := 0
	for i in range(230):
		var events: Array = brain.step(1.0/60,player)
		for event in events:
			if event.event == "damage": contacts += 1
	expect(contacts==1,"charge crosses a stationary hero once without repeated overlap hits")
	brain = Brain.new("b00",Vector2(900,575),10)
	brain.definition.moves = [brain.definition.moves[0]]
	var tell_seen := false
	var release_seen := false
	var travel_hit := false
	for i in range(250):
		for event in brain.step(1.0/60,Vector2(560,575)):
			if event.event == "windup": tell_seen = true
			if event.event == "release": release_seen = true
			if event.event == "damage": travel_hit = tell_seen and release_seen and brain.phase_clock>.1
	expect(travel_hit,"volley deals damage on projectile arrival after tell, not instantly on cast")
func _rules_checks() -> void:
	var state = fresh()
	var one = Boss.new(state,0,10,"attack",false,Catalogue.entry("b01"))
	var two = Boss.new(fresh(),0,10,"attack",false,Catalogue.entry("b01"))
	one.hp = 10000
	two.hp = 10000
	var frozen: Dictionary = one.stats.duplicate(true)
	for i in range(12): one.step(1.0,Vector2(550,575))
	for i in range(720): two.step(1.0/60,Vector2(550,575))
	expect(one.hp==two.hp and one.boss_position.distance_to(two.boss_position)<.2,"coarse and fine frame partitions produce equal movement and damage")
	expect(one.stats==frozen,"AI stages do not mutate equipment snapshot")
	var guard = Boss.new(fresh(),0,10,"attack",false,Catalogue.entry("b06"))
	guard.dodge()
	expect(guard.receive_damage(50).event in ["evaded","perfect_evade"],"existing cloud-step invulnerability applies to moving attacks")
	guard.dodge_time = 0
	guard.hurt_grace = 0
	var before: int = guard.hp
	guard.receive_damage(30)
	guard.receive_damage(30)
	expect(guard.hp<before and guard.hit_count==1,"overlapping boss and adds cannot burst through hit grace")
	var adds = Boss.new(fresh(),0,10,"attack",false,Catalogue.entry("b03"))
	adds.boss_hp = int(adds.boss_max_hp*.6)
	adds._sync_stage()
	var spawn: Vector2 = adds.adds[0].position
	for i in range(60): adds.step(1.0/60,Vector2(500,600))
	expect(Vector2(adds.adds[0].position).distance_to(spawn)>45,"summoned adds independently pursue the hero")
	adds.boss_position = Vector2(1200,600)
	adds.adds[0].position = Vector2(500,600)
	var attack: Dictionary = adds.attack(Vector2(490,600))
	expect(attack.damage>0 and attack.target=="add","an in-range add is hittable even when the boss is far away")
	state.lifecycle_v2 = state.LifecycleRecord.fresh("seclusion")
	var position: Vector2 = one.boss_position
	one.step(1,Vector2(500,600))
	expect(one.finished and not one.won and one.boss_position==position,"lifecycle change interrupts locomotion and prevents a false win")

func _drain_cast(stage: int = 0) -> RefCounted:
	var rules = Boss.new(fresh(), 0, 10, "attack", false, Catalogue.entry("b03"))
	var brain: RefCounted = rules.brain
	brain.definition.moves = [brain.definition.moves[2]]
	brain.position = Vector2(950, 575)
	brain.stage = stage
	rules.stage_index = stage
	rules.boss_hp = 4000
	brain._begin(Vector2(550, 575))
	brain.phase = "attack"
	brain.phase_clock = 0.0
	brain.phase_duration = float(brain.move.active)
	return rules

func _wood_heart_checks() -> void:
	var player := Vector2(550, 575)
	var drained = _drain_cast(1)
	var initial_hp: int = drained.hp
	var events: Array = drained.step(.12, player).events
	var heal: Array = events.filter(func(event): return event.event == "drain")
	expect(heal.size() == 1 and drained.hp < initial_hp and drained.boss_hp - 4000 == (initial_hp - drained.hp) * 8,
		"wood heart recovers only from health actually taken")
	expect(drained.stage_index == 1, "drain recovery never rolls the encounter stage back")

	var shielded = _drain_cast()
	shielded.shield_hp = 1000
	shielded.shield_time = 2.0
	shielded.step(.12, player)
	expect(shielded.hp == shielded.max_hp and shielded.boss_hp == 4000, "fully shielded drain gives no recovery")
	var dodged = _drain_cast()
	dodged.dodge()
	dodged.step(.12, player)
	expect(dodged.hp == dodged.max_hp and dodged.boss_hp == 4000, "timed dodge gives no recovery")
	var capped = _drain_cast()
	capped.boss_hp = capped.boss_max_hp - 1
	capped.step(.12, player)
	expect(capped.boss_hp == capped.boss_max_hp, "drain cannot overheal")

	var final_wave = _drain_cast(2)
	var pulses: Array = final_wave.step(1.32, Vector2(550, 675)).events.filter(func(event): return event.event == "sap_pulse")
	expect(pulses.size() == 3 and final_wave.hp == final_wave.max_hp and final_wave.boss_hp == 4000,
		"phase three fires three pulses down the locked lane and never follows a player who steps aside")

	var clone_wave = Boss.new(fresh(), 0, 10, "attack", false, Catalogue.entry("b03"))
	clone_wave.boss_hp = roundi(clone_wave.boss_max_hp * .6)
	clone_wave._sync_stage()
	clone_wave.brain.phase_duration = 100.0
	expect(clone_wave.active_adds() == 2 and clone_wave.adds[0].variant == "small" and clone_wave.adds[1].variant == "large"
		and clone_wave.adds[0].hp < clone_wave.adds[1].hp and clone_wave.adds[0].phase == "bud",
		"phase two grows a fast small clone and a sturdy large clone with a bud warning")
	clone_wave.hp = 10000
	clone_wave.step(8.6, Vector2(200, 575))
	expect(clone_wave.active_adds() == 4, "wood heart splits again on its own without exceeding the active cap")
	for add in clone_wave.adds:
		add.hp = 0
	clone_wave.boss_hp = roundi(clone_wave.boss_max_hp * .25)
	clone_wave._sync_stage()
	expect(clone_wave.active_adds() == 3, "final phase immediately grows three clones if room is available")
	var first_id: String = clone_wave.adds[0].id
	for add in clone_wave.adds:
		add.hp = 0
	clone_wave.step(5.6, Vector2(200, 575))
	expect(clone_wave.active_adds() == 3 and clone_wave.adds[0].id != first_id,
		"final phase repeats sooner and replaced clones have distinct identities")

func _signature_checks() -> void:
	var signatures := {}
	for row in Catalogue.all():
		var brain = Brain.new(row.id, Vector2(950, 575), int(row.tier))
		var moves: Array = brain.definition.moves.filter(func(move): return move.has("signature"))
		if row.id == "b03":
			expect(moves.is_empty(), "wood heart retains its original drain and split")
			continue
		expect(moves.size() == 1, row.id + " has one authored signature")
		if moves.size() != 1:
			continue
		var move: Dictionary = moves[0]
		expect(not signatures.has(move.name), row.id + " has a distinct signature name")
		signatures[move.name] = true
		brain.definition.moves = moves
		brain.stage = 2
		brain._begin(Vector2(650, 575))
		var preview: Array = _signature_profiles(brain).duplicate(true)
		expect(not preview.is_empty(), row.id + " shows a signature warning before release")
		brain.stage = 0
		brain.step(.1, Vector2(430, 650))
		expect(_signature_profiles(brain) == preview, row.id + " signature warning stays locked when the player moves or the stage changes")
		var groups := {}
		for beat in Signatures.data[row.id].beats:
			groups[beat.at] = true
		var last_beat := 0
		var released := false
		var complete_sequence := true
		var had_safe_route := true
		var last_zones: Array = []
		for frame in range(300):
			var zones := _signature_profiles(brain)
			if not zones.is_empty() and zones != last_zones:
				had_safe_route = had_safe_route and _has_safe_point(zones)
				last_zones = zones.duplicate(true)
			for event in brain.step(1.0 / 60, Vector2(430, 650)):
				if event.event == "release":
					released = true
				if event.event == "signature_beat":
					complete_sequence = complete_sequence and released and int(event.number) == last_beat + 1 and not str(event.label).is_empty()
					last_beat = int(event.number)
			if brain.phase in ["breath", "link"]:
				break
		expect(complete_sequence and last_beat == groups.size(), row.id + " delivers every signature beat in order after the tell")
		expect(had_safe_route, row.id + " always leaves an escape space during its signature")
	expect(signatures.size() == 19, "all remaining bosses have different authored signatures")

func _signature_profiles(brain: RefCounted) -> Array:
	return brain.signature_zones().map(func(zone): return zone.profile)

func _has_safe_point(zones: Array) -> bool:
	for y in range(470, 670, 24):
		for x in range(175, 1230, 60):
			var point := Vector2(x, y)
			if not zones.any(func(profile): return Patterns.hits(profile, point)):
				return true
	return false

func _signature_cast(id: String, target: Vector2) -> RefCounted:
	var rules = Boss.new(fresh(), 0, 10, "attack", false, Catalogue.entry(id))
	var brain: RefCounted = rules.brain
	var moves: Array = brain.definition.moves.filter(func(move): return move.has("signature"))
	if moves.is_empty():
		return null
	brain.definition.moves = moves
	brain.position = Vector2(950, 575)
	brain._begin(target)
	rules.step(brain.phase_duration + .02, target)
	return rules

func _wind_corridor_checks() -> void:
	var safe_lane := Brain.FLOOR.get_center()
	var rules := _signature_cast("b10", safe_lane)
	expect(rules != null, "closed furnace signature exists")
	if rules == null:
		return
	rules.step(.30, safe_lane)
	expect(rules.hp == rules.max_hp, "paired furnace seals leave the center lane safe")
	var pairs: Array = rules.brain.hazards
	expect(pairs.size() == 2 and pairs.all(func(hazard): return not Patterns.hits(hazard.profile, safe_lane)),
		"both simultaneous wind bands persist outside the safe lane")

func _wind_launch_checks() -> void:
	var player := Vector2(650, 575)
	var rules := _signature_cast("b12", player)
	expect(rules != null, "folded wings signature exists")
	if rules == null:
		return
	var result: Dictionary = rules.step(.24, player)
	var pulled: Vector2 = result.get("displacement", Vector2.ZERO)
	expect(pulled.x > 0.0 and rules.hp == rules.max_hp,
		"the first wind beat pulls toward the boss without dealing health damage")
	player += pulled
	result = rules.step(.70, player)
	var launch: Array = result.events.filter(func(event): return event.event == "forced_move" and event.get("effect") == "launch")
	expect(not launch.is_empty() and rules.airborne_time > 0.0 and rules.airborne_height() > 0.0,
		"the narrow follow-up sends an unguarded player visibly airborne")
	expect(rules.hp == rules.max_hp, "fall damage waits until the player lands")
	player += Vector2(result.get("displacement", Vector2.ZERO))
	rules.step(1.0, player)
	expect(rules.airborne_time == 0.0 and rules.hp < rules.max_hp,
		"fall damage is applied on landing after the airborne state expires")

	var shielded := _signature_cast("b12", Vector2(650, 575))
	shielded.shield_hp = 1000
	shielded.shield_time = 2.0
	shielded.step(1.15, Vector2(650, 575))
	expect(shielded.hp == shielded.max_hp and shielded.airborne_time == 0.0,
		"a fully absorbed gale cannot launch the player")

	var air_guard := _signature_cast("b12", Vector2(650, 575))
	result = air_guard.step(.94, Vector2(650, 575))
	air_guard.stats.shield = 1000
	expect(air_guard.airborne_time > 0.0 and air_guard.defend(), "cloud shield is available after launch")
	air_guard.step(1.0, Vector2(650, 575) + Vector2(result.displacement))
	expect(air_guard.airborne_time == 0.0 and air_guard.hp == air_guard.max_hp,
		"shielding mid-air can absorb the landing damage")

	var dodged := _signature_cast("b12", Vector2(650, 575))
	dodged.step(.74, Vector2(650, 575))
	dodged.dodge()
	dodged.step(.24, Vector2(650, 575))
	expect(dodged.hp == dodged.max_hp and dodged.airborne_time == 0.0,
		"timed cloud step prevents wind launch")
