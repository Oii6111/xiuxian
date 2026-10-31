extends SceneTree
var passed = 0
var failed = 0

func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS: ", message)
	else:
		failed += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func wait_reply(client) -> void:
	var deadline = Time.get_ticks_msec() + 4000
	while client.busy and Time.get_ticks_msec() < deadline:
		await process_frame

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.family.persist_enabled = false
	game.family.choose_companion("gourd_dragon", "团团")
	game.account_api.token = "test-session"
	var client = game.companion_api
	check(not client.endpoint_url.is_empty(), "Test runner configured a loopback API endpoint")
	client.trusted_auth_origin = client.origin(client.endpoint_url)
	var original = game.family.to_data().duplicate(true)
	check(client.send_message("hello"), "The HTTP adapter accepts a chat message")
	check(not client.send_message("duplicate"), "Concurrent sends are blocked while a reply is pending")
	await wait_reply(client)
	check(not client.busy and client.online and client.history[-1].text == "模拟服务已收到：hello", "HTTP JSON request and authenticated response complete end to end")
	check(client.history[-1].actions.size() == 1 and client.history[-1].actions[0].id == "family", "Unknown remote actions never become clickable commands")
	check(game.family.to_data() == original, "A remote reward field cannot alter task state or currency")
	for message in ["wrong_id", "malformed", "error"]:
		client.send_message(message)
		await wait_reply(client)
		check(not client.busy and not client.online and client.history[-1].source == "local_guide", "API failure returns to local guidance: " + message)
	client.request.timeout = 0.1
	client.send_message("delay")
	await wait_reply(client)
	check(not client.busy and client.history[-1].source == "local_guide", "A request timeout returns to usable local guidance")
	client.request.timeout = 15.0
	client.send_message("delay")
	client.cancel_pending()
	var count = client.history.size()
	await create_timer(0.9).timeout
	check(not client.busy and client.history.size() == count, "A cancelled request cannot append a late reply")
	game.ui.open_companion()
	game.ui.companion_panel.send_message("delay")
	game.ui.close_modal()
	count = client.history.size()
	await create_timer(0.9).timeout
	check(game.ui.companion_panel == null and not client.busy and client.history.size() == count, "Closing the panel cancels network work and its UI callbacks")
	client.send_message("delay")
	game.account_ready = false
	client.reset_session()
	await create_timer(0.9).timeout
	check(client.history.is_empty() and not client.busy, "Logout prevents old-account replies from repopulating the conversation")
	game.queue_free()
	await process_frame
	print("COMPANION API CHECKS: ", passed, " passed, ", failed, " failed")
	quit(1 if failed else 0)
