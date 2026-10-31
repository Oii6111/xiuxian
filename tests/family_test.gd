extends SceneTree
const State = preload("res://scripts/game_state.gd")
const Roster = preload("res://scripts/family_roster.gd")
var passed = 0
var failed = 0

func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS: ", message)
	else:
		failed += 1
		push_error(message)

func person(mother: bool = false) -> Dictionary:
	return {"name": "李秀兰" if mother else "张建国", "relation": "母亲" if mother else "父亲", "age": 65 if mother else 68, "sex": "女" if mother else "男", "title": "云霞仙子" if mother else "青松真人", "avatar": "female" if mother else "male", "mode": "family", "consent": true}

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var family = Roster.new()
	family.persist_enabled = false
	var invalid = person()
	invalid.consent = false
	check(not family.add_member(invalid).ok and family.members.is_empty(), "Delegated entry requires family consent before occupying a slot")
	invalid = person()
	invalid.age = 0
	check(not family.add_member(invalid).ok, "Invalid basic information cannot create an elder")
	var father = family.add_member(person())
	check(father.ok and family.members.size() == 1, "A child account can add the first elder")
	check(not family.add_member(person()).ok and family.members.size() == 1, "An existing elder is selected instead of duplicating their profile")
	var mother = family.add_member(person(true))
	check(mother.ok and family.members.size() == 2 and father.id != mother.id, "A second elder receives an independent identity")
	check(not family.add_member(person()).ok and family.members.size() == 2, "The two-elder limit is enforced in the data layer")
	var a = family.state_for(father.id)
	var b = family.state_for(mother.id)
	check(a != b and a.equipment.qi == 0 and b.equipment.qi == 0 and a.cultivation == 0 and b.days == 0, "New elders start with separate empty growth and wish wallets")
	a.apply_health_profile(a.HealthProfile.mock(40, 1))
	b.apply_health_profile(b.HealthProfile.mock(20, 1))
	check(a.equipment.initial_score == 40 and b.equipment.initial_score == 20, "Each elder freezes their own initial draw support")
	check(a.record_task("planned_record", true).rewarded and a.equipment.qi == 100 and b.equipment.qi == 0, "Father's daily habit rewards only his wallet")
	check(b.record_task("planned_record", true).rewarded and b.equipment.qi == 100, "Mother can earn her own reward on the same day")
	check(not a.record_task("planned_record", true).ok and a.equipment.qi == 100, "Switching elders does not reset daily duplicate protection")
	var pull_a = a.draw_equipment(1, "same-local-request")
	check(pull_a.ok and a.equipment.qi == 30 and b.equipment.qi == 100 and b.equipment.inventory.is_empty(), "Drawing equipment affects only the selected elder")
	check(not b.equip_item(pull_a.items[0].id).ok, "An elder cannot equip another elder's item")
	var pull_b = b.draw_equipment(1, "same-local-request")
	check(pull_b.ok and b.equipment.qi == 30 and b.equipment.inventory.size() == 1, "Identical request IDs are scoped to the owning elder")
	a.equip_item(pull_a.items[0].id)
	a.complete_boss("b00", {"time": 20})
	a.complete_boss("b01", {"time": 22})
	check(a.heal_unlocked() and not b.heal_unlocked() and b.cleared_bosses.is_empty(), "Boss clears, records and skill unlocks stay with the correct elder")
	var original_support = a.equipment.initial_score
	var renamed = person()
	renamed.title = "松风剑客"
	check(family.update_member(father.id, renamed).ok and a.player_name == "松风剑客" and a.family_identity.name == "张建国", "Real display name and cultivation title are independent")
	check(a.equipment.initial_score == original_support and a.equipment.inventory.size() == 1, "Editing identity never resets draw support or equipment")
	check(family.select_member(father.id).ok and family.active_state() == a, "Selecting an elder returns their entire state")
	check(not family.select_member("missing").ok and family.active_state() == a, "Invalid selection keeps the current elder")
	# One account file commits both members and the current selection.
	var fixture = "res://output/family-test-%d.json" % OS.get_process_id()
	family.persist_enabled = true
	family.save_file_override = fixture
	a.persist_enabled = true
	b.persist_enabled = true
	check(a.save_game(), "A member's normal save delegates to the complete family save")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(fixture))
	check(saved.schema == 8 and saved.has("owner") and saved.members.size() == 2 and not saved.has("health_drafts"), "Family schema saves two members without raw report drafts")
	var restored = Roster.new()
	restored.save_file_override = fixture
	restored.load_game(State.new())
	check(restored.members.size() == 2 and restored.active_id == father.id, "Restart restores both elders and the last selected one")
	check(typeof(restored.identity_for(father.id).age) == TYPE_INT, "Reloaded family ages remain valid integer form values")
	check(restored.state_for(father.id).equipment.qi == 30 and restored.state_for(mother.id).equipment.qi == 30, "Both independent wallets survive restart")
	check(restored.state_for(father.id).heal_unlocked() and not restored.state_for(mother.id).heal_unlocked(), "Restart preserves separate progression")
	check(restored.state_for(father.id).draw_equipment(1, "same-local-request").items == pull_a.items and restored.state_for(father.id).equipment.qi == 30, "A restarted member keeps their own idempotent draw receipt")
	var broken_path = "res://output/missing-family-test-directory/save.json"
	restored.save_file_override = broken_path
	check(not restored.select_member(mother.id).ok and restored.active_id == father.id, "Failed selection saving keeps the old active elder")
	var before_identity = restored.state_for(father.id).family_identity.duplicate(true)
	check(not restored.update_member(father.id, person()).ok and restored.state_for(father.id).family_identity == before_identity, "Failed metadata saving rolls back name, title and identity")
	var unable = Roster.new()
	unable.save_file_override = broken_path
	check(not unable.add_member(person()).ok and unable.members.is_empty() and unable.active_id == "self", "Failed creation neither consumes a slot nor changes selection")
	# Legacy migration preserves the existing equipment-rich character in slot one.
	var legacy = State.new()
	legacy.persist_enabled = false
	legacy.apply_health_profile(legacy.HealthProfile.mock(35, 1))
	legacy.equipment.qi = 700
	legacy.draw_equipment(10, "legacy-pull")
	legacy.equip_item(legacy.equipment.inventory[0].id)
	legacy.complete_boss("b04", {"time": 8})
	var file = FileAccess.open(fixture, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy.to_data()))
	file.close()
	var migrated = Roster.new()
	migrated.save_file_override = fixture
	migrated.load_game(State.new())
	check(migrated.members.is_empty() and migrated.active_state().boss_cleared("b04"), "The old player migrates into self without taking an elder slot")
	check(migrated.active_state().equipment == legacy.equipment and FileAccess.file_exists(fixture.trim_suffix(".json") + "-before-accounts-v8.json"), "Migration preserves equipped gear, receipts and a complete original backup")
	var added = migrated.add_member(person(true))
	check(added.ok and migrated.state_for(added.id).equipment.inventory.is_empty(), "Adding an elder does not copy the owner equipment")
	# UI: real two-slot panel, delegated form, avatar/name refresh and busy-state guards.
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.family.persist_enabled = false
	game.ui.open_family()
	check(is_instance_valid(game.ui.family_panel) and game.player.blocked, "The family selector is a real modal from the map")
	var panel = game.ui.family_panel
	panel.show_form("")
	panel.name_input.text = "张建国"
	panel.age_input.text = "68"
	panel.sex_input.select(1)
	panel.relation_input.text = "父亲"
	panel.title_input.text = "青松真人"
	panel.consent_input.button_pressed = true
	panel.save_form()
	await process_frame
	check(game.family.members.size() == 1 and is_instance_valid(game.ui.health_entry), "Saving the actual add-family form opens delegated health entry")
	var father_id = game.family.active_id
	var health = game.ui.health_entry
	check(health.name_input.text == "张建国" and health.age_input.text == "68" and health.relation_input.text == "父亲" and health.sex_input.selected == 1, "Delegated health entry pre-fills the selected elder's basic information")
	health.history_input.text = "父亲资料草稿"
	game.ui.close_modal()
	var keeps_medical_cache = false
	for property in game.family.get_property_list():
		keeps_medical_cache = keeps_medical_cache or property.name == "health_drafts"
	check(not keeps_medical_cache, "Family Store contains no shared medical draft cache")
	var mother_added = game.family.add_member(person(true))
	check(game.ui.activate_family(mother_added.id, true), "The second elder can be selected for delegated entry")
	await process_frame
	health = game.ui.health_entry
	check(health.name_input.text == "李秀兰" and health.history_input.text.is_empty() and game.state.avatar_id == "female", "Mother's entry and avatar do not inherit father's report draft")
	health.busy = true
	check(not game.ui.activate_family(father_id) and game.state.family_member_id == mother_added.id, "An active analysis blocks elder switching")
	health.busy = false
	game.ui.close_modal()
	game.ui.activate_family(father_id, true)
	await process_frame
	check(game.ui.health_entry.history_input.text.is_empty() and game.player_name_label.text == "青松真人", "Returning restores only father's basic identity and cultivation title")
	var stale_panel = game.ui.health_entry
	var mother_state = game.family.state_for(mother_added.id)
	var father_state = game.state
	var mother_before = mother_state.health_snapshot()
	game.state = mother_state
	var sample = JSON.parse_string(FileAccess.get_file_as_string("res://health-entry/sample-baseline.json"))
	sample.recognition_mode = "sample"
	stale_panel.commit(sample)
	check(mother_state.health_snapshot() == mother_before and father_state.health_baseline.is_empty(), "A late response cannot commit into either elder after context changes")
	game.state = father_state
	var before_withdrawal = father_state.health_snapshot()
	stale_panel.consent.button_pressed = false
	stale_panel.commit(sample)
	check(father_state.health_snapshot() == before_withdrawal, "Withdrawing the current consent blocks delegated confirmation")
	stale_panel.consent.button_pressed = true
	sample.baseline_id = "family-confirmed-father"
	sample.display_name = "张建国"
	stale_panel.commit(sample)
	check(father_state.family_identity.name == "张建国" and father_state.player_name == "青松真人" and not father_state.health_baseline.is_empty(), "Confirming delegated health data preserves the separate cultivation title")
	check(mother_state.health_baseline.is_empty() and not father_state.health_baseline.has("attribute_notes"), "Confirmation applies only the owning elder's sanitized game projection")
	game.ui.open_health_entry()
	var failed_panel = game.ui.health_entry
	var old_snapshot = father_state.health_snapshot()
	var saved_path = game.family.save_file_override
	game.family.persist_enabled = true
	game.family.save_file_override = broken_path
	father_state.persist_enabled = true
	failed_panel.name_input.text = "新显示名"
	failed_panel.consent.button_pressed = true
	sample.baseline_id = "family-failed-father"
	sample.display_name = "新显示名"
	failed_panel.commit(sample)
	check(father_state.health_snapshot() == old_snapshot, "A failed delegated confirmation rolls back both health attributes and family identity")
	game.family.persist_enabled = false
	game.family.save_file_override = saved_path
	father_state.persist_enabled = false
	game.ui.close_modal()
	father_state.apply_health_profile(father_state.HealthProfile.mock(40, 1))
	mother_state.apply_health_profile(mother_state.HealthProfile.mock(20, 1))
	game.ui.start_battle()
	check(not game.ui.activate_family(mother_added.id) and game.state == father_state, "An active battle blocks switching to another elder")
	game.ui.close_modal()
	game.ui.activate_family(mother_added.id)
	check(game.state == mother_state and game.ui.hud_name_label.text == "云霞仙子" and game.walk_textures == game.avatar_frames.female, "Selecting mother refreshes HUD, playable sprite and the complete state")
	game.ui.open_treasure()
	check(game.ui.treasure.last_receipt().is_empty() and game.state.equipment.qi == 0, "Mother's pavilion starts with her own empty wallet and results")
	game.ui.close_modal()
	mother_state.equipment.qi = 700
	game.ui.open_treasure()
	game.ui.treasure.summon(10)
	check(game.ui.treasure.busy and mother_state.equipment.inventory.size() == 10, "Mother's ten-pull is committed before its reveal finishes")
	game.ui.open_family()
	check(is_instance_valid(game.ui.family_panel) and not is_instance_valid(game.ui.treasure) and mother_state.equipment.qi == 0, "Opening family selection can finish a committed reveal without another debit")
	game.ui.activate_family(father_id)
	check(father_state.equipment.inventory.is_empty() and mother_state.equipment.inventory.size() == 10, "Switching after a reveal leaves all ten items with the drawing elder")
	game.ui.activate_family(mother_added.id)
	game.ui.open_treasure()
	check(game.ui.treasure.result_cards.size() == 10, "Returning to an elder restores her own last ten-pull results")
	game.ui.close_modal()
	game.queue_free()
	await process_frame
	var malformed = FileAccess.open(fixture, FileAccess.WRITE)
	malformed.store_string('{"schema":7,"members":[{}, {}, {}]}')
	malformed.close()
	var protected_roster = Roster.new()
	protected_roster.save_file_override = fixture
	protected_roster.load_game(State.new())
	var damaged_before = FileAccess.get_file_as_string(fixture)
	check(protected_roster.load_blocked and not protected_roster.add_member(person()).ok and FileAccess.get_file_as_string(fixture) == damaged_before, "A malformed family save cannot be overwritten by a fresh roster")
	protected_roster.dispose()
	for roster in [family, restored, unable, migrated]:
		roster.dispose()
	for path in [fixture, fixture.trim_suffix(".json") + "-before-accounts-v8.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("FAMILY TESTS: ", passed, " passed, ", failed, " failed")
	quit(0 if failed == 0 else 1)
