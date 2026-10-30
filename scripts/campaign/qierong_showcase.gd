extends Node3D
## Review the actual runtime GLB independently of the combat camera.
const Art = preload("res://scripts/campaign/creatures.gd")
var camera: Camera3D
var yaw := 0.61
var elevation := 0.27
var camera_size := 5.7
var dragging := false
var target := Vector3(0,2.3,-0.15)

func _ready() -> void:
	var environment = WorldEnvironment.new()
	var settings = Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("dfd1b5").srgb_to_linear()
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.30
	settings.ambient_light_sky_contribution = 0.0
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	add_child(environment)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-44,-32,0)
	sun.light_color = Color.WHITE
	sun.light_energy = 0.42
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mesh = PlaneMesh.new()
	floor_mesh.size = Vector2(100,100)
	Art.part(self,floor_mesh,Vector3.ZERO,Color("c2b69f"))
	var model = Art.blender_asset("b03")
	add_child(model)
	var animator = model.find_child("AnimationPlayer",true,false) as AnimationPlayer
	if animator != null:
		animator.stop()
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	add_child(camera)
	get_viewport().msaa_3d = Viewport.MSAA_4X
	_position_camera()
	_capture.call_deferred()

func _position_camera() -> void:
	camera.size = camera_size
	camera.position = target + Vector3(sin(yaw)*cos(elevation),sin(elevation),cos(yaw)*cos(elevation))*12.0
	camera.look_at(target)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			camera_size = clampf(camera_size+(-0.3 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.3),3.5,9.0)
			_position_camera()
	if event is InputEventMouseMotion and dragging:
		yaw -= event.relative.x*0.008
		elevation = clampf(elevation+event.relative.y*0.005,0.05,1.0)
		_position_camera()
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: yaw = 0.0
			KEY_2: yaw = PI*0.5
			KEY_3: yaw = PI
			KEY_4: yaw = 0.61
		_position_camera()

func _capture() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--showcase-capture="):
			await get_tree().create_timer(2.0).timeout
			await RenderingServer.frame_post_draw
			var result = get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--showcase-capture="))
			print("SHOWCASE_CAPTURE ",result)
			get_tree().quit()
