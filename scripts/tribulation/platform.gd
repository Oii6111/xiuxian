extends Control
## 渡劫台演示场景：阶段雷劫、护法点灯、家属确认后的庆典。
## 所有状态迁移都走 GameKernel 的 lifecycle.* 命令；没有服务端确认通道时明确显示失败，不在本地伪造确认。
## 护法只影响画面与留言，不影响渡劫结果；到达出院阶段不会自动结算，庆典必须另行确认。
const Rules = preload("res://scripts/systems/lifecycle/lifecycle_rules.gd")
## 仅用于显示的中文名称；规则与命令仍使用英文标识。
const STATE_NAMES: Dictionary = {"cultivating": "修行", "tribulation": "渡劫", "seclusion": "闭关", "ascended": "飞升"}
const STAGE_NAMES: Dictionary = {
	"admission": "入院", "emergency": "急诊处置", "monitoring": "监护观察", "ward": "转入普通病房", "discharge": "出院",
	"preop": "术前准备", "surgery": "手术", "recovery": "术后恢复",
	"acute": "加重期", "stable": "稳定期", "improving": "好转"
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

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "KaiTi"])
	if kernel == null:
		kernel = get_node_or_null("/root/GameKernel")
	var current: Dictionary = _entry()
	if not str(current.get("template_id", "")).is_empty():
		template_id = current.template_id
	_build_controls()
	_refresh()

func _build_controls() -> void:
	var column := VBoxContainer.new()
	column.position = Vector2(60, 720)
	column.size.x = 1320
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 12)
	column.add_child(row)
	for stage in Rules.TEMPLATES[template_id].stages:
		var button := Button.new()
		button.text = STAGE_NAMES.get(stage, stage)
		button.pressed.connect(func() -> void: update_stage(stage))
		row.add_child(button)
		_stage_buttons.append(button)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 12)
	column.add_child(actions)
	for item in [["开启渡劫", "begin"], ["痊愈出院", "celebrate"], ["闭关 / 出关", "seclusion"], ["羽化飞升", "ascend"]]:
		var button := Button.new()
		button.text = item[0]
		var action: String = item[1]
		_state_buttons[action] = button
		button.pressed.connect(func() -> void: request_confirmation(action))
		actions.add_child(button)
	var lamp := Button.new()
	lamp.text = "护法点灯"
	lamp.pressed.connect(light_lamp)
	actions.add_child(lamp)
	var retry := Button.new()
	retry.text = "重试上次操作"
	retry.pressed.connect(func() -> void: request_confirmation(_last_action))
	actions.add_child(retry)
	var share := Button.new()
	share.text = "保存庆典卡片"
	share.pressed.connect(export_card)
	actions.add_child(share)
	var back := Button.new()
	back.text = "返回"
	back.pressed.connect(func() -> void: left.emit())
	actions.add_child(back)
	_dialog = ConfirmationDialog.new()
	_dialog.title = "家属确认"
	_dialog.get_ok_button().text = "确认"
	_dialog.get_cancel_button().text = "取消"
	_dialog.confirmed.connect(confirm_pending)
	_dialog.canceled.connect(cancel_pending)
	add_child(_dialog)
	var templates := OptionButton.new()
	_template_selector = templates
	templates.position = Vector2(60, 120)
	for key in Rules.TEMPLATES:
		templates.add_item(Rules.TEMPLATES[key].title)
		templates.set_item_metadata(templates.item_count - 1, key)
	var initial_index: int = Rules.TEMPLATES.keys().find(template_id)
	templates.select(maxi(0, initial_index))
	templates.item_selected.connect(func(index: int) -> void:
		if current_state() != "cultivating":
			status = "渡劫期间保留已选模板"
			return
		template_id = str(templates.get_item_metadata(index))
		template_chosen.emit(template_id)
		for i in range(_stage_buttons.size()):
			_stage_buttons[i].text = STAGE_NAMES[Rules.TEMPLATES[template_id].stages[i]]
		_refresh()
	)
	add_child(templates)

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
	_flash = maxf(0, _flash - delta)
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
	for button in _stage_buttons:
		button.disabled = busy or state != "tribulation"
	for action in _state_buttons:
		var allowed: bool = state in ["tribulation", "seclusion"] if action in ["ascend", "seclusion"] else (state == "cultivating" if action == "begin" else state == "tribulation")
		_state_buttons[action].disabled = busy or not allowed
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.08, 0.14))
	if current_state() == "seclusion" and quiet_background_texture != null:
		draw_texture_rect(quiet_background_texture, Rect2(Vector2.ZERO, size), false, Color(0.4, 0.4, 0.45))
	elif background_texture != null:
		draw_texture_rect(background_texture, Rect2(Vector2.ZERO, size), false, Color(0.36, 0.36, 0.42))
	if cultivator_texture != null:
		var portrait_size := Vector2(cultivator_texture.get_width(), cultivator_texture.get_height())
		portrait_size *= 140.0 / portrait_size.y
		draw_texture_rect(cultivator_texture, Rect2(Vector2(1260, 590) - Vector2(portrait_size.x / 2.0, portrait_size.y), portrait_size), false)

	var entry: Dictionary = _entry()
	var stage_index: int = int(entry.get("stage_index", -1))
	var count: int = Rules.TEMPLATES[template_id].stages.size()
	for index in range(count if current_state() not in ["seclusion", "ascended"] else 0):
		var lit: bool = index <= stage_index
		var center := Vector2(240 + index * 240, 330)
		draw_circle(center, 54.0, Color(0.85, 0.8, 0.35) if lit else Color(0.2, 0.22, 0.3))
		if index == stage_index:
			draw_arc(center, 64.0, 0.0, TAU, 48, Color(1.0, 0.95, 0.7), 4.0)
		var stage_key: String = Rules.TEMPLATES[template_id].stages[index]
		var label_color: Color = Color(1.0, 0.95, 0.7) if index == stage_index else Color(0.7, 0.75, 0.85)
		draw_string(_font, center + Vector2(-90, 110), STAGE_NAMES.get(stage_key, stage_key), HORIZONTAL_ALIGNMENT_CENTER, 180, 22, label_color)
	for lamp in range(lamps):
		draw_circle(Vector2(120 + lamp * 44, 560), 14.0, Color(1.0, 0.85, 0.4))
	if current_state() == "seclusion":
		if quiet_background_texture == null:
			draw_rect(Rect2(500, 250, 440, 260), Color("#243f46"))
			draw_rect(Rect2(630, 335, 180, 175), Color("#142b35"))
		else:
			draw_rect(Rect2(440, 275, 560, 190), Color(0.06, 0.12, 0.15, 0.85))
			draw_rect(Rect2(440, 275, 560, 190), Color("#b9ba8c"), false, 2)
			draw_string(_font, Vector2(605, 380), "静守 · 闭关", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color("#ead9ac"))
		draw_arc(Vector2(720, 360), 160 + sin(_clock) * 4, PI, TAU, 40, Color("#b9ba8c"), 3)
		draw_string(_font, Vector2(530, 565), "专业的人负责照护，家人负责陪伴", HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
	if _flash > 0 and current_state() == "tribulation":
		var bolt := PackedVector2Array([Vector2(700, 175), Vector2(660, 230), Vector2(735, 222), Vector2(690, 300)])
		draw_polyline(bolt, Color(0.9, 0.95, 1, _flash), 7)
	if current_state() == "ascended":
		for star in range(18):
			draw_circle(Vector2(140 + star * 70, 130 + (star * 37) % 100), 4.0 + star % 3, Color(0.85, 0.9, 1.0))
	if celebrating:
		for spark in range(24):
			draw_circle(Vector2(180 + spark * 48, 150 + (spark % 5) * 36), 6.0, Color.from_hsv(spark / 24.0, 0.6, 1.0))
	var title: String = "%s · 状态：%s" % [Rules.TEMPLATES[template_id].title if current_state() == "tribulation" else "家人修行", STATE_NAMES.get(current_state(), current_state()) if not current_state().is_empty() else "未同步"]
	draw_string(_font, Vector2(60, 80), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.95, 0.9, 0.75))
	draw_string(_font, Vector2(60, 650), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.95, 0.9, 0.75))
	draw_string(_font, Vector2(60, 690), "护法只影响画面与留言，不影响渡劫结果", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.7, 0.75, 0.85))

func _exit_tree() -> void:
	for child in get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null

