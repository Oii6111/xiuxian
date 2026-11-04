extends CanvasLayer
## 触屏控制层：手机浏览器上的虚拟摇杆 + 圆形按键。
##
## 统一约定：
## - 左侧永远是摇杆，右侧是圆形按键；探索和战斗共用同一层、同一套绘制风格。
## - 探索模式：交互 / 疾行 / 菜单。
## - 战斗绑定后，右侧显示普攻和该场战斗支持的技能，直接调用 perform_action。
## - 移动走 Input.action_press，兼容 village(move_*)、saga_*、realm_* 三套动作名。
## - 交互/菜单走 Input.parse_input_event 合成按键，能触发现有 keycode 逻辑。
## - 只有触摸设备（或 --touch / F8）才显示；登录页无角色时自动隐藏。

const MOVE_PREFIXES := ["move", "saga", "realm"]
const DEADZONE := 0.22
const TAP_HOLD := 0.06
const MOUSE_FINGER := -2
signal controls_toggled(enabled: bool)

var force_show := false
var surface: Control
var battle_bound: Node = null
var _enabled := false
var _joystick_index := -1
var _joystick_value := Vector2.ZERO
var _sprint_index := -1
var _sprint_held := false
var _releases: Array = []
var _buttons: Array = []
var _battle_buttons: Array = []
var _movement_actions: Dictionary = {}
var _captured_fingers: Dictionary = {}
var _showing_controls := false

class Surface extends Control:
	var pad: CanvasLayer

	func _draw() -> void:
		pad.draw_surface(self)

func _ready() -> void:
	layer = 64
	process_mode = Node.PROCESS_MODE_ALWAYS
	surface = Surface.new()
	surface.pad = self
	surface.set_anchors_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(surface)
	surface.resized.connect(_resize_controls)
	if not force_show:
		force_show = "--touch" in OS.get_cmdline_user_args() or OS.has_environment("XIUXIAN_TOUCH")
	_enabled = force_show or DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	_set_enabled(_enabled)

func controls_enabled() -> bool:
	return _enabled

func _active() -> bool:
	if not _enabled:
		return false
	var focus := get_viewport().gui_get_focus_owner()
	if (focus is LineEdit or focus is TextEdit) and focus.is_visible_in_tree():
		return false
	if is_battle():
		if battle_bound is CanvasItem and not battle_bound.is_visible_in_tree():
			return false
		if battle_bound.has_method("touch_actions_active"):
			return battle_bound.touch_actions_active()
		var rules: Variant = battle_bound.get("rules")
		return rules == null or not (rules.get("paused") == true or rules.get("finished") == true)
	var scene := get_tree().current_scene if is_inside_tree() else null
	if scene == null:
		return true
	if scene.get("account_ready") == false:
		return false
	var ui := _exploration_ui()
	return is_instance_valid(ui) and (ui.get("modal_open") != true or _in_boss_corridor(ui))

func _exploration_ui() -> Node:
	var scene := get_tree().current_scene
	var ui: Variant = scene.get("ui") if scene != null else null
	if not is_instance_valid(ui):
		return null
	var campaign: Variant = ui.get("campaign")
	if is_instance_valid(campaign):
		return campaign.ui
	return ui

func _in_boss_corridor(ui: Node) -> bool:
	var corridor: Variant = ui.get("corridor")
	return is_instance_valid(corridor) and corridor.is_visible_in_tree() and not corridor.is_queued_for_deletion()

func is_battle() -> bool:
	return is_instance_valid(battle_bound) and not battle_bound.is_queued_for_deletion()

func bind_battle(node: Node) -> void:
	_reset_state()
	battle_bound = node
	_layout()
	_sync_visibility()
	_redraw()

func unbind_battle(node: Node) -> void:
	if battle_bound == node:
		battle_bound = null
		_reset_state()
		_layout()
		_sync_visibility()
		_redraw()

func _process(delta: float) -> void:
	_sync_visibility()
	if not _showing_controls or not _is_landscape():
		return
	_apply_movement()
	_flush_releases(delta)
	if is_battle():
		# 冷却和禁用状态由战斗实时提供，这里保持重绘。
		_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		_set_enabled(not _enabled)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		if _touch_press(event.index, event.position, event.pressed and not event.canceled):
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if _touch_drag(event.index, event.position):
			get_viewport().set_input_as_handled()
	elif force_show and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if _touch_press(MOUSE_FINGER, event.position, event.pressed):
				get_viewport().set_input_as_handled()
		elif event is InputEventMouseMotion and _touch_drag(MOUSE_FINGER, event.position):
			get_viewport().set_input_as_handled()

func _touch_press(index: int, position: Vector2, pressed: bool) -> bool:
	_sync_visibility()
	if not pressed and _captured_fingers.erase(index):
		_handle_press(index, position, false)
		return true
	if not pressed or not _showing_controls or not _is_landscape():
		return false
	_layout()
	if not _handle_press(index, position, true):
		return false
	_captured_fingers[index] = true
	return true

func _touch_drag(index: int, position: Vector2) -> bool:
	if not _captured_fingers.has(index):
		return false
	_sync_visibility()
	if _showing_controls and _is_landscape():
		_handle_drag(index, position)
	return true

func _set_enabled(value: bool) -> void:
	_enabled = value
	visible = value
	set_process(value)
	_sync_visibility()
	_redraw()
	controls_toggled.emit(value)

func _sync_visibility() -> void:
	var active := _active()
	if _showing_controls != active:
		_showing_controls = active
		if not active:
			_reset_state()
		_redraw()
	surface.visible = active

func _resize_controls() -> void:
	_reset_state()
	_layout()
	_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_reset_state()
		_captured_fingers.clear()
		_redraw()

func _redraw() -> void:
	if is_instance_valid(surface):
		surface.queue_redraw()

# ---------- 输入处理 ----------

func _handle_press(index: int, position: Vector2, pressed: bool) -> bool:
	if pressed:
		if is_battle() and _press_battle_button(position):
			return true
		if _joystick_index == -1 and _in_joystick(position):
			_joystick_index = index
			_joystick_value = _value_for(position)
			_apply_movement()
			_redraw()
			return true
		if is_battle():
			return false
		for button in _buttons:
			if _in_circle(position, button.center, button.radius):
				if button.kind == "sprint":
					if _sprint_index == -1:
						_sprint_index = index
						_sprint_held = true
						if InputMap.has_action("sprint"):
							Input.action_press("sprint")
						else:
							_send_key(KEY_SHIFT, true)
				else:
					_press_explore_button(button)
				button.pressed_until = 0.18
				_redraw()
				return true
		return false
	if index == _joystick_index:
		_joystick_index = -1
		_joystick_value = Vector2.ZERO
		_apply_movement()
		_redraw()
		return true
	if index == _sprint_index:
		_sprint_index = -1
		_sprint_held = false
		_release_sprint()
		_redraw()
		return true
	return false

func _press_explore_button(button: Dictionary) -> void:
	var ui := _exploration_ui()
	if button.kind == "menu" and is_instance_valid(ui) and not _in_boss_corridor(ui) and ui.has_method("open_family"):
		ui.open_family()
	else:
		_tap(button.key)

func _press_battle_button(position: Vector2) -> bool:
	for button in _battle_buttons:
		if _in_circle(position, button.center, button.radius):
			if not button.disabled:
				button.pressed_until = 0.18
				if is_instance_valid(battle_bound) and battle_bound.has_method("perform_action"):
					battle_bound.perform_action(int(button.id))
			_redraw()
			return true
	return false

func _handle_drag(index: int, position: Vector2) -> bool:
	if index != _joystick_index:
		return false
	_joystick_value = _value_for(position)
	_apply_movement()
	_redraw()
	return true

func _value_for(position: Vector2) -> Vector2:
	var center := _joystick_center()
	var radius := _joystick_radius()
	var offset := (position - center) / radius
	if offset.length() > 1.0:
		offset = offset.normalized()
	if offset.length() < DEADZONE:
		return Vector2.ZERO
	return offset

func _in_joystick(position: Vector2) -> bool:
	return _in_circle(position, _joystick_center(), _joystick_radius() * 1.35)

static func _in_circle(position: Vector2, center: Vector2, radius: float) -> bool:
	return position.distance_to(center) <= radius

# ---------- 动作注入 ----------

func _apply_movement() -> void:
	if _joystick_index == -1 and _movement_actions.is_empty():
		return
	for prefix in MOVE_PREFIXES:
		var left := "%s_left" % prefix
		if not InputMap.has_action(left):
			continue
		var up := "%s_forward" % prefix
		var down := "%s_back" % prefix
		if not InputMap.has_action(up) or not InputMap.has_action(down):
			up = "%s_up" % prefix
			down = "%s_down" % prefix
		_set_action(left, maxf(0.0, -_joystick_value.x), absf(_joystick_value.x))
		_set_action("%s_right" % prefix, maxf(0.0, _joystick_value.x), absf(_joystick_value.x))
		if InputMap.has_action(up) and InputMap.has_action(down):
			_set_action(up, maxf(0.0, -_joystick_value.y), absf(_joystick_value.y))
			_set_action(down, maxf(0.0, _joystick_value.y), absf(_joystick_value.y))
	if _sprint_held and InputMap.has_action("sprint"):
		Input.action_press("sprint")

func _set_action(action: String, strength: float, magnitude: float) -> void:
	if strength > DEADZONE:
		_movement_actions[action] = true
		Input.action_press(action, clampf(magnitude, 0.0, 1.0))
	elif _movement_actions.erase(action):
		Input.action_release(action)

func _release_sprint() -> void:
	if InputMap.has_action("sprint"):
		Input.action_release("sprint")
	else:
		_send_key(KEY_SHIFT, false)

func _tap(key: Key) -> void:
	_send_key(key, true)
	_releases.append({"key": key, "time": TAP_HOLD})

func _send_key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)

func _flush_releases(delta: float) -> void:
	var remaining: Array = []
	for item in _releases:
		item.time -= delta
		if item.time <= 0.0:
			_send_key(item.key, false)
		else:
			remaining.append(item)
	_releases = remaining
	var dirty := false
	for button in _buttons + _battle_buttons:
		if button.pressed_until > 0.0:
			button.pressed_until = maxf(0.0, button.pressed_until - delta)
			dirty = true
	if dirty:
		_redraw()

func _reset_state() -> void:
	_joystick_index = -1
	_joystick_value = Vector2.ZERO
	if _sprint_held:
		_release_sprint()
	_sprint_index = -1
	_sprint_held = false
	for action in _movement_actions:
		Input.action_release(action)
	_movement_actions.clear()
	for item in _releases:
		_send_key(item.key, false)
	_releases.clear()

# ---------- 布局与绘制 ----------

func _surface_size() -> Vector2:
	return surface.size if is_instance_valid(surface) else Vector2(1440, 900)

func _is_landscape() -> bool:
	var s := _surface_size()
	return s.x >= s.y

func _layout_scale() -> float:
	var s := _surface_size()
	return minf(1.0, minf(s.x / 1000.0, s.y / 730.0))

func _joystick_center() -> Vector2:
	var s := _surface_size()
	var inset := (152.0 if is_battle() else 190.0) * _layout_scale()
	return Vector2(136.0 * _layout_scale(), s.y - inset)

func _joystick_radius() -> float:
	return maxf(1.0, 90.0 * _layout_scale())

func _layout() -> void:
	var s := _surface_size()
	var scale := _layout_scale()
	var ui := _exploration_ui()
	var menu_label := "菜单"
	if is_instance_valid(ui):
		if _in_boss_corridor(ui):
			menu_label = "返回"
		elif ui.has_method("open_family"):
			menu_label = "家人"
	var specs := [
		{"kind": "interact", "key": KEY_E, "label": "交互", "offset": Vector2(120, 189), "radius": 70.0},
		{"kind": "sprint", "key": KEY_SHIFT, "label": "疾行", "offset": Vector2(267, 195), "radius": 57.0},
		{"kind": "menu", "key": KEY_ESCAPE, "label": menu_label, "offset": Vector2(123, 329), "radius": 56.0},
	]
	for i in range(specs.size()):
		var button: Dictionary = specs[i]
		button.center = s - button.offset * scale
		button.radius *= scale
		button.pressed_until = _buttons[i].pressed_until if i < _buttons.size() else 0.0
	_buttons = specs
	_battle_buttons = _battle_layout()

func _battle_layout() -> Array:
	var s := _surface_size()
	var scale := _layout_scale()
	var state: Array = []
	if is_instance_valid(battle_bound) and battle_bound.has_method("battle_action_state"):
		state = battle_bound.battle_action_state()
	# Cluster actions in two rows around the larger attack key.
	var specs := [
		{"label": "普攻", "offset": Vector2(123, 126), "r": 79.0},
		{"label": "技能", "offset": Vector2(288, 134), "r": 63.0},
		{"label": "护盾", "offset": Vector2(256, 273), "r": 56.0},
		{"label": "闪避", "offset": Vector2(112, 287), "r": 61.0},
		{"label": "阵眼", "offset": Vector2(388, 251), "r": 55.0},
	]
	var out: Array = []
	for i in range(specs.size()):
		var spec: Dictionary = specs[i]
		var entry: Dictionary = state[i] if i < state.size() else {}
		out.append({
			"id": i, "label": entry.get("label", spec.label), "hint": entry.get("hint", ""),
			"center": s - spec.offset * scale, "radius": spec.r * scale,
			"disabled": bool(entry.get("disabled", false)),
			"cooldown": float(entry.get("cooldown", 0.0)),
			"pressed_until": _battle_pressed(i),
		})
	return out

func _battle_pressed(id: int) -> float:
	for button in _battle_buttons:
		if button.id == id:
			return button.pressed_until
	return 0.0

func draw_surface(canvas: Control) -> void:
	if not _showing_controls:
		return
	_layout()
	var font := canvas.get_theme_default_font()
	if not _is_landscape():
		_draw_hint(canvas, font, "请横屏游玩")
		return
	_draw_joystick(canvas, font)
	if is_battle():
		for button in _battle_buttons:
			_draw_round(canvas, font, button.center, button.radius, button.label, button.hint,
				button.disabled, button.pressed_until > 0.0, button.cooldown)
	else:
		for button in _buttons:
			_draw_round(canvas, font, button.center, button.radius, button.label, "",
				false, button.pressed_until > 0.0, 0.0)

func _draw_joystick(canvas: Control, font: Font) -> void:
	var ink := Color(0.82, 0.70, 0.48, 0.72)
	var paper := Color(0.08, 0.14, 0.19, 0.56)
	var center := _joystick_center()
	var radius := _joystick_radius()
	canvas.draw_circle(center, radius + 2.0, Color(0.08, 0.07, 0.06, 0.45))
	canvas.draw_circle(center, radius, paper)
	canvas.draw_arc(center, radius, 0.0, TAU, 48, ink, 3.5, true)
	var knob := center + _joystick_value * radius * 0.62
	canvas.draw_circle(knob, radius * 0.38, Color(0.96, 0.82, 0.52, 0.75))
	canvas.draw_arc(knob, radius * 0.38, 0.0, TAU, 32, ink, 2.5, true)

func _draw_round(canvas: Control, font: Font, center: Vector2, radius: float, label: String,
		hint: String, disabled: bool, pressed: bool, cooldown: float) -> void:
	var ink := Color(0.91, 0.76, 0.49, 0.78)
	var paper := Color(0.09, 0.16, 0.22, 0.77)
	var accent := Color(0.37, 0.25, 0.10, 0.9)
	var fill := paper
	if disabled:
		fill = Color(0.14, 0.17, 0.20, 0.62)
	elif pressed:
		fill = accent
	canvas.draw_circle(center, radius + 2.0, Color(0.08, 0.07, 0.06, 0.45))
	canvas.draw_circle(center, radius, fill)
	canvas.draw_arc(center, radius, 0.0, TAU, 48, ink, 3.5, true)
	var font_size := int(clampf(radius * 0.49, 12.0, 36.0))
	var label_color := Color(0.99, 0.91, 0.73, 0.62 if disabled else 1.0)
	var width := radius * 2.0
	var sub := "%.1f秒" % cooldown if cooldown > 0.0 else hint
	var label_pos := center + Vector2(-width * 0.5, font_size * (0.34 if sub.is_empty() else 0.04))
	canvas.draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, label_color)
	if not sub.is_empty():
		var small := int(clampf(font_size * 0.65, 9.0, 20.0))
		var sub_pos := label_pos + Vector2(0, small + 4.0)
		canvas.draw_string(font, sub_pos, sub, HORIZONTAL_ALIGNMENT_CENTER, width, small, label_color)

func _draw_hint(canvas: Control, font: Font, text: String) -> void:
	var s := _surface_size()
	var font_size := int(clampf(s.x * 0.06, 18.0, 40.0))
	canvas.draw_string(font, Vector2(0, s.y * 0.5), text, HORIZONTAL_ALIGNMENT_CENTER, s.x, font_size,
		Color(0.16, 0.14, 0.12, 0.85))
