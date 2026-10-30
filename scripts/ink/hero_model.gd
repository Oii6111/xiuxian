extends RefCounted

const Library = preload("res://scripts/ink/mesh_library.gd")

func build() -> CharacterBody3D:
	var m = Library.new()
	var hero := CharacterBody3D.new()
	hero.name = "Songfeng"
	hero.set_script(load("res://scripts/ink/hero.gd"))
	hero.floor_snap_length = 0.4
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.27
	capsule.height = 1.9
	collision.shape = capsule
	collision.position.y = 0.95
	hero.add_child(collision)
	var shadow = m.cylinder(hero, Vector3(0, 0.025, 0), 0.44, 0.008, Color("788d78"))
	shadow.name = "FootShadow"
	shadow.scale.z = 0.65
	var model = m.node(hero, "Model")
	var skin := Color("dcb99b")
	var hair := Color("35433d")
	var green := Color("80a18a")
	var cream := Color("e8e0c8")
	var dark := Color("3d514a")
	# Boots and legs are separately pivoted for the walk cycle.
	for side in [-1, 1]:
		var leg = m.node(model, "LeftLeg" if side < 0 else "RightLeg", Vector3(side * 0.18, 0.94, 0))
		m.ball(leg, Vector3(0, -0.29, 0), Vector3(0.31, 0.66, 0.34), dark, "Trousers")
		m.ball(leg, Vector3(0, -0.70, 0.065), Vector3(0.29, 0.43, 0.44), Color("34443e"), "ClothBoot")
		m.box(leg, Vector3(0, -0.89, 0.09), Vector3(0.29, 0.06, 0.44), Color("a4a58c"), "BootSole")
	# Layered robe, waist belt, crossed ivory collar, and separated front panels.
	m.cylinder(model, Vector3(0, 1.27, 0), 0.34, 0.70, green, 0.39, 20)
	m.cylinder(model, Vector3(0, 0.83, -0.04), 0.52, 0.58, green, 0.32, 24)
	m.cloth(model, PackedVector3Array([Vector3(-0.13, 1.0, 0.32), Vector3(-0.21, 0.65, 0.45), Vector3(-0.30, 0.37, 0.37)]), [0.16, 0.20, 0.13], cream)
	m.cloth(model, PackedVector3Array([Vector3(0.15, 1.0, 0.32), Vector3(0.27, 0.63, 0.43), Vector3(0.37, 0.40, 0.26)]), [0.17, 0.20, 0.12], Color("a8b89a"))
	m.line(model, PackedVector3Array([Vector3(-0.25, 1.62, 0.24), Vector3(0.14, 1.27, 0.33), Vector3(0.29, 1.1, 0.29)]), 0.05, cream)
	m.line(model, PackedVector3Array([Vector3(0.24, 1.62, 0.24), Vector3(-0.10, 1.36, 0.33)]), 0.045, cream)
	var belt = m.cylinder(model, Vector3(0, 1.04, 0), 0.365, 0.13, dark, -1, 24)
	belt.scale.z = 1.05
	for side in [-1, 1]:
		var arm = m.node(model, "LeftArm" if side < 0 else "RightArm", Vector3(side * 0.33, 1.52, 0))
		arm.rotation.z = side * 0.18
		m.ball(arm, Vector3(side * 0.12, -0.22, 0), Vector3(0.38, 0.65, 0.42), cream, "LooseSleeve")
		m.cylinder(arm, Vector3(side * 0.17, -0.47, 0.03), 0.13, 0.16, dark, -1, 14)
		m.ball(arm, Vector3(side * 0.18, -0.58, 0.04), Vector3(0.18, 0.25, 0.19), skin, "Hand")
	# Mature face, swept-back hair, silver temples, eyebrows, ears and small bun.
	m.cylinder(model, Vector3(0, 1.70, 0), 0.11, 0.18, skin, -1, 16)
	m.ball(model, Vector3(0, 1.99, 0), Vector3(0.59, 0.67, 0.53), skin, "Face")
	m.ball(model, Vector3(0, 2.12, -0.09), Vector3(0.62, 0.53, 0.53), hair, "SweptHair")
	m.ball(model, Vector3(0.025, 2.40, -0.09), Vector3(0.28, 0.28, 0.29), hair, "Topknot")
	m.ring(model, Vector3(0.025, 2.34, -0.09), 0.15, 0.025, Color("9aaf8c"))
	for side in [-1, 1]:
		m.ball(model, Vector3(side * 0.29, 1.98, 0), Vector3(0.10, 0.18, 0.12), skin, "Ear")
		m.line(model, PackedVector3Array([Vector3(side * 0.25, 2.17, 0.12), Vector3(side * 0.28, 2.06, 0.11), Vector3(side * 0.26, 1.98, 0.10)]), 0.045, Color("d3d6c3"))
		m.line(model, PackedVector3Array([Vector3(side * 0.055, 2.08, 0.25), Vector3(side * 0.18, 2.10, 0.23)]), 0.018, hair)
		m.ball(model, Vector3(side * 0.12, 2.035, 0.255), Vector3(0.045, 0.05, 0.025), hair, "Eyes")
	m.ball(model, Vector3(0, 1.98, 0.277), Vector3(0.07, 0.10, 0.09), skin.lightened(0.07), "Nose")
	m.line(model, PackedVector3Array([Vector3(-0.07, 1.89, 0.244), Vector3(0.015, 1.88, 0.259), Vector3(0.08, 1.91, 0.24)]), 0.012, Color("9c7462"))
	# Short cloud scarf: real double-sided mesh, animated by the cloth shader.
	m.ball(model, Vector3(0, 1.65, -0.02), Vector3(0.78, 0.24, 0.60), Color("a2b99c"), "ScarfCollar")
	m.cloth(model, PackedVector3Array([Vector3(-0.20, 1.63, -0.16), Vector3(-0.55, 1.47, -0.55), Vector3(-0.59, 1.26, -0.96), Vector3(-0.38, 1.20, -1.35), Vector3(-0.12, 1.35, -1.55)]), [0.12, 0.15, 0.17, 0.12, 0.015], Color("9db59a"))
	m.cloth(model, PackedVector3Array([Vector3(0.17, 1.62, -0.20), Vector3(0.38, 1.54, -0.59), Vector3(0.55, 1.65, -0.94), Vector3(0.45, 1.79, -1.21)]), [0.10, 0.13, 0.10, 0.01], Color("c7d1b4"))
	m.cloth(model, PackedVector3Array([Vector3(0.02, 2.39, -0.14), Vector3(0.22, 2.39, -0.38), Vector3(0.37, 2.31, -0.60)]), [0.035, 0.045, 0.005], green)
	# Taotie buckle: a round jade beast face, with eyes, curled horns and mouth.
	var buckle = m.node(model, "TaotieBuckle", Vector3(0, 1.04, 0.38))
	var disc = m.cylinder(buckle, Vector3.ZERO, 0.15, 0.07, Color("b8b080"), -1, 24)
	disc.rotation.x = PI / 2
	var jade = m.cylinder(buckle, Vector3(0, 0, 0.04), 0.125, 0.03, Library.JADE, -1, 24)
	jade.rotation.x = PI / 2
	for side in [-1, 1]:
		m.ball(buckle, Vector3(side * 0.05, 0.025, 0.07), Vector3(0.05, 0.05, 0.025), cream)
		m.ball(buckle, Vector3(side * 0.05, 0.025, 0.085), Vector3(0.02, 0.025, 0.02), dark)
		m.line(buckle, PackedVector3Array([Vector3(side * 0.02, 0.07, 0.07), Vector3(side * 0.085, 0.095, 0.065), Vector3(side * 0.10, 0.045, 0.065)]), 0.012, Color("d6cc9f"))
	m.line(buckle, PackedVector3Array([Vector3(-0.07, -0.05, 0.07), Vector3(0, -0.075, 0.08), Vector3(0.07, -0.05, 0.07)]), 0.015, cream)
	m.line(model, PackedVector3Array([Vector3(0.29, 1.0, 0.28), Vector3(0.32, 0.64, 0.32), Vector3(0.31, 0.42, 0.29)]), 0.025, Color("b7654f"))
	# Shoulder-height floating bamboo sword, separate pivot for idle motion.
	var sword = m.node(model, "FloatingSword", Vector3(0.66, 1.70, -0.14))
	sword.rotation.z = -0.23
	m.box(sword, Vector3(0, 0.25, 0), Vector3(0.10, 0.75, 0.045), Color("b6c6ad"), "JadeBlade")
	var tip = m.cylinder(sword, Vector3(0, 0.69, 0), 0.055, 0.17, Color("cbd6bf"), 0, 4)
	tip.rotation.y = PI / 4
	m.box(sword, Vector3(0, -0.15, 0), Vector3(0.28, 0.065, 0.08), Library.GOLD)
	m.cylinder(sword, Vector3(0, -0.30, 0), 0.045, 0.25, dark, -1, 10)
	for i in range(3):
		m.ring(sword, Vector3(0, -0.23 - i * 0.06, 0), 0.047, 0.007, Library.GOLD)
	m.cloth(sword, PackedVector3Array([Vector3(0, -0.43, 0), Vector3(0.07, -0.62, -0.02), Vector3(0.10, -0.77, 0.02)]), [0.02, 0.04, 0.01], Color("b96953"))
	var outline := ShaderMaterial.new()
	outline.shader = load("res://assets/ink/hero_outline.gdshader")
	for material: ShaderMaterial in m.materials.values():
		material.next_pass = outline
	return hero
