extends RefCounted

var materials: Dictionary = {}
var random := RandomNumberGenerator.new()
const INK = preload("res://assets/ink/ink_material.gdshader")
const CLOTH = preload("res://assets/ink/cloth.gdshader")
const SAGE = Color("8baf98")
const JADE = Color("4f8273")
const DARK = Color("344b46")
const IVORY = Color("e7e1cb")
const GOLD = Color("b4a476")

func _init() -> void:
	random.seed = 73021

func mat(color: Color) -> ShaderMaterial:
	var key := color.to_html()
	if not materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = INK
		material.set_shader_parameter("ink_color", color.srgb_to_linear())
		materials[key] = material
	return materials[key]

func node(parent: Node, label: String, pos := Vector3.ZERO) -> Node3D:
	var item := Node3D.new()
	item.name = label
	item.position = pos
	parent.add_child(item)
	return item

func mesh(parent: Node3D, geometry: Mesh, pos: Vector3, color: Color, label := "Mesh") -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.name = label
	item.mesh = geometry
	item.material_override = mat(color)
	item.position = pos
	parent.add_child(item)
	return item

func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, label := "Timber") -> MeshInstance3D:
	var geometry := BoxMesh.new()
	geometry.size = size
	return mesh(parent, geometry, pos, color, label)

func ball(parent: Node3D, pos: Vector3, size: Vector3, color: Color, label := "Stone") -> MeshInstance3D:
	var geometry := SphereMesh.new()
	geometry.radius = 0.5
	geometry.height = 1.0
	geometry.radial_segments = 16
	geometry.rings = 10
	var item := mesh(parent, geometry, pos, color, label)
	item.scale = size
	return item

func cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color, top := -1.0, sides := 32) -> MeshInstance3D:
	var geometry := CylinderMesh.new()
	geometry.bottom_radius = radius
	geometry.top_radius = radius if top < 0.0 else top
	geometry.height = height
	geometry.radial_segments = sides
	return mesh(parent, geometry, pos, color)

func ring(parent: Node3D, pos: Vector3, radius: float, thickness: float, color: Color) -> MeshInstance3D:
	var geometry := TorusMesh.new()
	geometry.inner_radius = radius - thickness
	geometry.outer_radius = radius + thickness
	geometry.rings = 64
	geometry.ring_segments = 8
	return mesh(parent, geometry, pos, color, "CloudRing")

func line(parent: Node3D, points: PackedVector3Array, width: float, color: Color) -> Node3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(points.size() - 1):
		var start := points[index]
		var end := points[index + 1]
		if start.distance_squared_to(end) < 0.000001:
			continue
		var direction := (end - start).normalized()
		var axis := direction.cross(Vector3.UP).normalized()
		if axis.length_squared() < 0.1:
			axis = direction.cross(Vector3.FORWARD).normalized()
		var other := direction.cross(axis).normalized()
		for segment in range(6):
			var a := axis * cos(segment * TAU / 6) + other * sin(segment * TAU / 6)
			var b := axis * cos((segment + 1) * TAU / 6) + other * sin((segment + 1) * TAU / 6)
			for pair in [[start + a * width, a], [end + a * width, a], [end + b * width, b], [start + a * width, a], [end + b * width, b], [start + b * width, b]]:
				surface.set_normal(pair[1])
				surface.add_vertex(pair[0])
	return mesh(parent, surface.commit(), Vector3.ZERO, color, "BrushStroke")

func cloud_scroll(parent: Node3D, center: Vector3, size: float, color: Color) -> void:
	var points := PackedVector3Array()
	for i in range(27):
		var t := float(i) / 26.0
		var angle := t * TAU * 1.25
		var radius := size * (0.1 + 0.8 * t)
		points.append(center + Vector3(cos(angle) * radius, 0, sin(angle) * radius * 0.58))
	line(parent, points, size * 0.028, color)

func collider(parent: Node3D, pos: Vector3, size: Vector3, label := "Solid") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = pos
	var shape := CollisionShape3D.new()
	var geometry := BoxShape3D.new()
	geometry.size = size
	shape.shape = geometry
	body.add_child(shape)
	parent.add_child(body)
	return body

func floor_disc(parent: Node3D, radius: float) -> void:
	var body := StaticBody3D.new()
	body.name = "WalkableGround"
	var shape := CollisionShape3D.new()
	var geometry := CylinderShape3D.new()
	geometry.radius = radius
	geometry.height = 0.4
	shape.shape = geometry
	shape.position.y = -0.2
	body.add_child(shape)
	parent.add_child(body)
	# A hidden ring of physical boundary walls keeps the cultivator on the island.
	for i in range(64):
		var angle := float(i) * TAU / 64.0
		var wall := collider(parent, Vector3(sin(angle) * radius, 0.7, cos(angle) * radius), Vector3(radius * 0.105, 2.5, 0.3), "IslandBoundary")
		wall.rotation.y = angle

func island(parent: Node3D, radius: float, color: Color = SAGE) -> void:
	cylinder(parent, Vector3(0, -0.19, 0), radius, 0.4, color, radius * 0.99, 72)
	cylinder(parent, Vector3(0, -0.56, 0), radius * 0.96, 0.6, Color("8d9e86"), radius, 56)
	for i in range(30):
		var angle := float(i) * TAU / 30.0
		var rad := radius * random.randf_range(0.78, 0.98)
		var height := random.randf_range(1.7, 4.6) * radius / 12.0
		var rock := cylinder(parent, Vector3(sin(angle) * rad, -height * 0.43 - 0.5, cos(angle) * rad), radius * 0.10, height, Color("86988b").lerp(Color("b6bda4"), random.randf()), radius * 0.15, 5)
		rock.rotation.z = random.randf_range(-0.14, 0.14)
		ball(parent, Vector3(sin(angle) * rad, -0.05, cos(angle) * rad), Vector3(1.6, 0.45, 1.4) * radius / 12.0, color)
	for i in range(9):
		var angle := i * 2.4
		var pos := Vector3(cos(angle) * radius * 0.62, -radius * 0.33, sin(angle) * radius * 0.62)
		cylinder(parent, pos, radius * 0.11, radius * 0.42, Color("7e9186"), radius * 0.27, 6)

func path(parent: Node3D, from: Vector3, to: Vector3, width := 1.7) -> void:
	var length := from.distance_to(to)
	var count := maxi(2, int(length / 0.65))
	for i in range(count + 1):
		var point := from.lerp(to, float(i) / count)
		var slab := box(parent, point + Vector3(0, 0.025, 0), Vector3(width, 0.055, 0.58), IVORY.lerp(Color("c6cbb3"), random.randf() * 0.3), "SteppingStone")
		slab.rotation.y = atan2(to.x - from.x, to.z - from.z) + random.randf_range(-0.025, 0.025)

func plaza(parent: Node3D, radius: float, color := IVORY) -> void:
	cylinder(parent, Vector3(0, 0.025, 0), radius, 0.06, color, -1, 72)
	for scale_factor in [0.98, 0.9, 0.68]:
		ring(parent, Vector3(0, 0.065, 0), radius * scale_factor, 0.015, GOLD)
	for i in range(12):
		var angle := i * TAU / 12.0
		line(parent, PackedVector3Array([Vector3(sin(angle), 0.065, cos(angle)) * Vector3(radius * 0.70, 1, radius * 0.70), Vector3(sin(angle), 0.065, cos(angle)) * Vector3(radius * 0.89, 1, radius * 0.89)]), 0.012, Color("b9b9a0"))
	cloud_scroll(parent, Vector3(0, 0.07, 0), radius * 0.4, Color("a3b69e"))

func pine(parent: Node3D, pos: Vector3, scale_factor := 1.0, foliage := Color("527b68")) -> void:
	var tree := node(parent, "InkPine", pos)
	tree.scale = Vector3.ONE * scale_factor
	line(tree, PackedVector3Array([Vector3.ZERO, Vector3(-0.12, 1.0, 0), Vector3(0.25, 2.2, 0.08), Vector3(0.1, 3.15, 0)]), 0.13, Color("686758"))
	for i in range(5):
		var angle := i * 2.39
		var point := Vector3(cos(angle) * 0.8, 1.5 + i * 0.34, sin(angle) * 0.7)
		line(tree, PackedVector3Array([Vector3(0.1, point.y - 0.4, 0), point]), 0.065, Color("686758"))
		for j in range(3):
			var offset := Vector3(cos(j * 2.1) * 0.37, j * 0.06, sin(j * 2.1) * 0.32)
			ball(tree, point + offset, Vector3(1.3, 0.46, 0.9), foliage.lerp(Color("a6b58c"), j * 0.12), "PineCanopy")
	ball(tree, Vector3(0.1, 3.25, 0), Vector3(1.5, 0.55, 1.1), foliage)

func bamboo(parent: Node3D, pos: Vector3, scale_factor := 1.0) -> void:
	var clump := node(parent, "Bamboo", pos)
	clump.scale = Vector3.ONE * scale_factor
	for i in range(4):
		var height := 2.2 + i * 0.4
		var stem := node(clump, "Stem", Vector3(i * 0.22, 0, sin(i) * 0.25))
		stem.rotation.z = (i - 1.5) * 0.055
		cylinder(stem, Vector3(0, height * 0.5, 0), 0.036, height, Color("648c64"), -1, 8)
		for j in range(1, 5):
			var y := j * height / 5.0
			cylinder(stem, Vector3(0, y, 0), 0.045, 0.035, Color("bcc797"), -1, 8)
			for sign_value in [-1.0, 1.0]:
				var leaf := ball(stem, Vector3(sign_value * 0.25, y + 0.13, 0), Vector3(0.65, 0.055, 0.13), Color("70966e"), "BambooLeaf")
				leaf.rotation.z = sign_value * 0.5

func roof(parent: Node3D, center: Vector3, width: float, depth: float) -> void:
	parent = node(parent, "Roof")
	parent.add_to_group("ink_roofs", true)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Curved tiled roof, with visibly upturned eaves.
	for side in [-1.0, 1.0]:
		for j in range(8):
			var t0 := float(j) / 8.0
			var t1 := float(j + 1) / 8.0
			var z0: float = side * depth * 0.5 * t0
			var z1: float = side * depth * 0.5 * t1
			var y0 := 0.65 * pow(1.0 - t0, 2) + 0.18 * pow(t0, 8)
			var y1 := 0.65 * pow(1.0 - t1, 2) + 0.18 * pow(t1, 8)
			var a := Vector3(-width / 2, y0, z0)
			var b := Vector3(width / 2, y0, z0)
			var c := Vector3(width / 2, y1, z1)
			var d := Vector3(-width / 2, y1, z1)
			var vertices := [a, b, c, a, c, d] if side > 0 else [c, b, a, d, c, a]
			for point in vertices:
				surface.add_vertex(point)
	surface.generate_normals()
	var item := mesh(parent, surface.commit(), center, Color("48685f"), "CurvedTileRoof")
	var double_sided := StandardMaterial3D.new()
	double_sided.albedo_color = Color("516d61")
	double_sided.cull_mode = BaseMaterial3D.CULL_DISABLED
	double_sided.roughness = 1
	item.material_override = double_sided
	for i in range(int(width / 0.18) + 1):
		var x := -width * 0.5 + i * 0.18
		for side in [-1.0, 1.0]:
			var points := PackedVector3Array()
			for j in range(9):
				var t := j / 8.0
				points.append(center + Vector3(x, 0.65 * pow(1.0 - t, 2) + 0.18 * pow(t, 8) + 0.025, side * depth * 0.5 * t))
			line(parent, points, 0.018, Color("82917a"))
	line(parent, PackedVector3Array([center + Vector3(-width * 0.56, 0.83, 0), center + Vector3(-width * 0.4, 0.70, 0), center + Vector3(width * 0.4, 0.70, 0), center + Vector3(width * 0.56, 0.83, 0)]), 0.055, DARK)

func lantern(parent: Node3D, pos: Vector3) -> void:
	line(parent, PackedVector3Array([pos + Vector3(0, 0.4, 0), pos + Vector3(0, 0.75, 0)]), 0.018, GOLD)
	ball(parent, pos, Vector3(0.32, 0.5, 0.32), Color("e6b672"), "PaperLantern")
	cylinder(parent, pos + Vector3(0, 0.23, 0), 0.14, 0.05, GOLD)
	cylinder(parent, pos - Vector3(0, 0.23, 0), 0.14, 0.05, GOLD)
	line(parent, PackedVector3Array([pos - Vector3(0, 0.25, 0), pos - Vector3(0, 0.48, 0)]), 0.025, Color("ae6750"))

func label(parent: Node3D, content: String, pos: Vector3, size := 38) -> Label3D:
	var item := Label3D.new()
	item.text = content
	item.position = pos
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["KaiTi", "STKaiti", "Microsoft YaHei"])
	item.font = font
	item.font_size = size
	item.pixel_size = 0.011
	item.modulate = Color("345b4e")
	item.outline_modulate = Color("f6efda")
	item.outline_size = 8
	item.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	item.no_depth_test = false
	item.add_to_group("ink_location_labels", true)
	parent.add_child(item)
	return item

func cloth(parent: Node3D, points: PackedVector3Array, widths: Array, color: Color) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(points.size() - 1):
		var a := points[i] + Vector3(widths[i], 0, 0)
		var b := points[i] - Vector3(widths[i], 0, 0)
		var c := points[i + 1] - Vector3(widths[i + 1], 0, 0)
		var d := points[i + 1] + Vector3(widths[i + 1], 0, 0)
		var verts := [a, b, c, a, c, d]
		var uvs := [Vector2(1, float(i) / points.size()), Vector2(0, float(i) / points.size()), Vector2(0, float(i + 1) / points.size()), Vector2(1, float(i) / points.size()), Vector2(0, float(i + 1) / points.size()), Vector2(1, float(i + 1) / points.size())]
		for j in range(6):
			surface.set_uv(uvs[j])
			surface.add_vertex(verts[j])
	surface.generate_normals()
	var item := mesh(parent, surface.commit(), Vector3.ZERO, color, "SilkRibbon")
	var material := ShaderMaterial.new()
	material.shader = CLOTH
	material.set_shader_parameter("ink_color", color.srgb_to_linear())
	item.material_override = material
	return item
