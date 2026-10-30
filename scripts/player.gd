extends CharacterBody3D

var model: Node3D
var camera: Camera3D
var blocked: bool = false
var walk_clock: float = 0.0

func _physics_process(delta: float) -> void:
	var input = Vector2.ZERO
	if not blocked:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var right = camera.global_basis.x
	var forward = camera.global_basis.z
	right.y = 0
	forward.y = 0
	var direction = (right.normalized() * input.x + forward.normalized() * input.y).normalized()
	var speed = 5.2 if Input.is_action_pressed("sprint") else 3.2
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	velocity.y -= 22.0 * delta
	move_and_slide()
	var flat = Vector2(position.x, position.z)
	if flat.length() > 10.2:
		flat = flat.normalized() * 10.2
		position.x = flat.x
		position.z = flat.y
	if direction.length() > 0.05:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(direction.x, direction.z), delta * 12)
		walk_clock += delta * speed * 3
		model.position.y = abs(sin(walk_clock)) * 0.09
		model.rotation.z = sin(walk_clock) * 0.05
	else:
		model.position.y = lerpf(model.position.y, 0, delta * 8)
		model.rotation.z = lerpf(model.rotation.z, 0, delta * 8)
