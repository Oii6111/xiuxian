extends SceneTree

const Scenery = preload("res://scripts/ink/scenery.gd")
const HeroModel = preload("res://scripts/ink/hero_model.gd")

func _initialize() -> void:
	call_deferred("build")

func assign_owner(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		if child.scene_file_path.is_empty():
			assign_owner(child, root)

func save_scene(node: Node, path: String) -> void:
	assign_owner(node, node)
	var packed := PackedScene.new()
	var result := packed.pack(node)
	if result == OK:
		result = ResourceSaver.save(packed, path)
	if result != OK:
		push_error("Could not save scene: %s (%d)" % [path, result])
		quit(1)
	print("INK_BUILT ", path, " nodes=", node.get_child_count())
	node.free()

func environment(root: Node3D) -> void:
	var env := WorldEnvironment.new()
	var atmosphere := Environment.new()
	atmosphere.background_mode = Environment.BG_CANVAS
	atmosphere.background_canvas_max_layer = -1
	atmosphere.background_color = Color("e9e8d9")
	atmosphere.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	atmosphere.ambient_light_color = Color("f2f1e9")
	atmosphere.ambient_light_energy = 0.45
	atmosphere.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	atmosphere.fog_enabled = true
	atmosphere.fog_light_color = Color("e8e9d9")
	atmosphere.fog_density = 0.0028
	env.environment = atmosphere
	env.name = "InkAtmosphere"
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.name = "AfternoonSun"
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_color = Color("fff9ef")
	sun.light_energy = 0.50
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 75
	sun.shadow_bias = 0.05
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	root.add_child(sun)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 27
	camera.position = Vector3(0, 25, 24)
	camera.rotation_degrees.x = -46
	camera.far = 160
	camera.current = true
	root.add_child(camera)

func build() -> void:
	DirAccess.make_dir_recursive_absolute("res://scenes/ink")
	var hero: CharacterBody3D = HeroModel.new().build()
	save_scene(hero, "res://scenes/ink/songfeng.tscn")
	for index in range(6):
		var world := Node3D.new()
		world.name = "SongfengHome" if index == 0 else "Trial%d" % index
		world.set_script(load("res://scripts/ink/world.gd"))
		world.set_meta("scene_index", index)
		environment(world)
		var scenery = Scenery.new()
		# The distant ink mountains use a painted backdrop; all playable geometry is 3D.
		if index == 0:
			scenery.build_hub(world)
		else:
			var stage := Node3D.new()
			stage.name = "TrialEnvironment"
			world.add_child(stage)
			scenery.build_arena(stage, index)
		var character: CharacterBody3D = load("res://scenes/ink/songfeng.tscn").instantiate()
		character.position = Vector3(0, 0.12, 2.0 if index == 0 else 4.4)
		world.add_child(character)
		save_scene(world, "res://scenes/main.tscn" if index == 0 else "res://scenes/ink/trial_%d.tscn" % index)
	print("INK_BUILD_COMPLETE")
	quit()
