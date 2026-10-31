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
var last_safe_position: Vector2

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
	last_safe_position = position if game.can_stand(position) else game.safe_road_position(position)

func _physics_process(delta: float) -> void:
	if not game.can_stand(position):
		position = last_safe_position if game.can_stand(last_safe_position) else game.safe_road_position(position)
		route.clear()
		destination_site = ""
	last_safe_position = position
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
	var allowed_motion = game.walk_motion(position, velocity * delta)
	velocity = allowed_motion / maxf(delta, 0.00001)
	move_and_slide()
	# Physics sliding against facades must obey the same bank boundary.
	if not game.can_stand(position):
		position = last_safe_position
		velocity = Vector2.ZERO
	else:
		last_safe_position = position
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
