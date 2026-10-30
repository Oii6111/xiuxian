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
	check(state.cultivation == 90 and state.qi == 28 and state.charms == 3 and state.days == 29, "Daily reward accounting remains unchanged")
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
	var boss_state = State.new()
	boss_state.persist_enabled = false
	check(boss_state.begin_boss(true).ok and boss_state.charms == 1, "Optional support consumes exactly one charm at entry")
	var boss = Boss.new(boss_state, 20)
	check(boss.attack().damage == 116, "Support adds 20 to the first attack")
	check(not boss.attack().ok, "Repeated attack is gated by cooldown")
	boss.step(0.66, Vector2(300, 600))
	check(boss.attack().damage == 96 and boss.damage_total == 212, "Support cannot boost subsequent attacks")
	check(boss_state.contribution == 212, "Dealt damage becomes actual local contribution")
	var incoming = Boss.new(State.new())
	check(incoming.step(2.5, Vector2(300, 600)).event == "windup", "Boss telegraphs before attacking")
	check(incoming.step(1.15, Vector2(300, 600)).event == "hurt" and incoming.hp == 220, "Staying in the warning area takes damage")
	var shielded = Boss.new(State.new())
	shielded.step(2.5, Vector2(300, 600))
	shielded.defend()
	check(shielded.step(1.15, Vector2(300, 600)).event == "blocked" and shielded.hp == 300, "Timed shield blocks an actual boss attack")
	var evaded = Boss.new(State.new())
	evaded.step(2.5, Vector2(300, 600))
	check(evaded.step(1.15, Vector2(300, 490)).event == "evaded" and evaded.hp == 300, "Moving outside the displayed warning ellipse avoids damage")
	var dodged = Boss.new(State.new())
	dodged.step(2.5, Vector2(300, 600))
	dodged.step(0.9, Vector2(300, 600))
	dodged.dodge()
	check(dodged.step(0.25, Vector2(300, 600)).event == "evaded", "Dodge invulnerability works at impact time")
	check(not dodged.dodge(), "Dodge has a real cooldown")
	while not boss.finished:
		boss.step(0.66, Vector2(100, 450))
		boss.attack()
	check(boss.won and boss.damage_total == 1440 and boss_state.contribution == 1440, "Boss defeat caps actual damage and contribution at its health")
	boss_state.begin_boss(false)
	boss_state.begin_boss(false)
	check(not boss_state.begin_boss(false).ok and boss_state.boss_attempts == 3, "Daily boss entry limit is enforced")
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
	var family = scene.ui.modal.find_children("*", "CheckBox", true, false)[0]
	family.button_pressed = true
	find_button(scene.ui.modal, "开启篇章").pressed.emit()
	check(scene.state.recovery_status == "active" and scene.state.longterm_enabled, "Recovery UI activates a parallel chapter")
	scene.ui.close_modal()
	scene.ui.start_battle()
	check(scene.ui.combat.elder.texture != null and scene.ui.combat.mode == "tribulation", "Trial scene has an independent meditating elder sprite")
	scene.ui.combat.use_skill(0)
	scene.ui.combat.use_skill(0)
	check(scene.ui.combat.rules.round == 1 and scene.ui.combat.busy, "Input is gated while a visual trial turn animates")
	await create_timer(0.65).timeout
	check(scene.ui.combat.lightning_visual > 0, "Lightning is a live timed effect during the turn")
	await create_timer(0.95).timeout
	scene.ui.combat.use_skill(2)
	await create_timer(1.6).timeout
	scene.ui.combat.use_skill(0)
	await create_timer(2.1).timeout
	check(scene.ui.combat.rules.won and scene.ui.combat.result_shown, "Visual trial completes and displays a result")
	check(scene.state.recovery_status == "active", "Visual trial also leaves recovery awaiting separate confirmation")
	scene.ui.close_modal()
	scene.state.qi = 4
	var cultivation_before = scene.state.cultivation
	scene.ui.open_battle()
	find_button(scene.ui.modal, "演示补给").pressed.emit()
	check(scene.state.qi == 15 and scene.state.cultivation == cultivation_before and scene.state.recovery_status == "active", "Low-resource legacy saves can practice without resetting care progress")
	scene.ui.close_modal()
	scene.ui.start_boss(false)
	check(scene.ui.combat.dragon_frames.size() == 4 and scene.state.boss_attempts == 1, "Boss scene has four real state sprites and records entry")
	scene.ui.combat.use_skill(0)
	check(scene.ui.combat.rules.boss_hp == 1344 and scene.ui.combat.cast_visual > 0, "Attack button deals damage and triggers a visible slash")
	var town_position = scene.player.position
	var hero_position = scene.ui.combat.hero.position
	Input.action_press("move_forward")
	await create_timer(0.18).timeout
	Input.action_release("move_forward")
	check(scene.ui.combat.hero.position.distance_to(hero_position) > 15 and scene.player.position.distance_to(town_position) < 1, "WASD moves the battle character while town character stays blocked")
	scene.ui.combat.rules.phase = "windup"
	scene.ui.combat.rules.phase_clock = 1.0
	scene.ui.combat.rules.target_position = scene.ui.combat.hero.position
	await create_timer(0.22).timeout
	check(scene.ui.combat.rules.hp == 220 and scene.ui.combat.rules.phase == "breath", "The rendered boss actually attacks and damages the player")
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
		if is_instance_valid(scene.ui.campaign):
			scene.ui.campaign.request_exit()
			await process_frame
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
	print("GAMEPLAY TEST RESULT: ", "PASS" if errors == 0 else "FAIL", " (", passed, " passed, ", errors, " failures)")
	quit(errors)
