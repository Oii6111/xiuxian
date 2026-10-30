extends RefCounted
## Original procedural, Q-proportioned 3D characters. No external art dependency.
static var materials: Dictionary = {}

static func material(color: Color) -> StandardMaterial3D:
	var key = color.to_html()
	if not materials.has(key):
		var m = StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.82
		if color.a < 1:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		materials[key] = m
	return materials[key]

static func part(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, scale_value: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var item = MeshInstance3D.new()
	item.mesh = mesh
	item.material_override = material(color)
	item.position = pos
	item.scale = scale_value
	parent.add_child(item)
	return item

static func ball(parent: Node3D, pos: Vector3, radius: float, color: Color, ratio: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	mesh.radial_segments = 16
	mesh.rings = 8
	return part(parent, mesh, pos, color, ratio)

static func box(parent: Node3D, pos: Vector3, dimensions: Vector3, color: Color) -> MeshInstance3D:
	var mesh = BoxMesh.new()
	mesh.size = dimensions
	return part(parent, mesh, pos, color)

static func cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color, top: float = -1.0) -> MeshInstance3D:
	var mesh = CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top < 0 else top
	mesh.height = height
	mesh.radial_segments = 16
	return part(parent, mesh, pos, color)

static func ring(parent: Node3D, pos: Vector3, radius: float, width: float, color: Color) -> MeshInstance3D:
	var mesh = TorusMesh.new()
	mesh.inner_radius = maxf(0.02,radius - width)
	mesh.outer_radius = radius + width
	mesh.rings = 32
	mesh.ring_segments = 6
	return part(parent, mesh, pos, color)

static func beam(parent: Node3D, from: Vector3, to: Vector3, width: float, color: Color) -> MeshInstance3D:
	var item = cylinder(parent, (from+to)*0.5,width,from.distance_to(to),color)
	if from.distance_to(to) > 0.01:
		item.quaternion = Quaternion(Vector3.UP,(to-from).normalized())
	return item

static func label(parent: Node3D, text: String, pos: Vector3, color: Color = Color.WHITE, size: int = 42) -> Label3D:
	var node = Label3D.new()
	node.text = text
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei","Noto Sans CJK SC"])
	node.font = font
	node.position = pos
	node.font_size = size
	node.pixel_size = 0.012
	node.modulate = color
	node.outline_size = 4
	node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(node)
	return node

static func hero(avatar: String) -> Node3D:
	var root = Node3D.new()
	var coat = Color("64bada") if avatar == "male" else Color("cd93d6")
	ball(root,Vector3(0,0.8,0),0.46,coat,Vector3(0.85,1.15,0.7))
	ball(root,Vector3(0,1.66,0),0.49,Color("ffe1bc"))
	ball(root,Vector3(0,1.91,0.03),0.48,Color("293b59"),Vector3(1,0.7,0.95))
	ball(root,Vector3(0,2.2,0.08),0.15,Color("293b59"))
	# Oversized eyes and a jade forehead band support Q-style readability.
	for x in [-0.18,0.18]:
		ball(root,Vector3(x,1.69,-0.435),0.055,Color("233346"),Vector3(0.75,1.3,0.45))
	for x in [-0.25,0.25]:
		var leg = box(root,Vector3(x,0.26,0),Vector3(0.28,0.40,0.40),Color("314b6b"))
		leg.name = "Leg" + str(x)
		ball(root,Vector3(x*2,0.9,-0.04),0.17,coat)
	cylinder(root,Vector3(0,0.75,0),0.39,0.10,Color("f8d98d"))
	var sword = box(root,Vector3(0.64,0.85,-0.3),Vector3(0.10,0.95,0.13),Color("e7fbff"))
	sword.rotation.z = -0.35
	ring(root,Vector3(0,0.025,0),0.57,0.035,Color("d7f8e8"))
	return root

static func beast(entry: Dictionary) -> Node3D:
	var root = Node3D.new()
	var c = Color(entry.color)
	var dark = c.darkened(0.42)
	var pale = c.lightened(0.45)
	var kind: String = entry.creature
	var eye = Color("172943")
	match kind:
		"deer","hinge":
			ball(root,Vector3(0,1.3,0),1.1,pale,Vector3(1.35,0.8,0.8))
			ball(root,Vector3(-1.1,1.95,-0.15),0.58,pale)
			for x in [-0.7,0.6]:
				for z in [-0.55,0.55]:
					beam(root,Vector3(x,0.12,z),Vector3(x,1.2,z),0.14,dark)
			for side in [-1,1]:
				var start = Vector3(-1.0,2.3,side*0.3)
				beam(root,start,start+Vector3(0.25,1.2,side*0.55),0.1,dark)
				for i in range(3):
					var p = start+Vector3(i*0.1,i*0.35,side*i*0.18)
					beam(root,p,p+Vector3(-0.45,0.4,side*0.25),0.07,dark)
			if entry.id == "b03":
				for i in range(9):
					var p = Vector3(sin(i*2.4)*1.4,2.6+float(i%3)*0.35,cos(i*2.4)*0.9)
					beam(root,Vector3(0,1.3,0),p,0.06,dark)
					ball(root,p,0.36,Color("d4eabb"))
					ball(root,p+Vector3(0.2,0.1,0),0.12,Color("fff1da"))
			elif kind == "hinge":
				for x in [-0.7,0.6]:
					ring(root,Vector3(x,1.0,0),0.42,0.09,c)
			else:
				for i in range(5):
					box(root,Vector3(-0.8+i*0.4,1.5,0),Vector3(0.18,0.4,1.7),dark)
		"boar","pangolin","rhino","ox":
			ball(root,Vector3(0,1.2,0),1.2,dark,Vector3(1.4,0.95,0.85))
			ball(root,Vector3(-1.3,1.1,-0.1),0.75,c)
			ball(root,Vector3(-1.9,0.95,-0.1),0.4,pale,Vector3(0.65,0.7,1))
			for x in [-0.8,0.7]:
				for z in [-0.6,0.6]:
					cylinder(root,Vector3(x,0.35,z),0.24,0.7,dark)
			if kind == "boar":
				for i in range(11):
					cylinder(root,Vector3(sin(i*3.1)*1.1,1.8+float(i%2)*0.3,cos(i*2.4)*0.6),0.25,0.95,Color("ff916d"),0.02)
			elif kind == "ox":
				box(root,Vector3(0.1,2.25,0),Vector3(1.9,1.1,1.5),Color("c48e52"))
				cylinder(root,Vector3(0.1,3,0),1.4,0.6,Color("68634e"),0.1)
				for i in range(4):
					ball(root,Vector3(-0.55+i*0.4,2.2,-0.8),0.16,Color("ffe29a"))
			elif kind == "rhino":
				for i in range(4):
					ring(root,Vector3(-0.5+i*0.4,1.6,0),0.65,0.12,pale)
				cylinder(root,Vector3(-1.65,1.7,0),0.25,0.7,pale,0.02)
			else:
				for i in range(8):
					var scale_node = box(root,Vector3(-0.8+float(i%4)*0.5,1.85,float(i/4)*0.6-0.3),Vector3(0.65,0.18,0.8),pale)
					scale_node.rotation.z = 0.25
		"crane","heron":
			ball(root,Vector3(0,1.6,0),0.8,pale,Vector3(1,1.1,0.8))
			beam(root,Vector3(-0.3,1.9,0),Vector3(-0.8,3.1,0),0.18,pale)
			ball(root,Vector3(-0.85,3.15,0),0.32,pale)
			var beak = cylinder(root,Vector3(-1.35,3.15,0),0.12,0.7,Color("cb9a58"),0.01)
			beak.rotation.z = PI*0.5
			for side in [-1,1]:
				beam(root,Vector3(0,1.8,side*0.3),Vector3(0.65,2.2,side*1.7),0.12,dark)
				for i in range(5):
					var feather = box(root,Vector3(0.35+i*0.16,1.8-i*0.13,side*(0.7+i*0.25)),Vector3(0.5,0.8,0.21),c if i%2==0 else pale)
					feather.rotation.x = side*0.3
				beam(root,Vector3(0.1,0.1,side*0.35),Vector3(0,1.2,side*0.35),0.065,dark)
			for i in range(3):
				ring(root,Vector3(-0.5-i*0.12,2.2+i*0.25,0),0.25,0.045,Color("b8eadc"))
		"tortoise","clam","kui":
			ball(root,Vector3(0,0.9,0),1.6,dark,Vector3(1.15,0.65,0.9))
			ball(root,Vector3(-1.65,0.7,0),0.52,c)
			for side in [-1,1]:
				for x in [-0.9,0.9]:
					ball(root,Vector3(x,0.25,side*1.0),0.4,c,Vector3(1.0,0.5,0.8))
			if kind == "tortoise":
				for i in range(5):
					cylinder(root,Vector3(sin(i*2.4)*0.85,1.8,cos(i*2.4)*0.65),0.55,1.1+float(i%2)*0.5,Color("7a93a6"),0.04)
					ring(root,Vector3(0,1.0,0),1.35,0.04,Color("a5e5ff"))
			elif kind == "clam":
				for i in range(5):
					ring(root,Vector3(0,1.25+i*0.12,0),1.3-i*0.18,0.08,pale)
				ball(root,Vector3(0,1.8,0),0.42,Color("d7faff"))
			else:
				for side in [-1,1]:
					var wheel = ring(root,Vector3(0.0,1.7,side*1.0),0.65,0.16,pale)
					wheel.rotation.x = PI*0.5
		"serpent","dragon","fish":
			for i in range(9):
				var p = Vector3(-1.6+i*0.4,0.9+sin(i*0.7)*0.3,cos(i*0.7)*0.5)
				ball(root,p,0.55 if kind!="fish" else 0.42,c if i%2==0 else dark)
			ball(root,Vector3(-2,1.2,0.4),0.65,pale)
			for side in [-1,1]:
				beam(root,Vector3(-1.9,1.6,0.4+side*0.25),Vector3(-1.55,2.3,0.4+side*0.65),0.07,Color("efd69a"))
			if kind == "fish":
				for i in range(6):
					box(root,Vector3(-0.6+i*0.3,1.65,0),Vector3(0.24,0.55,0.65),Color("f2e4bd"))
		"astrolabe":
			for i in range(4):
				var r = ring(root,Vector3(0,1.7,0),1.2+i*0.18,0.10,[c,Color("eacb85"),pale,dark][i])
				r.rotation = Vector3(i*0.7,0,i*0.9)
			ball(root,Vector3(0,1.7,0),0.65,Color("ffe5a1"))
		_:
			ball(root,Vector3(0,1.3,0),0.65,c)
			for side in [-1,1]:
				var wing = ball(root,Vector3(0,1.4,side*0.9),0.9,pale,Vector3(0.7,0.2,1))
				wing.rotation.x = side*0.3
			if kind == "moon":
				ring(root,Vector3(0,2.0,0),0.95,0.10,Color("f7dda4"))
			if kind == "cicada":
				cylinder(root,Vector3(0,1.5,0),0.6,0.7,Color("d3ac6d"))
	# A clear face and grounded contact ring unify the cartoon cast.
	ball(root,Vector3(-1.1,1.55,-0.58),0.085,eye)
	ring(root,Vector3(0,0.025,0),1.55,0.035,Color(c,0.35))
	return root

static func minion(entry: Dictionary) -> Node3D:
	var root = Node3D.new()
	var c = Color(entry.color)
	var dark = c.darkened(0.35)
	var light = c.lightened(0.30)
	var kind: String = entry.kind
	ball(root,Vector3(0,0.5,0),0.44,c,Vector3(1.1,0.9,0.85))
	for side in [-1,1]:
		ball(root,Vector3(side*0.18,0.62,-0.34),0.065,Color("24394d"))
	match kind:
		"sprout":
			beam(root,Vector3(0,0.8,0),Vector3(0,1.35,0),0.045,dark)
			for side in [-1,1]:
				var leaf = ball(root,Vector3(side*0.25,1.16,0),0.28,light,Vector3(1.2,0.22,0.65))
				leaf.rotation.z = side*0.35
		"paperbug":
			for i in range(3):
				box(root,Vector3(-0.3+i*0.3,0.75,0),Vector3(0.23,0.12,0.7),light)
			for side in [-1,1]:
				beam(root,Vector3(side*0.2,0.7,-0.25),Vector3(side*0.4,1,-0.5),0.025,dark)
		"ferret":
			ball(root,Vector3(0,0.6,-0.35),0.32,light)
			var tail = ball(root,Vector3(0,0.65,0.6),0.34,dark,Vector3(0.5,1,1.5))
			tail.rotation.x = 0.5
			ball(root,Vector3(0,0.9,0.85),0.15,Color("ffe7a0"))
		"goat":
			for side in [-1,1]:
				var horn = cylinder(root,Vector3(side*0.22,1.0,-0.12),0.12,0.5,light,0.01)
				horn.rotation.z = side*0.3
				cylinder(root,Vector3(side*0.28,0.16,0),0.13,0.3,dark)
		"badger":
			box(root,Vector3(0,0.8,0),Vector3(0.7,0.15,0.6),light)
			box(root,Vector3(0,0.6,-0.39),Vector3(0.17,0.25,0.06),dark)
		"mouse":
			for side in [-1,1]:
				ball(root,Vector3(side*0.32,0.97,0),0.23,light,Vector3(1,1,0.3))
			ball(root,Vector3(0,0.32,-0.45),0.24,Color("ffe5a1"))
		"paperbird","bellbird":
			for side in [-1,1]:
				var wing = box(root,Vector3(side*0.5,0.65,0),Vector3(0.75,0.09,0.5),light)
				wing.rotation.z = side*0.25
			if kind=="bellbird":
				ring(root,Vector3(0,0.3,0),0.34,0.06,Color("d5c18f"))
			cylinder(root,Vector3(0,0.58,-0.5),0.10,0.25,dark,0.01).rotation.x = PI*0.5
		"tadpole":
			for i in range(3):
				ball(root,Vector3(0,0.4,0.35+i*0.23),0.18-float(i)*0.04,dark)
		"turtle":
			ball(root,Vector3(0,0.75,0.12),0.50,dark,Vector3(1,0.55,1))
			for i in range(3):
				ball(root,Vector3(sin(i*2.1)*0.25,0.99,cos(i*2.1)*0.2),0.12,light)
	ring(root,Vector3(0,0.03,0),0.55,0.025,Color("e7f9dc"))
	return root

static func npc(entry: Dictionary) -> Node3D:
	var root = hero("female" if entry.id in ["tinglan","suniang","ahe"] else "male")
	match str(entry.id):
		"lei":
			cylinder(root,Vector3(0,2.15,0),0.58,0.3,Color("b9d1bc"),0.10)
		"tinglan":
			beam(root,Vector3(0.65,0.2,0),Vector3(0.65,2.1,0),0.045,Color("deb784"))
		"hesheng":
			box(root,Vector3(-0.5,1,-0.3),Vector3(0.4,0.3,0.14),Color("d8c39a"))
		"suniang":
			ball(root,Vector3(-0.5,1.1,-0.3),0.22,Color("e5efe3"))
		"taobo":
			ball(root,Vector3(-0.45,0.95,-0.2),0.23,Color("bc8669"))
		"ahe":
			for i in range(3):
				ball(root,Vector3(-0.45,1.1+i*0.12,-0.25),0.13,Color("d8b4d7"))
	return root

static func model(entry: Dictionary, folder: String) -> Node3D:
	var path = "res://assets/generated/" + folder + "/" + str(entry.id) + ".tscn"
	if ResourceLoader.exists(path):
		var scene = load(path)
		if scene is PackedScene:
			return scene.instantiate()
	if folder == "bosses":
		return beast(entry)
	if folder == "minions":
		return minion(entry)
	return npc(entry)
