extends SceneTree
## 触控层测试：摇杆映射、按键合成、探索/战斗同一套圆形按键、布局不重叠。

var pad: CanvasLayer
var received: Array = []
var calls: Array = []

class KeySink extends Node:
	var received: Array

	func _init(store: Array) -> void:
		received = store

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and not event.echo:
			received.append({"key": event.keycode, "pressed": event.pressed})

class DummyBattle extends Node:
	var calls: Array
	var disabled_ids: Array = []

	func _init(store: Array) -> void:
		calls = store

	func perform_action(action: int) -> void:
		calls.append(action)

	func battle_action_state() -> Array:
		var out: Array = []
		for i in range(5):
			out.append({"cooldown": 0.0, "disabled": i in disabled_ids})
		return out

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	print(("PASS: " if condition else "FAIL: ") + message)
	if not condition:
		quit(1)

func run() -> void:
	for prefix in ["move", "saga", "realm"]:
		for suffix in ["left", "right", "forward", "back", "up", "down"]:
			var action := "%s_%s" % [prefix, suffix]
			if not InputMap.has_action(action):
				InputMap.add_action(action)
	InputMap.add_action("sprint")

	pad = load("res://scripts/ui/touch_controls.gd").new()
	pad.force_show = true
	root.add_child(pad)
	pad.surface.set_anchors_preset(Control.PRESET_TOP_LEFT)
	pad.surface.size = Vector2(1440, 900)
	await process_frame
	pad._layout()

	check(pad.visible, "触控层默认可见（--touch / 触屏设备）")
	check(pad.get_child_count() == 1 and pad.surface is Control, "触控层只有一层绘制面")

	var center: Vector2 = pad._joystick_center()
	var radius: float = pad._joystick_radius()
	pad._handle_press(1, center, true)
	pad._handle_drag(1, center + Vector2(radius, 0))
	pad._process(0.016)
	check(Input.get_action_strength("move_right") > 0.5, "摇杆右拖按下 move_right")
	check(Input.get_action_strength("move_left") < 0.1, "摇杆右拖不误按 move_left")
	check(Input.get_action_strength("saga_right") > 0.5, "同一摇杆兼容 saga_right")
	pad._handle_press(1, center, false)
	pad._process(0.016)
	check(Input.get_action_strength("move_right") < 0.1, "松手后释放移动动作")

	pad._handle_press(2, center, true)
	pad._handle_drag(2, center + Vector2(0, -radius))
	pad._process(0.016)
	check(Input.get_action_strength("move_forward") > 0.5, "摇杆上拖按下 move_forward")
	check(Input.get_action_strength("move_back") < 0.1, "摇杆上拖不误按 move_back")
	pad._handle_press(2, center, false)

	var sink := KeySink.new(received)
	root.add_child(sink)
	pad._layout()
	var interact: Dictionary = pad._buttons[0]
	pad._handle_press(3, interact.center, true)
	await process_frame
	pad._process(0.1)
	await process_frame
	check(received.any(func(item): return item.key == KEY_E and item.pressed), "交互按钮发出 E 按下")
	check(received.any(func(item): return item.key == KEY_E and not item.pressed), "交互按钮自动补发 E 抬起")

	var sprint: Dictionary = pad._buttons[1]
	pad._handle_press(4, sprint.center, true)
	pad._process(0.016)
	check(Input.is_action_pressed("sprint"), "疾行按钮按住时 sprint 生效")
	pad._handle_press(4, sprint.center, false)
	pad._process(0.016)
	check(not Input.is_action_pressed("sprint"), "松开疾行后 sprint 释放")

	received.clear()
	var menu: Dictionary = pad._buttons[2]
	pad._handle_press(5, menu.center, true)
	await process_frame
	pad._process(0.1)
	await process_frame
	check(received.any(func(item): return item.key == KEY_ESCAPE and item.pressed), "菜单按钮发出 Esc")

	# 战斗模式：同一层、同一套圆形按键，点击直接调用 perform_action
	var dummy := DummyBattle.new(calls)
	root.add_child(dummy)
	pad.bind_battle(dummy)
	pad._layout()
	check(pad.is_battle(), "战斗绑定后进入战斗按键模式")
	var attack: Dictionary = pad._battle_buttons[0]
	pad._handle_press(10, attack.center, true)
	check(calls == [0], "点击攻击圆键调用 perform_action(0)")
	calls.clear()
	dummy.disabled_ids = [1]
	pad._layout()
	var skill: Dictionary = pad._battle_buttons[1]
	pad._handle_press(11, skill.center, true)
	check(calls.is_empty(), "冷却/禁用的技能键不触发动作")
	dummy.disabled_ids = []
	pad._layout()
	pad._handle_press(12, pad._joystick_center() + Vector2(radius, 0), true)
	pad._process(0.016)
	check(Input.get_action_strength("realm_right") > 0.5, "战斗里摇杆仍驱动 realm_right")
	pad._handle_press(12, pad._joystick_center(), false)

	# 布局：全部在右半屏、在屏幕内、彼此不重叠、也不压到摇杆
	var layout_ok := true
	var joystick_center: Vector2 = pad._joystick_center()
	var joystick_radius: float = pad._joystick_radius()
	for i in range(pad._battle_buttons.size()):
		var a: Dictionary = pad._battle_buttons[i]
		if a.center.x < 720.0 or a.center.x + a.radius > 1440.0 or a.center.y - a.radius < 0.0 or a.center.y + a.radius > 900.0:
			layout_ok = false
		if a.center.distance_to(joystick_center) < joystick_radius + a.radius:
			layout_ok = false
		for j in range(i + 1, pad._battle_buttons.size()):
			var b: Dictionary = pad._battle_buttons[j]
			if a.center.distance_to(b.center) < a.radius + b.radius + 4.0:
				layout_ok = false
	check(layout_ok, "战斗五键都在右半屏、互不遮挡、不压摇杆")
	check(pad._battle_buttons[0].radius > pad._battle_buttons[1].radius, "攻击键最大")

	pad.unbind_battle(dummy)
	check(not pad.is_battle(), "退出战斗后恢复探索按键")

	pad.surface.size = Vector2(600, 1000)
	pad.surface.queue_redraw()
	await process_frame
	check(pad.visible, "竖屏时保留提示层")

	pad._set_enabled(false)
	check(not pad.visible, "F8 可收起触控层")
	check(Input.get_action_strength("move_left") < 0.1, "收起时释放所有移动动作")

	print("TOUCH_CONTROLS_TEST: all checks passed; 0 failures")
	quit(0)
