extends SceneTree
## Persistent live joint-test session. Uses normal server login and actual channel data.
var game: Node
var last_state = ""
var capturing = false

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.account_legacy_source_override = "user://no-live-test-legacy.json"
	root.add_child(game)
	await process_frame
	await process_frame
	game.account_api.allow_autostart = false
	var credentials = JSON.parse_string(OS.get_environment("WECHAT_EXPERIENCE_CREDENTIALS"))
	if not credentials is Dictionary:
		push_error("Live test account configuration is unavailable")
		quit(1)
		return
	game.account_api.authenticate("login", credentials)
	await game.account_api.completed
	await process_frame
	if not game.account_ready:
		push_error("Live test account did not authenticate")
		return
	if game.family.companion.id.is_empty():
		game.family.choose_companion("gourd_dragon", "团团")
		game.companion_actor.refresh_pet()
	game.ui.open_wechat_link()
	await process_frame
	var deadline = Time.get_ticks_msec() + 8000
	while not game.ui.wechat_link_panel.operation.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	if not game.companion_tasks.manages(game.family.active_id):
		game.ui.wechat_link_panel.send("invite")
	var timer = Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(observe)
	root.add_child(timer)
	timer.start()
	print("LIVE EXPERIENCE READY: normal game account; awaiting Weixin scan and messages")

func observe() -> void:
	if capturing or not is_instance_valid(game) or not game.account_ready:
		return
	var tasks = game.companion_tasks.members.get(game.family.active_id, [])
	if tasks.is_empty():
		return
	var completed = 0
	for task in tasks:
		completed += int(task.status == "confirmed")
	var value = str(tasks.size()) + ":" + str(completed)
	if value == last_state:
		return
	last_state = value
	capturing = true
	game.ui.close_modal()
	game.ui.open_record()
	await create_timer(.4).timeout
	var suffix = "completed" if completed > 0 else "pending"
	await game.capture(OS.get_environment("WECHAT_LIVE_CAPTURE_DIR").path_join("real-wechat-" + suffix + ".png"))
	print("REAL WECHAT GAME UPDATE: tasks=", tasks.size(), ", completed=", completed)
	capturing = false
