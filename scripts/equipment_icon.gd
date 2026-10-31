extends Control
## Equipment illustrations: distinct materials, ornaments and auras by template and quality.
const Rules = preload("res://scripts/equipment_rules.gd")
const INK = Color("101522")
const GOLD = Color("e8b96e")
var slot = "weapon"
var tint = Color("ffd36b")
var rarity = 0
var template = 0
var clock = 0.0

func setup(item: Dictionary) -> void:
	var info = Rules.detail(item)
	slot = info.slot
	tint = info.color
	rarity = info.rarity
	template = int(item.template)
	set_process(rarity >= 2)
	queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	set_process(rarity >= 2)

func _process(delta: float) -> void:
	if is_visible_in_tree():
		clock += delta
		queue_redraw()

func poly(points: Array, color: Color, outline: bool = true) -> void:
	var vertices = PackedVector2Array()
	for p in points:
		vertices.append(Vector2(p[0], p[1]))
	draw_colored_polygon(vertices, color)
	if outline:
		vertices.append(vertices[0])
		draw_polyline(vertices, INK, 1.5)

func gem(center: Vector2, radius: float, color: Color) -> void:
	var x = center.x
	var y = center.y
	poly([[x,y-radius],[x+radius*0.7,y],[x,y+radius],[x-radius*0.7,y]], GOLD)
	poly([[x,y-radius+2],[x+radius*0.45,y],[x,y+radius-2],[x-radius*0.45,y]], color, false)
	draw_line(Vector2(x,y-radius+2), Vector2(x-2,y), Color("f5ffff"), 1.5)

func _draw() -> void:
	var scale_factor = minf(size.x, size.y) / 96.0
	draw_set_transform(size * 0.5, 0, Vector2.ONE * scale_factor)
	for ring in range(5, 0, -1):
		draw_circle(Vector2.ZERO, 15 + ring * 5, Color(tint, 0.018 + rarity * 0.006))
	if rarity >= 2:
		draw_arc(Vector2.ZERO, 36, 0, TAU, 48, Color(tint, 0.22), 1)
		for i in range(4 + rarity):
			var angle = i * TAU / (4 + rarity) + clock * 0.18
			var p = Vector2.from_angle(angle) * (36 + sin(clock * 1.5 + i) * 3)
			var glow = Color(tint.lightened(0.5), 0.55 + sin(clock * 2 + i) * 0.25)
			draw_line(p - Vector2(2,0), p + Vector2(2,0), glow, 1.5)
			draw_line(p - Vector2(0,2), p + Vector2(0,2), glow, 1.5)
	match slot:
		"weapon": draw_sword()
		"robe": draw_robe()
		"boots": draw_boots()
		"amulet": draw_amulet()

func draw_sword() -> void:
	var blade_colors = [Color("b6d5ac"), Color("b7e1ed"), Color("d8c9ff"), Color("fff0b8"), Color("ffe3ed")]
	var steel: Color = blade_colors[rarity]
	poly([[0,-39],[7,-26],[6,13],[-6,13],[-7,-26]], steel)
	poly([[0,-36],[0,12],[5,12],[5,-25]], tint.darkened(0.15), false)
	draw_line(Vector2(-3,-25), Vector2(-3,10), Color("f5ffff"), 1.8)
	if rarity == 0:
		for y in [-19,-8,3]:
			draw_line(Vector2(-5,y),Vector2(5,y),Color("608c6c"),2)
	if rarity >= 2:
		poly([[-5,-6],[-17,-18],[-12,0],[-5,9]], tint.darkened(0.3))
		poly([[5,-6],[17,-18],[12,0],[5,9]], tint)
		gem(Vector2(0,-12),5,tint)
	poly([[-18,11],[-12,8],[-6,12],[6,12],[12,8],[18,11],[12,17],[-12,17]], GOLD)
	draw_rect(Rect2(-3,17,6,14), Color("5b3f64"))
	for y in [19,24,29]:
		draw_line(Vector2(-3,y),Vector2(3,y-2),GOLD,1.5)
	gem(Vector2(0,14),5,tint)
	gem(Vector2(0,34),4,tint)
	if rarity >= 3:
		for side in [-1,1]:
			poly([[side*9,-29],[side*17,-34],[side*14,-22]], tint.lightened(0.2))
		draw_polyline(PackedVector2Array([Vector2(3,30),Vector2(17,34),Vector2(21,25)]), tint, 2)

func draw_robe() -> void:
	var life_robe = template == 2
	var fabric = tint.darkened(0.4) if not life_robe else Color("327f80").lerp(tint,0.3)
	var trim = GOLD if rarity >= 2 else tint.lightened(0.3)
	poly([[-10,-30],[-20,-26],[-34,-8],[-26,2],[-15,-4],[-13,4],[-23,33],[0,38],[23,33],[13,4],[15,-4],[26,2],[34,-8],[20,-26],[10,-30],[0,-23]], fabric)
	poly([[-20,-23],[-30,-8],[-25,-3],[-14,-10]], fabric.lightened(0.18),false)
	poly([[20,-23],[30,-8],[25,-3],[14,-10]],fabric.darkened(0.2),false)
	poly([[-10,-28],[3,-11],[10,-28],[14,-23],[5,0],[-5,0],[-15,-23]], trim)
	poly([[-11,7],[-19,30],[-3,34],[-3,8]],fabric.lightened(0.16),false)
	poly([[4,8],[4,34],[19,30],[11,7]],fabric.darkened(0.2),false)
	draw_line(Vector2(-22,32), Vector2(0,37),trim,2)
	draw_line(Vector2(0,37), Vector2(22,32),trim,2)
	draw_rect(Rect2(-14,0,28,6), INK)
	draw_rect(Rect2(-13,1,26,3), trim)
	gem(Vector2(0,3),5,tint.lightened(0.5))
	if rarity >= 1:
		for side in [-1,1]:
			draw_polyline(PackedVector2Array([Vector2(side*7,16),Vector2(side*13,20),Vector2(side*8,25)]),trim,1.5)
	if rarity >= 2:
		for side in [-1,1]:
			poly([[side*12,-27],[side*25,-30],[side*28,-21],[side*19,-16]],trim)
			gem(Vector2(side*20,-23),4,tint)
	if rarity >= 3:
		for side in [-1,1]:
			poly([[side*20,8],[side*27,19],[side*22,35],[side*17,28]],trim)
			draw_line(Vector2(side*16,-12),Vector2(side*27,-7),trim,2)
	if life_robe:
		draw_circle(Vector2(0,20),5,Color("a2f2cd"))
		draw_line(Vector2(-3,20),Vector2(3,20),fabric,2)
		draw_line(Vector2(0,17),Vector2(0,23),fabric,2)

func draw_boots() -> void:
	var leather = tint.darkened(0.4)
	for side in [-1,1]:
		poly([[side*5,-27],[side*22,-27],[side*21,8],[side*32,20],[side*31,28],[side*5,28]],leather)
		poly([[side*7,-24],[side*13,-24],[side*13,12],[side*7,18]],tint.lightened(0.1),false)
		draw_line(Vector2(side*5,-24),Vector2(side*23,-24),GOLD,4)
		draw_line(Vector2(side*6,27),Vector2(side*31,27),GOLD,4)
		for y in [-14,-6,2]:
			draw_line(Vector2(side*15,y),Vector2(side*21,y-3),GOLD,2)
		gem(Vector2(side*16,-17),5,tint.lightened(0.5))
		if rarity >= 2:
			poly([[side*22,-1],[side*35,-13],[side*31,1],[side*23,10]],tint.lightened(0.2))
		if rarity >= 3:
			poly([[side*21,7],[side*38,-2],[side*31,12],[side*23,18]],GOLD)
	if rarity >= 1:
		draw_arc(Vector2(0,31),31,0.15,PI-0.15,20,Color(tint,0.6),2)

func draw_amulet() -> void:
	draw_arc(Vector2(0,-14),17,PI,TAU,24,GOLD,2.5)
	draw_line(Vector2(-17,-14),Vector2(-11,0),GOLD,2)
	draw_line(Vector2(17,-14),Vector2(11,0),GOLD,2)
	if rarity >= 1:
		for side in [-1,1]:
			poly([[0,10],[side*25,-9],[side*27,6],[side*17,22],[0,26]],tint.darkened(0.35))
	if rarity >= 2:
		draw_arc(Vector2(0,7),25,0,TAU,32,GOLD,2)
		for i in range(6):
			var p = Vector2(0,7) + Vector2.from_angle(i*TAU/6) * 25
			draw_circle(p,2.5,tint.lightened(0.5))
	gem(Vector2(0,7),20,tint)
	gem(Vector2(0,5),10,tint.lightened(0.6))
	for side in [-1,0,1]:
		draw_line(Vector2(side*3,27),Vector2(side*6,39),Color("bc6380") if rarity >= 3 else GOLD,2.5)
	if rarity >= 3:
		for side in [-1,1]:
			poly([[side*9,0],[side*31,-20],[side*27,-4],[side*17,8]],GOLD)
