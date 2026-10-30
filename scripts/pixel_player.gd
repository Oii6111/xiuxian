extends CharacterBody2D

var game: Node2D
var blocked: bool = false
var sprite: Sprite2D
var frame_clock: float = 0.0
var facing: int = 0
var route: PackedVector2Array = PackedVector2Array()
var destination_site: String = ""
var walk_textures: Array[Texture2D] = []
var shadow: Polygon2D

func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var collision = CollisionShape2D.new()
	var body = CircleShape2D.new()
	body.radius = 8
	collision.shape = body
	add_child(collision)
	shadow = Polygon2D.new()
	var points = PackedVector2Array()
	for i in range(16):
		var angle = i * TAU / 16
		points.append(Vector2(cos(angle) * 18, sin(angle) * 6))
	shadow.polygon = points
	shadow.color = Color(0.1, 0.15, 0.12, 0.32)
	add_child(shadow)
	sprite = Sprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	if not walk_textures.is_empty():
		sprite.texture = walk_textures[0]
		sprite.scale = Vector2.ONE * 86.0 / sprite.texture.get_height()
		sprite.position.y = -43
	set_notify_transform(true)

func _physics_process(delta: float) -> void:
	var direction = Vector2.ZERO
	if not blocked:
		direction = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if direction.length() > 0:
			route.clear()
			destination_site = ""
		elif not route.is_empty():
			if position.distance_to(route[0]) < 7:
				route.remove_at(0)
				if route.is_empty() and destination_site != "":
					var id = destination_site
					destination_site = ""
					game.ui.open_site(id)
			if not route.is_empty():
				direction = position.direction_to(route[0])
	var speed = 205.0 if Input.is_action_pressed("sprint") else 125.0
	velocity = direction * speed
	# Hand measured navigation contours keep the sprite on roads, terraces and the bridge.
	if not game.can_walk(position + Vector2(velocity.x * delta, 0)):
		velocity.x = 0
	if not game.can_walk(position + Vector2(0, velocity.y * delta)):
		velocity.y = 0
	move_and_slide()
	if direction.length() > 0.05 and velocity.length() > 0:
		frame_clock += delta * (11.0 if speed > 150 else 8.0)
		if abs(direction.x) > abs(direction.y):
			facing = 2 if direction.x > 0 else 1
		else:
			facing = 0 if direction.y > 0 else 3
		sprite.position.y = -43 - abs(sin(frame_clock * PI / 2)) * 1.4
	else:
		frame_clock = 0
		sprite.position.y = -43 - sin(Time.get_ticks_msec() * 0.002) * 0.5
	if walk_textures.size() == 16:
		sprite.texture = walk_textures[facing * 4 + int(frame_clock) % 4]
		sprite.scale = Vector2.ONE * 86.0 / sprite.texture.get_height()
	z_index = int(position.y)
