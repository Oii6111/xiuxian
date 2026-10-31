extends SceneTree
## B 的登录/家族界面跑在 C 的统一账号与角色库上；由 server/tools/godot-b.ts 启动回环服务与内存数据库。
var passed = 0
var failed = 0
var game: Node
var cache_root: String

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
	for i in range(5):
		await process_frame

func submit(suffix: String, register: bool, password: String = "fixture-password-123") -> void:
	var panel = game.ui.account_panel
	panel.register_mode = register
	panel.build()
	panel.username_input.text = "fixture_%d_%s" % [OS.get_process_id(), suffix]
	panel.password_input.text = password
	if register:
		panel.repeat_input.text = password
		panel.display_input.text = "子女" + suffix
	panel.submit()
	await wait_api()

func elder(name: String, relation: String, sex: String) -> Dictionary:
	return {"name": name, "relation": relation, "age": 68, "sex": sex, "title": name + "真人", "avatar": "female" if sex == "女" else "male", "mode": "family", "consent": true}

func run() -> void:
	cache_root = "res://output/account-test-%d" % OS.get_process_id()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.account_cache_root_override = cache_root
	game.account_legacy_source_override = "res://output/account-no-legacy-%d.json" % OS.get_process_id()
	game.account_api.allow_autostart = false
	game.ui.open_login()
	check(is_instance_valid(game.ui.account_panel) and game.player.blocked, "Login screen gates the game")
	await submit("a", true)
	check(game.account_ready and game.family.is_remote(), "Registration logs in through C and creates the self character there")
	var core = root.get_node("GameKernel")
	var listed = await core.dispatch("growth.list", {})
	check(listed.ok and listed.data.cultivators.size() == 1 and listed.data.cultivators[0].role == "self", "C holds exactly one self character")
	var first = await game.family.remote_add_member(elder("张建国", "父亲", "男"), core)
	var second = await game.family.remote_add_member(elder("李秀兰", "母亲", "女"), core)
	var third = await game.family.remote_add_member(elder("王第三", "外公", "男"), core)
	check(first.ok and second.ok and not third.ok, "Two elders are created in C; the third is refused")
	listed = await core.dispatch("growth.list", {})
	check(listed.data.cultivators.size() == 3, "C stores self plus two elders")
	check(not game.family.state_for(first.id).record_task("planned_record", true).ok, "Formal accounts cannot mint daily rewards inside the game")
	check(not game.family.state_for(first.id).draw_equipment(1, "local").ok, "Formal accounts cannot draw locally")
	game.ui.logout_account()
	await wait_api()
	check(not game.account_ready and game.family.members.is_empty(), "Logout clears identity and family")
	await submit("b", true)
	check(game.account_ready and game.family.members.is_empty() and game.family.owner_state.equipment.qi == 0, "Another account gets its own empty family")
	game.ui.logout_account()
	await wait_api()
	await submit("a", false, "wrong-password-0000")
	check(not game.account_ready, "Wrong password cannot open an account")
	await submit("a", false)
	check(game.account_ready and game.family.members.size() == 2, "Logging back in restores both elders from C")
	game.queue_free()
	await process_frame
	var dir = DirAccess.open(cache_root)
	if dir != null:
		for file in dir.get_files():
			dir.remove(file)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cache_root))
	print("ACCOUNT TESTS: ", passed, " passed, ", failed, " failed")
	quit(0 if failed == 0 else 1)
