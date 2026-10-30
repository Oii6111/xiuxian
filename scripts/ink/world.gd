extends Node3D

const Hud = preload("res://scripts/ink/hud.gd")
const TITLES = ["松风小筑", "山门石卫", "铁甲玄龟", "焚心妖狐", "逐雷鹏", "五相劫主"]
const REALMS = ["云海归处", "炼气", "筑基", "结丹", "元婴", "化神"]
var scene_index := 0
var zoom_target := 31.0
var close_view := false
var elapsed := 0.0
var nearest := ""
var ui: Control
var capture_path := ""
var capture_elapsed := 0.0
var capture_done := false
@onready var player: CharacterBody3D = $Songfeng
@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	scene_index = get_meta("scene_index", 0)
	_setup_input()
	var background_layer := CanvasLayer.new()
	background_layer.name = "PaintedCloudSea"
	background_layer.layer = -1
	add_child(background_layer)
	var background := TextureRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.texture = load("res://assets/ink/cloud-sea.png")
	background_layer.add_child(background)
	player.camera = camera
	zoom_target = 31.0 if scene_index == 0 else 22.0
	camera.size = zoom_target
	var layer := CanvasLayer.new()
	layer.name = "Interface"
	add_child(layer)
	ui = Hud.new()
	ui.game = self
	layer.add_child(ui)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
		if argument == "--close":
			close_view = true
			zoom_target = 6.2
	_update_camera(1.0)

func _setup_input() -> void:
	var actions := {"ink_left": [KEY_A, KEY_LEFT], "ink_right": [KEY_D, KEY_RIGHT], "ink_up": [KEY_W, KEY_UP], "ink_down": [KEY_S, KEY_DOWN], "ink_run": [KEY_SHIFT], "ink_interact": [KEY_E], "ink_map": [KEY_M], "ink_close": [KEY_V], "ink_home": [KEY_HOME]}
	for action: String in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for code: int in actions[action]:
			var event := InputEventKey.new()
			event.physical_keycode = code
			if not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)

func _process(delta: float) -> void:
	elapsed += delta
	_update_camera(delta)
	var location := _nearest_site()
	if location != nearest:
		nearest = location
		ui.update_site(nearest)
	if not capture_path.is_empty() and not capture_done:
		capture_elapsed += delta
		if capture_elapsed > 2.0:
			capture_done = true
			_capture.call_deferred()

func _update_camera(delta: float) -> void:
	var follow := player.position * (1.0 if close_view else 0.28)
	follow.y = 0.8 if close_view else 0.0
	if scene_index == 0 and not close_view:
		follow.z -= 4.0
	var offset := Vector3(0, 25, 24) if not close_view else Vector3(0, 8, 15)
	var target_position := follow + offset
	camera.position = camera.position.lerp(target_position, 1 - exp(-4.0 * delta))
	camera.look_at(follow, Vector3.UP)
	camera.size = lerpf(camera.size, zoom_target, 1 - exp(-7.0 * delta))
	for roof: Node3D in get_tree().get_nodes_in_group("ink_roofs"):
		var distance := Vector2(roof.global_position.x - player.position.x, roof.global_position.z - player.position.z).length()
		roof.visible = not close_view and distance > 3.8
	for item: Label3D in get_tree().get_nodes_in_group("ink_location_labels"):
		item.visible = not close_view

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ink_map"):
		ui.toggle_map()
	elif event.is_action_pressed("ink_close"):
		close_view = not close_view
		zoom_target = 6.2 if close_view else (31.0 if scene_index == 0 else 22.0)
	elif event.is_action_pressed("ink_home"):
		travel(0)
	elif event.is_action_pressed("ink_interact"):
		if nearest == "五境试炼":
			ui.toggle_map()
		elif nearest == "归途":
			travel(0)
		elif not nearest.is_empty():
			ui.show_site(nearest)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		ui.dismiss()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		get_viewport().get_texture().get_image().save_png("res://output/ink/screenshot.png")
		ui.toast("画面已保存至 output/ink/screenshot.png")
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_target = clampf(zoom_target - 1.5, 5.0, 38.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_target = clampf(zoom_target + 1.5, 5.0, 38.0)

func _nearest_site() -> String:
	var pos := Vector2(player.position.x, player.position.z)
	if scene_index != 0:
		return "归途" if pos.distance_to(Vector2(0, 6.6)) < 1.5 else ""
	var sites := {"家族洞府": Vector2(-7, 0.1), "灵根测试": Vector2(6.6, -0.8), "成就碑林": Vector2(0, 6.0), "五境试炼": Vector2(0, -7.0)}
	for key: String in sites:
		if pos.distance_to(sites[key]) < 2.1:
			return key
	return ""

func travel(index: int) -> void:
	var path := "res://scenes/main.tscn" if index == 0 else "res://scenes/ink/trial_%d.tscn" % index
	get_tree().change_scene_to_file.call_deferred(path)

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(capture_path)
	print("INK_CAPTURE ", capture_path, " result=", result)
	get_tree().quit(0 if result == OK else 1)
