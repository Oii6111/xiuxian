extends SceneTree

var passed := 0
var failed := 0

func check(value: bool, message: String) -> void:
	if value:
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
	check(game.can_walk(game.SPAWN), "Village spawn remains walkable")
	for point in [Vector2(620, 820), Vector2(900, 820), Vector2(1080, 820)]:
		check(not game.can_walk(point), "Pond water blocks " + str(point))
	for point in [Vector2(700, 650), Vector2(840, 685), Vector2(920, 710), Vector2(1000, 738), Vector2(1060, 720)]:
		check(game.can_walk(point), "Stone bridge remains walkable at " + str(point))
	for point in [Vector2(760, 780), Vector2(900, 760), Vector2(1120, 700)]:
		check(not game.can_walk(point), "Bridge underside/channel blocks " + str(point))
	check(not game.can_walk(Vector2(520, 700)), "Water edge requires the full player footprint to stay on land")
	game.queue_free()
	await process_frame
	print("TERRAIN COLLISION RESULT: ", passed, " passed, ", failed, " failed")
	quit(0 if failed == 0 else 1)
