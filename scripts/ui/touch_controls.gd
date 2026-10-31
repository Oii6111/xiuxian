extends CanvasLayer
## 触屏控制层：手机浏览器上的虚拟摇杆 + 圆形按键。
##
## 统一约定：
## - 左侧永远是摇杆，右侧是圆形按键；探索和战斗共用同一层、同一套绘制风格。
## - 探索模式：交互 / 疾行 / 菜单。
## - 战斗模式：战斗把自身绑定进来（bind_battle），右侧换成 攻击 / 技能 / 护盾 / 闪避 / 阵眼，
##   点击直接调用战斗的 perform_action，不再由战斗自己另画一排按钮。
## - 移动走 Input.action_press，兼容 village(move_*)、saga_*、realm_* 三套动作名。
## - 交互/菜单走 Input.parse_input_event 合成按键，能触发现有 keycode 逻辑。
## - 只有触摸设备（或 --touch / F8）才显示；登录页无角色时自动隐藏。

const MOVE_PREFIXES := ["move", "saga", "realm"]
const DEADZONE := 0.22
const TAP_HOLD := 0.06

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
	if not force_show:
		force_show = "--touch" in OS.get_cmdline_user_args() or OS.has_environment("XIUXIAN_TOUCH")
	_enabled = force_show or DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	_set_enabled(_enabled)

func _active() -> bool:
	if not _enabled:
		return false
	var scene := get_tree().current_scene if is_inside_tree() else null
	if scene == null:
		return true
	var ready = scene.get("account_ready")
	return not (ready is bool and not ready)

func is_battle() -> bool:
	return is_instance_valid(battle_bound)

func bind_battle(node: Node) -> void:
	battle_bound = node
	_redraw()

func unbind_battle(node: Node) -> void:
	if battle_bound == node:
		battle_bound = null
		_reset_state()
		_redraw()

func _process(delta: float) -> void:
	if not _active():
		_reset_state()
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
	if not _active():
		return
	if event is InputEventScreenTouch:
		if _handle_press(event.index, event.position, event.pressed):
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if _handle_drag(event.index, event.position):
			get_viewport().set_input_as_handled()
	elif force_show and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_press(0, event.position, event.pressed)
	elif force_show and event is InputEventMouseMotion and _joystick_index == 0:
		_handle_drag(0, event.position)

func _set_enabled(value: bool) -> void:
	_enabled = value
	visible = value
	set_process(value)
	set_process_input(value)
	if not value:
		_reset_state()
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
			_redraw()
			return true
		if is_battle():
			return false
		for button in _buttons:
			if _in_circle(position, button.center, button.radius):
				if button.kind == "sprint":
					_sprint_index = index
					_sprint_held = true
					if InputMap.has_action("sprint"):
						Input.action_press("sprint")
					else:
						_send_key(KEY_SHIFT, true)
				else:
					_tap(button.key)
				button.pressed_until = 0.18
				_redraw()
				return true
		return false
	if index == _joystick_index:
		_joystick_index = -1
		_joystick_value = Vector2.ZERO
		_redraw()
		return true
	if index == _sprint_index:
		_sprint_index = -1
		_sprint_held = false
		_release_sprint()
		_redraw()
		return true
	return false

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
		Input.action_press(action, clampf(magnitude, 0.0, 1.0))
	else:
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
	_sprint_index = -1
	_sprint_held = false
	for prefix in MOVE_PREFIXES:
		for suffix in ["left", "right", "forward", "back", "up", "down"]:
			var action := "%s_%s" % [prefix, suffix]
			if InputMap.has_action(action):
				Input.action_release(action)
	_release_sprint()
	_releases.clear()

# ---------- 布局与绘制 ----------

func _surface_size() -> Vector2:
	return surface.size if is_instance_valid(surface) else Vector2(1440, 900)

func _joystick_center() -> Vector2:
	var s := _surface_size()
	return Vector2(150.0, s.y - 150.0)

func _joystick_radius() -> float:
	var s := _surface_size()
	return clampf(minf(s.x, s.y) * 0.15, 72.0, 118.0)

func _layout() -> void:
	var s := _surface_size()
	var right := s.x
	var bottom := s.y
	_buttons = [
		{"kind": "interact", "key": KEY_E, "label": "交互", "hint": "[E]", "center": Vector2(right - 90.0, bottom - 120.0), "radius": 56.0, "pressed_until": 0.0},
		{"kind": "sprint", "key": KEY_SHIFT, "label": "疾行", "hint": "[Shift]", "center": Vector2(right - 90.0, bottom - 250.0), "radius": 44.0, "pressed_until": 0.0},
		{"kind": "menu", "key": KEY_ESCAPE, "label": "菜单", "hint": "[Esc]", "center": Vector2(right - 90.0, bottom - 380.0), "radius": 38.0, "pressed_until": 0.0},
	]
	_battle_buttons = _battle_layout()

func _battle_layout() -> Array:
	var s := _surface_size()
	var state: Array = []
	if is_instance_valid(battle_bound) and battle_bound.has_method("battle_action_state"):
		state = battle_bound.battle_action_state()
	var specs := [
		{"id": 0, "label": "攻击", "hint": "[J]", "x": s.x - 95.0, "y": s.y - 130.0, "r": 80.0},
		{"id": 1, "label": "技能", "hint": "[1]", "x": s.x - 262.0, "y": s.y - 148.0, "r": 62.0},
		{"id": 2, "label": "护盾", "hint": "[K]", "x": s.x - 262.0, "y": s.y - 300.0, "r": 54.0},
		{"id": 3, "label": "闪避", "hint": "[空格]", "x": s.x - 95.0, "y": s.y - 312.0, "r": 54.0},
		{"id": 4, "label": "阵眼", "hint": "[E]", "x": s.x - 95.0, "y": s.y - 452.0, "r": 50.0},
	]
	var out: Array = []
	for spec in specs:
		var entry: Dictionary = state[spec.id] if spec.id < state.size() else {}
		out.append({
			"id": spec.id, "label": spec.label, "hint": spec.hint,
			"center": Vector2(spec.x, spec.y), "radius": spec.r,
			"disabled": bool(entry.get("disabled", false)),
			"cooldown": float(entry.get("cooldown", 0.0)),
			"pressed_until": _battle_pressed(spec.id),
		})
	return out

func _battle_pressed(id: int) -> float:
	for button in _battle_buttons:
		if button.id == id:
			return button.pressed_until
	return 0.0

func draw_surface(canvas: Control) -> void:
	if not _active():
		return
	_layout()
	var s := _surface_size()
	var font := canvas.get_theme_default_font()
	if s.x < s.y:
		_draw_hint(canvas, font, "请横屏游玩")
		return
	_draw_joystick(canvas, font)
	if is_battle():
		for button in _battle_buttons:
			_draw_round(canvas, font, button.center, button.radius, button.label, button.hint,
				button.disabled, button.pressed_until > 0.0, button.cooldown)
	else:
		for button in _buttons:
			_draw_round(canvas, font, button.center, button.radius, button.label, button.hint,
				false, button.pressed_until > 0.0, 0.0)

func _draw_joystick(canvas: Control, font: Font) -> void:
	var ink := Color(0.12, 0.10, 0.09, 0.9)
	var paper := Color(0.93, 0.88, 0.76, 0.62)
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
	var ink := Color(0.12, 0.10, 0.09, 0.9)
	var paper := Color(0.93, 0.88, 0.76, 0.62)
	var accent := Color(0.96, 0.82, 0.52, 0.78)
	var fill := paper
	if disabled:
		fill = Color(0.55, 0.52, 0.46, 0.4)
	elif pressed:
		fill = accent
	canvas.draw_circle(center, radius + 2.0, Color(0.08, 0.07, 0.06, 0.45))
	canvas.draw_circle(center, radius, fill)
	canvas.draw_arc(center, radius, 0.0, TAU, 48, ink, 3.5, true)
	var font_size := int(clampf(radius * 0.42, 15.0, 30.0))
	var label_color := Color(0.10, 0.09, 0.08, 0.45 if disabled else 0.95)
	var width := radius * 2.2
	var label_pos := center + Vector2(-width * 0.5, font_size * 0.34)
	canvas.draw_string_outline(font, label_pos, label, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, 4,
		Color(0.98, 0.96, 0.9, 0.85))
	canvas.draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, label_color)
	var small := int(clampf(font_size * 0.62, 11.0, 17.0))
	var sub := "%.1fs" % cooldown if cooldown > 0.0 else hint
	var sub_pos := center + Vector2(-width * 0.5, font_size * 0.34 + small + 6.0)
	canvas.draw_string_outline(font, sub_pos, sub, HORIZONTAL_ALIGNMENT_CENTER, width, small, 3,
		Color(0.98, 0.96, 0.9, 0.75))
	canvas.draw_string(font, sub_pos, sub, HORIZONTAL_ALIGNMENT_CENTER, width, small, Color(0.10, 0.09, 0.08, 0.7))

func _draw_hint(canvas: Control, font: Font, text: String) -> void:
	var s := _surface_size()
	var font_size := int(clampf(s.x * 0.06, 18.0, 40.0))
	canvas.draw_string(font, Vector2(0, s.y * 0.5), text, HORIZONTAL_ALIGNMENT_CENTER, s.x, font_size,
		Color(0.16, 0.14, 0.12, 0.85))
