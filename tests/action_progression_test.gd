extends SceneTree
const State = preload("res://scripts/game_state.gd")
const Health = preload("res://scripts/health_profile.gd")
const Boss = preload("res://scripts/boss_rules.gd")
var errors = 0
var passed = 0

func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS: ", message)
	else:
		errors += 1
		push_error(message)

func fresh(score: int = 40):
	var state = State.new()
	state.persist_enabled = false
	state.apply_health_profile(Health.mock(score, 1))
	return state

func find_button(parent: Node, prefix: String) -> Button:
	for child in parent.find_children("*", "Button", true, false):
		if child.text.begins_with(prefix):
			return child
	return null

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var state = fresh()
	check(state.health_attributes.attack == 40 and state.health_simulated, "Explicit simulated import initializes five attributes")
	var original = state.health_attributes.duplicate(true)
	var invalid = Health.mock(60, 2)
	invalid.attributes.erase("defense")
	check(not state.apply_health_profile(invalid).ok and state.health_attributes == original, "Incomplete external profiles are rejected atomically")
	invalid = Health.mock(60, 2)
	invalid.attributes.attack = 101
	check(not state.apply_health_profile(invalid).ok, "Out-of-range health scores are rejected")
	invalid.attributes.attack = "60"
	check(not state.apply_health_profile(invalid).ok, "String scores are not silently accepted")
	invalid.attributes.attack = true
	check(not state.apply_health_profile(invalid).ok, "Boolean scores are not numbers")
	check(not state.apply_health_profile(Health.mock(60, 1)).ok, "Repeated profile revisions cannot overwrite current data")
	check(state.apply_health_profile(Health.mock(60, 2)).ok and state.health_attributes.attack == 60, "A newer assessment changes capability")
	var low = Boss.new(fresh(0))
	var high = Boss.new(fresh(100))
	check(low.max_hp > 0 and low.max_mp >= Boss.SWORD_COST and low.max_stamina >= Boss.DODGE_COST, "The score interface never performs a medical/death decision")
	check(high.max_hp == 100 and low.max_hp == 100 and high.max_mp > low.max_mp and high.max_stamina > low.max_stamina, "Base health stays 100 while spirit and stamina scale battle limits")
	check(high.stats.attack > low.stats.attack and high.stats.shield > low.stats.shield and high.stats.damage_multiplier < low.stats.damage_multiplier, "Attack and defense affect damage and protection")
	check(not state.stage_available("attack", 20) and state.stage_available("life", 10), "Each attribute track starts at tier ten")
	check(not state.begin_boss(false, 25, "attack").ok and not state.begin_boss(false, 10, "unknown").ok, "Invalid track and tier requests are rejected")
	check(not state.complete_stage("attack", 100), "Clears cannot skip locked stages")
	check(state.complete_stage("attack", 10) and state.next_tier("attack") == 20, "First clear opens the next ten-point tier")
	check(not state.heal_unlocked(), "One first clear does not unlock healing")
	check(not state.complete_stage("attack", 10) and not state.heal_unlocked(), "Repeating one boss does not count as two clears")
	state.complete_stage("attack", 20)
	check(state.heal_unlocked() and state.realm() == "筑基", "Second distinct first clear unlocks healing and progress")
	state.apply_health_profile(Health.mock(10, 3))
	check(state.heal_unlocked() and state.stage_cleared("attack", 20), "Later health changes preserve earned progression")
	for i in range(5):
		check(state.begin_boss(false, 10, "attack").ok, "Practice attempts are not capped at three: " + str(i))
	check(state.health_attributes.attack < 10 + 1 and state.stage_available("attack", 30), "Attribute values are recommendations, not entry gates")
	check(state.begin_boss(false, 0, "life").ok and state.selected_tier == 10, "Automatic tier selection uses the requested attribute track")
	check(state.complete_stage("life", 10, {"time": 20.0}), "A different attribute track records its own first clear")
	state.complete_stage("life", 10, {"time": 30.0})
	check(state.best_records.life_10.time == 20.0, "A slower replay cannot replace the best result")
	state.complete_stage("life", 10, {"time": 15.0})
	check(state.best_records.life_10.time == 15.0, "A faster replay updates the local best result")
	var combat_state = fresh()
	var battle = Boss.new(combat_state)
	var baseline = combat_state.health_attributes.duplicate(true)
	battle.mp = 0
	var miss = battle.attack(Vector2(200, 500))
	check(miss.ok and miss.damage == 0 and battle.mp == 0, "Out-of-range basic attacks cannot deal damage or generate mana")
	battle.step(0.61, Vector2(200, 500))
	var hit = battle.attack(Vector2(900, 575))
	check(hit.damage == battle.stats.attack and battle.mp == 5, "A genuine basic hit restores five mana")
	check(not battle.attack().ok and battle.mp == 5, "Cooldown blocks repeated basic hits and mana farming")
	check(not battle.sword(Vector2(600, 600), Vector2.RIGHT).ok, "Sword requires mana")
	battle.mp = battle.max_mp
	var mana_before = battle.mp
	var sword = battle.sword(Vector2(600, 575), Vector2.RIGHT)
	check(sword.ok and sword.damage > hit.damage and battle.mp == mana_before - Boss.SWORD_COST, "Sword spends mana and exceeds basic damage")
	check(not battle.sword(Vector2(600, 575), Vector2.RIGHT).ok, "Sword cooldown is enforced")
	var targets = [{"id": "one", "position": Vector2(200, 100)}, {"id": "two", "position": Vector2(400, 110)}, {"id": "outside", "position": Vector2(300, 350)}, {"id": "behind", "position": Vector2(0, 100)}]
	var path_hits = Boss.sword_hits(Vector2(100, 100), Vector2.RIGHT, targets)
	check(path_hits.size() == 2, "Sword hits multiple targets along its forward path")
	var crowd = [{"id": "a", "position": Vector2(700, 575), "hp": 500}, {"id": "b", "position": Vector2(800, 575), "hp": 500}]
	var crowd_battle = Boss.new(fresh())
	var multi = crowd_battle.sword(Vector2(600, 575), Vector2.RIGHT, crowd)
	check(multi.hit_count == 3 and crowd[0].hp < 500 and crowd[1].hp < 500, "Sword applies damage to every path target, including the boss")
	var dodger = Boss.new(fresh())
	dodger.stamina = Boss.DODGE_COST - 1
	check(not dodger.dodge(), "Dodge cannot be used without stamina")
	dodger.stamina = dodger.max_stamina
	var stamina_before = dodger.stamina
	check(dodger.dodge() and dodger.stamina == stamina_before - Boss.DODGE_COST, "Cloud step consumes stamina")
	check(dodger.receive_damage(100).event == "evaded" and dodger.hp == dodger.max_hp, "Cloud step provides an actual invulnerability window")
	dodger.step(0.5, Vector2(100, 450))
	check(dodger.stamina == stamina_before - Boss.DODGE_COST, "Stamina regeneration waits for its delay")
	dodger.step(0.7, Vector2(100, 450))
	check(dodger.stamina > stamina_before - Boss.DODGE_COST, "Stamina recovers automatically")
	var guarded = Boss.new(fresh())
	check(guarded.defend() and guarded.mp == guarded.max_mp - Boss.SHIELD_COST, "Cloud shield consumes mana")
	var shield_before = guarded.shield_hp
	var blocked = guarded.receive_damage(60)
	check(blocked.event == "blocked" and guarded.shield_hp < shield_before and guarded.hp == guarded.max_hp, "Shield absorbs finite damage rather than granting total invulnerability")
	var overflow = guarded.receive_damage(1000)
	check(overflow.event == "hurt" and overflow.absorbed > 0 and guarded.shield_hp == 0, "Damage beyond remaining shield reaches health")
	var expire = Boss.new(fresh())
	expire.defend()
	expire.step(3.3, Vector2(100, 450))
	check(expire.shield_hp == 0, "Shield expires after its duration")
	var healer = Boss.new(fresh())
	healer.hp = maxi(1,healer.max_hp-60)
	check(not healer.heal() and healer.mp == healer.max_mp, "Locked healing consumes no resources")
	healer.state.complete_stage("attack", 10)
	healer.state.complete_stage("attack", 20)
	check(healer.heal() and healer.heal_cast > 0 and healer.mp == healer.max_mp - Boss.HEAL_COST, "Unlocked healing spends mana and starts channeling")
	check(not healer.attack().ok and not healer.defend() and not healer.dodge(), "Channeling cannot overlap other combat actions")
	var health_before = healer.hp
	healer.step(0.6, Vector2(100, 450))
	check(healer.hp == health_before, "Healing is delayed until channel completion")
	healer.step(0.6, Vector2(100, 450))
	check(healer.hp > health_before and healer.hp <= healer.max_hp, "Channel completion heals without exceeding max health")
	var stopped = Boss.new(healer.state)
	stopped.hp = maxi(1,stopped.max_hp-60)
	stopped.heal()
	stopped.receive_damage(20)
	health_before = stopped.hp
	stopped.step(1.2, Vector2(100, 450))
	check(stopped.heal_cast == 0 and stopped.hp == health_before, "Incoming damage interrupts recovery")
	check(not stopped.heal(), "Interrupted recovery retains its cooldown")
	check(combat_state.health_attributes == baseline, "Combat cannot consume permanent health attributes")
	var snapshot = Boss.new(combat_state)
	var snapshot_hp = snapshot.max_hp
	combat_state.apply_health_profile(Health.mock(70, 2))
	check(snapshot.max_hp == snapshot_hp and Boss.new(combat_state).max_hp == 100 and Boss.new(combat_state).stats.attack > snapshot.stats.attack, "New assessments affect the next battle, not an active battle snapshot")
	var victor_state = fresh()
	var victor = Boss.new(victor_state)
	while not victor.finished:
		victor.step(0.61, Vector2(100, 450))
		victor.attack()
	check(victor.won and victor_state.stage_cleared("attack", 10), "Actual boss defeat records first clear")
	check(victor.damage_total == victor.boss_max_hp, "Overkill does not inflate contribution")
	var replay = Boss.new(victor_state)
	while not replay.finished:
		replay.step(0.61, Vector2(100, 450))
		replay.attack()
	check(victor_state.cleared_stages.size() == 1, "Replaying a cleared boss cannot unlock healing early")
	var training_state = fresh()
	var training = Boss.new(training_state, 0, 10, "attack", true)
	while not training.finished:
		training.step(0.61, Vector2(100, 450))
		training.attack()
	check(training_state.cleared_stages.is_empty() and training_state.contribution == 0, "Training grants no progression or ranked contribution")
	var defeated = Boss.new(fresh())
	defeated.receive_damage(99999)
	check(defeated.finished and not defeated.won and defeated.state.cleared_stages.is_empty(), "Defeat never awards first-clear progression")
	var after_defeat = defeated.hp
	defeated.step(3.0, Vector2.ZERO)
	check(not defeated.attack().ok and defeated.hp == after_defeat, "Finished battles reject further actions")
	var persistence = fresh(55)
	persistence.persist_enabled = true
	persistence.save_file_override = "user://pixel-progression-test-" + str(OS.get_process_id()) + ".json"
	persistence.complete_stage("attack", 10, {"time": 22.5})
	persistence.complete_stage("attack", 20, {"time": 28.0})
	persistence.save_game()
	var loaded = State.new()
	loaded.save_file_override = persistence.save_file_override
	loaded.load_game()
	check(loaded.health_attributes == persistence.health_attributes and loaded.health_revision == 1, "Assessment attributes and revision survive save/load")
	check(loaded.heal_unlocked() and loaded.best_records.attack_10.time == 22.5, "Stage clears, unlocks and records survive save/load")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(persistence.save_file_override))
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.state = fresh()
	scene.ui.refresh()
	scene.ui.open_home()
	check(find_button(scene.ui.modal, "导入已评估档案") != null, "Pixel profile exposes the external assessment import")
	scene.state.health_profile_id = "ui-before-import"
	find_button(scene.ui.modal, "导入已评估档案").pressed.emit()
	scene.ui.profile_file_dialog.file_selected.emit(ProjectSettings.globalize_path("res://data/health-profile.example.json"))
	check(scene.state.health_attributes.life == 45 and scene.state.health_attributes.spirit == 50, "The actual JSON file selection imports assessed attributes")
	await process_frame
	find_button(scene.ui.modal, "攻击 40").pressed.emit()
	check(scene.state.health_attributes.attack == 40 and scene.state.health_attributes.spirit == 50, "Simulated profiles create different values for different attributes")
	find_button(scene.ui.modal, "模拟健康改善").pressed.emit()
	check(scene.state.health_attributes.attack == 50 and scene.state.health_attributes.spirit == 60, "The mock improvement updates attributes visibly")
	scene.ui.open_boss()
	check(scene.ui.corridor.portal_buttons.size() == 20 and scene.ui.corridor.jump_buttons.size() == 20, "The active challenge UI is the twenty-Boss corridor")
	scene.ui.start_boss(false, 10, "attack")
	check(scene.ui.combat.skill_nodes.size() == 4 and scene.ui.combat.skill_nodes[3].disabled, "Combat displays four named skills with healing initially locked")
	check(scene.ui.combat.vital_bars.size() == 3, "Battle HUD displays health, mana and stamina separately")
	scene.ui.combat.use_skill(0)
	check(scene.ui.combat.cast_visual > 0 and scene.ui.combat.sword_visual, "Sword input triggers a live pixel ink effect")
	var roll_start: Vector2 = scene.ui.combat.hero.position
	scene.ui.combat.use_skill(1)
	check(scene.ui.combat.dodge_visual > 0 and scene.ui.combat.rules.stamina < scene.ui.combat.rules.max_stamina, "Cloud step starts its animation and consumes stamina in the live scene")
	check(scene.ui.combat.hero.position==roll_start and scene.ui.combat.roll_remaining==145,"Cloud step reserves continuous travel without teleporting")
	scene.ui.combat.use_skill(2)
	check(scene.ui.combat.rules.shield_hp==0,"Cloud shield waits until the dodge movement finishes")
	await create_timer(.24).timeout
	check(scene.ui.combat.hero.position.distance_to(roll_start)>120 and scene.ui.combat.roll_remaining==0,"Cloud step completes real continuous movement")
	scene.ui.combat.use_skill(2)
	check(scene.ui.combat.rules.shield_hp > 0, "Cloud shield produces actual shield health after dodge recovery")
	scene.ui.close_modal()
	await process_frame
	check(not scene.player.blocked and not scene.ui.modal_open, "Leaving battle restores village controls")
	scene.ui.start_battle()
	check(scene.ui.combat.mode == "practice" and scene.ui.combat.rules.practice, "The old trial entrance now opens four-skill practice")
	scene.ui.close_modal()
	scene.state.complete_stage("attack", 10)
	scene.state.complete_stage("attack", 20)
	scene.ui.start_boss(false, 30, "attack")
	scene.ui.combat.rules.hp = maxi(1,scene.ui.combat.rules.max_hp-60)
	scene.ui.combat.use_skill(3)
	check(scene.ui.combat.rules.heal_cast > 0 and scene.ui.combat.skill_nodes[3].text.contains("吐纳"), "Unlocked recovery works through the actual fourth skill button")
	var channel_start: Vector2 = scene.ui.combat.hero.position
	Input.action_press("move_right")
	await create_timer(0.2).timeout
	Input.action_release("move_right")
	var channel_distance = scene.ui.combat.hero.position.distance_to(channel_start)
	check(channel_distance > 3 and channel_distance < 30, "Recovery permits movement at a genuinely reduced speed")
	scene.ui.close_modal()
	scene.queue_free()
	await process_frame
	print("ACTION / PROGRESSION RESULT: ", "PASS" if errors == 0 else "FAIL", " (", passed, " passed, ", errors, " failures)")
	quit(errors)
