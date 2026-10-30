extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS ", message)
	else:
		failures += 1
		push_error("FAIL " + message)

func physics_frames(count: int) -> void:
	for i in range(count):
		await physics_frame

func create_world(index: int) -> Node3D:
	var path := "res://scenes/main.tscn" if index == 0 else "res://scenes/ink/trial_%d.tscn" % index
	var instance: Node3D = load(path).instantiate()
	root.add_child(instance)
	current_scene = instance
	return instance

func run() -> void:
	var world := create_world(0)
	await physics_frames(8)
	var hero: CharacterBody3D = world.player
	check(hero.is_on_floor(), "Main island has a physical walkable floor")
	var spawn := hero.position
	var physical_key := InputEventKey.new()
	physical_key.physical_keycode = KEY_D
	physical_key.pressed = true
	Input.parse_input_event(physical_key)
	Input.flush_buffered_events()
	await physics_frames(35)
	physical_key.pressed = false
	Input.parse_input_event(physical_key)
	Input.flush_buffered_events()
	await physics_frames(10)
	var straight_distance := hero.position.distance_to(spawn)
	check(hero.position.x > spawn.x + 1.6, "D moves right relative to the camera")
	check(absf(hero.position.z - spawn.z) < 0.05, "Horizontal movement does not drift")
	check(hero.model.get_node("LeftLeg").rotation.x != 0, "Moving character has a leg walk cycle")
	hero.position = spawn
	hero.velocity = Vector3.ZERO
	Input.action_press("ink_right")
	Input.action_press("ink_up")
	await physics_frames(35)
	Input.action_release("ink_right")
	Input.action_release("ink_up")
	await physics_frames(10)
	var diagonal_distance := hero.position.distance_to(spawn)
	check(absf(diagonal_distance - straight_distance) < 0.18, "Diagonal movement is normalized (straight=%.3f diagonal=%.3f)" % [straight_distance, diagonal_distance])
	check(hero.position.z < spawn.z - 1.1, "W moves toward the back of the island")
	hero.position = Vector3(-7, 0.15, 1.1)
	hero.velocity = Vector3.ZERO
	Input.action_press("ink_up")
	await physics_frames(70)
	Input.action_release("ink_up")
	check(hero.position.z > -1.5 and hero.position.z < 0.0, "Cave wall blocks movement")
	hero.position = Vector3(0, 0.15, 0)
	hero.velocity = Vector3.ZERO
	Input.action_press("ink_right")
	Input.action_press("ink_run")
	await physics_frames(160)
	Input.action_release("ink_right")
	Input.action_release("ink_run")
	check(hero.position.x < 11.8 and hero.position.x > 9.5, "Island edge physically prevents falling")
	check(hero.position.y > -0.1, "Character remains on the island after edge collision")
	hero.velocity = Vector3.ZERO
	world.ui.toggle_map()
	var frozen := hero.position
	Input.action_press("ink_left")
	await physics_frames(15)
	Input.action_release("ink_left")
	check(hero.position.distance_to(frozen) < 0.05, "Map overlay pauses player movement")
	world.ui.dismiss()
	check(hero.input_enabled, "Closing map restores movement")
	world.travel(3)
	await process_frame
	await process_frame
	await physics_frames(8)
	check(current_scene.get_meta("scene_index") == 3, "Map travel loads the requested trial scene")
	current_scene.travel(0)
	await process_frame
	await process_frame
	await physics_frames(8)
	check(current_scene.get_meta("scene_index") == 0, "Return-home action restores the main island")
	current_scene.free()
	for index in range(1, 6):
		var trial := create_world(index)
		await physics_frames(8)
		check(trial.player.is_on_floor(), "Trial %d has a walkable floor" % index)
		check(trial.scene_index == index, "Trial %d has correct scene metadata" % index)
		check(trial.get_node_or_null("TrialEnvironment") != null, "Trial %d contains its own 3D environment" % index)
		trial.free()
	await process_frame
	print("INK_TEST_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
