extends SceneTree

const State = preload("res://scripts/game_state.gd")
const Trial = preload("res://scripts/tribulation_rules.gd")
const Boss = preload("res://scripts/boss_rules.gd")
var errors: int = 0
var passed: int = 0

class ClockState extends State:
	var date_value: String = "2026-10-30"
	func today() -> String:
		return date_value

func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS: ", message)
	else:
		errors += 1
		push_error(message)

func find_button(parent: Node, prefix: String) -> Button:
	for item in parent.find_children("*", "Button", true, false):
		if item.text.begins_with(prefix):
			return item
	return null

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var state = ClockState.new()
	state.persist_enabled = false
	check(not state.record_task("medication", false).ok, "Daily records require family consent")
	state.medication_required = false
	check(not state.record_task("medication", true).ok, "No medication task without an existing plan")
	state.medication_required = true
	check(state.record_task("medication", true).rewarded, "First confirmed medication record earns the daily reward")
	check(state.cultivation == 90 and state.qi == 24 and state.charms == 2 and state.days == 29 and state.equipment.qi == 100, "Daily rewards add 100 wish qi without altering legacy battle consumables")
	check(not state.record_task("medication", true).ok, "Duplicate medication record is rejected")
	var second = state.record_task("planned_record", true)
	check(second.ok and not second.rewarded and state.cultivation == 90 and state.days == 29, "Two different tasks share one daily reward")
	state.date_value = "2026-10-31"
	check(not state.task_done("medication"), "A new day gets a fresh task status")
	check(state.record_task("medication", true).rewarded and state.cultivation == 100, "The next day can earn a new reward")
	check(not state.begin_recovery(false), "Recovery chapter requires family confirmation")
	check(state.begin_recovery(true) and state.longterm_enabled, "Long-term management and recovery coexist")
	var trial_state = State.new()
	trial_state.persist_enabled = false
	trial_state.begin_recovery(true)
	var trial = Trial.new(trial_state)
	trial.choose(0)
	trial.choose(2)
	trial.choose(0)
	check(trial.won and trial.finished and trial.hp > 0 and trial.thunder == 0, "Attack, talisman, attack completes three-turn trial")
	check(trial_state.qi == 14 and trial_state.charms == 1, "Trial consumes chosen resources exactly once")
	check(trial_state.trial_cleared and trial_state.recovery_status == "active", "Winning a game never confirms real recovery")
	check(not trial.choose(0).ok and trial_state.qi == 14, "Finished trial cannot consume resources again")
	check(not trial_state.confirm_recovery(true, false), "Recovery needs a separately confirmed reliable source")
	check(trial_state.confirm_recovery(true, true) and trial_state.recovery_status == "recovered", "Family confirmation can separately close the recovery chapter")
	var no_resources = State.new()
	no_resources.qi = 0
	no_resources.charms = 0
	var dry_trial = Trial.new(no_resources)
	check(not dry_trial.choose(0).ok and not dry_trial.choose(2).ok and dry_trial.round == 0, "Unavailable skills cannot advance a round")
	# Detailed action combat cases live in action_progression_test.gd.
	# Persistence checks use a separate fixture and never write the live player save.
	var save_state = State.new()
	save_state.save_file_override = "res://output/gameplay-test-fixture.json"
	var path = save_state.save_path()
	check(path != State.new().save_path(), "Automated persistence tests use an isolated fixture")
	var had_save = FileAccess.file_exists(path)
	var backup = FileAccess.get_file_as_string(path) if had_save else ""
	var legacy = FileAccess.open(path, FileAccess.WRITE)
	legacy.store_string('{"cultivation":137,"qi":31,"charms":6,"days":42,"contribution":296}')
	legacy.close()
	save_state.load_game()
	check(save_state.cultivation == 137 and save_state.days == 42 and save_state.contribution == 296 and not save_state.profile_created, "Legacy save migration preserves old progress")
	save_state.choose_avatar("female", "清岚")
	save_state.begin_recovery(true)
	save_state.save_game()
	var loaded = State.new()
	loaded.save_file_override = path
	loaded.load_game()
	check(loaded.avatar_id == "female" and loaded.player_name == "清岚" and loaded.profile_created and loaded.cultivation == 137, "Avatar and nickname persist without resetting resources")
	check(loaded.recovery_status == "active" and loaded.longterm_enabled, "Both care tracks persist")
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.state = State.new()
	scene.state.persist_enabled = false
	scene.state.apply_health_profile(scene.state.HealthProfile.mock(40, 1))
	scene.ui.refresh()
	scene.ui.show_start()
	check(scene.ui.modal_open and scene.player.blocked and scene.ui.avatar_buttons.size() == 2, "Start screen blocks the town and offers two avatars")
	scene.ui.select_avatar("female")
	scene.ui.nickname_input.text = "清岚"
	scene.ui.start_selected()
	check(scene.state.avatar_id == "female" and scene.player.walk_textures == scene.avatar_frames.female and not scene.ui.modal_open, "Choosing female changes the actual playable walking character")
	check(scene.player_name_label.text == "清岚" and scene.ui.hud_name_label.text == "清岚", "Player name and family member remain distinct in HUD")
	scene.ui.show_start()
	scene.ui.select_avatar("male")
	scene.ui.start_selected()
	check(scene.player.walk_textures == scene.avatar_frames.male, "Male character can be selected again")
	scene.ui.open_record()
	var consent = scene.ui.modal.find_children("*", "CheckBox", true, false)[0]
	var medication = find_button(scene.ui.modal, "确认今日服药")
	check(medication != null and medication.disabled, "Medication UI requires an explicit family checkbox")
	consent.button_pressed = true
	medication.pressed.emit()
	check(scene.state.task_done("medication") and scene.state.cultivation == 90, "Actual medication button records and awards")
	scene.ui.open_record()
	consent = scene.ui.modal.find_children("*", "CheckBox", true, false)[0]
	consent.button_pressed = true
	find_button(scene.ui.modal, "确认今日计划").pressed.emit()
	check(scene.state.task_done("planned_record") and scene.state.cultivation == 90, "Actual second task UI cannot duplicate reward")
	scene.ui.close_modal()
	scene.ui.open_recovery()
	var care: Control = scene.ui.lifecycle_panel
	care.request_confirmation("begin")
	await care.confirm_pending()
	check(scene.state.recovery_status == "active" and scene.state.longterm_enabled, "Recovery UI activates a parallel chapter through explicit family confirmation")
	scene.ui.close_modal()
	await process_frame
	scene.ui.start_battle()
	check(not is_instance_valid(scene.ui.combat), "An elder in tribulation cannot enter a game battle")
	scene.ui.open_recovery()
	care = scene.ui.lifecycle_panel
	care.request_confirmation("celebrate")
	await care.confirm_pending()
	scene.ui.close_modal()
	await process_frame

	scene.ui.start_battle()
	check(scene.ui.combat.mode == "practice" and scene.ui.combat.rules.practice, "The training entrance uses the four-skill battle")
	scene.ui.combat.use_skill(0)
	check(scene.ui.combat.rules.mp < scene.ui.combat.rules.max_mp and scene.ui.combat.cast_visual > 0, "Sword input consumes mana and produces a live effect")
	scene.ui.close_modal()
	scene.ui.start_boss(false)
	check(scene.ui.combat.dragon_frames.size() == 16 and scene.ui.combat.boss_id == "b00" and scene.state.boss_attempts == 1, "Named boss loads sixteen redrawn action frames")
	scene.ui.combat.hero.position = Vector2(900, 575)
	var boss_hp_before = scene.ui.combat.rules.boss_hp
	scene.ui.combat.basic_attack()
	await create_timer(.18).timeout
	check(scene.ui.combat.rules.boss_hp < boss_hp_before and scene.ui.combat.cast_visual > 0, "Basic attack requires an actual nearby hit")
	var town_position = scene.player.position
	var hero_position = scene.ui.combat.hero.position
	Input.action_press("move_forward")
	await create_timer(0.18).timeout
	Input.action_release("move_forward")
	check(scene.ui.combat.hero.position.distance_to(hero_position) > 15 and scene.player.position.distance_to(town_position) < 1, "WASD moves the battle character while town character stays blocked")
	var hp_before = scene.ui.combat.rules.hp
	# Observe the new named-enemy timeline: tell -> travelling volley -> recovery.
	var combat: Control = scene.ui.combat
	combat.set_process(false)
	combat.hero.position = Vector2(700,575)
	var saw_warning := false
	var saw_projectile := false
	for frame in range(900):
		combat._process(1.0/60)
		saw_warning = saw_warning or combat.rules.phase == "windup"
		saw_projectile = saw_projectile or not combat.rules.brain.projectiles.is_empty()
		if saw_projectile and combat.rules.hp<hp_before and combat.rules.phase == "breath":
			break
	check(saw_warning and saw_projectile and combat.rules.hp<hp_before and combat.rules.phase == "breath", "The rendered moving boss telegraphs, fires travelling shots and damages on contact")
	scene.ui.close_modal()
	check(not scene.ui.modal_open and not scene.player.blocked, "Returning from a battle restores town controls")
	for index in range(3):
		scene.ui.open_npc(index)
		check(scene.ui.modal_open, "Existing NPC interaction remains available: " + str(index))
		scene.ui.close_modal()
	check(not scene.can_walk(Vector2(740, 820)) and not scene.can_walk(Vector2(395, 340)), "Water and rooftops remain blocked")
	Engine.time_scale = 4.0
	for site in scene.sites:
		scene.player.position = scene.SPAWN
		scene.travel_to(site.id)
		var deadline = Time.get_ticks_msec() + 6000
		while not scene.ui.modal_open and Time.get_ticks_msec() < deadline:
			await create_timer(0.1).timeout
		check(scene.ui.modal_open and scene.player.position.distance_to(site.position) < 12, "Full automatic town walk to " + site.id)
		scene.ui.close_modal()
	Engine.time_scale = 1.0
	scene.queue_free()
	await process_frame
	if had_save:
		var restored_file = FileAccess.open(path, FileAccess.WRITE)
		restored_file.store_string(backup)
		restored_file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path.trim_suffix(".json") + "-before-corridor-v4.json"))
	print("GAMEPLAY TEST RESULT: ", "PASS" if errors == 0 else "FAIL", " (", passed, " passed, ", errors, " failures)")
	quit(errors)
