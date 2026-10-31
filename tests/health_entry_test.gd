extends SceneTree
const State = preload("res://scripts/game_state.gd")
const Baseline = preload("res://scripts/health_baseline.gd")
const Boss = preload("res://scripts/boss_rules.gd")
const REPORT_FIXTURE = "res://health-entry/样本体检报告.png"
const REPORT_FIXTURES = [REPORT_FIXTURE, "res://health-entry/手写既往病史记录.png", "res://health-entry/四款药品包装展示.png"]
var fixture_url = "http://127.0.0.1:" + (OS.get_environment("XIUXIAN_HEALTH_TEST_PORT") if OS.has_environment("XIUXIAN_HEALTH_TEST_PORT") else "8001")
var passed = 0
var errors = 0

func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS: ", message)
	else:
		errors += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func wait_idle(panel) -> void:
	var deadline = Time.get_ticks_msec() + 10000
	while is_instance_valid(panel) and (panel.busy or panel.probe.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED) and Time.get_ticks_msec() < deadline:
		await process_frame
	await process_frame

func fill_profile(panel, display_name: String) -> void:
	panel.name_input.text = display_name
	panel.age_input.text = "68"
	panel.sex_input.select(1)
	panel.relation_input.text = "父亲"
	panel.input_changed()

func exposes_notes(panel) -> bool:
	for node in panel.result_box.find_children("*", "Label", true, false):
		if node.text.contains("计算依据"):
			return true
		for note in panel.draft.get("attribute_notes", {}).values():
			if not str(note).is_empty() and node.text.contains(str(note)):
				return true
	return false

func run() -> void:
	var sample = JSON.parse_string(FileAccess.get_file_as_string("res://health-entry/sample-baseline.json"))
	sample.recognition_mode = "sample"
	var state = State.new()
	state.persist_enabled = false
	state.complete_boss("b00", {"time": 10})
	state.complete_boss("b01", {"time": 15})
	check(state.apply_health_baseline(sample).ok, "Confirmed interface baseline is accepted")
	var stats = state.battle_stats()
	check(stats.max_hp == 80 and stats.attack == 50 and stats.max_mp == 48 and stats.max_stamina == 50, "Interface units are used directly, with the new HP cap and no double scaling")
	check(state.heal_unlocked() and state.boss_records.b00.time == 10, "Health initialization preserves earned Boss progress")
	check(not state.apply_health_profile(state.HealthProfile.mock(60, 2)).ok, "Locked report baseline rejects manual simulated edits")
	check(not state.apply_health_baseline(sample).ok, "Repeated baseline cannot overwrite the same record")
	var invalid = sample.duplicate(true)
	invalid.baseline_id = "bad"
	invalid.character_state.attack = true
	var before = state.health_snapshot()
	check(not state.apply_health_baseline(invalid).ok and state.health_snapshot() == before, "Malformed baseline is rejected atomically")
	invalid = sample.duplicate(true)
	invalid.character_state.hp_current = 0
	check(not Baseline.validate(invalid).ok, "Initialization requires full life")
	invalid = sample.duplicate(true)
	invalid.source_document = {"person": "private"}
	invalid.data_url = "private-image"
	check(not Baseline.validate(invalid).baseline.has("source_document") and not Baseline.validate(invalid).baseline.has("data_url"), "Report contents are excluded from normalized save data")
	var battle = Boss.new(state)
	battle.receive_damage(20)
	check(state.health_snapshot() == before, "Battle damage cannot change the health baseline")
	state.persist_enabled = true
	state.save_file_override = "user://health-entry-test-" + str(OS.get_process_id()) + ".json"
	check(state.save_game(), "Baseline save reports successful disk write")
	var loaded = State.new()
	loaded.save_file_override = state.save_file_override
	loaded.load_game()
	check(loaded.health_baseline == state.health_baseline and loaded.battle_stats().max_hp == 80 and loaded.heal_unlocked(), "Interface baseline, direct HP and Boss progress survive reload")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state.save_file_override))
	var legacy = State.new()
	legacy.apply_health_profile(legacy.HealthProfile.mock(45, 1))
	legacy.complete_boss("b04", {"time": 8})
	legacy.save_file_override = state.save_file_override
	legacy.save_game()
	var old_data = JSON.parse_string(FileAccess.get_file_as_string(legacy.save_file_override))
	old_data.schema = 4
	old_data.erase("health_baseline")
	var f = FileAccess.open(legacy.save_file_override, FileAccess.WRITE)
	f.store_string(JSON.stringify(old_data))
	f.close()
	loaded = State.new()
	loaded.save_file_override = legacy.save_file_override
	loaded.load_game()
	check(loaded.health_attributes.attack == 45 and loaded.boss_cleared("b04") and loaded.health_baseline.is_empty(), "Existing schema 4 profiles migrate without losing attributes or Bosses")
	var backup = state.save_file_override.trim_suffix(".json") + "-before-health-v5.json"
	check(FileAccess.file_exists(backup), "Existing save is backed up before health schema migration")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(backup))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(state.save_file_override))
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.state = State.new()
	scene.state.persist_enabled = false
	scene.state.apply_health_profile(scene.state.HealthProfile.mock(40, 1))
	scene.state.profile_created = true
	scene.ui.open_health_entry()
	check(is_instance_valid(scene.ui.health_entry) and not is_instance_valid(scene.ui.start_screen) and scene.player.blocked, "Selected character can open delegated state creation without the avatar menu")
	var panel = scene.ui.health_entry
	var original = scene.state.health_snapshot()
	check(panel.name_input.text.is_empty() and panel.age_input.text.is_empty() and panel.relation_input.text.is_empty() and panel.sex_input.selected == 0, "Required profile starts blank, including name, age, sex and relation")
	check(panel.preview.texture == null and panel.report_placeholder.visible, "Report area shows a neutral upload placeholder instead of an avatar")
	var has_demo_prompt = false
	for child in panel.find_children("*", "Control", true, false):
		if child is Label or child is Button:
			if child.text.contains("示例") or child.text.contains("样例"):
				has_demo_prompt = true
	check(not has_demo_prompt, "Player entry contains no sample or offline-demo buttons or prompts")
	panel.select_file(ProjectSettings.globalize_path(REPORT_FIXTURE))
	check(not panel.chosen_path.is_empty() and panel.analyze_button.disabled and panel.draft.is_empty(), "Selecting a report requires analysis and consent instead of prefilled sample stats")
	check(panel.preview.texture != null and not panel.report_placeholder.visible, "Only a selected report creates an image preview")
	panel.clear_files()
	check(panel.preview.texture == null and panel.report_placeholder.visible, "Clearing reports restores the neutral placeholder")
	scene.ui.close_modal()
	check(scene.state.health_snapshot() == original, "Cancelling onboarding leaves current attributes unchanged")
	await process_frame
	scene.ui.open_health_entry()
	panel = scene.ui.health_entry
	panel.service_url = fixture_url
	panel.connect_service()
	await wait_idle(panel)
	check(panel.configured and panel.service_verified and panel.model_name == "test-fixture", "Native HTTP client verifies local service identity (fixture, not real model)")
	var fixture_paths = PackedStringArray()
	for path in REPORT_FIXTURES:
		fixture_paths.append(ProjectSettings.globalize_path(path))
	panel.select_files(fixture_paths)
	check(panel.chosen_paths.size() == 3, "File selection still supports multiple reports without a sample shortcut")
	panel.consent.button_pressed = true
	panel.analyze()
	check(not panel.busy and panel.draft.is_empty() and panel.analyze_button.disabled, "Missing mandatory fields cannot send an analysis request")
	fill_profile(panel, "新姓名")
	for key in ["age", "sex", "relation"]:
		if key == "age":
			panel.age_input.text = ""
		elif key == "sex":
			panel.sex_input.select(0)
		else:
			panel.relation_input.text = ""
		panel.input_changed()
		check(panel.analyze_button.disabled, "Every required field independently blocks submission: " + key)
		fill_profile(panel, "新姓名")
	panel.age_input.text = "0"
	panel.input_changed()
	check(panel.analyze_button.disabled, "Invalid ages cannot enable analysis")
	fill_profile(panel, "新姓名")
	panel.consent.button_pressed = true
	panel.analyze_button.pressed.emit()
	await wait_idle(panel)
	check(not panel.draft.is_empty() and panel.draft.recognition_mode == "live" and scene.state.health_snapshot() == original, "HTTP extraction preview remains a draft until explicit confirmation")
	if not panel.draft.is_empty():
		check(not exposes_notes(panel), "Analysis preview shows final stats without attribute formulas or source calculations")
		var hp = panel.draft.character_state.hp_max
		panel.confirm_button.pressed.emit()
		await wait_idle(panel)
		check(scene.state.health_baseline.get("rules_revision") == "1f356a0" and scene.state.health_baseline.get("model") == "test-fixture" and scene.state.battle_stats().max_hp == hp and scene.state.player_name == "新姓名", "Confirm button obtains authoritative baseline and initializes game state")
		check(not is_instance_valid(scene.ui.health_entry) and not scene.player.blocked, "Successful confirmation returns control to the pixel village")
	# Verify a real text-only HTTP request and a subsequent edit invalidating its draft.
	scene.ui.open_health_entry()
	panel = scene.ui.health_entry
	panel.service_url = fixture_url
	panel.connect_service()
	await wait_idle(panel)
	fill_profile(panel, "文字姓名")
	panel.history_input.text = "高血压10年"
	panel.medication_input.text = "氨氯地平"
	panel.configured = false
	panel.consent.button_pressed = true
	check(not panel.analyze_button.disabled, "Text-only submissions work without a model key")
	panel.analyze_button.pressed.emit()
	await wait_idle(panel)
	check(panel.draft.get("recognition_mode") == "text" and panel.draft.character_state.spirit == 48 and panel.draft.has("attribute_notes") and not panel.draft.has("five_elements"), "Text mode follows current body-system rules and keeps calculation notes")
	panel.history_input.text = "已修改病史"
	panel.confirm_draft()
	check(panel.draft.is_empty() and panel.confirm_button.disabled, "Editing submitted inputs invalidates the old preview")
	panel.history_input.text = "高血压10年"
	panel.analyze_button.pressed.emit()
	await wait_idle(panel)
	panel.confirm_button.pressed.emit()
	await wait_idle(panel)
	check(scene.state.health_baseline.get("recognition_mode") == "text" and not scene.state.health_simulated and scene.state.player_name == "文字姓名", "Confirmed text record is saved as text, never as model recognition or an offline demo")
	check(scene.ui.hud_name_label.text == "文字姓名" and scene.player_name_label.text == "文字姓名", "Confirmed display name updates both portrait HUD and world label")
	scene.ui.open_home()
	var notes_button = false
	for node in scene.ui.modal.find_children("*", "Button", true, false):
		notes_button = notes_button or node.text.contains("依据")
	check(not notes_button, "Confirmed profile exposes no calculation-detail entry point")
	# A failed request must not overwrite an existing baseline.
	scene.ui.open_health_entry()
	panel = scene.ui.health_entry
	panel.service_url = fixture_url
	before = scene.state.health_snapshot()
	panel.phase = "parse"
	panel.busy = true
	panel.work_completed(HTTPRequest.RESULT_SUCCESS, 502, PackedStringArray(), JSON.stringify({"message": "fixture failure"}).to_utf8_buffer())
	check(scene.state.health_snapshot() == before and panel.draft.is_empty(), "Model errors keep the existing confirmed baseline intact")
	scene.ui.close_modal()
	scene.queue_free()
	await process_frame
	print("HEALTH ENTRY RESULT: ", "PASS" if errors == 0 else "FAIL", " (", passed, " passed, ", errors, " failures)")
	quit(errors)
