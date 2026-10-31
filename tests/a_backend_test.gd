extends SceneTree
## A 的生命周期确认与具名 Boss 会话经 C 服务端执行；由 server/tools/godot-b.ts a_backend_test 启动回环服务。
var passed = 0
var failed = 0
var game: Node

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

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.account_cache_root_override = "res://output/a-backend-%d" % OS.get_process_id()
	game.account_legacy_source_override = "res://output/a-backend-none-%d.json" % OS.get_process_id()
	game.account_api.allow_autostart = false
	game.ui.open_login()
	var panel = game.ui.account_panel
	panel.register_mode = true
	panel.build()
	panel.username_input.text = "a_fixture_%d" % OS.get_process_id()
	panel.password_input.text = "fixture-password-123"
	panel.repeat_input.text = "fixture-password-123"
	panel.display_input.text = "测试子女"
	panel.submit()
	await wait_api()
	var core = root.get_node("GameKernel")
	var added = await game.family.remote_add_member({"name": "张建国", "relation": "父亲", "age": 68, "sex": "男", "title": "青松", "avatar": "male", "mode": "family", "consent": true}, core)
	check(added.ok, "Elder created in C")
	var state = game.family.state_for(added.id)
	game.state = state
	var gateway = preload("res://scripts/tribulation/family_gateway.gd").new()
	gateway.remote_api = game.account_api.api
	root.add_child(gateway)
	check(gateway.bind(state, "scope", func(): return "scope").ok, "Lifecycle gateway binds the formal elder")
	var ticket = await gateway._authority("request_change", {"target_state": "tribulation", "from_version": state.lifecycle_record().version})
	check(ticket.ok and not str(ticket.data.get("confirmation_token", "local-family")).begins_with("local-family"), "Confirmation token is issued by C, not locally")
	var confirmed = await gateway._authority("confirm_change", {"confirmation_token": ticket.data.confirmation_token, "request_id": "confirm-1", "target_state": "tribulation"})
	check(confirmed.ok and state.lifecycle_record().state == "tribulation" and not state.allows_battle(), "Confirmed tribulation blocks battle locally")
	var remote = await core.dispatch("growth.snapshot", {"cultivator_id": state.cultivator_id})
	check(remote.ok and remote.data.lifecycle == "tribulation" and int(remote.data.progress.version) == 1, "C stores the authoritative lifecycle state")
	var stage = await gateway._authority("update_stage", {"stage_id": "cardio.admission", "from_version": state.lifecycle_record().version})
	check(stage.ok and state.lifecycle_record().stage_index == 0, "Stage update goes through C")
	var blocked = await game.account_api.api.invoke("combat.start", {"cultivator_id": state.cultivator_id, "encounter_id": "b00"})
	check(blocked.code == "NOT_ALLOWED", "C refuses boss fights during tribulation")
	var back = await gateway._authority("request_change", {"target_state": "cultivating", "from_version": state.lifecycle_record().version})
	await gateway._authority("confirm_change", {"confirmation_token": back.data.confirmation_token, "request_id": "confirm-2", "target_state": "cultivating"})
	check(state.allows_battle(), "Returning to cultivating allows battle again")
	gateway.queue_free()
	var session = await game.account_api.api.invoke("combat.start", {"cultivator_id": state.cultivator_id, "encounter_id": "b00"})
	check(session.ok, "C opens a boss session")
	var cheat = await game.account_api.api.invoke("combat.finish", {"session_id": session.data.session_id, "won": true, "duration_seconds": 600.0})
	check(cheat.code == "INVALID_RESULT", "A result longer than the real session is rejected")
	await create_timer(3.2).timeout
	var finished = await game.account_api.api.invoke("combat.finish", {"session_id": session.data.session_id, "won": true, "duration_seconds": 3.1})
	check(finished.ok and finished.data.first_clear, "Boss win records a first clear in C")
	await game.account_api.sync_family(game.family)
	state = game.family.state_for(added.id)
	check("b00" in state.cleared_bosses and state.equipment.qi == 0, "First clear syncs back without granting currency")
	var cache = game.account_cache_root_override
	game.queue_free()
	await process_frame
	var dir = DirAccess.open(cache)
	if dir != null:
		for file in dir.get_files():
			dir.remove(file)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cache))
	print("A BACKEND TESTS: ", passed, " passed, ", failed, " failed")
	quit(0 if failed == 0 else 1)
