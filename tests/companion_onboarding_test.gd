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

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	check(not game.account_ready and game.ui.account_panel != null and not game.companion_actor.visible, "The default launch retains login gating and hides another account's pet")
	var account = game.FamilyRoster.new()
	account.persist_enabled = false
	account.account = {"id": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "name": "测试账号"}
	game.pending_account_roster = account
	game.ui.finish_account_setup(false)
	await process_frame
	await process_frame
	check(game.account_ready and game.ui.companion_panel != null and game.ui.companion_panel.choose_mode, "A newly authenticated account opens the four-pet chooser")
	game.ui.companion_panel.select_pet("herb_deer")
	game.ui.companion_panel.confirm_choice()
	await process_frame
	check(game.family.companion.id == "herb_deer" and game.companion_actor.visible, "The first choice activates the selected pet and conversation")
	game.ui.close_modal()
	var before = game.companion_actor.position
	game.player.position += Vector2(130, 0)
	await create_timer(0.7).timeout
	check(game.companion_actor.position.distance_to(before) > 15, "The selected pet follows actual map movement")
	game.ui.open_companion()
	game.ui.companion_panel.send_message("你好")
	await process_frame
	await process_frame
	game.ui.reset_logged_out()
	await process_frame
	check(not game.account_ready and not game.companion_actor.visible and game.companion_api.history.is_empty(), "Logout hides the pet and clears all in-memory conversations")
	game.queue_free()
	await process_frame
	print("COMPANION ONBOARDING CHECKS: ", passed, " passed, ", failed, " failed")
	quit(1 if failed else 0)
