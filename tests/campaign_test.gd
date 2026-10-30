extends SceneTree
const Catalogue = preload("res://scripts/campaign/catalogue.gd")
const State = preload("res://scripts/campaign/state.gd")
const Encounter = preload("res://scripts/campaign/encounter.gd")
var failures: int = 0
var passed: int = 0

func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS: ",message)
	else:
		failures += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func advance(r: RefCounted, seconds: float, position: Vector2) -> void:
	var steps = ceili(seconds / 0.05)
	for i in range(steps):
		r.step(0.05,position)

func run() -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/generated/model_manifest.json"))
	check(manifest.models.size()==36,"Thirty-six editable models exported")
	for model in manifest.models:
		check(ResourceLoader.exists(model.path),"Editable model exists: "+str(model.name))
	var rows = Catalogue.all()
	check(rows.size()==20,"Catalogue loads twenty actual encounters")
	var ids: Array = []
	for row in rows:
		check(row.id not in ids and row.patterns.size()>=2,"Unique boss and readable move set: "+row.name)
		ids.append(row.id)
	var state = State.new()
	state.persist_enabled = false
	check(state.availability("b19")!="","Finale locked before five seals")
	check(not state.begin("b03").ok,"Tutorial precedes region encounters")
	check(not state.begin("missing").ok,"Unknown encounter rejected")
	var tutorial = state.begin("b00")
	check(tutorial.ok,"Teaching encounter needs no health data or resources")
	check(not state.settle("fake","b00",true,"story").ok,"Forged settlement rejected")
	check(state.settle(tutorial.token,"b00",true,"story").first,"Tutorial first clear settles")
	var xp = state.data.xp
	check(not state.settle(tutorial.token,"b00",true,"story").ok and state.data.xp==xp,"Duplicate win is idempotent")
	check(state.availability("b03")=="" and state.availability("b15")=="","Regions open in any order")
	var r = Encounter.new(Catalogue.entry("b15"),state.snapshot())
	check(not r.interact(Vector2(-8,-5)) and r.interactions==0,"Cannot activate a distant gate")
	var source = state.snapshot()
	var frozen = Encounter.new(Catalogue.entry("b15"),source)
	source.attack = 9
	state.data.simulated_health = "steady"
	check(frozen.snapshot.attack==1.0,"In-flight health snapshot is immutable")
	check(state.snapshot().attack==1.10,"Explicit simulation modifies next combat snapshot")
	check(not state.data.has("recovery_status"),"Campaign has no authority to overwrite clinical recovery")
	var base = Encounter.new(Catalogue.entry("b00"),{"attack":1.0})
	var boosted = Encounter.new(Catalogue.entry("b00"),{"attack":1.10})
	check(boosted.attack(boosted.boss_position).damage > base.attack(base.boss_position).damage,"Snapshot changes actual damage")
	check(not base.attack(base.boss_position).ok,"Attack cooldown prevents click spamming")
	var geometry = Encounter.new(Catalogue.entry("b00"))
	var circle = geometry._spawn("circle",Vector2(0,0),2.0,1.5)
	check(geometry.contains(circle,Vector2(0,0)) and not geometry.contains(circle,Vector2(4,0)),"Circle hitbox matches floor disc")
	var ring = geometry._spawn("ring",Vector2(0,0),4.0,1.5,0.6)
	check(geometry.contains(ring,Vector2(4,0)) and not geometry.contains(ring,Vector2.ZERO),"Ring has a safe centre")
	geometry._line(Vector2(-3,0),Vector2(3,0),0.5,1.5)
	var line = geometry.hazards.back()
	check(geometry.contains(line,Vector2(0,0)) and not geometry.contains(line,Vector2(0,2)),"Line uses capsule segment, not whole arena")
	var cone = geometry._spawn("cone",Vector2.ZERO,5.0,1.5)
	cone.angle = 0.0
	check(geometry.contains(cone,Vector2(3,0)) and not geometry.contains(cone,Vector2(-3,0)),"Cone direction is respected")
	var shielded = Encounter.new(Catalogue.entry("b00"))
	shielded._spawn("circle",Vector2.ZERO,2.0,0.2)
	check(shielded.guard(),"Guard activates")
	advance(shielded,0.3,Vector2.ZERO)
	check(shielded.hp==shielded.hp_max and shielded.perfect_blocks>0,"Shield blocks at actual impact and grants feedback")
	var dodged = Encounter.new(Catalogue.entry("b00"))
	dodged._spawn("circle",Vector2.ZERO,2.0,0.1)
	check(dodged.dash(),"Dodge activates")
	advance(dodged,0.2,Vector2.ZERO)
	check(dodged.hp==dodged.hp_max and dodged.stamina<dodged.stamina_max,"Dodge grants bounded invulnerability and costs stamina")
	var hit = Encounter.new(Catalogue.entry("b00"))
	hit._spawn("circle",Vector2.ZERO,2.0,0.15)
	advance(hit,0.3,Vector2.ZERO)
	check(hit.hp<hit.hp_max and hit.last_hit!="","Standing in an active tell causes real damage")
	var paused = Encounter.new(Catalogue.entry("b03"))
	paused.paused = true
	paused.step(0.1,Vector2.ZERO)
	check(paused.elapsed==0 and not paused.attack(Vector2.ZERO).ok,"Pause freezes simulation and actions")
	for row in rows:
		var encounter = Encounter.new(row,{"attack":1.0,"stamina":1.0})
		for cycle_index in range(row.patterns.size()):
			encounter._prepare_attack(Vector2(-4,2))
		check(encounter.hazards.size()>0 and encounter.hazards.all(func(h): return not h.active and h.warning>=1.15),"Every move telegraphs before impact: "+row.name)
		if row.id=="b17":
			check(not encounter.interact(encounter.nodes[0].position),"Memory side story retains order hints without punishment")
			for index in [2,0,1]:
				encounter.interact(encounter.nodes[index].position)
		else:
			for node in encounter.nodes:
				encounter.interact(node.position)
		check(encounter.remaining_nodes()==0,"Counterplay can remove all wards: "+row.name)
		encounter.until_attack = 9999
		advance(encounter,3.2,Vector2(-8.3,-5.2))
		encounter.hazards.clear()
		var limit = 0
		while not encounter.finished and limit<200:
			encounter.attack(encounter.boss_position)
			advance(encounter,0.45,Vector2(-8,5))
			limit += 1
		check(encounter.won and encounter.damage_done<=encounter.boss_max+0.01,"Boss is defeatable and damage capped: "+row.name)
	for id in Catalogue.cores():
		var pending = state.begin(id)
		check(state.settle(pending.token,id,true,"story").first,"Region first-clear progression: "+id)
	check(state.data.seals.size()==5 and state.availability("b19")=="","Five distinct seals unlock finale")
	var replay = state.begin("b15")
	var before = state.data.xp
	var repeat = state.settle(replay.token,"b15",true,"story")
	check(not repeat.first and repeat.xp==0 and state.data.xp==before,"Practice cannot farm first-clear XP")
	var loss = state.begin("b15")
	var before_materials = state.data.materials
	state.settle(loss.token,"b15",false,"story")
	check(state.data.xp==before and state.data.materials==before_materials,"Failure does not remove progress")
	check(state.build("门灯") and not state.build("门灯"),"Home construction charges once")
	# Dedicated fixture. Never touch either the live campaign or legacy player save.
	var record_run = state.begin("b15")
	var record_result = state.settle(record_run.token,"b15",true,"story",{"seconds":42.0,"preset":"unknown","skill":"雷诀"})
	check(record_result.new_best,"Personal record rewards mastery without replay XP")
	var slow_run = state.begin("b15")
	var slow_result = state.settle(slow_run.token,"b15",true,"story",{"seconds":55.0,"preset":"unknown","skill":"雷诀"})
	check(not slow_result.new_best,"Slower run cannot replace personal best")
	var fixture = "res://work/twenty-boss/test-save.json"
	var writer = State.new()
	writer.save_override = fixture
	writer.data.name = "测试守灯者"
	writer.data.xp = 987
	writer.data.materials = 12
	writer.data.clears = ["b00","b15"]
	writer.save_game()
	var reader = State.new()
	reader.save_override = fixture
	reader.load_game()
	check(reader.data.xp==987 and reader.data.materials==12 and reader.data.name=="测试守灯者","JSON numeric roundtrip preserves progress")
	check("水" in reader.data.seals,"Seals reconstructed from verified region clear IDs")
	for suffix in ["",".bak",".tmp"]:
		var path = ProjectSettings.globalize_path(fixture+suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	check(Catalogue.minions().size()==10 and Catalogue.people().size()==6,"Ten minion species and six villagers have complete records")
	for region in ["木","火","土","金","水"]:
		check(Catalogue.minions_for(region).size()==2,"Two minion types per region: "+region)
	var mob_fight = Encounter.new(Catalogue.entry("b03"))
	check(mob_fight.minions.size()==2,"Regional battle spawns two smaller enemies")
	var far_attack = mob_fight.attack(Vector2(-8,-5))
	check(not far_attack.get("minion",false),"Melee cannot damage distant minions")
	var mob0 = mob_fight.minions[0]
	mob_fight.attack_cd = 0
	mob_fight.attack(mob0.position)
	mob_fight.attack_cd = 0
	mob_fight.attack(mob0.position)
	check(mob0.hp<=0 and mob_fight.living_minions()==1,"Actual attacks defeat a nearby minion")
	var other_mob = mob_fight.minions[1]
	mob_fight.attack_cd = 0
	mob_fight.attack(other_mob.position)
	mob_fight.attack_cd = 0
	mob_fight.attack(other_mob.position)
	check(mob_fight.living_minions()==0,"Clearing the prelude releases the boss encounter")
	check(mob_fight.feedback.any(func(event): return event.kind=="minion_defeat"),"Defeating minions emits lore and restoration feedback")
	state.record_minion("m01")
	state.record_minion("m01")
	check(state.data.minion_lore.count("m01")==1,"Minion bestiary unlocks idempotently")
	var scene = load("res://scenes/campaign_main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	check(scene is Node3D and scene.camera.projection==Camera3D.PROJECTION_ORTHOGONAL,"New game is true 3D with an isometric 2.5D camera")
	check(scene.portals.size()==6,"Five realm portals plus tutorial exist in the 3D world")
	check(scene.townfolk.size()==6,"Six modeled NPCs are physically present in the new town")
	scene.ui.open_npc("ahe")
	check(scene.ui.modal_open,"NPC story and regional quest panel opens")
	scene.ui.close_panel()
	scene.ui.open_minions()
	check(scene.ui.modal_open,"Minion lore and return-to-region links are available")
	scene.ui.close_panel()
	scene.ui.open_atlas()
	check(scene.ui.modal_open and scene.ui.panel.find_children("*","Button",true,false).size()>=20,"All twenty boss stories are accessible in the atlas")
	scene.ui.close_panel()
	check(scene.start_encounter("b00") and scene.boss is Node3D,"Playable teaching encounter spawns a 3D beast")
	scene.combat_action(2)
	check(scene.rules.guard_time>0 and scene.rules.guard_cd>0,"Actual guard UI action controls combat")
	scene.ui.pause_menu()
	var elapsed_before = scene.rules.elapsed
	scene.rules.step(0.1,Vector2.ZERO)
	check(scene.rules.elapsed==elapsed_before,"Actual pause menu freezes battle")
	scene.ui.close_panel()
	scene.state.data.clears = ["b00","b03","b06","b09","b12","b15"]
	scene.state.data.seals = ["木","火","土","金","水"]
	for row in rows:
		check(scene.start_encounter(row.id),"Scene can instantiate: "+row.name)
		if row.region in ["木","火","土","金","水"]:
			check(scene.minion_visuals.size()==2,"Regional minions have actual 3D models: "+row.name)
		scene.rules._prepare_attack(Vector2(-3,2))
		scene._sync_visuals()
		check(scene.hazard_visuals.size()==scene.rules.hazards.size(),"Every real hazard has a rendered telegraph: "+row.name)
		await process_frame
	scene.return_town()
	check(scene.rules==null and not scene.ui.modal_open,"Returning restores exploration")
	check(scene.peaceful_minions.size()==10,"Five restored realms return ten peaceful minions to the 3D town")
	scene.queue_free()
	await process_frame
	print("CAMPAIGN TEST RESULT: ",passed," passed, ",failures," failures")
	quit(failures)
