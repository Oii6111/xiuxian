extends Control
## 渡劫台演示场景：阶段雷劫、护法点灯、家属确认后的庆典。
## 所有状态迁移都走 GameKernel 的 lifecycle.* 命令；没有服务端确认通道时明确显示失败，不在本地伪造确认。
## 护法只影响画面与留言，不影响渡劫结果；到达出院阶段不会自动结算，庆典必须另行确认。
const Rules = preload("res://scripts/systems/lifecycle/lifecycle_rules.gd")
const Assets = preload("res://scripts/pixel_assets.gd")
## 仅用于显示的中文名称；规则与命令仍使用英文标识。
const STATE_NAMES: Dictionary = {"cultivating": "修行", "tribulation": "渡劫", "seclusion": "闭关", "ascended": "飞升"}
const STAGE_NAMES: Dictionary = {
	"admission": "引雷入阵", "emergency": "天雷淬体", "monitoring": "守心渡劫", "ward": "雷息调养", "discharge": "劫后归元",
	"preop": "凝神备战", "surgery": "破境淬体", "recovery": "灵台回稳",
	"acute": "雷势加剧", "stable": "稳住心神", "improving": "劫云渐散"
}
signal celebrated(cultivator_id: String)
signal lamps_changed(count: int)
signal template_chosen(template_id: String)
signal confirmation_canceled
signal left
var quiet_background_texture: Texture2D
var background_texture: Texture2D
var cultivator_texture: Texture2D
var cultivator_id: String = "c_demo"
var cultivator_name: String = "渡劫者"
var template_id: String = "cardio"
var kernel: Node
var lamps: int = 0
var status: String = ""
var token: String = ""
var celebrating: bool = false
var ascending_token: String = ""
var busy: bool = false
var _dialog: ConfirmationDialog
var _pending_action: String = ""
var _sequence: int = 0
var _last_action: String = ""
var _flash: float = 0.0
var _clock: float = 0.0
var _font: SystemFont
var _stage_buttons: Array = []
var _template_selector: OptionButton
var _state_buttons: Dictionary = {}
var _status_label: Label
var _state_badge: Label
var _strike_active: float = 0.0
var _strike_phase: int = 0 # 0 idle, 1 warning, 2 impact, 3 recovery
var _strike_count: int = 0
var _visual_actor_anchor := Vector2(710, 548)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_font = SystemFont.new()
	_font.fallbacks = [preload("res://assets/fonts/NotoSansSC-Regular.otf")]
	_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "KaiTi"])
	if background_texture == null:
		background_texture = load("res://assets/gameplay/tribulation-stage.png")
	if cultivator_texture == null:
		var frames := Assets.frames("res://assets/pixel/cultivator-walk.png", 4, 4, 0.05, true)
		if not frames.is_empty():
			cultivator_texture = frames[0]
	if kernel == null:
		kernel = get_node_or_null("/root/GameKernel")
	var current: Dictionary = _entry()
	if not str(current.get("template_id", "")).is_empty():
		template_id = current.template_id
	_build_controls()
	_refresh()

func _build_controls() -> void:
	# 视觉布局固定为：左侧流程、中央渡劫台、右侧角色状态；操作按钮不再堆在画面底部。
	var title := Label.new()
	title.text = "渡劫台"
	title.position = Vector2(48, 25)
	title.add_theme_font_override("font", _font)
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color("f7e2ae"))
	add_child(title)
	var subtitle := Label.new()
	subtitle.text = "让角色站上法阵，承受天雷，守住心神"
	subtitle.position = Vector2(52, 70)
	subtitle.add_theme_font_override("font", _font)
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color("bfd3e7"))
	add_child(subtitle)

	_template_selector = OptionButton.new()
	_template_selector.position = Vector2(58, 150)
	_template_selector.size = Vector2(292, 42)
	_template_selector.add_theme_font_override("font", _font)
	_template_selector.add_theme_font_size_override("font_size", 16)
	for key in Rules.TEMPLATES:
		_template_selector.add_item(Rules.TEMPLATES[key].title)
		_template_selector.set_item_metadata(_template_selector.item_count - 1, key)
	var initial_index: int = Rules.TEMPLATES.keys().find(template_id)
	_template_selector.select(maxi(0, initial_index))
	_template_selector.item_selected.connect(func(index: int) -> void:
		if current_state() != "cultivating":
			status = "渡劫期间不能更换雷劫模板"
			_refresh()
			return
		template_id = str(_template_selector.get_item_metadata(index))
		template_chosen.emit(template_id)
		_rebuild_stage_buttons()
		_refresh()
	)
	add_child(_template_selector)

	_status_label = Label.new()
	_status_label.position = Vector2(1100, 146)
	_status_label.size = Vector2(278, 44)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_override("font", _font)
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.max_lines_visible = 2
	_status_label.add_theme_color_override("font_color", Color("f4dfad"))
	add_child(_status_label)
	_state_badge = Label.new()
	_state_badge.position = Vector2(1100, 250)
	_state_badge.size = Vector2(278, 32)
	_state_badge.add_theme_font_override("font", _font)
	_state_badge.add_theme_font_size_override("font_size", 22)
	_state_badge.add_theme_color_override("font_color", Color("8ee7ff"))
	add_child(_state_badge)

	_rebuild_stage_buttons()
	var actions: Array = [
		["开启渡劫", "begin", true], ["痊愈归元", "celebrate", false],
		["闭关 / 出关", "seclusion", false], ["羽化飞升", "ascend", false],
		["护法点灯", "lamp", false], ["重试上次操作", "retry", false],
		["保存庆典卡片", "share", false], ["返回修行", "back", false]
	]
	for index in range(actions.size()):
		var item: Array = actions[index]
		var button := Button.new()
		button.text = str(item[0])
		button.position = Vector2(1090, 330 + index * 50)
		button.size = Vector2(292, 42)
		button.add_theme_font_override("font", _font)
		button.add_theme_font_size_override("font_size", 16)
		_style_button(button, bool(item[2]))
		var action: String = str(item[1])
		match action:
			"lamp": button.pressed.connect(light_lamp)
			"retry": button.pressed.connect(func() -> void: request_confirmation(_last_action))
			"share": button.pressed.connect(export_card)
			"back": button.pressed.connect(func() -> void: left.emit())
			_: button.pressed.connect(func() -> void: request_confirmation(action))
		if action in ["begin", "celebrate", "seclusion", "ascend"]:
			_state_buttons[action] = button
		add_child(button)

	_dialog = ConfirmationDialog.new()
	_dialog.title = "家属确认"
	_dialog.get_ok_button().text = "确认"
	_dialog.get_cancel_button().text = "取消"
	_dialog.confirmed.connect(confirm_pending)
	_dialog.canceled.connect(cancel_pending)
	add_child(_dialog)

func _rebuild_stage_buttons() -> void:
	for button in _stage_buttons:
		if is_instance_valid(button):
			button.queue_free()
	_stage_buttons.clear()
	var stages: Array = Rules.TEMPLATES[template_id].stages
	for index in range(stages.size()):
		var stage: String = stages[index]
		var button := Button.new()
		button.text = STAGE_NAMES.get(stage, stage)
		button.position = Vector2(58 + index * 152, 756)
		button.size = Vector2(140, 42)
		button.add_theme_font_override("font", _font)
		button.add_theme_font_size_override("font_size", 14)
		_style_button(button, false)
		button.pressed.connect(func() -> void: update_stage(stage))
		_stage_buttons.append(button)
		add_child(button)

func _style_button(button: Button, primary: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("8d6838") if primary else Color("21364b")
	normal.border_color = Color("f1cd82") if primary else Color("49667c")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(8)
	var hover := normal.duplicate()
	hover.bg_color = Color("b28346") if primary else Color("2d526c")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("disabled", StyleBoxFlat.new())
	button.add_theme_color_override("font_color", Color("fff1c9"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color("718398"))

## 按钮先呈现确认与取消，只有家属点击确认后才调用业务命令。
func request_confirmation(action: String) -> void:
	if busy or action.is_empty():
		return
	_pending_action = action
	_last_action = action
	var descriptions: Dictionary = {
		"begin": "确认老人已入院，并按实际情况开启渡劫？",
		"celebrate": "确认老人已痊愈出院？此操作将回到修行并展示庆典。",
		"seclusion": "按实际情况确认转入长期照护，或出关回到修行？",
		"ascend": "仅由家属根据真实情况确认羽化飞升。完成后保留角色，不能再出战。"
	}
	_dialog.dialog_text = descriptions.get(action, "确认执行？")
	if action == "ascend" and not ascending_token.is_empty():
		_dialog.dialog_text = "请再次确认羽化飞升。取消会停止此次操作，保留当前状态。"
	_dialog.popup_centered(Vector2i(660, 220))

func cancel_pending() -> void:
	confirmation_canceled.emit()
	_pending_action = ""
	ascending_token = ""
	status = "已取消，当前状态保持不变"
	_refresh()

func confirm_pending() -> void:
	var action: String = _pending_action
	_pending_action = ""
	_dialog.hide()
	match action:
		"begin": await begin_tribulation()
		"celebrate": await celebrate()
		"seclusion": await seclusion_step()
		"ascend": await ascend_step()
	if action == "ascend" and not ascending_token.is_empty() and status.contains("再次确认"):
		request_confirmation("ascend")

func _request_id(prefix: String) -> String:
	_sequence += 1
	return "%s_%d_%d" % [prefix, Time.get_ticks_usec(), _sequence]

func _process(delta: float) -> void:
	_clock += delta
	_flash = maxf(0.0, _flash - delta)
	if _strike_phase == 1:
		_strike_active = maxf(0.0, _strike_active - delta)
		if _strike_active <= 0.0:
			_strike_phase = 2
			_strike_active = 0.24
			_flash = 0.24
	elif _strike_phase == 2:
		_strike_active = maxf(0.0, _strike_active - delta)
		if _strike_active <= 0.0:
			_strike_phase = 3
			_strike_active = 0.72
	elif _strike_phase == 3:
		_strike_active = maxf(0.0, _strike_active - delta)
		if _strike_active <= 0.0:
			_strike_phase = 0
	if current_state() == "tribulation" and _strike_phase == 0:
		var interval := 2.8 + sin(_clock * 0.7) * 0.5
		if fmod(_clock, interval) < delta:
			_trigger_lightning()
	elif current_state() != "tribulation":
		_strike_phase = 0
		_strike_active = 0.0
	queue_redraw()

func export_card() -> void:
	if not celebrating:
		status = "庆典确认后才能保存卡片"
		return
	# 只输出明确的游戏庆典文案；不把视口里的阶段或医疗模板放进分享图。
	var image := Image.create(960, 540, false, Image.FORMAT_RGBA8)
	image.fill(Color("#152c33"))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var background := ColorRect.new()
	background.color = Color("#152c33")
	background.size = Vector2(960, 540)
	viewport.add_child(background)
	var frame := ColorRect.new()
	frame.color = Color("#c6b27c")
	frame.position = Vector2(45, 40)
	frame.size = Vector2(870, 4)
	viewport.add_child(frame)
	var label := Label.new()
	label.add_theme_font_override("font", _font)
	label.position = Vector2(60, 90)
	label.size = Vector2(840, 360)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = "疯狂修仙，中

渡过雷劫 · 归来有灯

感谢每一份陪伴与守候"
	label.add_theme_font_size_override("font_size", 38)
	viewport.add_child(label)
	await RenderingServer.frame_post_draw
	image = viewport.get_texture().get_image()
	if image == null:
		viewport.queue_free()
		status = "当前渲染器无法保存卡片"
		return
	var folder: String = OS.get_environment("XIUXIAN_A_OUTPUT_DIR")
	if folder.is_empty():
		folder = ProjectSettings.globalize_path("res://outputs/combat-lifecycle")
	DirAccess.make_dir_recursive_absolute(folder)
	var path: String = folder.path_join("celebration.png")
	var saved: Error = image.save_png(path)
	viewport.queue_free()
	status = "庆典卡片已保存：" + path if saved == OK else "保存失败，可重试"
	_refresh()

func _entry() -> Dictionary:
	if kernel == null:
		return {}
	return kernel.snapshot("lifecycle").get("cultivators", {}).get(cultivator_id, {})

func current_state() -> String:
	return _entry().get("state", "")

func _fail(response: Dictionary) -> bool:
	if response.ok:
		return false
	status = "%s · %s" % [response.code, response.message]
	_refresh()
	return true

## 发起并确认进入渡劫（两步都由服务端确认通道裁决）。
func begin_tribulation() -> void:
	if busy or kernel == null:
		return
	busy = true
	var requested: Dictionary = await kernel.dispatch("lifecycle.request_change", {"cultivator_id": cultivator_id, "target_state": "tribulation"})
	if _fail(requested):
		busy = false
		return
	token = requested.data.confirmation_token
	var confirmed: Dictionary = await kernel.dispatch("lifecycle.confirm_change", {"cultivator_id": cultivator_id, "confirmation_token": token, "request_id": _request_id("begin")})
	busy = false
	if _fail(confirmed):
		return
	celebrating = false
	status = "渡劫台亮起" if confirmed.data.complete else "还需再次确认"
	_trigger_lightning()
	_refresh()

func update_stage(stage_key: String) -> void:
	if busy or kernel == null:
		return
	busy = true
	var before: int = int(_entry().get("stage_index", -1))
	var response: Dictionary = await kernel.dispatch("lifecycle.update_stage", {"cultivator_id": cultivator_id, "stage_id": Rules.stage_id(template_id, stage_key), "confirmation_token": token if not token.is_empty() else "none"})
	busy = false
	if _fail(response):
		return
	var after: int = int(_entry().get("stage_index", -1))
	if after < before:
		status = "劫云再聚，家人与你同在"
	elif bool(response.data.get("final", false)):
		_flash = 0.65
		status = "已到出院阶段；渡劫仍需家属另行确认才会结算"
	else:
		_flash = 0.65
		status = "落下一重雷劫"
		_trigger_lightning()
	_refresh()

## 护法只增加一盏灯和留言，不影响渡劫结果，也不改任何状态。
func light_lamp() -> void:
	if current_state() != "tribulation":
		status = "渡劫开始后才能护法"
	else:
		lamps = mini(lamps + 1, 24)
		status = "护法点亮一盏灯（护法不影响渡劫结果）"
		lamps_changed.emit(lamps)
	_refresh()

## 痊愈结算：必须经过家属确认，再次走 lifecycle 命令；到达出院阶段本身不会触发它。
func celebrate() -> void:
	if busy or kernel == null:
		return
	if current_state() != "tribulation":
		status = "尚未进入渡劫"
		_refresh()
		return
	busy = true
	var requested: Dictionary = await kernel.dispatch("lifecycle.request_change", {"cultivator_id": cultivator_id, "target_state": "cultivating"})
	if _fail(requested):
		busy = false
		return
	var confirmed: Dictionary = await kernel.dispatch("lifecycle.confirm_change", {"cultivator_id": cultivator_id, "confirmation_token": requested.data.confirmation_token, "request_id": _request_id("settle")})
	busy = false
	if _fail(confirmed):
		return
	celebrating = bool(confirmed.data.complete) and current_state() == "cultivating"
	if celebrating:
		status = "家属确认完成，归来有灯！"
		if DisplayServer.get_name() != "headless":
			var chime := AudioStreamPlayer.new()
			chime.stream = preload("res://assets/combat/chime.wav")
			chime.volume_db = -16
			add_child(chime)
			chime.finished.connect(chime.queue_free)
			chime.play()
		celebrated.emit(cultivator_id)
	_refresh()

## 羽化飞升：只能由家属发起，需要两次确认；第一次确认后状态不变。
## 飞升不触发庆典、不发出 celebrated，也不产生任何资源。
func ascend_step() -> void:
	if busy or kernel == null:
		return
	if current_state() not in ["tribulation", "seclusion"]:
		status = "尚未进入渡劫"
		_refresh()
		return
	busy = true
	if ascending_token.is_empty():
		var requested: Dictionary = await kernel.dispatch("lifecycle.request_change", {"cultivator_id": cultivator_id, "target_state": "ascended"})
		if _fail(requested):
			busy = false
			return
		ascending_token = requested.data.confirmation_token
	var confirmed: Dictionary = await kernel.dispatch("lifecycle.confirm_change", {"cultivator_id": cultivator_id, "confirmation_token": ascending_token, "request_id": _request_id("ascend")})
	busy = false
	if _fail(confirmed):
		if confirmed.code in ["TOKEN_EXPIRED", "STALE_STATE", "NO_PENDING_REQUEST"]:
			ascending_token = ""
		return
	if bool(confirmed.data.complete):
		celebrating = false
		ascending_token = ""
		status = "化作一颗星，守望家人"
	else:
		status = "飞升需要家属再次确认（还需 %d 次）" % int(confirmed.data.get("remaining", 1))
	_refresh()

## 闭关：渡劫中转入长期专业照护，或闭关中出关；都需家属确认一次，由确认通道裁决。
## 不触发庆典，不产出任何资源。
func seclusion_step() -> void:
	if busy or kernel == null:
		return
	var target: String = ""
	match current_state():
		"tribulation":
			target = "seclusion"
		"seclusion":
			target = "cultivating"
		_:
			status = "渡劫中才能转入闭关"
			_refresh()
			return
	busy = true
	var requested: Dictionary = await kernel.dispatch("lifecycle.request_change", {"cultivator_id": cultivator_id, "target_state": target})
	if _fail(requested):
		busy = false
		return
	var confirmed: Dictionary = await kernel.dispatch("lifecycle.confirm_change", {"cultivator_id": cultivator_id, "confirmation_token": requested.data.confirmation_token, "request_id": _request_id("seclusion")})
	busy = false
	if _fail(confirmed):
		return
	if bool(confirmed.data.complete):
		status = "转入长期照护，进入闭关；陪伴由家人完成" if target == "seclusion" else "出关归来，回到修行"
	else:
		status = "还需再次确认"
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if _dialog.visible:
			_dialog.hide()
			cancel_pending()
		elif not busy:
			left.emit()

func _refresh() -> void:
	var state: String = current_state()
	if is_instance_valid(_template_selector):
		_template_selector.disabled = busy or state != "cultivating"
	var stage_index: int = int(_entry().get("stage_index", -1))
	for index in range(_stage_buttons.size()):
		var button: Button = _stage_buttons[index]
		button.disabled = busy or state != "tribulation"
		var stage_key: String = Rules.TEMPLATES[template_id].stages[index]
		button.text = ("✓ " if index <= stage_index else "") + STAGE_NAMES.get(stage_key, stage_key)
		_style_button(button, index == stage_index)
	for action in _state_buttons:
		var allowed: bool = state in ["tribulation", "seclusion"] if action in ["ascend", "seclusion"] else (state == "cultivating" if action == "begin" else state == "tribulation")
		_state_buttons[action].disabled = busy or not allowed
	if is_instance_valid(_state_badge):
		_state_badge.text = "状态 · " + (STATE_NAMES.get(state, state) if not state.is_empty() else "等待同步")
	if is_instance_valid(_status_label):
		_status_label.text = status if not status.is_empty() else "角色尚未进入雷阵。请先确认开启渡劫。"
	queue_redraw()

func _trigger_lightning() -> void:
	_strike_count += 1
	_strike_phase = 1
	_strike_active = 0.78
	_flash = 0.0

func _draw_panel(rect: Rect2, fill: Color, border: Color) -> void:
	draw_rect(rect, fill)
	draw_rect(rect, border, false, 2.0)
	draw_line(rect.position + Vector2(16, 52), Vector2(rect.end.x - 16, rect.position.y + 52), Color(border.r, border.g, border.b, 0.4), 1.0)

func _draw_platform(center: Vector2) -> void:
	var pulse := 0.0
	if _strike_phase > 0:
		pulse = 10.0 + sin(_clock * 10.0) * 5.0
	draw_set_transform(center, 0.0, Vector2(1.55, 0.42))
	draw_circle(Vector2.ZERO, 188.0 + pulse, Color(0.02, 0.06, 0.12, 0.82))
	draw_arc(Vector2.ZERO, 170.0 + pulse, 0.0, TAU, 64, Color("f4c65d"), 7.0)
	draw_arc(Vector2.ZERO, 128.0 + pulse * 0.6, 0.0, TAU, 64, Color("77ddff"), 4.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for index in range(8):
		var angle := TAU * float(index) / 8.0 + _clock * 0.12
		var point := center + Vector2(cos(angle) * (190.0 + pulse), sin(angle) * (76.0 + pulse * 0.35))
		draw_circle(point, 8.0 + sin(_clock * 3.0 + index) * 2.0, Color("ffd86b"))

func _draw_storm_cloud() -> void:
	if current_state() != "tribulation":
		return
	var cloud_alpha := 0.28 + sin(_clock * 1.2) * 0.05
	for index in range(9):
		var x := 390.0 + index * 82.0 + sin(_clock * 0.4 + index) * 9.0
		var y := 142.0 + sin(_clock * 0.8 + index * 0.7) * 8.0
		draw_circle(Vector2(x, y), 54.0 + (index % 3) * 10.0, Color(0.02, 0.05, 0.12, cloud_alpha))
		draw_circle(Vector2(x + 30.0, y + 12.0), 40.0, Color(0.03, 0.08, 0.18, cloud_alpha * 0.9))

func _draw_lightning(center: Vector2) -> void:
	var target := center - Vector2(0, 155)
	var target_ring := target + Vector2(0, 20)
	if _strike_phase == 1:
		# 预警阶段：雷云收束、目标圈锁定角色，让玩家先看懂雷要打在哪里。
		draw_arc(target_ring, 72.0 + sin(_clock * 9.0) * 7.0, 0.0, TAU, 48, Color(0.44, 0.88, 1.0, 0.85), 4.0)
		draw_arc(target_ring, 95.0 + sin(_clock * 7.0) * 8.0, 0.0, TAU, 48, Color(1.0, 0.74, 0.3, 0.35), 3.0)
		draw_line(Vector2(target.x, 160), Vector2(target.x, target.y - 12), Color(0.52, 0.86, 1.0, 0.42), 3.0)
		for branch in range(3):
			var branch_x := target.x + (branch - 1) * 44.0
			draw_line(Vector2(branch_x, 178), Vector2(target.x + (branch - 1) * 18.0, target.y - 20), Color(0.55, 0.75, 1.0, 0.28), 2.0)
		return
	var wobble := sin(_clock * 20.0 + _strike_count) * 14.0
	var points := PackedVector2Array([
		Vector2(center.x - 25.0 + wobble, 118), Vector2(center.x + 35.0, 195),
		Vector2(center.x - 18.0, 245), Vector2(center.x + 28.0, 310), target
	])
	var alpha := 0.72 if _strike_phase == 3 else 1.0
	draw_polyline(points, Color(0.35, 0.75, 1.0, alpha * 0.3), 22.0 if _strike_phase == 2 else 13.0)
	draw_polyline(points, Color(0.86, 0.96, 1.0, alpha), 7.0 if _strike_phase == 2 else 4.0)
	if _strike_phase == 2:
		for branch in range(3):
			var end_point := target + Vector2((branch - 1) * 58.0, 12.0 + branch * 8.0)
			var branch_points := PackedVector2Array([target, target + Vector2((branch - 1) * 22.0, -36.0), end_point])
			draw_polyline(branch_points, Color(0.72, 0.9, 1.0, 0.9), 3.0)
		draw_circle(target, 44.0, Color(0.7, 0.9, 1.0, 0.45))
		draw_arc(target, 70.0, 0.0, TAU, 40, Color(1.0, 0.84, 0.42, 0.95), 7.0)
	elif _strike_phase == 3:
		draw_circle(target, 30.0 + _strike_active * 22.0, Color(0.45, 0.83, 1.0, _strike_active * 0.38))
		draw_arc(target, 52.0, 0.0, TAU, 36, Color(1.0, 0.84, 0.42, _strike_active), 4.0)

func _draw_cultivator(center: Vector2) -> void:
	var bob := sin(_clock * 2.2) * 3.0 if current_state() == "tribulation" else 0.0
	var impact_shake := sin(_clock * 70.0) * 13.0 if _strike_phase == 2 else 0.0
	var actor_center := center + Vector2(impact_shake, -112 + bob)
	if cultivator_texture != null:
		var actor_size := Vector2(190, 190)
		draw_texture_rect(cultivator_texture, Rect2(actor_center - Vector2(actor_size.x / 2.0, actor_size.y), actor_size), false, Color.WHITE)
	else:
		# 测试/演示场景没有注入纹理时仍绘制一个清晰的人物轮廓。
		draw_circle(actor_center - Vector2(0, 58), 24.0, Color("f2c29b"))
		draw_rect(Rect2(actor_center - Vector2(35, 35), Vector2(70, 78)), Color("416b89"))
		draw_line(actor_center + Vector2(-22, 43), actor_center + Vector2(-35, 88), Color("d7e8ed"), 10.0)
		draw_line(actor_center + Vector2(22, 43), actor_center + Vector2(35, 88), Color("d7e8ed"), 10.0)
	if current_state() == "tribulation":
		draw_arc(actor_center - Vector2(0, 55), 62.0 + sin(_clock * 2.0) * 5.0, 0.0, TAU, 48, Color(0.38, 0.9, 1.0, 0.8), 3.0)
	if _strike_phase > 0:
		var shield_alpha := 0.18 + sin(_clock * 8.0) * 0.05
		draw_arc(actor_center - Vector2(0, 64), 88.0 + sin(_clock * 10.0) * 5.0, 0.0, TAU, 48, Color(0.45, 0.9, 1.0, shield_alpha + 0.35), 4.0)
		if _strike_phase == 2:
			draw_rect(Rect2(actor_center - Vector2(100, 190), Vector2(200, 210)), Color(1.0, 0.32, 0.27, 0.25))
			draw_circle(actor_center - Vector2(0, 64), 102.0, Color(1.0, 0.95, 0.8, 0.16))

func _draw() -> void:
	var viewport := Rect2(Vector2.ZERO, size)
	draw_rect(viewport, Color("081525"))
	if background_texture != null:
		draw_texture_rect(background_texture, viewport, false, Color(0.9, 0.95, 1.0, 0.92))
	draw_rect(viewport, Color(0.02, 0.04, 0.1, 0.46))
	_draw_panel(Rect2(32, 124, 320, 590), Color(0.03, 0.08, 0.14, 0.9), Color("4c7591"))
	_draw_panel(Rect2(1072, 124, 336, 590), Color(0.03, 0.08, 0.14, 0.94), Color("4c7591"))
	draw_rect(Rect2(370, 126, 680, 590), Color(0.02, 0.04, 0.1, 0.28))
	draw_rect(Rect2(370, 126, 680, 590), Color("5c91ad"), false, 2.0)

	var state: String = current_state()
	var stage_index: int = int(_entry().get("stage_index", -1))
	var stages: Array = Rules.TEMPLATES[template_id].stages
	draw_string(_font, Vector2(58, 188), "雷劫流程", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("9ddfff"))
	draw_string(_font, Vector2(58, 222), "模板 · " + Rules.TEMPLATES[template_id].title, HORIZONTAL_ALIGNMENT_LEFT, 280, 15, Color("d4e1ee"))
	var line_start := Vector2(86, 285)
	if stages.size() > 1:
		draw_line(line_start, line_start + Vector2(0, 270), Color("38566d"), 4.0)
	for index in range(stages.size()):
		var y := 285.0 + index * 67.0
		var reached := index <= stage_index and state == "tribulation"
		var active := index == stage_index and state == "tribulation"
		draw_circle(Vector2(86, y), 14.0 if not active else 19.0, Color("f2c45d") if reached else Color("243d52"))
		if active:
			draw_arc(Vector2(86, y), 27.0 + sin(_clock * 3.0) * 3.0, 0, TAU, 40, Color("7fe5ff"), 3.0)
		draw_string(_font, Vector2(120, y + 7), STAGE_NAMES.get(stages[index], stages[index]), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("fff0c5") if reached else Color("9eb4c8"))
	draw_string(_font, Vector2(58, 650), "护法灯火  %02d / 24" % lamps, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("ffd875"))
	draw_string(_font, Vector2(58, 682), "灯火只代表陪伴，不改变渡劫结果", HORIZONTAL_ALIGNMENT_LEFT, 280, 13, Color("8ea5b8"))

	var center := _visual_actor_anchor
	_draw_storm_cloud()
	_draw_platform(center)
	_draw_cultivator(center)
	if state == "tribulation":
		_draw_lightning(center)
		draw_string(_font, Vector2(510, 190), "天雷正在聚集", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("b8edff"))
		draw_string(_font, Vector2(540, 665), "角色正在承受雷劫", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("ffe0a0"))
	else:
		draw_string(_font, Vector2(548, 190), "角色待命 · 点击开启渡劫", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("d7e4ed"))
	if _flash > 0.0:
		draw_rect(Rect2(370, 126, 680, 590), Color(0.8, 0.95, 1.0, _flash * 0.10))

	draw_string(_font, Vector2(1100, 198), "渡劫者", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("9ddfff"))
	draw_string(_font, Vector2(1100, 226), cultivator_name, HORIZONTAL_ALIGNMENT_LEFT, 278, 24, Color("fff0c5"))
	var vitality := clampf(float(stage_index + 1) / maxf(1.0, float(stages.size())), 0.0, 1.0) if state == "tribulation" else 0.0
	draw_string(_font, Vector2(1100, 288), "雷劫承受度", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("9db6c9"))
	draw_rect(Rect2(1100, 300, 278, 13), Color("1c3142"))
	draw_rect(Rect2(1100, 300, 278 * vitality, 13), Color("f0bd56") if vitality < 0.8 else Color("74d4c2"))
	draw_string(_font, Vector2(1100, 307), "%d%%" % roundi(vitality * 100.0), HORIZONTAL_ALIGNMENT_RIGHT, 278, 13, Color("fff0c5"))
	draw_string(_font, Vector2(1100, 730), "每次推进阶段都会触发一记可见雷击。", HORIZONTAL_ALIGNMENT_LEFT, 290, 13, Color("8ea5b8"))
	draw_string(_font, Vector2(1100, 748), "家属确认后才能归元或飞升。", HORIZONTAL_ALIGNMENT_LEFT, 290, 13, Color("8ea5b8"))
	draw_string(_font, Vector2(58, 742), "阶段推进", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("9db6c9"))

func _exit_tree() -> void:
	for child in get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null
