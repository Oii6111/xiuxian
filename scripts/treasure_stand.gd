extends Node2D
## A small physical treasure stand at the existing village shop's doorstep.
var elapsed = 0.0

func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()

func _draw() -> void:
	var glow = Color(1.0, 0.79, 0.35, 0.16 + sin(elapsed * 2.0) * 0.05)
	draw_ellipse_shadow()
	draw_circle(Vector2(0, -22), 38, glow)
	draw_rect(Rect2(-30, -38, 60, 33), Color("342824"))
	draw_rect(Rect2(-27, -35, 54, 27), Color("8b542e"))
	draw_rect(Rect2(-29, -44, 58, 13), Color("c58b45"))
	draw_rect(Rect2(-25, -40, 50, 6), Color("f3c775"))
	for x in [-21, 16]:
		draw_rect(Rect2(x, -38, 5, 30), Color("d7a45d"))
	draw_rect(Rect2(-5, -31, 10, 13), Color("ffe4a0"))
	draw_rect(Rect2(-2, -27, 4, 6), Color("62402c"))
	for i in range(5):
		var p = Vector2(sin(elapsed * 0.6 + i * 1.7) * 32, -35 - fmod(elapsed * 15 + i * 14, 58))
		draw_rect(Rect2(p, Vector2(3, 3)), Color(1, 0.86, 0.48, 0.6))

func draw_ellipse_shadow() -> void:
	var points = PackedVector2Array()
	for i in range(24):
		var angle = TAU * i / 24.0
		points.append(Vector2(cos(angle) * 39, sin(angle) * 12))
	draw_colored_polygon(points, Color(0.1, 0.08, 0.05, 0.35))
