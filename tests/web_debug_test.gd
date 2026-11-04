extends SceneTree
## Regression coverage for the first web-debug batch. Preview state never writes player data.
const Icon = preload("res://scripts/equipment_icon.gd")
var passed = 0
var failed = 0
var game: Node2D

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if ok:
		passed += 1
		print("PASS: ", message)
	else:
		failed += 1
		push_error(message)

func press_e() -> void:
	var event = InputEventKey.new()
	event.physical_keycode = KEY_E
	event.keycode = KEY_E
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func screenshot(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var path = "res://work/debug-series/" + filename
	check(root.get_texture().get_image().save_png(path) == OK, "Capture " + filename)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://work/debug-series"))
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.player.set_physics_process(false)
	game.family.persist_enabled = false
	game.state.persist_enabled = false
	check(ProjectSettings.get_setting("application/config/name") == "疯狂修仙，中", "Visible product name uses the requested title")
	if OS.has_feature("windows"):
		check(OS.get_user_data_dir().replace("\\", "/").ends_with("/Godot/app_userdata/家族修真录 · 像素仙村"), "Renaming preserves the existing Windows save/session directory")
	# The real physical key goes through input dispatch, including after a HUD button has focus.
	game.player.position = Vector2(275,503)
	game.nearest = ""
	var hud_button = game.ui.find_children("*", "Button", true, false)[0]
	hud_button.grab_focus()
	await press_e()
	check(game.ui.modal_open and is_instance_valid(game.ui.treasure), "Physical E opens a building with focused HUD and stale proximity")
	await screenshot("wish-preview.png")
	var treasure = game.ui.treasure
	await press_e()
	check(game.ui.treasure == treasure and game.ui.modal_open, "E cannot replace an active modal")
	game.ui.close_modal()
	var positions = [Vector2(810,560), Vector2(430,480), Vector2(1150,640)]
	for i in range(3):
		game.player.position = positions[i]
		game.update_nearest()
		check(game.can_stand(positions[i]) and game.nearest == "npc_%d" % i, "NPC %d has a reachable E interaction point" % i)
		game.ui.update_proximity(game.nearest)
		check("对话" in game.ui.hint.text, "NPC %d displays a dialogue hint" % i)
		await press_e()
		check(game.ui.modal_open and game.player.blocked, "Physical E opens NPC %d dialogue" % i)
		if i == 0:
			await screenshot("npc-dialogue.png")
		game.ui.close_modal()
	game.player.position = game.SPAWN
	await press_e()
	check(not game.ui.modal_open, "E away from a target does not open an unrelated panel")
	# Sample every navigation edge in both directions, including the entire bridge.
	var routes_ok = true
	for id in game.navigation.get_point_ids():
		for other in game.navigation.get_point_connections(id):
			var start = game.navigation.get_point_position(id)
			var end = game.navigation.get_point_position(other)
			var cursor = start
			for step in range(ceili(start.distance_to(end) / 2.0)):
				var motion = (end - cursor).limit_length(2.0)
				cursor += game.walk_motion(cursor, motion)
				if not game.can_stand(cursor):
					routes_ok = false
			if cursor.distance_to(end) > 0.1:
				routes_ok = false
				print("BLOCKED EDGE ", id, " -> ", other, " at ", cursor)
	check(routes_ok, "All navigation routes remain traversable in both directions with the full footprint")
	# Sweep diagonally from every walkable sample around both banks; simulate low frame rates.
	var sweep_ok = true
	var exercised = 0
	for x in range(760,1200,12):
		for y in range(540,760,12):
			var origin = Vector2(x,y)
			if not game.can_stand(origin):
				continue
			for motion in [Vector2(35,35),Vector2(35,-35),Vector2(-35,35),Vector2(-35,-35),Vector2(180,0)]:
				var destination = origin + game.walk_motion(origin,motion)
				sweep_ok = sweep_ok and game.can_stand(destination)
				exercised += 1
	check(sweep_ok and exercised > 100, "Bank/diagonal/large-frame movement stays on land (%d sweeps)" % exercised)
	check(not game.can_stand(Vector2(850,780)) and not game.can_stand(Vector2(740,820)), "Water beside the bridge remains impassable")
	game.player.last_safe_position = Vector2(939,668)
	game.player.position = Vector2(850,780)
	game.player.route = PackedVector2Array([Vector2(850,780)])
	game.player.destination_site = "records"
	game.player._physics_process(1.0 / 60)
	check(game.player.position.distance_to(Vector2(939,668)) < 0.1 and game.player.route.is_empty(), "An invalid water position recovers to the last safe bridge position")
	game.player.last_safe_position = Vector2(-999,-999)
	game.player.position = Vector2(850,780)
	game.player._physics_process(1.0 / 60)
	check(game.can_stand(game.player.position), "Recovery also works when the saved fallback position is invalid")
	# Real card -> detail, with the exact item rather than a slot-only silhouette.
	game.state.apply_health_profile(game.state.HealthProfile.mock(40,1))
	game.state.equipment.inventory = []
	for t in range(5):
		for r in range(5):
			game.state.equipment.inventory.append({"id":"gear_%06d" % (t*5+r+1),"template":t,"rarity":r})
	game.ui.open_treasure()
	treasure = game.ui.treasure
	treasure.selected_id = "gear_000005"
	treasure.switch_tab("bag")
	await process_frame
	var preview = treasure.find_child("EquipmentDetailPreview",true,false)
	check(preview != null and preview.rarity == 4 and preview.template == 0, "Selected equipment opens a matching large illustrated preview")
	var panels_fit = true
	for child in treasure.get_children():
		if child is PanelContainer:
			panels_fit = panels_fit and child.get_global_rect().end.y <= 865
	check(panels_fit, "Probability and detail panels fit inside the pavilion backdrop")
	var cards_fit = true
	for card in treasure.find_children("*", "Button", true, false):
		if card.tooltip_text.ends_with("点击查看与穿戴"):
			var column = card.get_child(0)
			var foot = column.get_child(column.get_child_count()-1)
			cards_fit = cards_fit and foot.get_global_rect().end.y <= card.get_global_rect().end.y
	check(cards_fit, "Equipment card names, bonuses and footers remain inside their cards")
	await screenshot("equipment-bag.png")
	game.ui.close_modal()
	# Render every template/quality together for visual review.
	var sheet = ColorRect.new()
	sheet.color = Color("191d25")
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.ui.add_child(sheet)
	for t in range(5):
		for r in range(5):
			var icon = Icon.new()
			icon.setup({"id":"preview","template":t,"rarity":r})
			icon.position = Vector2(150+r*235,30+t*169)
			icon.size = Vector2(150,140)
			sheet.add_child(icon)
			var label = Label.new()
			label.text = Icon.Rules.TEMPLATES[t].names[r]
			label.position = icon.position + Vector2(-20,135)
			label.size.x = 190
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			sheet.add_child(label)
	await screenshot("equipment-catalogue.png")
	game.queue_free()
	await process_frame
	print("WEB DEBUG TESTS: ", passed, " passed, ", failed, " failed")
	quit(0 if failed == 0 else 1)
