extends SceneTree
const State = preload("res://scripts/game_state.gd")
const Roster = preload("res://scripts/family_roster.gd")
var passed = 0
var failed = 0
var game: Node
var ids: Array = []
var cache_root: String
var legacy_path: String

func check(value: bool, message: String) -> void:
	if value:
		passed += 1
		print("PASS: ", message)
	else:
		failed += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func wait_api() -> void:
	var deadline = Time.get_ticks_msec() + 15000
	while game.account_api.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	await process_frame

func register_user(suffix: String) -> String:
	var panel = game.ui.account_panel
	panel.register_mode = true
	panel.build()
	panel.username_input.text = "fixture_%d_%s" % [OS.get_process_id(), suffix]
	panel.password_input.text = "fixture-password"
	panel.repeat_input.text = "fixture-password"
	panel.display_input.text = "测试子女" + suffix
	panel.submit()
	await wait_api()
	var id = str(game.account_api.account.get("id", ""))
	ids.append(id)
	return id

func run() -> void:
	cache_root = "res://output/account-test-%d" % OS.get_process_id()
	legacy_path = "res://output/account-legacy-%d.json" % OS.get_process_id()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.account_ready = false
	game.account_cache_root_override = cache_root
	game.account_legacy_source_override = legacy_path
	game.account_api.allow_autostart = false
	game.ui.open_login()
	game.ui.close_modal()
	check(is_instance_valid(game.ui.account_panel) and game.player.blocked, "Login screen cannot be dismissed into another user's game")
	var a = await register_user("a")
	check(not a.is_empty() and game.account_ready and is_instance_valid(game.ui.family_panel), "Actual registration logs in and opens the account page")
	check(game.family.members.is_empty() and game.family.owner_state.family_member_id == "self", "Self exists outside both empty elder slots")
	var person = {"name": "父亲", "relation": "父亲", "age": 68, "sex": "男", "title": "青松真人", "avatar": "male", "mode": "family", "consent": true}
	game.family.add_member(person)
	person.name = "母亲"
	person.relation = "母亲"
	person.sex = "女"
	game.family.add_member(person)
	check(game.family.members.size() == 2 and game.family.owner_state != game.family.members[0].state, "The registered child can add two elders in addition to self")
	person.relation = "本人"
	check(not game.family.validate_identity(person).ok, "Self cannot be entered into an elder slot")
	game.family.owner_state.equipment.qi = 111
	game.family.save_game()
	check(not FileAccess.get_file_as_string(game.family.save_path()).contains("fixture-password"), "Account progress files never contain passwords")
	game.ui.logout_account()
	await wait_api()
	check(not game.account_ready and not game.account_api.is_authenticated() and game.family.members.is_empty(), "Logout clears the active identity and in-memory family data")
	var b = await register_user("b")
	check(b != a and game.family.members.is_empty() and game.family.owner_state.equipment.qi == 0, "Another login receives its own empty family slots and wallet")
	game.ui.logout_account()
	await wait_api()
	game.account_api.authenticate("login", {"username": "fixture_%d_a" % OS.get_process_id(), "password": "wrong-password"})
	await wait_api()
	check(not game.account_ready and not game.account_api.is_authenticated(), "Incorrect passwords cannot open a saved account")
	game.account_api.authenticate("login", {"username": "fixture_%d_a" % OS.get_process_id(), "password": "fixture-password"})
	await wait_api()
	check(game.account_ready and game.family.members.size() == 2 and game.family.owner_state.equipment.qi == 111, "Logging back in restores self and both elders from that account only")
	game.ui.logout_account()
	await wait_api()
	var legacy = State.new()
	legacy.equipment.qi = 222
	var file = FileAccess.open(legacy_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy.to_data()))
	file.close()
	var c = await register_user("c")
	check(game.ui.account_panel.migration_mode and not game.account_ready, "Legacy progress requires an explicit account ownership choice")
	game.ui.import_old_account()
	await wait_api()
	check(game.account_ready and game.family.owner_state.equipment.qi == 222 and game.family.members.is_empty(), "Old player progress imports into self and leaves both elder slots free")
	check(FileAccess.file_exists(legacy_path.trim_suffix(".json") + "-before-accounts-v8.json"), "Legacy import retains an untouched original backup")
	game.ui.logout_account()
	await wait_api()
	await register_user("d")
	game.ui.import_old_account()
	await wait_api()
	check(not game.account_ready and game.ui.account_panel.status_label.text.contains("其他账号"), "The same old progress cannot be copied into another account")
	game.ui.finish_account_setup(false)
	check(game.account_ready and game.family.owner_state.equipment.qi == 0 and game.family.members.is_empty(), "A new account can start clean without taking the old progress")
	game.queue_free()
	await process_frame
	var old_self = State.new()
	old_self.equipment.qi = 333
	var old_elder = State.new()
	old_elder.equipment.qi = 44
	var old_data = {"schema": 7, "active_member_id": "elder_legacy", "members": [{"id": "elder_legacy", "identity": {"name": "原玩家", "relation": ""}, "progress": old_self.to_data()}, {"id": "elder_specific", "identity": {"name": "父亲", "relation": "父亲"}, "progress": old_elder.to_data()}]}
	file = FileAccess.open(legacy_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(old_data))
	file.close()
	var migrated = Roster.new()
	migrated.persist_enabled = false
	migrated.save_file_override = legacy_path
	migrated.load_game(State.new())
	check(migrated.owner_state.equipment.qi == 333 and migrated.members.size() == 1 and migrated.members[0].state.equipment.qi == 44, "Version-seven self is separated while an explicitly named elder is retained")
	migrated.dispose()
	old_data.members[0].identity.relation = "父亲"
	file = FileAccess.open(legacy_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(old_data))
	file.close()
	migrated = Roster.new()
	migrated.persist_enabled = false
	migrated.save_file_override = legacy_path
	migrated.load_game(State.new())
	check(migrated.members.size() == 2 and migrated.owner_state.equipment.qi == 0, "Explicit elder relationships take precedence over the old legacy ID")
	migrated.dispose()
	for id in ids:
		var path = cache_root.path_join(str(id) + ".json")
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cache_root))
	for path in [legacy_path, legacy_path.trim_suffix(".json") + "-before-accounts-v8.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("ACCOUNT TESTS: ", passed, " passed, ", failed, " failed")
	quit(0 if failed == 0 else 1)
