extends SceneTree
var passed = 0
var failed = 0
var game: Node
var transport: HTTPRequest

func check(value: bool, message: String) -> void:
	if value:
		passed += 1
		print("PASS: ", message)
	else:
		failed += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func message(text: String, share: bool = true) -> Dictionary:
	var body = {"text": text, "share": share, "message_id": Crypto.new().generate_random_bytes(12).hex_encode()}
	var headers = PackedStringArray(["Content-Type: application/json", "X-Demo-Token: " + OS.get_environment("XIUXIAN_WECHAT_DEMO_INPUT_TOKEN")])
	var error = transport.request(OS.get_environment("XIUXIAN_WECHAT_DEMO_INPUT_URL"), headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK:
		return {}
	var result = await transport.request_completed
	return JSON.parse_string(result[3].get_string_from_utf8()) if result[1] == 200 else {}

func sync() -> void:
	var deadline = Time.get_ticks_msec() + 5000
	while game.companion_tasks.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	game.companion_tasks.refresh_now()
	while game.companion_tasks.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	await process_frame

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	transport = HTTPRequest.new()
	transport.timeout = 6
	root.add_child(transport)
	await process_frame
	await process_frame
	await sync()
	check(game.companion_tasks.connected and game.companion_tasks.members.get("wechat-demo-father", []).is_empty(), "No confirmed arrangement means no fabricated daily medication task")
	check(OS.get_environment("ELDER_SIDECAR_TOKEN").is_empty() and OS.get_environment("HEALTH_EVENT_SINK_TOKEN").is_empty(), "The game receives a scoped read token, never the sidecar service credentials")
	var before = game.state.to_data().duplicate(true)
	var first = await message("我最近在吃联调用药")
	check(first.get("intent", "") == "medication_course", "The real sidecar accepts the elder's current-plan statement")
	await message("每天一次")
	await sync()
	check(game.companion_tasks.members.get("wechat-demo-father", []).is_empty(), "Partial schedule information never activates a guessed seven-day plan")
	await message("吃七天，饭后")
	await sync()
	var tasks = game.companion_tasks.members.get("wechat-demo-father", [])
	check(tasks.size() == 1 and tasks[0].status == "unrecorded", "A complete shared plan creates one task visible to the actual Godot client")
	var task_id = str(tasks[0].id) if not tasks.is_empty() else ""
	await message("我还没吃过药")
	await sync()
	check(game.companion_tasks.members["wechat-demo-father"][0].status == "unrecorded", "Negative statements do not complete a task")
	game.ui.companion_panel.send_message("下一步做什么？")
	await process_frame
	await process_frame
	check("微信" in game.companion_api.history[-1].text, "The companion's next-step advice uses the shared task, not local manual confirmation")
	var reported = await message("我今天已经服药了")
	check(reported.get("needs_confirmation", false), "The upstream candidate record remains subject to the elder's own confirmation")
	await sync()
	check(game.companion_tasks.members["wechat-demo-father"][0].status == "unrecorded", "An unconfirmed candidate cannot change shared task state")
	await message("确认")
	await sync()
	check(game.companion_tasks.members["wechat-demo-father"][0].id == task_id and game.companion_tasks.members["wechat-demo-father"][0].status == "confirmed", "Elder confirmation updates the same task automatically without family reapproval")
	check(game.state.to_data() == before, "Task synchronization changes no character stats, currency, inventory or boss progress")
	check("父亲" in game.companion_api.history[-1].text and "反馈完成" in game.companion_api.history[-1].text, "The companion automatically announces the received completion")
	game.ui.open_record()
	await process_frame
	check(is_instance_valid(game.ui.wechat_task_label) and "微信确认完成" in game.ui.wechat_task_label.text, "The record entry opens the shared read-only task view")
	game.ui.close_modal()
	game.ui.open_companion()
	await process_frame
	var invalid = {"schema_version": 1, "mode": "local_demo", "account_id": "other-user", "revision": 999, "business_date": game.state.today(), "members": []}
	check(game.companion_tasks.clean_snapshot(invalid).is_empty(), "Another account's snapshot is rejected")
	var original_owner = str(game.family.account.id)
	game.family.account.id = "another-test-account"
	check(not game.companion_tasks.manages("wechat-demo-father"), "Cached records are hidden immediately when account identity changes")
	game.family.account.id = original_owner
	if "--wechat-capture" in OS.get_cmdline_user_args():
		await create_timer(0.4).timeout
		await game.capture("res://output/wechat-link-completed.png")
	game.ui.reset_logged_out()
	await process_frame
	check(game.companion_tasks.members.is_empty() and not game.companion_tasks.connected, "Logout clears cached shared tasks")
	game.queue_free()
	transport.queue_free()
	await process_frame
	print("WECHAT LINK CHECKS: ", passed, " passed, ", failed, " failed")
	quit(1 if failed else 0)
