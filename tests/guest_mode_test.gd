extends SceneTree

var passed := 0
var failed := 0

func check(value: bool, message: String) -> void:
	if value:
		passed += 1
		print("PASS: ", message)
	else:
		failed += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.ui.open_login()
	var guest_button = false
	for node in game.ui.account_panel.find_children("*", "Button", true, false):
		guest_button = guest_button or node.text.contains("游客模式")
	check(guest_button, "Login screen exposes a guest mode action")
	game.ui.start_guest_mode()
	for i in range(4):
		await process_frame
	check(game.guest_mode and game.account_ready and not game.account_api.is_authenticated() and not game.family.persist_enabled, "Guest mode starts a local non-account roster")
	check(game.family.members.size() == 1 and game.state.family_identity.get("name", "") == "张建国", "Guest mode creates the sample family profile")
	var panel = game.ui.health_entry
	check(is_instance_valid(panel), "Guest mode opens the health profile flow")
	if is_instance_valid(panel):
		for i in range(4):
			await process_frame
		check(panel.chosen_paths.size() == 3 and panel.draft.recognition_mode == "sample", "Guest mode selects all three raw sample images and prepares the sample baseline")
		panel.confirm_draft()
		for i in range(2):
			await process_frame
		check(not is_instance_valid(game.ui.health_entry) and game.state.health_baseline.recognition_mode == "sample", "Guest sample baseline can be confirmed without an account")
		check(int(game.state.equipment.get("starter_ten_pulls", 0)) == 1 and is_instance_valid(game.ui.treasure), "Guest confirmation opens the pavilion with one free ten-pull")
	game.ui.logout_account()
	await process_frame
	check(not game.account_ready and is_instance_valid(game.ui.account_panel), "Guest exit returns to the login screen")
	game.queue_free()
	await process_frame
	print("GUEST MODE RESULT: ", passed, " passed, ", failed, " failed")
	quit(0 if failed == 0 else 1)
