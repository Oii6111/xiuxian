extends SceneTree
## 游客演示冒烟测试：登录页能直接进入演示，并走通「绑定家人 → 健康任务 → 结算」。
func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame

	var ok = is_instance_valid(game.ui.account_panel) and not game.account_ready
	print("GUEST: LOGIN PANEL SHOWN: ", "PASS" if ok else "FAIL")

	game.ui.start_guest_demo()
	await process_frame
	ok = ok and game.account_ready
	print("GUEST: ENTERED WITHOUT ACCOUNT: ", "PASS" if ok else "FAIL")
	ok = ok and game.family.members.size() == 1
	print("GUEST: ONE DEMO ELDER SEEDED: ", "PASS" if ok else "FAIL")

	var elder = game.family.state_for(game.ui.guest_elder_id)
	ok = ok and elder != null and not elder.health_profile_id.is_empty()
	print("GUEST: DEMO HEALTH PROFILE READY: ", "PASS" if ok else "FAIL")

	game.ui.guest_show_qr()
	await process_frame
	game.ui.guest_confirm_qr()
	await process_frame
	ok = ok and game.ui.guest_bound
	print("GUEST: SIMULATED WECHAT BIND: ", "PASS" if ok else "FAIL")

	var before = int(elder.cultivation)
	game.ui.guest_complete_task()
	await process_frame
	ok = ok and game.ui.guest_task_done and elder.task_done("medication") and elder.task_done("planned_record")
	print("GUEST: DAILY HEALTH TASKS RECORDED: ", "PASS" if ok else "FAIL")
	ok = ok and int(elder.cultivation) > before
	print("GUEST: CULTIVATION AWARDED: ", "PASS" if ok else "FAIL")

	game.ui.guest_show_result()
	await process_frame
	ok = ok and game.ui.modal_open
	print("GUEST: SETTLEMENT DIALOG OPENS: ", "PASS" if ok else "FAIL")

	game.ui.guest_exit_demo()
	await process_frame
	ok = ok and not game.account_ready and game.family.members.is_empty()
	print("GUEST: EXIT RETURNS TO LOGIN: ", "PASS" if ok else "FAIL")

	game.queue_free()
	await process_frame
	quit(0 if ok else 1)
