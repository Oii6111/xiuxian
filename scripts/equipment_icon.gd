extends Control
## Code-native pixel silhouettes, tinted by quality; no external asset dependency.
var slot = "weapon"
var tint = Color("ffd36b")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var scale_factor = minf(size.x, size.y) / 64.0
	draw_set_transform(size * 0.5, 0, Vector2.ONE * scale_factor)
	var dark = Color("141b25")
	var light = tint.lightened(0.35)
	match slot:
		"weapon":
			draw_colored_polygon(PackedVector2Array([Vector2(-14, 11), Vector2(12, -23), Vector2(22, -27), Vector2(20, -15), Vector2(-5, 18)]), dark)
			draw_colored_polygon(PackedVector2Array([Vector2(-10, 10), Vector2(14, -20), Vector2(18, -23), Vector2(16, -15), Vector2(-5, 13)]), tint)
			draw_line(Vector2(-5, 8), Vector2(15, -18), light, 3)
			draw_line(Vector2(-18, 9), Vector2(-2, 21), Color("c99a5f"), 5)
			draw_line(Vector2(-11, 18), Vector2(-18, 27), Color("8b5d46"), 6)
		"robe":
			var outline = PackedVector2Array([Vector2(-10, -23), Vector2(-24, -12), Vector2(-29, 1), Vector2(-15, 7), Vector2(-12, 0), Vector2(-17, 25), Vector2(17, 25), Vector2(12, 0), Vector2(15, 7), Vector2(29, 1), Vector2(24, -12), Vector2(10, -23), Vector2(0, -15)])
			draw_colored_polygon(outline, tint.darkened(0.25))
			draw_line(Vector2(-10, -21), Vector2(6, -2), light, 3)
			draw_line(Vector2(10, -21), Vector2(-6, -2), light, 3)
			draw_rect(Rect2(-12, 0, 24, 5), Color("d9b577"))
			draw_line(Vector2(0, 5), Vector2(0, 22), tint, 3)
		"boots":
			for offset in [-14, 8]:
				draw_rect(Rect2(offset, -22, 15, 31), tint.darkened(0.15))
				draw_rect(Rect2(offset, -22, 16, 6), light)
				draw_rect(Rect2(offset - 7, 5, 22, 15), tint)
				draw_rect(Rect2(offset - 8, 18, 24, 5), Color("b79362"))
		"amulet":
			draw_arc(Vector2(0, -9), 15, PI, TAU, 20, Color("c99a5f"), 3)
			draw_colored_polygon(PackedVector2Array([Vector2(0, -13), Vector2(17, 3), Vector2(0, 23), Vector2(-17, 3)]), tint.darkened(0.3))
			draw_colored_polygon(PackedVector2Array([Vector2(0, -7), Vector2(10, 3), Vector2(0, 16), Vector2(-10, 3)]), light)
			draw_line(Vector2(0, 23), Vector2(0, 29), Color("c99a5f"), 3)
			draw_rect(Rect2(-5, 27, 10, 4), tint)
