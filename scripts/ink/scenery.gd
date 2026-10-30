extends RefCounted

const Library = preload("res://scripts/ink/mesh_library.gd")
var m = Library.new()
const TITLES = ["松风小筑", "炼气 · 山门石卫", "筑基 · 铁甲玄龟", "结丹 · 焚心妖狐", "元婴 · 逐雷鹏", "化神 · 五相劫主"]

func build_hub(parent: Node3D) -> void:
	var hub = m.node(parent, "HomeIsland")
	m.island(hub, 12.4, Color("aab99a"))
	m.floor_disc(hub, 11.75)
	m.plaza(hub, 3.0)
	for target in [Vector3(-6.2, 0, -1.0), Vector3(6.0, 0, -0.3), Vector3(0, 0, 6.3), Vector3(0, 0, -7.8)]:
		m.path(hub, target.normalized() * 2.8, target)
	build_home(hub, Vector3(-7, 0, -1.8))
	build_spirit(hub, Vector3(6.6, 0, -0.8))
	build_achievements(hub, Vector3(0, 0, 7.0))
	build_gate(hub, Vector3(0, 0, -7.8))
	for p in [Vector3(-10, 0, 2.3), Vector3(-8.5, 0, -6), Vector3(-4.2, 0, -8), Vector3(4.5, 0, -8.2), Vector3(9.4, 0, 3.3), Vector3(7, 0, 7.1), Vector3(-7.3, 0, 7.1)]:
		m.pine(hub, p, m.random.randf_range(0.85, 1.30))
	for p in [Vector3(-9, 0, -3.4), Vector3(-10, 0, -1), Vector3(-5, 0, -5.7), Vector3(8.2, 0, -4.5), Vector3(10, 0, -2.5)]:
		m.bamboo(hub, p, 1.1)
	# Jade pond, rocks, stepping stones and waterfalls.
	var pond = m.cylinder(hub, Vector3(-6.3, 0.035, 4.4), 1.75, 0.065, Color("76a99c"), -1, 48)
	pond.scale.z = 0.7
	m.ring(hub, Vector3(-6.3, 0.075, 4.4), 0.60, 0.014, Color("c8d9bd"))
	m.ring(hub, Vector3(-5.7, 0.075, 4.7), 0.28, 0.01, Color("c8d9bd"))
	for i in range(9):
		var angle := i * TAU / 9
		m.ball(hub, Vector3(-6.3 + cos(angle) * 1.75, 0.12, 4.4 + sin(angle) * 1.2), Vector3(0.5, 0.35, 0.45), Color("b3b99f"))
	for x in [-8.8, 8.4]:
		for j in range(3):
			var stream = m.box(hub, Vector3(x + j * 0.18, -1.8, 8.3 - abs(x) * 0.1), Vector3(0.15, 3.5 + j * 0.30, 0.075), Color("d6e4d3"), "Waterfall")
			stream.rotation.z = sin(j) * 0.025
	# Small flowers and meadow patches at the edge, leaving the courtyard clear.
	for i in range(65):
		var angle: float = m.random.randf() * TAU
		var radius: float = m.random.randf_range(8.6, 11.1)
		var p := Vector3(sin(angle) * radius, 0.10, cos(angle) * radius)
		m.ball(hub, p, Vector3(0.34, 0.16, 0.30), Color("95ad86"), "Meadow")
		if i % 3 == 0:
			m.ball(hub, p + Vector3(0, 0.14, 0), Vector3(0.13, 0.09, 0.13), Color("ece4c8") if i % 2 == 0 else Color("d3b0a0"), "Flower")
	for p in [Vector3(-3.8, 0.09, -3.8), Vector3(3.8, 0.09, 3.8)]:
		m.cloud_scroll(hub, p, 0.95, Color("ccd0b3"))
	# These are scenic previews; each destination also has a full-sized walkable scene.
	var positions := [Vector3(-15, 0.6, -10), Vector3(-8.5, 1.2, -16), Vector3(0, 1.6, -18), Vector3(8.5, 1.2, -16), Vector3(15, 0.6, -10)]
	for i in range(5):
		var preview = m.node(parent, "TrialPreview%d" % (i + 1), positions[i])
		preview.scale = Vector3.ONE * 0.36
		build_arena(preview, i + 1, true)
		m.label(parent, "%s" % TITLES[i + 1], positions[i] + Vector3(0, 2.7, 0), 26)

func build_home(parent: Node3D, pos: Vector3) -> void:
	var home = m.node(parent, "FamilyCave", pos)
	for i in range(8):
		var angle := i * PI / 7.0
		m.ball(home, Vector3(cos(angle) * 2.0, sin(angle) * 1.9 + 0.3, -0.7), Vector3(1.5, 1.8, 1.6), Color("9cae9c").lerp(Color("7e9585"), i / 10.0), "GrottoRock")
	m.box(home, Vector3(0, 1.0, -0.28), Vector3(3.1, 2.0, 0.45), Color("b69b75"), "TimberWall")
	m.box(home, Vector3(0, 1.0, -0.01), Vector3(1.0, 1.7, 0.05), Color("6f7860"), "Door")
	for side in [-1, 1]:
		m.box(home, Vector3(side * 1.02, 1.28, 0.03), Vector3(0.65, 0.75, 0.07), Color("e1bd7d"), "WarmWindow")
		for i in range(3):
			m.box(home, Vector3(side * 1.02 - 0.23 + i * 0.23, 1.28, 0.08), Vector3(0.035, 0.75, 0.03), Library.DARK)
		m.cylinder(home, Vector3(side * 1.65, 1.13, 0.5), 0.10, 2.25, Color("7f755b"), -1, 12)
		m.lantern(home, Vector3(side * 1.55, 1.65, 0.72))
	m.roof(home, Vector3(0, 2.22, 0), 4.1, 2.5)
	m.box(home, Vector3(0, 0.08, 0.55), Vector3(3.8, 0.15, 2.3), Library.IVORY, "Porch")
	m.collider(home, Vector3(0, 1.3, -0.5), Vector3(3.7, 2.6, 1.3), "CaveWall")
	# Tea table and two stools make the cave feel lived in.
	m.cylinder(home, Vector3(-0.8, 0.36, 1.9), 0.45, 0.09, Color("a99b74"))
	m.cylinder(home, Vector3(-0.8, 0.18, 1.9), 0.12, 0.36, Library.DARK)
	for x in [-1.55, -0.05]:
		m.cylinder(home, Vector3(x, 0.18, 2.05), 0.22, 0.34, Color("9b9272"))
	m.ball(home, Vector3(-0.8, 0.47, 1.9), Vector3(0.20, 0.14, 0.18), Color("c4cdb5"), "TeaPot")
	m.label(home, "家族洞府", Vector3(0, 3.3, 0.2))

func build_spirit(parent: Node3D, pos: Vector3) -> void:
	var platform = m.node(parent, "SpiritRootTerrace", pos)
	m.cylinder(platform, Vector3(0, 0.10, 0), 2.15, 0.2, Color("c0c9ae"), -1, 48)
	m.plaza(platform, 1.9, Color("dfdfc4"))
	for radius in [1.2, 1.65, 1.9]:
		m.ring(platform, Vector3(0, 0.23, 0), radius, 0.025, Library.JADE)
	var colors := [Color("b58163"), Color("9aaa70"), Color("7dafa9"), Color("bc9c5c"), Color("a493b2")]
	for i in range(5):
		var angle := i * TAU / 5.0
		var p := Vector3(sin(angle) * 1.35, 0.32, cos(angle) * 1.35)
		m.cylinder(platform, p, 0.26, 0.14, Library.IVORY)
		crystal(platform, p + Vector3(0, 0.32, 0), 0.38, colors[i])
	crystal(platform, Vector3(0, 1.05, 0), 1.2, Color("a4d3bc"))
	m.label(platform, "灵根测试", Vector3(0, 2.7, 0))

func crystal(parent: Node3D, pos: Vector3, height: float, color: Color) -> void:
	m.cylinder(parent, pos + Vector3(0, height * 0.10, 0), height * 0.20, height * 0.70, color, height * 0.17, 5)
	m.cylinder(parent, pos + Vector3(0, height * 0.60, 0), height * 0.17, height * 0.30, color.lightened(0.12), 0, 5)
	m.cylinder(parent, pos - Vector3(0, height * 0.35, 0), 0, height * 0.20, color.darkened(0.1), height * 0.20, 5)

func build_achievements(parent: Node3D, pos: Vector3) -> void:
	var garden = m.node(parent, "AchievementGallery", pos)
	m.box(garden, Vector3(0, 0.08, 0), Vector3(5.8, 0.16, 2.6), Library.IVORY)
	for x in [-2.4, 2.4]:
		m.cylinder(garden, Vector3(x, 1.15, -0.6), 0.10, 2.3, Color("8f8568"), -1, 12)
	m.roof(garden, Vector3(0, 2.35, -0.45), 6.0, 2.0)
	for i in range(5):
		var x := (i - 2) * 0.94
		m.box(garden, Vector3(x, 0.23, 0), Vector3(0.71, 0.20, 0.65), Color("b0b99e"))
		m.box(garden, Vector3(x, 0.99, 0), Vector3(0.57, 1.35, 0.19), Color("afc3aa"), "JadeAchievementTablet")
		m.ball(garden, Vector3(x, 1.66, 0), Vector3(0.57, 0.28, 0.19), Color("afc3aa"))
		var emblem = m.ring(garden, Vector3(x, 1.18, 0.12), 0.15, 0.025, Library.GOLD)
		emblem.rotation.x = PI / 2
		m.label(garden, ["初", "守", "同", "破", "归"][i], Vector3(x, 0.75, 0.15), 24)
		m.collider(garden, Vector3(x, 0.8, 0), Vector3(0.72, 1.6, 0.65), "TabletCollision")
	m.label(garden, "成就碑林", Vector3(0, 3.3, 0))

func build_gate(parent: Node3D, pos: Vector3) -> void:
	var gate = m.node(parent, "TrialGate", pos)
	m.plaza(gate, 2.05)
	for x in [-1.6, 1.6]:
		m.box(gate, Vector3(x, 1.85, 0), Vector3(0.42, 3.7, 0.48), Color("7c9f8a"))
		m.box(gate, Vector3(x, 0.20, 0), Vector3(0.8, 0.4, 0.8), Library.IVORY)
		m.ball(gate, Vector3(x, 3.85, 0), Vector3(0.63, 0.48, 0.55), Color("99b99b"))
		m.lantern(gate, Vector3(x * 0.8, 2.55, 0.25))
	m.box(gate, Vector3(0, 3.5, 0), Vector3(3.8, 0.3, 0.55), Library.JADE)
	m.cloud_scroll(gate, Vector3(-1.6, 3.68, 0), 0.43, Library.GOLD)
	m.cloud_scroll(gate, Vector3(1.6, 3.68, 0), 0.43, Library.GOLD)
	var portal = m.ring(gate, Vector3(0, 1.67, 0), 1.28, 0.055, Color("bad5ba"))
	portal.name = "PortalHalo"
	portal.rotation.x = PI / 2
	var inner = m.ring(gate, Vector3(0, 1.67, 0.02), 1.12, 0.02, Color("d2dfbd"))
	inner.rotation.x = PI / 2
	m.label(gate, "五境试炼", Vector3(0, 4.4, 0))
	for side in [-1, 1]:
		m.collider(gate, Vector3(side * 1.6, 1.7, 0), Vector3(0.55, 3.4, 0.6))

func build_arena(parent: Node3D, index: int, preview := false) -> void:
	var base_color: Color = [Color("acb99b"), Color("8eaf9c"), Color("baae8a"), Color("a6b6ac"), Color("a7b9ab")][index - 1]
	m.island(parent, 8.5, base_color)
	m.plaza(parent, 5.8, Color("dddcc4") if index != 4 else Color("d1d9cf"))
	if not preview:
		m.floor_disc(parent, 7.8)
		m.path(parent, Vector3(0, 0, 7), Vector3(0, 0, 5.8))
	for i in range(8):
		var angle := i * TAU / 8
		var p := Vector3(cos(angle) * 6.7, 0, sin(angle) * 6.7)
		m.cylinder(parent, p + Vector3(0, 0.38, 0), 0.18, 0.8, Library.IVORY, -1, 12)
		m.ball(parent, p + Vector3(0, 0.85, 0), Vector3(0.38, 0.24, 0.38), Library.GOLD)
	if index == 1:
		for p in [Vector3(-6, 0, -2), Vector3(5.8, 0, -3.4), Vector3(-3.8, 0, -6.6)]:
			m.bamboo(parent, p, 1.25)
		m.pine(parent, Vector3(4.7, 0, -5.6), 1.35)
		guardian(parent, Vector3(0, 0, -2.2))
	elif index == 2:
		for i in range(12):
			var angle := i * TAU / 12
			var water = m.cylinder(parent, Vector3(cos(angle) * 6.65, 0.04, sin(angle) * 6.65), 0.9, 0.05, Color("6a9b94"), -1, 20)
			water.scale.z = 0.7
		m.pine(parent, Vector3(-5, 0, -5), 1.5)
		m.pine(parent, Vector3(5, 0, -5), 1.1)
		var turtle = m.node(parent, "TurtleEffigy", Vector3(0, 0.1, -2.3))
		m.ball(turtle, Vector3(0, 0.8, 0), Vector3(3.1, 1.7, 2.6), Color("677c6b"))
		m.ball(turtle, Vector3(0, 0.4, 1.5), Vector3(0.9, 0.65, 0.85), Color("9aa38a"))
		for side in [-1, 1]:
			for z in [-0.75, 0.75]:
				m.ball(turtle, Vector3(side * 1.25, 0.25, z), Vector3(0.7, 0.5, 0.8), Color("9aa38a"))
		for r in [0.45, 0.85, 1.2]:
			m.ring(turtle, Vector3(0, 1.45 - r * 0.25, 0), r, 0.035, Library.GOLD)
	elif index == 3:
		for p in [Vector3(-5.8, 0, -3.7), Vector3(5.5, 0, -4.1), Vector3(-4, 0, 5.5), Vector3(5.5, 0, 3)]:
			m.pine(parent, p, 1.2, Color("bb7857"))
			m.ball(parent, p + Vector3(0, 0.02, 0.6), Vector3(2.0, 0.06, 1.5), Color("c3976c"))
		fox(parent, Vector3(0, 0.1, -2.3))
	elif index == 4:
		for i in range(6):
			var x := (i - 2.5) * 2.0
			var rock = m.cylinder(parent, Vector3(x, 1.0, -6), 0.8, 3 + i % 3, Color("839997"), 0.2, 5)
			rock.rotation.z = (i - 2.5) * 0.12
		var feather = m.node(parent, "ThunderFeather", Vector3(0, 0.15, -2.8))
		m.line(feather, PackedVector3Array([Vector3(0, 0, 0), Vector3(0.5, 3.8, 0), Vector3(0.2, 5, 0)]), 0.12, Library.DARK)
		for i in range(7):
			for side in [-1, 1]:
				m.line(feather, PackedVector3Array([Vector3(0.25, 0.7 + i * 0.5, 0), Vector3(side * (0.9 - i * 0.06), 1.2 + i * 0.5, 0)]), 0.12, Color("647d77"))
	else:
		var halo = m.ring(parent, Vector3(0, 3.0, -4.2), 2.7, 0.22, Color("8aac98"))
		halo.rotation.x = PI / 2
		for i in range(5):
			var angle := i * TAU / 5
			var p := Vector3(cos(angle) * 4.3, 0.8, sin(angle) * 4.3)
			m.cylinder(parent, p, 0.34, 1.6, [Color("ac895c"), Color("819873"), Color("759c9c"), Color("b17b62"), Color("93849f")][i], -1, 6)
			crystal(parent, p + Vector3(0, 1.0, 0), 0.38, Color("cdd5b9"))
		crystal(parent, Vector3(0, 1.8, -2), 2.0, Color("5f7f73"))
		m.cloud_scroll(parent, Vector3(-2, 0.1, 1.8), 1.2, Library.GOLD)
		m.cloud_scroll(parent, Vector3(2, 0.1, 1.8), 1.2, Library.GOLD)
	if not preview:
		m.label(parent, TITLES[index], Vector3(0, 5.7, -5.0), 42)
		m.label(parent, "环境预览 · 首领尚未苏醒", Vector3(0, 4.8, -5.0), 24)
		m.label(parent, "归途", Vector3(0, 1.6, 6.6), 28)
		m.ring(parent, Vector3(0, 0.13, 6.6), 0.75, 0.045, Library.GOLD)

func guardian(parent: Node3D, pos: Vector3) -> void:
	var statue = m.node(parent, "StoneGuardian", pos)
	var stone := Color("879988")
	m.cylinder(statue, Vector3(0, 0.15, 0), 1.3, 0.3, Library.IVORY, -1, 12)
	m.ball(statue, Vector3(0, 1.45, 0), Vector3(1.45, 1.6, 0.95), stone)
	m.ball(statue, Vector3(0, 2.55, 0), Vector3(1.05, 1.0, 0.9), stone)
	for side in [-1, 1]:
		m.ball(statue, Vector3(side * 0.8, 1.4, 0), Vector3(0.6, 1.2, 0.65), stone)
		m.box(statue, Vector3(side * 0.4, 0.6, 0.05), Vector3(0.55, 0.9, 0.65), stone)
		m.box(statue, Vector3(side * 0.22, 2.61, 0.43), Vector3(0.22, 0.10, 0.04), Color("d4cc9c"))
	m.cloud_scroll(statue, Vector3(0, 0.33, 0.5), 0.45, Library.GOLD)
	m.collider(statue, Vector3(0, 1.3, 0), Vector3(2.0, 2.8, 1.2), "EffigySolid")

func fox(parent: Node3D, pos: Vector3) -> void:
	var statue = m.node(parent, "FoxEffigy", pos)
	var fox_color := Color("bd7958")
	m.ball(statue, Vector3(0, 0.8, 0), Vector3(1.3, 1.35, 1.8), fox_color)
	m.ball(statue, Vector3(0, 1.5, 0.75), Vector3(0.9, 1.0, 0.9), fox_color)
	m.ball(statue, Vector3(0, 1.25, 1.25), Vector3(0.55, 0.4, 0.65), Color("dfcb9e"))
	for side in [-1, 1]:
		m.cylinder(statue, Vector3(side * 0.3, 2.10, 0.65), 0.24, 0.7, fox_color, 0.02, 4)
		m.ball(statue, Vector3(side * 0.23, 1.57, 1.11), Vector3(0.11, 0.08, 0.04), Library.DARK)
	for i in range(3):
		var tail = m.ball(statue, Vector3((i - 1) * 0.8, 1.2, -1), Vector3(0.8, 2.3, 0.8), fox_color.lightened(i * 0.06))
		tail.rotation.z = (i - 1) * -0.65
	m.collider(statue, Vector3(0, 1.1, 0), Vector3(1.7, 2.3, 2.1), "EffigySolid")

func backdrop(parent: Node3D) -> void:
	var sky = m.node(parent, "CloudSea")
	for i in range(27):
		var angle := i * 2.399
		var radius := 14.0 + (i % 5) * 6.0
		var cloud = m.ball(sky, Vector3(cos(angle) * radius, -3.6 - (i % 3) * 0.45, sin(angle) * radius), Vector3(8 + i % 4 * 1.5, 0.8, 4.0), Color("e6e7d7").lerp(Color("f0edde"), (i % 4) / 4.0), "MistBank")
		cloud.rotation.y = angle
	for i in range(17):
		var x := -55.0 + i * 6.8
		var height := 7.0 + sin(i * 8.3) * 4.0
		var mountain = m.cylinder(sky, Vector3(x, -1.2, -43 - i % 3 * 4), 4.1, height, Color("c0cec0").lerp(Color("d5dccb"), (i % 3) / 3.0), 0.25, 5)
		mountain.rotation.z = sin(i) * 0.12
