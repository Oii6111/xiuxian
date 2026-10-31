extends SceneTree
const State = preload("res://scripts/game_state.gd")
const Boss = preload("res://scripts/boss_rules.gd")
const Brain = preload("res://scripts/systems/combat/pr4_boss_brain.gd")
const Catalogue = preload("res://scripts/trial_catalogue.gd")
const Patterns = preload("res://scripts/systems/combat/pr4_patterns.gd")
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
