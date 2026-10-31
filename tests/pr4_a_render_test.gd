extends SceneTree
var checks: int = 0
var failures: Array = []
var folder: String = "res://outputs/combat-lifecycle/pr4-adapted"
func _init() -> void:
	call_deferred("_run")
func expect(value: bool, title: String) -> void:
	checks += 1
	if not value:
		failures.append(title)
		printerr("FAIL: ", title)
func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	expect(image != null and image.save_png(folder.path_join(name + ".png")) == OK, "render " + name)
func find_button(node: Node, text: String) -> Button:
	for button in node.find_children("*", "Button", true, false):
		if button.text == text:
			return button
	return null
func click(button: Button) -> void:
	await process_frame
	var point: Vector2 = button.get_global_rect().get_center()
	var window: Window = button.get_window()
	if window.is_embedded():
		point += Vector2(window.position)
	var target_viewport: Viewport = root
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	target_viewport.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	target_viewport.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	target_viewport.push_input(event, true)
	await process_frame
func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.family.persist_enabled = false
	var father: Dictionary = scene.family.add_member({"name":"演示家人","relation":"父亲","age":65,"sex":"男","title":"松风真人","avatar":"male","mode":"family","consent":true})
	var actor = scene.family.state_for(father.id)
	actor.apply_health_profile(actor.HealthProfile.mock(40, 1))
	actor.equipment.qi = 700
	actor.equipment.inventory = [{"id":"gear_000001","template":0,"rarity":2}]
	actor.equipment.next_id = 2
	actor.equipment.draw_count = 1
	actor.equip_item("gear_000001")
	scene.ui.activate_family(father.id)
	await process_frame
	await capture("village")
	var life_button: Button = find_button(scene.ui, "渡劫台 / 修行状态")
	expect(life_button != null, "real village has lifecycle entry")
	await click(life_button)
	expect(is_instance_valid(scene.ui.lifecycle_panel), "viewport mouse click opens lifecycle")
	var panel: Control = scene.ui.lifecycle_panel
	await click(find_button(panel, "开启渡劫"))
	expect(panel._dialog.visible and actor.lifecycle_record().state == "cultivating", "button opens family confirmation without transition")
	await capture("family-confirmation")
	await click(panel._dialog.get_ok_button())
	expect(actor.lifecycle_record().state == "tribulation", "real mouse confirmation changes the bound elder")
	await panel.update_stage("admission")
	await panel.update_stage("emergency")
	panel.light_lamp()
	await capture("tribulation")
	panel.request_confirmation("seclusion")
	await panel.confirm_pending()
	await capture("seclusion")
	panel.request_confirmation("seclusion")
	await panel.confirm_pending()
	scene.ui.close_modal()
	await process_frame
	scene.ui.open_treasure("bag")
	await capture("treasure-bag")
	scene.ui.close_modal()
	await process_frame
	scene.ui.start_companion_practice()
	await process_frame
	var companion_practice: Control = scene.ui.combat
	companion_practice._process(1.9)
	companion_practice.set_process(false)
	expect(is_instance_valid(companion_practice.companion_sprite), "AI support appears in actual PR4 practice")
	await capture("ai-practice")
	scene.ui.close_modal()
	await process_frame
	scene.ui.start_corridor_boss("b03")
	await process_frame
	var combat: Control = scene.ui.combat
	expect(combat.rules.stats == actor.battle_stats() and combat.skill_nodes.size() == 4, "same family and gear feed existing four skills")
	combat.rules.boss_hp = int(combat.rules.boss_max_hp * 0.6)
	combat.rules._sync_stage()
	combat.rules.phase_clock = 3
	combat.rules.step(0.01, combat.hero.position)
	combat._refresh_adds()
	combat.refresh()
	combat.set_process(false)
	expect(combat.rules.stage_index == 1 and combat.rules.active_adds() == 2, "rendered named boss has staged summons")
	await capture("boss-stage2")
	await key(KEY_P)
	expect(combat.paused, "real P key pauses main combat")
	await key(KEY_P)
	expect(not combat.paused, "real P key resumes main combat")
	scene.ui.close_modal()
	await process_frame
	scene.ui.open_recovery()
	panel = scene.ui.lifecycle_panel
	panel.request_confirmation("begin")
	await panel.confirm_pending()
	await panel.update_stage("admission")
	await panel.update_stage("discharge")
	var wallet: int = actor.equipment.qi
	panel.request_confirmation("celebrate")
	await panel.confirm_pending()
	await capture("celebration")
	expect(actor.lifecycle_record().state == "cultivating" and actor.equipment.qi == wallet, "celebration does not credit wish currency")
	var output: String = OS.get_environment("XIUXIAN_A_OUTPUT_DIR")
	OS.set_environment("XIUXIAN_A_OUTPUT_DIR", ProjectSettings.globalize_path(folder))
	await panel.export_card()
	expect(panel.status.contains("已保存"), "adapted platform exports celebration card")
	OS.set_environment("XIUXIAN_A_OUTPUT_DIR", output)
	scene.ui.close_modal()
	await process_frame
	scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("PR4_A_RENDER_TEST: %d assertions; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)