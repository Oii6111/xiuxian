extends SceneTree
const Hub = preload("res://scenes/combat/demo_hub.tscn")
var checks: int = 0
var failures: Array = []
var folder: String = "res://outputs/combat-lifecycle"
func _init() -> void:
	call_deferred("_run")
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL: ", label)
func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	expect(image != null and image.save_png(folder.path_join(name + ".png")) == OK, "save rendered " + name)
func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var hub: Control = Hub.instantiate()
	hub.demo_authority = true
	root.add_child(hub)
	await process_frame
	await capture("entry")
	for element in ["wood", "fire", "metal"]:
		await hub.launch_trial("trial_" + element)
		await process_frame
		var scene: Control = hub.current
		expect(scene != null and scene.fight.valid, "rendered trial starts")
		if scene == null:
			continue
		scene.set_process(false)
		await capture("trial_" + element)
		await key(KEY_P)
		expect(scene.paused, "keyboard pause reaches the mounted scene")
		await key(KEY_P)
		expect(not scene.paused, "keyboard resumes")
		await scene.request_leave()
		await process_frame
	hub.open("platform")
	await process_frame
	var platform: Control = hub.current
	platform.request_confirmation("begin")
	await capture("family_confirmation")
	platform.cancel_pending()
	platform._dialog.hide()
	platform.request_confirmation("begin")
	await platform.confirm_pending()
	await platform.update_stage("admission")
	await platform.update_stage("emergency")
	platform.light_lamp()
	platform.light_lamp()
	await capture("tribulation")
	platform.request_confirmation("seclusion")
	await platform.confirm_pending()
	await capture("seclusion")
	platform.request_confirmation("seclusion")
	await platform.confirm_pending()
	platform.request_confirmation("begin")
	await platform.confirm_pending()
	await platform.update_stage("admission")
	await platform.update_stage("discharge")
	platform.request_confirmation("celebrate")
	await platform.confirm_pending()
	await capture("celebration_scene")
	await platform.export_card()
	expect(platform.status.contains("已保存"), "celebration card exported successfully")
	var card := Image.new()
	var output: String = OS.get_environment("XIUXIAN_A_OUTPUT_DIR")
	if output.is_empty():
		output = ProjectSettings.globalize_path(folder)
	expect(card.load(output.path_join("celebration.png")) == OK and card.get_width() == 960 and card.get_height() == 540, "share card has expected dimensions")
	expect(not platform.status.contains("失败"), "export has no error")
	hub.close()
	hub.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("A_RENDER_TEST: %d assertions; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)