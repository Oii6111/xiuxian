extends Node2D
## Small pixel-aligned effects are separate live layers, not baked into the background.
var clock: float = 0
var ripples: Array[Vector2] = [Vector2(657, 779), Vector2(789, 818), Vector2(937, 826), Vector2(1009, 739)]
var lanterns: Array[Vector2] = [Vector2(234, 363), Vector2(501, 312), Vector2(787, 412), Vector2(940, 443), Vector2(1039, 525), Vector2(1271, 701)]

func _process(delta: float) -> void:
	clock += delta
	queue_redraw()

func _draw() -> void:
	# Elliptic rune orbits on the two interactable platforms.
	_orbit(Vector2(847, 183), Vector2(70, 22), Color("ffdc78"), 1)
	_orbit(Vector2(1230, 303), Vector2(43, 58), Color("bd74f5"), -1)
	for i in range(18):
		var x = 350 + fmod(i * 89.1 + sin(clock * 0.4 + i) * 14, 880)
		var y = 420 + fmod(i * 61.0 - clock * (6 + i % 3), 320)
		var alpha = (sin(clock * 1.6 + i * 4) * 0.5 + 0.5) * 0.6
		draw_rect(Rect2(Vector2(x, y).snapped(Vector2(2, 2)), Vector2(2, 2)), Color(1, 0.92, 0.57, alpha))
	for i in range(ripples.size()):
		var radius = 4 + fmod(clock * 6 + i * 7, 21)
		var points = PackedVector2Array()
		for j in range(25):
			var angle = j * TAU / 24
			points.append((ripples[i] + Vector2(cos(angle) * radius, sin(angle) * radius * 0.3)).snapped(Vector2(2, 2)))
		draw_polyline(points, Color(0.8, 0.98, 0.95, (1 - radius / 26) * 0.5), 1)
	for i in range(lanterns.size()):
		var pulse = 0.1 + sin(clock * 2.5 + i) * 0.04
		draw_circle(lanterns[i], 11, Color(1, 0.68, 0.16, pulse))

func _orbit(center: Vector2, radius: Vector2, color: Color, direction: int) -> void:
	for i in range(12):
		var angle = clock * 0.6 * direction + i * TAU / 12
		var point = (center + Vector2(cos(angle), sin(angle)) * radius).snapped(Vector2(2, 2))
		draw_rect(Rect2(point, Vector2(3, 3)), color)
