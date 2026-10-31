extends SceneTree
const State = preload("res://scripts/game_state.gd")
const Catalogue = preload("res://scripts/trial_catalogue.gd")
const Rules = preload("res://scripts/boss_rules.gd")
var errors = 0
var passed = 0

func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS: ", message)
	else:
		errors += 1
		push_error(message)

func fresh():
	var state = State.new()
	state.persist_enabled = false
	return state

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var rows = Catalogue.all()
	check(rows.size() == 20, "The corridor contains twenty Bosses total")
	var ids = {}
	var backgrounds = {}
	for row in rows:
		ids[row.id] = true
		backgrounds[row.background] = true
		check(ResourceLoader.exists(row.scene) and ResourceLoader.exists(row.background) and Catalogue.boss_texture(row.id) != null, "Arena and downloaded pixel art exist: " + row.id)
	check(ids.size() == 20 and backgrounds.size() == 7, "Twenty unique encounters use the seven regional base artworks")
	# Behavioral boundaries for difficulty-scaled telegraphs and elliptical attacks.
	var warning_center = Vector2(640, 560)
	var easy = Rules.new(fresh(), 0, 10)
	easy.phase = "windup"
	easy.target_position = warning_center
	easy.step(0.5, warning_center + Vector2(110, 0))
	check(easy.phase == "windup" and easy.hp == easy.max_hp, "Low-tier attacks retain a readable warning before impact")
	var easy_impact = easy.step(0.36, warning_center + Vector2(110, 0))
	check(easy_impact.get("event") == "hurt", "Low-tier attacks land sooner than the old 1.1-second tell and reach beyond the old radius")
	var hard = Rules.new(fresh(), 0, 100)
	hard.phase = "windup"
	hard.target_position = warning_center
	check(hard.step(0.46, warning_center + Vector2(210, 0)).get("event") == "hurt", "High-tier attacks strike sooner and reach substantially farther")
	var outside = Rules.new(fresh(), 0, 100)
	outside.phase = "windup"
	outside.target_position = warning_center
	check(outside.step(0.46, warning_center + Vector2(235, 0)).get("event") == "evaded", "Moving beyond the enlarged horizontal boundary remains safe")
	var vertical = Rules.new(fresh(), 0, 100)
	vertical.phase = "windup"
	vertical.target_position = warning_center
	check(vertical.step(0.46, warning_center + Vector2(0, 140)).get("event") == "hurt", "High-tier attacks also enlarge their vertical reach")
	var diagonal = Rules.new(fresh(), 0, 100)
	diagonal.phase = "windup"
	diagonal.target_position = warning_center
	check(diagonal.step(0.46, warning_center + Vector2(175, 115)).get("event") == "evaded", "The attack uses an ellipse rather than its enclosing rectangle")
	var evader = Rules.new(fresh(), 0, 100)
	evader.phase = "windup"
	evader.target_position = warning_center
	evader.step(0.3, warning_center)
	evader.dodge()
	check(evader.step(0.16, warning_center).get("event") == "evaded", "A correctly timed cloud step still avoids a fast high-tier impact")
	var monotonic = true
	var previous_windup = 10.0
	var previous_radius = Vector2.ZERO
	for row in rows:
		var tuned = Rules.new(fresh(), 0, row.tier, "attack", false, row)
		monotonic = monotonic and tuned.windup_duration <= previous_windup and tuned.attack_radius.x >= previous_radius.x and tuned.attack_radius.y >= previous_radius.y
		previous_windup = tuned.windup_duration
		previous_radius = tuned.attack_radius
	check(monotonic, "All twenty Bosses consistently gain speed and reach with difficulty")
	var state = fresh()
	check(not state.begin_named_boss("unknown").ok and state.boss_attempts == 0, "Invalid Boss identifiers do not consume an attempt")
	check(state.begin_named_boss("b19").ok and state.selected_boss_id == "b19", "All twenty doors can be selected without an attribute lock")
	check(not state.complete_boss("unknown"), "Unknown Bosses cannot create phantom clears")
	var hero_stats = state.health_attributes.duplicate(true)
	for id in ["b00", "b01"]:
		var data = Catalogue.entry(id)
		var combat = Rules.new(state, 0, data.tier, "attack", false, data)
		while not combat.finished:
			combat.step(0.61, Vector2(100, 450))
			combat.attack(combat.boss_position - Vector2(100, 0))
		check(combat.won and state.boss_cleared(id), "Defeating the actual named enemy stores its own clear: " + id)
	check(state.cleared_bosses.size() == 2 and state.heal_unlocked(), "Two distinct named Boss clears unlock recovery")
	check(state.health_attributes == hero_stats, "Boss progress does not consume health attributes")
	check(not state.complete_boss("b00") and state.cleared_bosses.size() == 2, "Repeated clears are idempotent")
	state.complete_boss("b00", {"time": 1.0, "damage_taken": 0, "hits": 0})
	state.complete_boss("b00", {"time": 3.0, "damage_taken": 80, "hits": 1})
	check(state.boss_records.b00.time == 1.0, "Named encounters retain the faster record")
	var defeated = Rules.new(fresh(), 0, 10, "attack", false, Catalogue.entry("b02"))
	defeated.receive_damage(99999)
	check(defeated.state.cleared_bosses.is_empty(), "Defeat does not grant a named clear")
	var file_path = "user://corridor-save-test-" + str(OS.get_process_id()) + ".json"
	state.persist_enabled = true
	state.save_file_override = file_path
	state.save_game()
	var loaded = State.new()
	loaded.save_file_override = file_path
	loaded.load_game()
	check(loaded.cleared_bosses.size() == 2 and loaded.boss_records.b00.time == 1.0 and loaded.selected_boss_id == "b19", "Named clears, records and selection survive save/load")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	var legacy_file = FileAccess.open(file_path, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify({"schema": 3, "cultivation": 137, "cleared_stages": ["attack_10", "attack_20"], "best_records": {"attack_10": {"time": 12.0}}}))
	legacy_file.close()
	loaded = State.new()
	loaded.save_file_override = file_path
	loaded.load_game()
	check(loaded.cultivation == 137 and loaded.heal_unlocked() and loaded.cleared_bosses.is_empty(), "Schema-three migration preserves earned growth and skill unlocks")
	check(FileAccess.file_exists(file_path.trim_suffix(".json") + "-before-corridor-v4.json"), "Migration backs up the old save before conversion")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path.trim_suffix(".json") + "-before-corridor-v4.json"))
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.state = fresh()
	scene.state.apply_health_profile(scene.state.HealthProfile.mock(40, 1))
	scene.ui.refresh()
	scene.ui.open_boss()
	await process_frame
	check(is_instance_valid(scene.ui.corridor) and scene.ui.modal_open and scene.player.blocked, "The village trial entrance opens the real corridor and blocks village movement")
	check(scene.ui.corridor.portal_buttons.size() == 20 and scene.ui.corridor.jump_buttons.size() == 20, "Every Boss has an interactive portal and a navigation shortcut")
	var hall_position: Vector2 = scene.ui.corridor.player_position
	var town_position: Vector2 = scene.player.position
	Input.action_press("move_right")
	await create_timer(0.18).timeout
	Input.action_release("move_right")
	check(scene.ui.corridor.player_position.x > hall_position.x + 20 and scene.player.position.distance_to(town_position) < 1, "Hall movement controls a separate pixel avatar")
	scene.ui.corridor.focus_boss(13)
	await process_frame
	check(scene.ui.corridor.camera_x > 1000, "Region navigation traverses a genuinely long camera-scrolling corridor")
	var resume_position: Vector2 = scene.ui.corridor.player_position
	var resume_camera: float = scene.ui.corridor.camera_x
	scene.ui.corridor.portal_buttons[13].pressed.emit()
	await process_frame
	check(scene.ui.combat.boss_id == "b13" and scene.ui.combat.scene_file_path == Catalogue.scene_path("b13"), "Clicking a portal loads that Boss's dedicated scene")
	check(scene.ui.combat.encounter.background.ends_with("map_water.png") and scene.ui.combat.top_label.text.contains("沉砂"), "The selected arena uses the right map and Boss name")
	scene.ui.combat.use_skill(0)
	check(scene.ui.combat.rules.boss_hp < scene.ui.combat.rules.boss_max_hp, "The existing four-skill combat damages the newly loaded enemy")
	scene.ui.combat.leave_battle()
	await process_frame
	check(scene.ui.corridor.player_position.distance_to(resume_position) < 1 and absf(scene.ui.corridor.camera_x - resume_camera) < 1, "Returning from combat restores hall position and camera")
	for row in rows:
		scene.ui.corridor.focus_boss(row.index)
		scene.ui.corridor.portal_buttons[row.index].pressed.emit()
		await process_frame
		check(scene.ui.combat.boss_id == row.id and scene.ui.combat.dragon.texture != null and scene.ui.combat.encounter.arena == row.arena, "Actual portal-to-arena handoff: " + row.id)
		scene.ui.combat.leave_battle()
		await process_frame
	scene.ui.corridor.focus_boss(0)
	await process_frame
	var key = InputEventKey.new()
	key.keycode = KEY_E
	key.physical_keycode = KEY_E
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	check(is_instance_valid(scene.ui.combat) and scene.ui.combat.boss_id == "b00", "The actual E key enters the nearest portal")
	if is_instance_valid(scene.ui.combat):
		scene.ui.combat.rules.boss_hp = 1
		scene.ui.combat.hero.position = scene.ui.combat.rules.boss_position - Vector2(100, 0)
		scene.ui.combat.basic_attack()
		check(scene.ui.combat.result_shown and scene.state.boss_cleared("b00"), "Actual victory UI records the named Boss clear")
		scene.ui.combat.leave_battle()
		await process_frame
		check(scene.ui.corridor.status_labels[0].text.contains("已通关"), "The returned corridor shows the saved clear marker")
		var portal_rect: Rect2 = scene.ui.corridor.portal_buttons[0].get_global_rect()
		var mouse = InputEventMouseMotion.new()
		mouse.position = portal_rect.get_center()
		mouse.global_position = mouse.position
		root.push_input(mouse, true)
		var click = InputEventMouseButton.new()
		click.position = portal_rect.get_center()
		click.global_position = click.position
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		root.push_input(click, true)
		click = click.duplicate()
		click.pressed = false
		root.push_input(click, true)
		await process_frame
		check(is_instance_valid(scene.ui.combat) and scene.ui.combat.boss_id == "b00", "A real viewport mouse click enters the portal under the pointer")

	scene.ui.close_modal()
	await process_frame
	check(not scene.player.blocked and not scene.ui.modal_open and not is_instance_valid(scene.ui.corridor), "Leaving the corridor restores the original village controls")
	scene.queue_free()
	await process_frame
	print("CORRIDOR RESULT: ", "PASS" if errors == 0 else "FAIL", " (", passed, " passed, ", errors, " failures)")
	quit(errors)
