extends SceneTree
## Check the actual Windows launcher and bridge identity. Does not send health data.
func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.state.persist_enabled = false
	game.ui.open_health_entry()
	var panel = game.ui.health_entry
	panel.connect_service()
	var deadline = Time.get_ticks_msec() + 12000
	while not panel.service_verified and Time.get_ticks_msec() < deadline:
		await process_frame
	var success = panel.service_verified and panel.model_name == "qwen3-vl-plus"
	print("LOCAL SERVICE: ", "PASS" if success else "FAIL", " configured=", panel.configured, " model=", panel.model_name)
	if not success:
		push_error(panel.status.text)
	game.ui.close_modal()
	game.queue_free()
	await process_frame
	quit(0 if success else 1)
