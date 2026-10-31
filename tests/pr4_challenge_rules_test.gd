extends SceneTree
const State = preload("res://scripts/game_state.gd")
const Boss = preload("res://scripts/boss_rules.gd")
const Brain = preload("res://scripts/systems/combat/pr4_boss_brain.gd")
const Catalogue = preload("res://scripts/trial_catalogue.gd")
const Actions = preload("res://scripts/systems/combat/action_atlas.gd")
const Patterns = preload("res://scripts/systems/combat/pr4_patterns.gd")
var checks: int = 0
var failures: Array = []
func _init() -> void: call_deferred("_run")
func expect(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures.append(title)
		printerr("FAIL: ",title)
func battle(id: String = "b06") -> RefCounted:
	var state = State.new()
	state.persist_enabled = false
	state.apply_health_profile(state.HealthProfile.mock(40,1))
	return Boss.new(state,0,10,"attack",false,Catalogue.entry(id))
func _run() -> void:
	_starting_health()
	_fixed_progression()
	_atlas_and_hit_frames()
	_precision_and_player_chain()
	_stagger_and_lifecycle()
	_residue_and_minion()
	_record_isolation()
	print("PR4_CHALLENGE_RULES_TEST: %d assertions; %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
func _starting_health() -> void:
	var state = State.new()
	state.persist_enabled = false
	expect(state.battle_stats().max_hp==100,"fresh default character starts at exactly 100 HP")
	for score in [0,40,100]:
		expect(state.HealthProfile.battle_stats(state.HealthProfile.mock(score,1).attributes).max_hp==100,"profile scores never silently restore 500 starting HP")
	var sample: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://health-entry/sample-baseline.json"))
	sample.recognition_mode = "sample"
	expect(state.apply_health_baseline(sample).ok and state.base_battle_stats().max_hp==100,"confirmed report path also starts at 100 HP")
	expect(state.health_baseline.character_state.hp_max==sample.character_state.hp_max,"combat HP tuning preserves original report evidence")
	state.equipment.inventory = [{"id":"gear_000001","template":2,"rarity":2}]
	state.equip_item("gear_000001")
	var rules = Boss.new(state,0,10,"attack",false,Catalogue.entry("b00"))
	expect(rules.max_hp==126 and rules.hp==126,"authentic life equipment is added to 100 and battle starts full")
	state.equipment.equipped.clear()
	expect(state.battle_stats().max_hp==100 and rules.max_hp==126,"unequip restores 100 only for the next frozen snapshot")
func _fixed_progression() -> void:
	var last_hp := 0
	var last_attack := 0.0
	var last_poise := 0.0
	expect(not Brain.CONFIG.data.has("difficulties"),"combat content has a fixed progression and no difficulty choice")
	for row in Catalogue.all():
		var rules = battle(row.id)
		expect(rules.combat_rank==int(row.index)+1,"rank follows corridor order")
		expect(is_equal_approx(float(rules.brain.definition.base_attack),(34+4.5*int(row.index))*1.25),"authored boss damage increases twenty-five percent "+row.id)
		expect(rules.boss_max_hp>last_hp and float(rules.brain.definition.base_attack)>last_attack and rules.max_poise>last_poise,"later boss base health, attack and poise strictly increase "+row.id)
		last_hp = rules.boss_max_hp
		last_attack = rules.brain.definition.base_attack
		last_poise = rules.max_poise
		var original: Dictionary = rules.stats.duplicate(true)
		rules.brain.stage = 2
		rules.brain._begin(Vector2(600,575))
		var frozen: Array = rules.brain.profiles.duplicate(true)
		var damage: int = rules.brain.raw_damage()
		var duration: float = rules.brain.phase_duration
		rules.brain.stage = 0
		rules.brain.step(.1,Vector2(1200,680))
		expect(rules.brain.profiles==frozen and rules.brain.raw_damage()==damage and rules.brain.phase_duration==duration and rules.stats==original,"in-flight tell and damage never change after phase update "+row.id)
	for id in ["b00","b06","b18"]:
		var brain = Brain.new(id,Vector2(1000,575),90)
		brain.stage = 2
		var tells := 0
		var recovered := false
		for frame in range(1800):
			for event in brain.step(1.0/60,Vector2(650,575)):
				if event.event=="windup": tells += 1
				if event.event=="recover": recovered = true
			if recovered: break
		expect(recovered and tells==int(brain.progression.combo[2]),"complete announced combo follows fixed rank "+id)

func _atlas_and_hit_frames() -> void:
	var assets: Dictionary = Actions.manifest().assets
	expect(assets.size()==24,"twenty bosses, two heroes and two effect atlases are available")
	for id in assets:
		var data: Dictionary = Actions.bank(id)
		expect(data.frames.size()==16 and assets[id].distinct_frames>=12,"generated atlas has real distinct poses "+id)
		var sprite := Sprite2D.new()
		var first_scale := Vector2.ZERO
		for frame in range(16):
			Actions.apply(sprite,data,frame,200)
			if frame==0: first_scale = sprite.scale
			expect(sprite.scale==first_scale and sprite.texture!=null,"pose changes do not resize the character "+id)
		sprite.free()
	var rules = battle()
	var boss_hp: int = rules.boss_hp
	var queued: Dictionary = rules.start_action("basic",rules.boss_position)
	expect(queued.ok and rules.boss_hp==boss_hp,"starting an attack only starts windup")
	rules.step(.10,rules.boss_position)
	expect(rules.boss_hp==boss_hp,"basic windup frames do not deal early damage")
	var result: Dictionary = rules.step(.04,rules.boss_position)
	expect(rules.boss_hp<boss_hp and result.events.any(func(e): return e.event=="player_hit"),"damage resolves at the extended-sword impact frame")
	rules = battle()
	var mp: float = rules.mp
	rules.start_action("sword",rules.boss_position-Vector2(100,0),Vector2.RIGHT)
	expect(rules.mp==mp-18 and not rules.start_action("sword",rules.boss_position,Vector2.RIGHT).ok,"queued spell cost cannot be spent twice")
	rules.dodge()
	boss_hp = rules.boss_hp
	rules.step(.2,rules.boss_position-Vector2(100,0))
	expect(rules.pending_action.is_empty() and rules.boss_hp==boss_hp,"rolling cancels pending windup without a ghost hit")
	rules = battle()
	rules.start_action("basic",rules.boss_position)
	rules.receive_damage(30)
	boss_hp = rules.boss_hp
	rules.step(.2,rules.boss_position)
	expect(rules.boss_hp==boss_hp,"real damage interrupts an uncommitted sword strike")
func _precision_and_player_chain() -> void:
	var rules = battle()
	var hp: int = rules.hp
	var stamina: float = rules.stamina
	rules.dodge()
	var result: Dictionary = rules.receive_damage(80)
	expect(result.event=="perfect_evade" and rules.hp==hp,"early contact during an actual dodge triggers precision without damage")
	expect(rules.perfect_dodges==1 and is_equal_approx(rules.stamina,stamina-14),"precision refunds ten local stamina exactly once")
	rules.receive_damage(80)
	expect(rules.perfect_dodges==1,"overlapping contacts cannot mint repeated precision rewards")
	var counter: Dictionary = rules.attack(rules.boss_position)
	expect(counter.counter and counter.damage==roundi(int(rules.stats.attack)*1.45) and rules.counter_time==0,"landed counter grants 45 percent damage once")
	rules.step(.61,Vector2(550,620))
	var normal: Dictionary = rules.attack(rules.boss_position)
	expect(not normal.counter and normal.damage==int(rules.stats.attack),"the next hit does not reuse a spent counter")
	rules = battle()
	rules.dodge()
	rules.step(.20,Vector2(550,620))
	expect(rules.receive_damage(80).event=="evaded" and rules.perfect_dodges==0,"late invulnerability still dodges but does not grant precision")
	rules.counter_time = 1
	var mana: float = rules.mp
	var miss: Dictionary = rules.sword(Vector2(150,680),Vector2.LEFT)
	expect(miss.damage==0 and rules.counter_time>0 and rules.mp==mana-18,"missing sword spends normal mana but preserves the unspent counter")
	rules.step(1.01,Vector2(550,620))
	expect(rules.counter_time==0,"counter expires rather than remaining forever")
	rules = battle()
	var damages: Array = []
	for i in range(3):
		damages.append(rules.attack(rules.boss_position).damage)
		rules.step(.61,Vector2(550,620))
	expect(damages[0]==damages[1] and damages[2]>damages[1] and rules.combo_step==3,"three landed basics have a stronger third strike")
	rules.attack(Vector2(150,458))
	expect(rules.combo_step==0,"missed basic breaks the chain")
func _stagger_and_lifecycle() -> void:
	var rules = battle()
	rules._strike_boss(1,10000)
	rules.step(.01,Vector2(550,620))
	expect(rules.phase=="stagger" and rules.stagger_count==1 and rules.poise==0,"full poise creates one finite stagger window")
	var hit: Dictionary = rules.attack(rules.boss_position)
	expect(hit.damage==roundi(int(rules.stats.attack)*1.2),"stagger window rewards a landed attack")
	var before: int = rules.stagger_count
	rules._strike_boss(1,10000)
	rules.step(.1,Vector2(550,620))
	expect(rules.stagger_count==before and not rules.brain.pending_stagger,"a broken boss cannot be chain-stunned by filling during stagger")
	rules = battle()
	rules.brain._begin(Vector2(550,575))
	for frame in range(120):
		rules.step(1.0/60,Vector2(550,575))
		if rules.phase=="attack": break
	rules._strike_boss(1,10000)
	expect(rules.phase=="attack" and rules.brain.pending_stagger,"committed active hit is not invisibly cancelled mid-flight")
	for frame in range(120):
		rules.step(1.0/60,Vector2(300,680))
		if rules.phase=="stagger": break
	expect(rules.phase=="stagger" and rules.brain.projectiles.is_empty() and rules.brain.hazards.is_empty(),"pending break resolves after commitment and clears hazards")
	var stats: Dictionary = rules.stats.duplicate(true)
	rules.state.lifecycle_v2 = rules.state.LifecycleRecord.fresh("seclusion")
	var position: Vector2 = rules.boss_position
	rules.step(1,Vector2.ZERO)
	expect(rules.finished and not rules.won and rules.boss_position==position and rules.stats==stats,"new actions cannot bypass lifecycle stop or mutate gear snapshot")
func _residue_and_minion() -> void:
	var brain = Brain.new("b03",Vector2(950,575),20)
	brain.stage = 1
	brain.definition.moves = [brain.definition.moves[0]]
	brain._begin(Vector2(650,575))
	var visible_hit = false
	for frame in range(300):
		var events: Array = brain.step(1.0/60,Vector2(650,575))
		for event in events:
			if str(event.get("source","")).begins_with("residue_"):
				for zone in brain.zones():
					if bool(zone.get("residue",false)) and Patterns.hits(zone.profile,Vector2(650,575)):
						visible_hit = true
		if frame==180: expect(brain.hazards.size()<=10,"residue count is bounded")
	expect(visible_hit,"persistent ground damage always has a visible matching region")
	brain.clear_attack()
	expect(brain.hazards.is_empty() and brain.projectiles.is_empty(),"leaving or ending a fight clears lingering damage")
	var rules = battle("b03")
	rules.boss_hp = int(rules.boss_max_hp*.60)
	rules._sync_stage()
	rules.adds[1].hp = 0
	var add: Dictionary = rules.adds[0]
	var player: Vector2 = Vector2(add.position)+Vector2(-70,0)
	var events: Array = []
	for frame in range(180):
		rules._step_adds(1.0/60,player,events)
		if add.phase=="lunge": break
	var origin: Vector2 = add.position
	var hp: int = rules.hp
	rules._step_adds(.08,player,events)
	expect(Vector2(add.position).distance_to(origin)>10 and rules.hp==hp,"small monster moves during pounce without early contact damage")
	rules._step_adds(.09,player,events)
	expect(rules.hp<hp and add.phase=="recover","pounce damages only on arrival then enters recovery")

func _record_isolation() -> void:
	var state: RefCounted = battle().state
	var wallet: Dictionary = state.equipment.duplicate(true)
	state.complete_boss("b06",{"time":2.0})
	state.complete_boss("b06",{"time":45.0,"ruleset":"pr4_actions_v4","rank":7})
	state.complete_boss("b06",{"time":50.0,"ruleset":"pr4_actions_v4","rank":7})
	expect(state.best_boss_record("b06").time==45 and state.boss_records.b06.time==2,"fixed progression records do not compare against older combat versions")
	var record: Dictionary = state.best_boss_record("b06")
	record.time = 0
	expect(state.best_boss_record("b06").time==45,"record query returns a read-only copy")
	var restored = State.new()
	restored.persist_enabled = false
	restored.load_data(state.to_data())
	expect(restored.best_boss_record("b06").time==45 and restored.equipment==wallet,"fixed-progression records round-trip without spending resources")
	expect(battle().state.best_boss_record("b06").is_empty(),"another elder retains separate progression records")
