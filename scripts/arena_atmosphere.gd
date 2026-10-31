extends Node2D
## Scene-specific floor seals and ambient pixels over the shared regional art.
var view: Control

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(view) or view.encounter.is_empty():
		return
	var data: Dictionary = view.encounter
	var color = Color(data.color)
	var variant: int = int(data.index) % 4
	var center = Vector2(820 + (variant - 1.5) * 22, 555)
	var ring = PackedVector2Array()
	for i in range(65):
		var a = i * TAU / 64
		ring.append((center + Vector2(cos(a) * (150 + variant * 16), sin(a) * 53)).snapped(Vector2(3, 3)))
	draw_polyline(ring, Color(color, 0.23), 3)
	for i in range(5 + variant):
		var a = i * TAU / (5 + variant) + 0.15 * variant
		var point = center + Vector2(cos(a) * (150 + variant * 16), sin(a) * 53)
		draw_rect(Rect2(point.snapped(Vector2(3, 3)) - Vector2(4, 4), Vector2(8, 8)), Color(color, 0.5), false, 2)
	# Ambient movements vary in placement/speed with each encounter, without hiding warnings.
	for i in range(23):
		var x = fmod(i * 173.0 + data.index * 47 + sin(view.clock * 0.3 + i) * 24, 1400)
		var y = 200 + fmod(i * 83.0 - view.clock * (10 + variant * 5) + data.index * 29, 485)
		var size_value = Vector2(6, 3) if data.region == "木" else Vector2(3, 3)
		draw_rect(Rect2(Vector2(x, y).snapped(Vector2(3, 3)), size_value), Color(color, 0.4))
