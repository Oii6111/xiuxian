extends SceneTree
var game: Node
var transport: HTTPRequest
var passed = 0
var failed = 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if value:
		passed += 1
		print("PASS: ", message)
	else:
		failed += 1
		push_error(message)

func fixture(step: String) -> void:
	var body = JSON.stringify({"step": step, "account_id": game.family.account.id})
	transport.request(OS.get_environment("WECHAT_NATIVE_FIXTURE_URL"), PackedStringArray(["Content-Type: application/json", "X-Test-Control: " + OS.get_environment("WECHAT_NATIVE_FIXTURE_TOKEN")]), HTTPClient.METHOD_POST, body)
	await transport.request_completed

func sync() -> void:
	var deadline = Time.get_ticks_msec() + 8000
	while game.companion_tasks.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	game.companion_tasks.refresh_now()
	while game.companion_tasks.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	await process_frame

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.account_cache_root_override = "user://native-test-accounts"
	game.account_legacy_source_override = "user://no-legacy-native-test.json"
	root.add_child(game)
	transport = HTTPRequest.new()
	transport.timeout = 8
	root.add_child(transport)
	await process_frame
	await process_frame
	game.account_api.allow_autostart = false
	game.account_api.authenticate("register", {"username": "native_" + Crypto.new().generate_random_bytes(4).hex_encode(), "display_name": "现场联测", "password": Crypto.new().generate_random_bytes(20).hex_encode(), "avatar": "male"})
	await game.account_api.completed
	await process_frame
	check(game.account_ready and game.account_api.is_authenticated(), "Actual Godot account client registers through the live account service")
	if not game.account_ready:
		quit(1)
		return
	game.family.choose_companion("gourd_dragon", "团团")
	game.companion_actor.refresh_pet()
	game.ui.open_wechat_link()
	await process_frame
	check(is_instance_valid(game.ui.wechat_link_panel), "The real game builds the Weixin connection panel")
	var deadline = Time.get_ticks_msec() + 8000
	while not game.ui.wechat_link_panel.operation.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	check("没有连接" in game.ui.wechat_link_panel.status.text, "The panel reads the selected role's real binding status")
	await fixture("bind")
	await sync()
	check(game.companion_tasks.connected and game.companion_tasks.manages("self"), "Account-scoped mode=live snapshot is accepted without a preview flag")
	var before = game.state.to_data().duplicate(true)
	await fixture("plan")
	await sync()
	var tasks = game.companion_tasks.members.get("self", [])
	check(tasks.size() == 1 and tasks[0].status == "unrecorded", "Confirmed Weixin arrangement becomes a pending task in the actual game")
	var id = str(tasks[0].id) if not tasks.is_empty() else ""
	await fixture("complete")
	await sync()
	tasks = game.companion_tasks.members.get("self", [])
	check(tasks.size() == 1 and tasks[0].id == id and tasks[0].status == "confirmed", "Completion updates the same task in the actual Godot client")
	check(game.state.to_data() == before, "Task reads do not change character stats, equipment, currency or combat progress")
	check("反馈完成" in game.companion_api.history[-1].text, "The companion announces the received completion automatically")
	game.ui.close_modal()
	game.ui.open_record()
	await process_frame
	check(is_instance_valid(game.ui.wechat_task_label) and "散步" in game.ui.wechat_task_label.text and "微信确认完成" in game.ui.wechat_task_label.text, "The actual task page displays the completed Weixin record")
	var screenshot = OS.get_environment("WECHAT_NATIVE_SCREENSHOT")
	if not screenshot.is_empty():
		await create_timer(.4).timeout
		await game.capture(screenshot)
	await fixture("revoke")
	await sync()
	check(not game.companion_tasks.manages("self"), "Revoking the binding removes its shared projection")
	game.queue_free()
	transport.queue_free()
	await process_frame
	print("NATIVE WECHAT CHECKS: ", passed, " passed, ", failed, " failed")
	quit(1 if failed else 0)
