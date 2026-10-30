extends SceneTree
## Pure rules: simulated controller inputs, no rendered scene or medical data.
const Catalogue = preload("res://scripts/pixel_campaign/catalogue.gd")
const State = preload("res://scripts/pixel_campaign/state.gd")
const Encounter = preload("res://scripts/pixel_campaign/encounter.gd")
var assertions: int = 0
var failures: Array[String] = []
var fight_records: Array = []

func _init() -> void:
	call_deferred("_run")

func expect(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures.append(description)
		printerr("FAIL: ", description)

func fresh():
	var state = State.new()
	state.persist_enabled = false
	return state

func clear_story(state, id: String) -> Dictionary:
	var opened: Dictionary = state.begin(id)
	expect(bool(opened.get("ok",false)), id+" opens in the intended story order")
	if not opened.get("ok",false):
		return {}
	return state.settle(opened.token,id,true,"story",{"seconds":25.0,"preset":"unknown","skill":"雷诀"})

func _run() -> void:
	catalogue_contract()
	story_progression()
	retry_and_reward_contract()
	prelude_contract()
	objective_gate_contract()
	building_contract()
	stream_skill_contract()
	geometry_and_timing()
	snapshot_contract()
	save_isolation()
	for row in Catalogue.all():
		play_encounter(row)
	print("PIXEL_CAMPAIGN_RULES ", assertions," assertions; ",failures.size()," failures")
	print("PURE_FIGHT_RESULTS ", JSON.stringify(fight_records))
	quit(0 if failures.is_empty() else 1)

func catalogue_contract() -> void:
	var ids: Array = []
	var shapes = ["circle","line","charge","cross","ring","cone","corridor","roots","pulse"]
	expect(Catalogue.all().size()==20,"all twenty boss entries exist")
	var document = JSON.parse_string(FileAccess.get_file_as_string(Catalogue.PATH))
	for row in Catalogue.all():
		expect(row.id not in ids,"unique boss id "+str(row.id))
		ids.append(row.id)
		for field in ["name","visual","backstory","core_mechanic","objective_hint","tell","patterns","clinical_inspiration","source_id"]:
			expect(row.has(field),str(row.id)+" preserves "+field)
		expect(not bool(row.health_diagnosis_required),str(row.id)+" does not require a diagnosis")
		expect(not bool(row.game_victory_changes_clinical_status),str(row.id)+" is not a cure assertion")
		if row.source_id != null and not str(row.source_id).is_empty():
			expect(document.sources.has(row.source_id),str(row.id)+" clinical inspiration retains its source")
		for pattern in row.patterns:
			expect(pattern in shapes,str(row.id)+" has a supported attack pattern")
	expect(Catalogue.minions().size()==10,"ten minion entries exist")
	expect(Catalogue.people().size()==6,"six region storytellers exist")
	var minion_ids: Array = []
	for mob in Catalogue.minions():
		expect(mob.id not in minion_ids,"unique minion id "+str(mob.id))
		minion_ids.append(mob.id)
	for region in ["木","火","土","金","水"]:
		expect(Catalogue.minions_for(region).size()==2,region+" has two related minions")
		expect(Catalogue.region_order(region).size()==3,region+" has a three-encounter story")

func story_progression() -> void:
	var state = fresh()
	expect(state.availability("b00").is_empty(),"tutorial starts unlocked")
	expect(not state.availability("b01").is_empty(),"tutorial gates the first expedition")
	expect(not state.begin("b03").ok,"cannot skip to a core")
	clear_story(state,"b00")
	expect("village_lamp_lit" in state.data.story_flags,"tutorial lights the village lamp")
	expect(not state.availability("b16").is_empty(),"night side story waits for a restored region")
	expect(not state.availability("b17").is_empty(),"memory side story waits for a restored region")
	expect(not state.availability("b18").is_empty(),"shared domain waits for a restored region")
	for region in ["木","火","土","金","水"]:
		var chain: Array = Catalogue.region_order(region)
		expect(state.availability(chain[0]).is_empty(),region+" can be freely chosen after the tutorial")
		expect(not state.availability(chain[1]).is_empty(),region+" middle encounter is gated")
		expect(not state.availability(chain[2]).is_empty(),region+" core encounter is gated")
		expect(not state.availability("b19").is_empty(),"finale stays locked before five actual core clears")
		clear_story(state,chain[0])
		expect(state.availability(chain[1]).is_empty(),region+" support clear opens middle encounter")
		expect(not state.availability(chain[2]).is_empty(),region+" support alone does not open core")
		clear_story(state,chain[1])
		expect(state.availability(chain[2]).is_empty(),region+" middle clear opens core")
		clear_story(state,chain[2])
		expect("region_"+region+"_restored" in state.data.story_flags,region+" restoration has a persistent story flag")
		expect(state.availability("b16").is_empty(),"first core opens night side story")
		expect(state.availability("b17").is_empty(),"first core opens memory side story")
		expect(state.availability("b18").is_empty(),"first core opens shared domain")
	expect(state.data.seals.size()==5,"five unique core victories yield five seals")
	expect("five_seals" in state.data.story_flags,"five-seal story flag is set")
	expect(state.availability("b19").is_empty(),"five cores open the finale")
	for id in ["b16","b17","b18","b19"]:
		clear_story(state,id)
	expect("finale_complete" in state.data.story_flags,"finale completion is persisted")
	expect(state.data.clears.size()==20,"the complete story can visit all twenty encounters")
	expect(state.data.minion_lore.size()==10,"five region restorations collect all ten minion stories")
	var forged = fresh()
	clear_story(forged,"b00")
	forged.data.seals = ["木","火","土","金","水"]
	expect(not forged.availability("b19").is_empty(),"seal display alone cannot bypass actual core progress")

func retry_and_reward_contract() -> void:
	var state = fresh()
	var start: Dictionary = state.begin("b00")
	var before: Dictionary = state.data.duplicate(true)
	var lost: Dictionary = state.settle(start.token,"b00",false,"story")
	expect(lost.ok and lost.xp==0 and lost.materials==0,"defeat gives no fabricated reward")
	expect(state.data.xp==before.xp and state.data.materials==before.materials,"defeat never charges family resources")
	expect(state.availability("b00").is_empty(),"defeat permits an immediate free retry")
	var retry: Dictionary = state.begin("b00")
	var first: Dictionary = state.settle(retry.token,"b00",true,"story")
	expect(first.ok and first.first and first.xp==80 and first.materials==3,"first tutorial clear has its fixed reward")
	var xp_before: int = state.data.xp
	var materials_before: int = state.data.materials
	expect(not state.settle(retry.token,"b00",true,"story").ok,"settlement token is idempotent")
	var replay: Dictionary = state.begin("b00")
	var repeat: Dictionary = state.settle(replay.token,"b00",true,"standard",{"seconds":12.0,"preset":"unknown","skill":"雷诀"})
	expect(repeat.ok and not repeat.first and repeat.xp==0 and repeat.materials==0,"replays do not duplicate story rewards")
	expect(state.data.xp==xp_before and state.data.materials==materials_before,"replay preserves earned resources")
	expect(state.data.best_records.has("b00|standard|unknown|雷诀"),"replay still records a useful personal best")
	var abandoned: Dictionary = state.begin("b00")
	state.abandon(abandoned.token)
	expect(not state.settle(abandoned.token,"b00",true,"story").ok,"abandoned battle cannot settle later")
	expect(state.data.xp==xp_before,"abandoning is free")

func prelude_contract() -> void:
	var battle = Encounter.new(Catalogue.entry("b03"),fresh().snapshot())
	var initial_hp: float = battle.boss_hp
	var hit: Dictionary = battle.attack(battle.boss_position)
	expect(hit.get("blocked_by_prelude",false) and battle.boss_hp==initial_hp,"melee cannot bypass living minions")
	var cast: Dictionary = battle.cast(Vector2(8.4,-0.8))
	expect(cast.get("blocked_by_prelude",false) and battle.boss_hp==initial_hp,"ranged skill cannot bypass living minions")
	var support = Encounter.new(Catalogue.entry("b03"),fresh().snapshot())
	var node_hit: Dictionary = support.attack(support.nodes[0].position)
	expect(node_hit.get("node",false) and support.nodes[0].hp==1,"ordinary array nodes remain valid during the prelude")
	var mob_hp: float = support.minions[0].hp
	var ranged_hit: Dictionary = support.cast(support.minions[0].position)
	expect(ranged_hit.get("minion",false) and support.minions[0].hp<mob_hp,"a valid prelude target still takes skill damage")
	expect(support.boss_hp==support.boss_max,"hitting a minion never damages the boss")

func clear_minions(battle) -> void:
	for _i in range(160):
		if battle.living_minions()==0:
			return
		var position = Vector2.ZERO
		for mob in battle.minions:
			if mob.hp>0:
				position = mob.position
				break
		battle.attack(position)
		battle.cast(position)
		battle.step(0.1,position)

func advance(battle, seconds: float, position: Vector2) -> void:
	for _i in range(ceili(seconds/0.1)):
		battle.step(0.1,position)

func objective_gate_contract() -> void:
	for row in Catalogue.all():
		if row.id=="b00":
			continue
		var battle = Encounter.new(row,fresh().snapshot())
		clear_minions(battle)
		advance(battle,3.5,Vector2(-8,-5))
		var hp_before: float = battle.boss_hp
		var melee: Dictionary = battle.attack(battle.boss_position)
		var spell: Dictionary = battle.cast(battle.boss_position)
		expect(melee.get("blocked_by_objective",false),str(row.id)+" cannot melee past its unresolved story objective")
		expect(spell.get("blocked_by_objective",false),str(row.id)+" cannot cast past its unresolved story objective")
		expect(battle.boss_hp==hp_before and not battle.hint.is_empty(),str(row.id)+" objective protection preserves enemy HP and gives a next action")
		if row.id=="b11":
			var original_node_hp: int = battle.nodes[0].hp
			expect(not battle.interact(battle.nodes[0].position),"feather lamp escort cannot be replaced by E on a node")
			advance(battle,0.5,Vector2(-8,-5))
			var bypass: Dictionary = battle.attack(battle.nodes[0].position)
			expect(bypass.get("blocked_by_objective",false) and battle.nodes[0].hp==original_node_hp,"feather lamp escort cannot be replaced by J on a node")
			for _i in range(100):
				battle.guard()
				battle.step(0.1,battle.escort)
			expect(battle.escort_done and battle.remaining_nodes()==0,"actual lamp arrival resolves its story objective")
		elif row.id=="b17":
			for index in [2,0,1]:
				battle.interact(battle.nodes[index].position)
		else:
			for node in battle.nodes:
				battle.interact(node.position)
		advance(battle,0.5,Vector2(-8,-5))
		var after: Dictionary = battle.attack(battle.boss_position)
		expect(after.get("damage",0)>0 and battle.boss_hp<hp_before,str(row.id)+" becomes vulnerable after its actual objective")

func building_contract() -> void:
	var state = fresh()
	state.data.materials = 100
	var specs: Dictionary = state.building_specs()
	expect(specs.size()==4 and specs["门灯"].cost==3 and specs["药圃"].cost==9 and specs["听雨亭"].cost==15 and specs["观星台"].cost==24,"four building costs share one canonical specification")
	expect(not state.build("未知房舍") and state.data.materials==100,"unknown building names cannot consume or create resources")
	expect(not state.build("门灯"),"lamp requires the tutorial even when materials are available")
	clear_story(state,"b00")
	var before: int = state.data.materials
	expect(state.build("门灯") and state.data.materials==before-3,"unlocked lamp deducts exactly its stated cost")
	before = state.data.materials
	expect(not state.build("门灯") and state.data.materials==before,"a built item cannot charge twice")
	state.data.seals = ["木","火","土","金","水"]
	expect(not state.build("药圃") and not state.build("听雨亭"),"forged seal display does not unlock building progression")
	state.data.seals = []
	for region in ["木","火","土","金","水"]:
		for id in Catalogue.region_order(region):
			clear_story(state,id)
		if region=="木":
			before = state.data.materials
			expect(state.build("药圃") and state.data.materials==before-9,"one actual core unlocks the nine-material garden")
			expect(not state.build("听雨亭"),"one core is not enough for the rain pavilion")
		if region=="火":
			expect(not state.build("听雨亭"),"two cores are not enough for the rain pavilion")
		if region=="土":
			before = state.data.materials
			expect(state.build("听雨亭") and state.data.materials==before-15,"three actual cores unlock the fifteen-material pavilion")
	expect(not state.build("观星台"),"five seals without the finale do not unlock the observatory")
	clear_story(state,"b19")
	state.data.materials = 23
	expect(not state.build("观星台") and state.data.materials==23,"insufficient material does not partially deduct")
	state.data.materials = 24
	expect(state.build("观星台") and state.data.materials==0,"finale observatory deducts exactly twenty-four materials")

func stream_skill_contract() -> void:
	var battle = Encounter.new(Catalogue.entry("b18"),fresh().snapshot(),"story","分流")
	battle._spawn("circle",Vector2.ZERO,1.0,0.05)
	battle.step(0.1,Vector2.ZERO)
	var damaged_hp: float = battle.hp
	expect(damaged_hp<battle.hp_max-25,"healing test receives a real telegraphed impact first")
	var result: Dictionary = battle.cast(Vector2.ZERO)
	expect(is_equal_approx(battle.hp-damaged_hp,25.0),"stream skill restores exactly twenty-five HP")
	expect(is_equal_approx(battle.skill_cd,6.0),"stream has its own six-second cooldown")
	expect(result.get("blocked_by_objective",false) and battle.boss_hp==battle.boss_max,"stream healing does not bypass the objective gate")
	advance(battle,3.5,Vector2(-8,-5))
	expect(not battle.cast(Vector2.ZERO).ok,"stream cannot use the shorter lightning cooldown")

	var prelude_healer = Encounter.new(Catalogue.entry("b03"),fresh().snapshot(),"story","分流")
	var minion_position: Vector2 = prelude_healer.minions[0].position
	prelude_healer._spawn("circle",minion_position,1.0,0.05)
	prelude_healer.step(0.1,minion_position)
	var before_heal: float = prelude_healer.hp
	var mob_before: float = prelude_healer.minions[0].hp
	var heal_cast: Dictionary = prelude_healer.cast(minion_position)
	expect(is_equal_approx(prelude_healer.hp-before_heal,25.0),"stream heals twenty-five even when it selects a living minion")
	expect(is_equal_approx(mob_before-prelude_healer.minions[0].hp,72.0) and heal_cast.get("minion",false),"stream uses its own seventy-two damage on minions")
	expect(is_equal_approx(prelude_healer.skill_cd,6.0) and prelude_healer.weak_time>=2.0,"stream prelude cast applies its own cooldown and support window")
	var prelude_guard = Encounter.new(Catalogue.entry("b03"),fresh().snapshot(),"story","镇心")
	mob_before = prelude_guard.minions[0].hp
	var guard_cast: Dictionary = prelude_guard.cast(prelude_guard.minions[0].position)
	expect(is_equal_approx(prelude_guard.guard_time,2.0),"guard skill applies its shield before selecting a living minion")
	expect(is_equal_approx(mob_before-prelude_guard.minions[0].hp,85.0) and guard_cast.get("minion",false),"guard skill uses its own eighty-five damage on minions")
	expect(is_equal_approx(prelude_guard.skill_cd,3.4),"guard skill keeps the standard skill cooldown during the prelude")

func geometry_and_timing() -> void:
	var battle = Encounter.new(Catalogue.entry("b00"))
	var circle: Dictionary = battle._spawn("circle",Vector2.ZERO,1.5,1.0)
	expect(battle.contains(circle,Vector2(1,0)) and not battle.contains(circle,Vector2(3,0)),"circle hit region matches its drawn radius")
	var ring: Dictionary = battle._spawn("ring",Vector2.ZERO,3.0,1.0,0.4)
	expect(battle.contains(ring,Vector2(3,0)) and not battle.contains(ring,Vector2.ZERO),"ring has a safe inner area")
	battle._line(Vector2(-3,0),Vector2(3,0),0.6,1.0)
	var line: Dictionary = battle.hazards.back()
	expect(battle.contains(line,Vector2(0,0.4)) and not battle.contains(line,Vector2(0,2)),"line collision uses the warned segment")
	battle._line(Vector2(-3,0),Vector2(3,0),0.6,1.0,true)
	expect(battle.hazards.back().shape=="charge","charge shares a visible line footprint")
	var cone: Dictionary = battle._spawn("cone",Vector2.ZERO,5.0,1.0)
	cone.angle = 0.0
	cone.half_angle = 0.5
	expect(battle.contains(cone,Vector2(3,0)) and not battle.contains(cone,Vector2(-3,0)),"cone has a safe rear sector")
	battle.hazards.clear()
	battle._spawn("circle",Vector2.ZERO,1.5,1.0)
	var original_hp: float = battle.hp
	for _i in range(8):
		battle.step(0.1,Vector2.ZERO)
	expect(battle.hp==original_hp,"a telegraph does no early damage")
	battle.guard()
	for _i in range(6):
		battle.step(0.1,Vector2.ZERO)
	expect(battle.hp==original_hp and battle.perfect_blocks==1,"timed guard converts a real warned impact into a counter window")
	var frozen: float = battle.elapsed
	battle.paused = true
	battle.step(0.1,Vector2.ZERO)
	expect(battle.elapsed==frozen and not battle.attack(Vector2.ZERO).ok,"pause freezes rules and combat input")
	var memory = Encounter.new(Catalogue.entry("b17"))
	expect(not memory.interact(memory.nodes[0].position),"memory story gives a readable hint instead of accepting the wrong order")
	for index in [2,0,1]:
		expect(memory.interact(memory.nodes[index].position),"memory story accepts its visible route order")
	expect(memory.remaining_nodes()==0,"memory route resolves after all three landmarks")

func snapshot_contract() -> void:
	var state = fresh()
	var initial: Dictionary = state.snapshot()
	var battle = Encounter.new(Catalogue.entry("b01"),initial)
	initial.attack = 9999
	state.data.simulated_health = "tired"
	expect(is_equal_approx(float(battle.snapshot.attack),1.0),"encounter uses its immutable entry snapshot")
	expect(bool(battle.snapshot.simulated),"preset is explicitly a simulation")
	expect(state.snapshot().attack<1.0,"a later demo preset changes only the next entry snapshot")
	for clinical_key in ["diagnosis","blood_pressure","blood_glucose","cancer_status","recovered"]:
		expect(not battle.snapshot.has(clinical_key),"combat snapshot contains no actual clinical value: "+clinical_key)

func save_isolation() -> void:
	var folder = ProjectSettings.globalize_path("res://work/pixel-campaign/test-state")
	DirAccess.make_dir_recursive_absolute(folder)
	var state = State.new()
	state.save_override = folder.path_join("isolated.json")
	state.data.name = "像素测试"
	state.save_game()
	expect(FileAccess.file_exists(state.save_override),"explicit test save override is honored")
	var restored = State.new()
	restored.save_override = state.save_override
	restored.load_game()
	expect(restored.data.name=="像素测试" and restored.data.schema==3,"new campaign round-trips schema three")
	var old_env = OS.get_environment("XIUXIAN_PIXEL_CAMPAIGN_SAVE_DIR")
	OS.set_environment("XIUXIAN_PIXEL_CAMPAIGN_SAVE_DIR",folder.path_join("env"))
	var environment = State.new()
	expect(environment.path()==folder.path_join("env/pixel_five_realms_v1.json"),"pixel-specific save environment selects an isolated filename")
	environment.save_override = folder.path_join("override.json")
	expect(environment.path()==environment.save_override,"explicit override wins over the environment")
	if old_env.is_empty():
		OS.unset_environment("XIUXIAN_PIXEL_CAMPAIGN_SAVE_DIR")
	else:
		OS.set_environment("XIUXIAN_PIXEL_CAMPAIGN_SAVE_DIR",old_env)
	var malformed_path = folder.path_join("malformed.json")
	var malformed = FileAccess.open(malformed_path,FileAccess.WRITE)
	malformed.store_string("{broken campaign")
	malformed.close()
	var invalid = State.new()
	invalid.save_override = malformed_path
	invalid.load_game()
	invalid.save_game()
	expect(not invalid.persist_enabled and not invalid.load_warning.is_empty(),"malformed save disables overwrite and explains recovery")
	expect(FileAccess.get_file_as_string(malformed_path)=="{broken campaign","malformed original is preserved")
	var source = FileAccess.get_file_as_string("res://scripts/pixel_campaign/state.gd")
	expect(not source.contains("family_cultivation_demo.json") and not source.contains("local-save.json"),"new saga never implicitly imports old village health or resources")
	for suffix in ["isolated.json","isolated.json.bak","isolated.json.tmp","malformed.json"]:
		var target = folder.path_join(suffix)
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)

func play_encounter(row: Dictionary) -> void:
	# Public attack/cast/interact/guard/step calls only. No HP or reward injection.
	var battle = Encounter.new(row,fresh().snapshot(),"story","雷诀")
	var player = Vector2(-1,0)
	for _i in range(1000):
		if battle.finished:
			break
		if battle.living_minions()>0:
			for mob in battle.minions:
				if mob.hp>0:
					player = mob.position
					break
		elif row.id=="b11" and not battle.escort_done:
			player = battle.escort
		elif battle.remaining_nodes()>0:
			if row.id=="b17":
				player = battle.nodes[[2,0,1][battle.interactions]].position
			else:
				for node in battle.nodes:
					if not node.done:
						player = node.position
						break
			battle.interact(player)
		else:
			player = battle.clamp_position(battle.boss_position+Vector2(-1.4,0))
		# React to the real telegraphs; shifting sides leaves the warning footprint.
		for hazard in battle.hazards:
			if hazard.timer<0.35 and battle.contains(hazard,player):
				battle.guard()
				if battle.guard_time<=0.0:
					battle.dash()
		if battle.living_minions()>0 or battle.remaining_nodes()==0:
			battle.attack(player)
			battle.cast(player)
		battle.step(0.1,player)
	fight_records.append({"id":row.id,"won":battle.won,"seconds":snappedf(battle.elapsed,0.1),"hp_remaining":battle.hp,"minions_left":battle.living_minions(),"nodes_left":battle.remaining_nodes()})
	expect(battle.finished and battle.won,str(row.id)+" can be cleared through real rule inputs")
	expect(battle.living_minions()==0,str(row.id)+" prelude can be completed")
	expect(battle.remaining_nodes()==0,str(row.id)+" array objective can be completed")
	if row.id=="b00":
		expect(battle.perfect_blocks+battle.avoided_attacks>0,"tutorial requires an observed evade or guard")
	if row.id=="b11":
		expect(battle.escort_done,"feather lamp reaches its destination")
