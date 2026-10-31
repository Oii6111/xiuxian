extends SceneTree
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var ok = is_instance_valid(game.ui.account_panel) and not game.account_ready and game.player.blocked
	print("DEFAULT STARTUP REQUIRES LOGIN: ", "PASS" if ok else "FAIL")
	game.ui.close_modal()
	ok = ok and is_instance_valid(game.ui.account_panel) and game.player.blocked
	print("ESC CANNOT BYPASS LOGIN: ", "PASS" if ok else "FAIL")
	ok = ok and game.family.members.is_empty() and game.family.owner_state != null
	print("SELF DOES NOT OCCUPY THE TWO ELDER SLOTS: ", "PASS" if ok else "FAIL")
	game.queue_free()
	await process_frame
	quit(0 if ok else 1)
