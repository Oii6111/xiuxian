extends SceneTree
const State = preload("res://scripts/game_state.gd")
const Roster = preload("res://scripts/family_roster.gd")
const Equipment = preload("res://scripts/equipment_rules.gd")
const Account = preload("res://scripts/net/backend_session.gd")
var passed = 0
var failed = 0

func check(value: bool, message: String) -> void:
	if value:
		passed += 1
		print("PASS: ", message)
	else:
		failed += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func write_fixture(path: String, data: Dictionary) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

func run() -> void:
	var midnight = int(Time.get_unix_time_from_datetime_string("2026-10-31T15:59:59"))
	check(State.reward_day(midnight) == "2026-10-31" and State.reward_day(midnight + 2) == "2026-11-01", "Beijing natural reward day changes at midnight independent of host timezone")
	var state = State.new()
	state.persist_enabled = true
	state.family_save = func(): return false
	var before = state.health_snapshot()
	check(not state.save_health_profile(state.HealthProfile.mock(60, 1)).ok and state.health_snapshot() == before, "Failed profile persistence restores attributes and frozen draw support")
	state.family_save = Callable()
	state.persist_enabled = false
	check(state.save_health_profile(state.HealthProfile.mock(60, 1)).ok, "Successful profile import preserves the existing game path")
	state.equipment.qi = 700
	state.draw_equipment(10, "valid")
	var broken_equipment = state.equipment.duplicate(true)
	broken_equipment.receipts["missing-items"] = {"count": 1}
	broken_equipment.receipts["duplicates"] = {"count": 10, "items": []}
	for i in range(10):
		broken_equipment.receipts.duplicates.items.append(broken_equipment.inventory[0])
	var cleaned = Equipment.normalize(broken_equipment)
	check(cleaned.receipts.has("valid") and not cleaned.receipts.has("missing-items") and not cleaned.receipts.has("duplicates"), "Corrupt receipt cannot crash loading or repeat one item as a ten-pull")
	check(cleaned.inventory == state.equipment.inventory and cleaned.qi == state.equipment.qi, "Receipt validation preserves all owned equipment and the actual balance")
	check(Equipment.normalize(JSON.parse_string(JSON.stringify(cleaned))).receipts.has("valid"), "Valid receipt remains recoverable after a JSON numeric round trip")
	var fixture = "res://output/alignment-%d.json" % OS.get_process_id()
	var family = Roster.new()
	family.persist_enabled = false
	family.save_file_override = fixture
	family.add_member({"name": "测试家人", "relation": "父亲", "age": 68, "sex": "男", "consent": true})
	family.owner_state.equipment.qi = 137
	write_fixture(fixture, family.to_data())
	family.load_game(State.new())
	var expected = family.to_data().duplicate(true)
	family.load_game(State.new())
	check(family.members.size() == 1 and family.to_data() == expected, "Repeated full-family reads replace the snapshot without appending duplicate elders")
	var invalid = expected.duplicate(true)
	invalid.members.append(invalid.members[0].duplicate(true))
	write_fixture(fixture, invalid)
	family.load_game(State.new())
	check(family.load_blocked and family.to_data() == expected, "Malformed snapshot leaves the entire previous family unchanged and blocks overwriting the source")
	invalid = expected.duplicate(true)
	invalid.members[0].id = "self"
	write_fixture(fixture, invalid)
	family.load_game(State.new())
	check(family.load_blocked and family.to_data() == expected, "An elder cannot shadow the reserved self identity")
	family.save_file_override = ""
	family.cache_root_override = "res://output/alignment-unused-%d" % OS.get_process_id()
	family.legacy_source_override = "res://output/alignment-no-legacy-%d.json" % OS.get_process_id()
	check(family.open_account({"id": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}).ok and family.members.is_empty() and family.owner_state.equipment.qi == 0 and not family.load_blocked, "Reusing a roster for another account clears old members, balances and load errors")
	family.dispose()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))
	check(Account.endpoint_allowed("https://game.example:8080") and Account.endpoint_allowed("http://127.0.0.1:8080") and not Account.endpoint_allowed("http://remote.example") and not Account.endpoint_allowed("https://game.example@other.example") and not Account.endpoint_allowed("https://game.example/path"), "Account credentials only use valid service roots with local HTTP or remote HTTPS")
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.family.persist_enabled = false
	game.state.persist_enabled = false
	game.state.apply_health_profile(state.HealthProfile.mock(40, 1))
	game.ui.open_health_entry()
	var panel = game.ui.health_entry
	panel.consent.button_pressed = true
	game.state.apply_health_profile(state.HealthProfile.mock(50, 2))
	before = game.state.health_snapshot()
	var sample = JSON.parse_string(FileAccess.get_file_as_string("res://health-entry/sample-baseline.json"))
	panel.commit(sample)
	check(game.state.health_snapshot() == before and not panel.context_matches(), "A delayed form cannot overwrite a newer health projection")
	game.ui.close_modal()
	var companion = game.companion_api
	companion.endpoint_url = "https://chat.example/api/chat"
	companion.trusted_auth_origin = ""
	check(not companion.may_send_account_token(), "Configuring a chat URL alone never authorizes sending the login token")
	companion.trusted_auth_origin = "https://chat.example"
	check(companion.may_send_account_token(), "An explicitly trusted chat origin may receive its agreed credential")
	companion.endpoint_url = "https://other.example/api/chat"
	check(not companion.may_send_account_token(), "Changing chat origin cannot inherit credential permission")
	companion.endpoint_url = ""
	companion.send_message("今天的记录")
	var message_count = companion.history.size()
	game.account_api.generation += 1
	await process_frame
	check(not companion.busy and companion.history.size() == message_count, "Chat callbacks are discarded after the account session changes")
	game.queue_free()
	await process_frame
	print("LEDGER ALIGNMENT TESTS: ", passed, " passed, ", failed, " failed")
	quit(1 if failed else 0)
