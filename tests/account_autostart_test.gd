extends SceneTree
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var client = Node.new()
	client.set_script(load("res://scripts/account_client.gd"))
	root.add_child(client)
	client.authenticate("register", {"username": "autostart_fixture", "password": "fixture-password", "display_name": "测试昵称"})
	var deadline = Time.get_ticks_msec() + 15000
	while client.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	var ok = client.is_authenticated() and client.started_server_pid > 0
	print("ACCOUNT SERVICE AUTO START AND REGISTER: ", "PASS" if ok else "FAIL")
	if client.started_server_pid > 0:
		OS.kill(client.started_server_pid)
	client.queue_free()
	await process_frame
	quit(0 if ok else 1)
