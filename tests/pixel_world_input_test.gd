extends SceneTree
## Actual rendered keyboard/mouse smoke playthrough; isolated saves, no combat/reward writes.
var game
var checks: Array = []
var out: String
var held: Array = []
var started: int
var finished = false
func _initialize() -> void:
	root.unfocusable = true
	root.position = Vector2i(-12000, -12000)
	root.size = Vector2i(1440, 900)
	out = ProjectSettings.globalize_path("res://outputs/pixel-campaign")
	DirAccess.make_dir_recursive_absolute(out)
	started = Time.get_ticks_msec()
	create_timer(200).timeout.connect(func():
		if not finished:
			check(false, "watchdog")
			finish())
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks.append({"passed":ok,"name":label})
	print("PIXEL_WORLD_INPUT ",ok," ",label)
func key(code: int, down: bool) -> void:
	var e = InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()
func directions(next: Array) -> void:
	for code in held:
		if code not in next:key(code, false)
	for code in next:
		if code not in held:key(code, true)
	held = next.duplicate()
func tap(code: int) -> void:
	key(code, true)
	await process_frame
	key(code, false)
	await process_frame
func click(text: String) -> bool:
	# Scene swaps defer layout and deletion; wait for the current controls to settle.
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	var scope: Node = game
	if is_instance_valid(game.ui.campaign) and is_instance_valid(game.ui.campaign.ui.modal):
		scope = game.ui.campaign.ui.modal
	elif is_instance_valid(game.ui.start_screen):
		scope = game.ui.start_screen
	for b in scope.find_children("*", "Button", true, false):
		if not b.is_visible_in_tree() or b.disabled or text not in b.text:continue
		var p = b.get_global_transform_with_canvas() * (b.size * .5)
		if not root.get_visible_rect().has_point(p):continue
		var motion = InputEventMouseMotion.new()
		var received = [false]
		b.pressed.connect(func(): received[0] = true, CONNECT_ONE_SHOT)
		motion.position = p
		motion.global_position = p
		root.push_input(motion, true)
		await process_frame
		for down in [true, false]:
			var e = InputEventMouseButton.new()
			e.position = p
			e.global_position = p
			e.button_index = MOUSE_BUTTON_LEFT
			e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
			e.pressed = down
			root.push_input(e, true)
			Input.flush_buffered_events()
			await process_frame
		await create_timer(.15).timeout
		if not received[0] and is_instance_valid(b) and b.is_visible_in_tree():
			await RenderingServer.frame_post_draw
			p = b.get_global_transform_with_canvas() * (b.size * .5)
			for down in [true, false]:
				var retry = InputEventMouseButton.new()
				retry.position = p
				retry.global_position = p
				retry.button_index = MOUSE_BUTTON_LEFT
				retry.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
				retry.pressed = down
				root.push_input(retry, true)
				Input.flush_buffered_events()
				await process_frame
			await create_timer(.15).timeout
		if not received[0]:
			check(false, 'GUI click delivered: ' + text)
		return received[0]
	check(false, "visible button: " + text)
	return false
func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
func run() -> void:
	game = load("res://scenes/legacy_campaign_village.tscn").instantiate()
	game.state.apply_health_profile(game.state.HealthProfile.mock(40, 1))
	game.state.profile_created = false
	game.state.save_file_override = out.path_join("isolated-village-save.json")
	root.add_child(game)
	current_scene = game
	await create_timer(.4).timeout
	game.ui.saga.persist_enabled = false
	game.ui.show_start()
	await process_frame
	if is_instance_valid(game.ui.start_screen):
		var b = game.ui.avatar_buttons[1]
		var p = b.get_global_transform_with_canvas() * (b.size*.5)
		for down in [true,false]:
			var e = InputEventMouseButton.new(); e.position=p; e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down
			root.push_input(e,true)
			await process_frame
	await click("开始修行")
	check(game.state.avatar_id == "female", "village female profile via GUI")
	await capture("01-village-entry")
	await click("五域山海")
	var world = game.ui.campaign
	check(is_instance_valid(world) and world.current_region == "序章", "village entry opens tutorial map")
	if not is_instance_valid(world):finish();return
	check(world.state.data.avatar == "female", "campaign inherits selected visual profile")
	await capture("02-origin-map")
	var original = world.player_position
	directions([KEY_D]);await create_timer(.25).timeout;directions([])
	check(world.player_position.distance_to(original) > 20, "regional WASD movement")
	await tap(KEY_M)
	check(world.ui.modal_open, "M opens five realms map")
	await capture("03-five-realms-map")
	await tap(KEY_ESCAPE)
	await tap(KEY_TAB)
	check(world.ui.modal_open, "Tab opens all twenty boss atlas")
	await capture("04-boss-atlas")
	await tap(KEY_ESCAPE)
	await click("听雷")
	await capture("05-boss-story")
	await click("进入祟门")
	check(world.battle != null, "boss story GUI starts live battle")
	if world.battle == null:finish();return
	await play(world,"b00")
	check("b00" in world.state.data.clears, "tutorial clear through keyboard combat")
	await capture("06-tutorial-result")
	await click("下一条线索")
	for id in ["b01","b02","b03"]:
		await click("进入祟门")
		await play(world,id)
		check(id in world.state.data.clears, id + " cleared through keyboard combat")
		if id != "b03":await click("下一条线索")
	await capture("07-wood-result")
	check("木" in world.state.data.seals, "wood seal and region restoration")
	check(world.state.data.xp == 440 and world.state.data.materials == 15, "four first-clear rewards settled once")
	await click("回到区域看变化")
	check(world.actors.filter(func(a):return a.kind == "minion").size() == 2, "two friendly minions inhabit restored wood map")
	await capture("08-wood-restored")
	await click("洞府")
	await capture("09-home-before")
	await click("营造门灯")
	check("门灯" in world.state.data.buildings and world.state.data.materials == 12, "spend earned materials on persistent camp prop")
	await tap(KEY_ESCAPE)
	await tap(KEY_M)
	await click("水")
	check(world.current_region == "水", "GUI region travel")
	await capture("10-water-map")
	await tap(KEY_M);await click("火");await capture("11-fire-map")
	await tap(KEY_M);await click("土");await capture("12-earth-map")
	await tap(KEY_M);await click("金");await capture("13-metal-map")
	await tap(KEY_M);await click("终章");await capture("14-final-map")
	await click("执衡")
	var button_count = world.ui.modal.find_children("*","Button",true,false).filter(func(b):return "进入祟门" in b.text and b.disabled).size()
	check(button_count == 1, "final boss remains locked with one of five seals")
	await tap(KEY_ESCAPE)
	await click("人物志")
	await capture("15-people-and-minions")
	await tap(KEY_ESCAPE)
	await click("归仙村")
	await click("返回像素仙村")
	check(not is_instance_valid(game.ui.campaign) and not game.player.blocked, "return restores village input")
	await process_frame
	check(game.ui.restored_visitors.get_child_count() >= 2, "restored minion visits village")
	await capture("16-return-village")
	finish()
func play(world, id: String) -> void:
	var deadline = Time.get_ticks_msec() + 50000
	var photographed = false
	while is_instance_valid(world.battle) and Time.get_ticks_msec() < deadline:
		var b = world.battle
		var r = b.rules
		if r.finished:
			directions([])
			await process_frame
			continue
		var target: Vector2 = r.boss_position
		var enemies = r.minions.filter(func(m):return m.hp > 0)
		if not enemies.is_empty():target = enemies[0].position
		else:
			var nodes = r.nodes.filter(func(n):return not n.done)
			if not nodes.is_empty():target = nodes[0].position
		var diff = target - b.player_position
		var codes: Array = []
		if absf(diff.x) > .45:codes.append(KEY_D if diff.x > 0 else KEY_A)
		if absf(diff.y) > .45:codes.append(KEY_S if diff.y > 0 else KEY_W)
		directions(codes)
		if not r.hazards.is_empty() and r.guard_cd <= 0:await tap(KEY_K)
		if diff.length() < 2:
			await tap(KEY_E)
			await tap(KEY_J)
		if r.skill_cd <= 0:await tap(KEY_1)
		if not photographed and r.elapsed > 2:
			await capture("battle-"+id)
			photographed = true
		await create_timer(.08).timeout
	directions([])
	check(not is_instance_valid(world.battle), id + " combat produces result screen within 50s")
func finish() -> void:
	if finished:return
	finished = true
	directions([])
	var failures = checks.filter(func(c):return not c.passed).size()
	var f = FileAccess.open(out.path_join("input-results.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failed":failures,"passed":checks.size()-failures,"seconds":(Time.get_ticks_msec()-started)/1000.0,"method":"Godot GL render, injected mouse + keyboard, no combat/reward state writes; AI test driver uses positions for routing; isolated save"},"\t"))
	f.close()
	print("PIXEL_WORLD_RESULT ",checks.size()," checks; ",failures," failures")
	quit(0 if failures == 0 else 1)
