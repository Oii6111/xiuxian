extends CharacterBody3D

@export var walk_speed := 3.7
@export var run_speed := 5.7
@export var acceleration := 20.0
var camera: Camera3D
var walk_phase := 0.0
var elapsed := 0.0
var input_enabled := true
@onready var model: Node3D = $Model
@onready var left_leg: Node3D = $Model/LeftLeg
@onready var right_leg: Node3D = $Model/RightLeg
@onready var left_arm: Node3D = $Model/LeftArm
@onready var right_arm: Node3D = $Model/RightArm
@onready var sword: Node3D = $Model/FloatingSword

func _physics_process(delta: float) -> void:
	elapsed += delta
	var axes := Input.get_vector("ink_left", "ink_right", "ink_up", "ink_down") if input_enabled else Vector2.ZERO
	var direction := Vector3(axes.x, 0, axes.y)
	if is_instance_valid(camera):
		var right := camera.global_basis.x
		var back := camera.global_basis.z
		right.y = 0
		back.y = 0
		direction = right.normalized() * axes.x + back.normalized() * axes.y
	var speed := run_speed if Input.is_action_pressed("ink_run") else walk_speed
	velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta)
	velocity.y = -0.5 if is_on_floor() else velocity.y - 18.0 * delta
	move_and_slide()
	if global_position.y < -5:
		global_position = Vector3(0, 0.15, 1.8)
		velocity = Vector3.ZERO
	var amount := clampf(Vector2(velocity.x, velocity.z).length() / walk_speed, 0, 1.5)
	if direction.length_squared() > 0.01:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(direction.x, direction.z), 1 - exp(-14 * delta))
	walk_phase += delta * 8.0 * amount
	var swing := sin(walk_phase) * amount
	left_leg.rotation.x = swing * 0.46
	right_leg.rotation.x = -swing * 0.46
	left_arm.rotation.x = -swing * 0.25
	right_arm.rotation.x = swing * 0.25
	model.position.y = abs(sin(walk_phase)) * 0.035 * amount + sin(elapsed * 1.7) * 0.008
	model.rotation.z = swing * 0.025
	sword.position.y = 1.70 + sin(elapsed * 2.0) * 0.055
	sword.rotation.x = sin(elapsed * 1.4) * 0.06
