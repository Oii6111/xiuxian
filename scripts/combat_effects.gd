extends Node2D
var view: Control

func _process(_delta: float) -> void:
	queue_redraw()

func ellipse(center: Vector2, radius: Vector2, color: Color, width: float = 2) -> void:
	var points = PackedVector2Array()
	for i in range(65):
		var angle = i * TAU / 64
		points.append((center + Vector2(cos(angle), sin(angle)) * radius).snapped(Vector2(2, 2)))
	draw_polyline(points, color, width)

func bolt(from: Vector2, to: Vector2, color: Color, seed_value: float, width: float = 3) -> void:
	var points = PackedVector2Array()
	for i in range(13):
		var point = from.lerp(to, i / 12.0)
		if i > 0 and i < 12:
			point.x += sin(i * 31.3 + seed_value) * 39
		points.append(point.snapped(Vector2(2, 2)))
	draw_polyline(points, Color(color, 0.16), width * 5)
	draw_polyline(points, color, width)
	draw_polyline(points, Color("fffbdc"), 1.5)

func _draw() -> void:
	if not is_instance_valid(view):
		return
	var time: float = view.clock
	var hero: Vector2 = view.hero.position
	if view.mode == "tribulation":
		var center = Vector2(895, 553)
		ellipse(center, Vector2(210, 66), Color(1, 0.79, 0.3, 0.6))
		for i in range(24):
			var angle = i * TAU / 24 + time * 0.12
			var p = center + Vector2(cos(angle) * 205, sin(angle) * 65)
			draw_rect(Rect2(p.snapped(Vector2(2, 2)), Vector2(4, 4)), Color("ffe49c"))
		if view.shield_visual > 0 or view.rules.shield > 0:
			var dome = PackedVector2Array()
			for i in range(49):
				var angle = PI + i * PI / 48
				dome.append((center + Vector2(cos(angle) * 210, sin(angle) * 210)).snapped(Vector2(2, 2)))
			var fill = dome.duplicate()
			draw_colored_polygon(fill, Color(1, 0.77, 0.22, 0.1))
			draw_polyline(dome, Color(1, 0.8, 0.25, 0.25), 13)
			draw_polyline(dome, Color("ffdd7b"), 4)
			ellipse(center, Vector2(210, 54), Color("ffdf85"), 3)
			for ratio in [-0.7, -0.35, 0.35, 0.7]:
				var curve = PackedVector2Array()
				for j in range(25):
					var t = j / 24.0
					curve.append(center + Vector2(ratio * 210 * sqrt(1 - t * t), -210 * t))
				draw_polyline(curve, Color(1, 0.86, 0.4, 0.35), 2)
			for x in [-140, -70, 0, 70, 140]:
				var y = -sqrt(210 * 210 - x * x)
				var p = center + Vector2(x, y)
				draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), Color("fff0b5"), false, 2)
		if view.lightning_visual > 0:
			var end = Vector2(895, 341) if view.shield_visual > 0 or view.rules.shield > 0 else Vector2(895, 469)
			bolt(Vector2(930, -20), end, Color("ffdf7d"), floor(time * 18), 6)
			bolt(Vector2(690, -15), end, Color("88c6ff"), floor(time * 18) + 10, 2)
		if view.cast_visual > 0:
			bolt(hero + Vector2(35, -85), Vector2(810, 430), Color("83d1ff"), floor(time * 20), 2)
			for i in range(4):
				var p = hero + Vector2(40 + i * 18, -100 - sin(time * 5 + i) * 25)
				draw_rect(Rect2(p.snapped(Vector2(2, 2)), Vector2(12, 21)), Color("efbd53"))
				draw_line(p + Vector2(4, 4), p + Vector2(8, 16), Color("9f4b2d"), 2)
	else:
		var rules = view.rules
		if rules.phase in ["windup", "breath"] and not rules.finished:
			var target: Vector2 = rules.target_position
			var end = target - Vector2(0, 65)
			var area = PackedVector2Array()
			for j in range(49):
				var angle = j * TAU / 48
				area.append(target + Vector2(cos(angle) * 90, sin(angle) * 55))
			var color = Color(1, 0.23, 0.19, 0.21 + sin(time * 13) * 0.06)
			draw_colored_polygon(area, color)
			area.append(area[0])
			draw_polyline(area, Color("ff7355"), 2)
			if rules.phase == "breath":
				for i in range(4):
					bolt(Vector2(995, 315), end + Vector2(0, (i - 1.5) * 15), Color("cd6aff"), floor(time * 25) + i * 2, 4)
		if rules.shield_time > 0:
			ellipse(hero + Vector2(0, -73), Vector2(63, 80), Color("82ddff"), 4)
			ellipse(hero + Vector2(0, -73), Vector2(69, 85), Color(0.5, 0.84, 1, 0.22), 7)
		if rules.dodge_time > 0:
			for i in range(3):
				ellipse(hero + Vector2(-i * 20, -35), Vector2(20, 30), Color(0.5, 0.8, 1, 0.4 - i * 0.1))
		if view.cast_visual > 0:
			var origin = hero + Vector2(45, -70)
			var travel = 1 - view.cast_visual / 0.38
			var center = origin.lerp(Vector2(1100, 400), clampf(travel, 0, 1))
			draw_arc(center, 65, -1.2, 1.2, 24, Color(0.4, 0.8, 1, 0.25), 16)
			draw_arc(center, 58, -1.2, 1.2, 24, Color("bdedff"), 5)
	for i in range(12):
		var p = Vector2(180 + i * 107, 500 + sin(i * 3.5 + time * 0.5) * 180)
		draw_rect(Rect2(p.snapped(Vector2(2, 2)), Vector2(2, 2)), Color(1, 0.9, 0.5, 0.3))
