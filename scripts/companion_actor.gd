extends Node2D
const Catalogue = preload("res://scripts/companion_catalogue.gd")
var game: Node
var sprite: Sprite2D
var name_label: Label
var bubble: PanelContainer
var bubble_text: Label
var current_id = ""
var clock = 0.0
var bubble_time = 0.0
var expression = "idle"
var expression_time = 0.0
var trail: Array[Vector2] = []

func _ready() -> void:
	name = "CompanionPet"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite = Sprite2D.new()
	add_child(sprite)
	name_label = Label.new()
	name_label.position = Vector2(-60, -83)
	name_label.size.x = 120
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_override("font", game.font)
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", Color("fff0ca"))
	name_label.add_theme_color_override("font_outline_color", Color("392d25"))
	name_label.add_theme_constant_override("outline_size", 4)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(name_label)
	bubble = PanelContainer.new()
	bubble.position = Vector2(-92, -129)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paper = StyleBoxFlat.new()
	paper.bg_color = Color("fff3d8")
	paper.border_color = Color("b69258")
	paper.set_border_width_all(2)
	paper.set_corner_radius_all(9)
	paper.content_margin_left = 10
	paper.content_margin_right = 10
	paper.content_margin_top = 7
	paper.content_margin_bottom = 7
	bubble.add_theme_stylebox_override("panel", paper)
	bubble_text = Label.new()
	bubble_text.add_theme_font_override("font", game.font)
	bubble_text.add_theme_font_size_override("font_size", 13)
	bubble_text.add_theme_color_override("font_color", Color("594330"))
	bubble_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(bubble_text)
	add_child(bubble)
	var area = Area2D.new()
	var hit = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 34
	hit.shape = circle
	hit.position.y = -31
	area.add_child(hit)
	area.input_event.connect(func(_view, event, _index):
		if visible and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not game.ui.modal_open:
			game.ui.open_companion()
	)
	add_child(area)
	position = game.player.position + Vector2(-56, 25)
	refresh_pet()

func refresh_pet() -> void:
	var pet = game.family.companion
	var id = str(pet.get("id", ""))
	visible = game.account_ready and Catalogue.valid(id)
	if not visible:
		current_id = ""
		return
	name_label.text = Catalogue.nickname(pet)
	if current_id != id:
		current_id = id
		sprite.texture = Catalogue.texture(id)
		position = game.player.position + Vector2(-56, 25)
		trail.clear()
		say("想知道下一步？来问我吧")

func say(text: String, animation: String = "talk") -> void:
	bubble_text.text = text.left(18)
	bubble_time = 5.5
	expression = animation
	expression_time = 3.0

func _process(delta: float) -> void:
	clock += delta
	refresh_pet()
	if not visible:
		return
	var target_position = game.player.position
	if trail.is_empty() or trail[-1].distance_to(target_position) > 8:
		trail.append(target_position)
	while trail.size() > 22:
		trail.pop_front()
	var target = trail[0] if trail.size() > 7 else target_position + Vector2(-52, 23)
	var distance = position.distance_to(target)
	var moving = distance > 16 and not game.ui.modal_open
	if distance > 400:
		position = target_position + Vector2(-52, 23)
		trail.clear()
	elif moving:
		position = position.move_toward(target, delta * clampf(100 + distance * 1.5, 100, 390))
		if position.distance_to(target) < 14 and trail.size() > 7:
			trail.pop_front()
		if absf(target.x - position.x) > 8:
			sprite.flip_h = target.x < position.x
	z_index = int(position.y) + 1
	bubble_time = maxf(0, bubble_time - delta)
	expression_time = maxf(0, expression_time - delta)
	bubble.visible = bubble_time > 0 and not game.ui.modal_open
	var base_scale = 61.0 / sprite.texture.get_height()
	var bob = absf(sin(clock * (10.0 if moving else 2.2))) * (5.0 if moving else 1.5)
	if expression == "celebrate" and expression_time > 0:
		bob += absf(sin(clock * 9)) * 10
	var stretch = sin(clock * 7) * 0.025 if expression_time > 0 else 0.0
	sprite.scale = Vector2(base_scale * (1 + stretch), base_scale * (1 - stretch))
	sprite.position.y = -31 - bob
	queue_redraw()

func _draw() -> void:
	if visible:
		draw_set_transform(Vector2.ZERO, 0, Vector2(1, 0.3))
		draw_circle(Vector2.ZERO, 21, Color(0.15, 0.2, 0.14, 0.2))
		draw_set_transform(Vector2.ZERO)
