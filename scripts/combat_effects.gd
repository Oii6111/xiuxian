extends Node2D
## Pixel-snapped 2D ink, cloud and jade effects; no 3D resources.
var view: Control

func _process(_delta: float) -> void:
	queue_redraw()

func ellipse(center: Vector2, radius: Vector2, color: Color, width: float = 2) -> void:
	var points = PackedVector2Array()
	for i in range(49):
		var angle = i * TAU / 48
		points.append((center + Vector2(cos(angle), sin(angle)) * radius).snapped(Vector2(3, 3)))
	draw_polyline(points, color, width)

func cloud(center: Vector2, scale_value: float, alpha: float) -> void:
	for i in range(3):
		var points = PackedVector2Array()
		for j in range(20):
			var angle = j * TAU / 19
			var radius = 4 + j * 0.75
			points.append((center + Vector2((i - 1) * 20 + cos(angle) * radius, sin(angle) * radius * 0.6) * scale_value).snapped(Vector2(3, 3)))
		draw_polyline(points, Color(0.72, 0.94, 0.9, alpha), 3)

func bolt(from: Vector2, to: Vector2, time: float) -> void:
	var points = PackedVector2Array()
	for i in range(13):
		var point = from.lerp(to, i / 12.0)
		if i > 0 and i < 12:
			point.x += sin(i * 31.3 + floor(time * 20)) * 28
		points.append(point.snapped(Vector2(3, 3)))
	draw_polyline(points, Color(0.7, 0.38, 0.9, 0.2), 18)
	draw_polyline(points, Color(view.encounter.color).lightened(0.25) if not view.encounter.is_empty() else Color("d69df0"), 4)

func _draw() -> void:
	if not is_instance_valid(view) or not is_instance_valid(view.hero):
		return
	var rules = view.rules
	var time: float = view.clock
	var hero: Vector2 = view.hero.position
	if rules.phase in ["windup", "breath"] and not rules.finished:
		var target: Vector2 = rules.target_position
		var area = PackedVector2Array()
		for j in range(49):
			var angle = j * TAU / 48
			area.append((target + Vector2(cos(angle) * rules.attack_radius.x, sin(angle) * rules.attack_radius.y)).snapped(Vector2(2, 2)))
		draw_colored_polygon(area, Color(1, 0.23, 0.19, 0.2 + sin(time * 13) * 0.06))
		area.append(area[0])
		draw_polyline(area, Color("ff7355"), 2)
		if rules.phase == "breath":
			for i in range(3):
				bolt(view.boss_anchor + Vector2(-60, -view.boss_height * 0.55), target + Vector2(0, -65 + (i - 1) * 16), time + i)
	# The jade buckle is a character detail, not an equipment system.
	var jade = (hero + Vector2(10, -64)).snapped(Vector2(2, 2))
	draw_rect(Rect2(jade - Vector2(8, 8), Vector2(16, 18)), Color("a4d6aa"))
	draw_rect(Rect2(jade - Vector2(5, 5), Vector2(10, 12)), Color("416f5b"))
	var active = rules.heal_cast > 0 or view.heal_visual > 0
	var eye_color = Color("ffdf9c") if active else Color("bed7a6")
	draw_rect(Rect2(jade + Vector2(-5, -3), Vector2(3, 3)), eye_color)
	draw_rect(Rect2(jade + Vector2(3, -3), Vector2(3, 3)), eye_color)
	draw_rect(Rect2(jade + Vector2(-2, 3), Vector2(5, 3)), Color("1f4239"))
	if rules.shield_time > 0 and rules.shield_hp > 0:
		var center = hero + Vector2(0, -74)
		ellipse(center, Vector2(63, 83), Color("b4e5e3"), 4)
		ellipse(center, Vector2(68, 88), Color(0.65, 0.9, 0.9, 0.2), 7)
		for i in range(3):
			var angle = time * 1.9 + i * TAU / 3
			cloud(center + Vector2(cos(angle) * 58, sin(angle) * 73), 0.55, 0.9)
		if view.shield_impact > 0:
			ellipse(center, Vector2(74, 94) * (1.0 + (0.6 - view.shield_impact) * 0.3), Color(0.12, 0.3, 0.28, view.shield_impact), 5)
	if view.shield_break_visual > 0:
		var spread = (0.55 - view.shield_break_visual) * 95
		for i in range(6):
			var angle = i * TAU / 6
			cloud(hero + Vector2(0, -70) + Vector2(cos(angle), sin(angle)) * (45 + spread), 0.45, view.shield_break_visual)
	if view.dodge_visual > 0:
		for i in range(4):
			var point: Vector2 = view.dodge_origin.lerp(hero, i / 4.0)
			cloud(point + Vector2(0, -16), 1.0 - i * 0.12, view.dodge_visual * (1.6 - i * 0.2))
		cloud(hero + Vector2(0, 2), 1.2, view.dodge_visual * 1.8)
	if view.cast_visual > 0:
		var travel = 1.0 - view.cast_visual / view.cast_duration
		var length = 720.0 if view.sword_visual else 120.0
		var center: Vector2 = view.cast_origin + view.cast_direction * length * travel
		var angle: float = view.cast_direction.angle()
		var arc = PackedVector2Array()
		for i in range(25):
			var a = angle - 1.15 + i * 2.3 / 24
			arc.append((center + Vector2(cos(a), sin(a)) * (68 if view.sword_visual else 47)).snapped(Vector2(3, 3)))
		draw_polyline(arc, Color(0.18, 0.35, 0.3, 0.5), 15 if view.sword_visual else 8)
		draw_polyline(arc, Color("8fd0b4"), 7 if view.sword_visual else 3)
		if view.sword_visual:
			draw_polyline(arc, Color("d0efd0"), 2)
			for i in range(8):
				var leaf = center + Vector2(sin(i * 2.2 + time * 8) * 60 - i * 12, (i - 4) * 13)
				leaf = leaf.snapped(Vector2(3, 3))
				draw_colored_polygon(PackedVector2Array([leaf, leaf + Vector2(12, -3), leaf + Vector2(21, 3), leaf + Vector2(9, 6)]), Color("6f9d79"))
	if active:
		var alpha = 0.85 if rules.heal_cast > 0 else view.heal_visual
		for i in range(14):
			var angle = i * TAU / 14 + time * 1.7
			var radius = 20 + fmod(i * 11.0 + time * 55, 110)
			var point = jade + Vector2(cos(angle) * radius, sin(angle) * radius * 0.7)
			draw_rect(Rect2(point.snapped(Vector2(3, 3)), Vector2(4, 4)), Color(0.58, 0.91, 0.72, alpha))
		cloud(hero + Vector2(0, -17), 1.4, alpha)
		ellipse(jade, Vector2(20, 24), Color(1, 0.86, 0.58, alpha), 4)
		if view.heal_visual > 0:
			ellipse(hero + Vector2(0, -70), Vector2(55, 78), Color(0.72, 1, 0.75, view.heal_visual), 5)
