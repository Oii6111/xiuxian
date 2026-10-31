extends Control
## 演示入口：三个按钮分别打开单敌人关卡、Boss 关卡和渡劫台，Esc 返回。
## 默认只挂载与卸载子场景，不碰内核状态；渡劫台没有确认通道时会如实显示 BACKEND_UNAVAILABLE。
## 启动参数带 --demo-authority 时，渡劫台改用隔离的演示运行时和替身确认通道（非真实家属确认）。
const LEVEL_SCENE = preload("res://scenes/combat/level.tscn")
const PLATFORM_SCENE = preload("res://scenes/tribulation/platform.tscn")
const DemoKernel = preload("res://scripts/combat/demo_kernel.gd")
var demo_authority: bool = "--demo-authority" in OS.get_cmdline_user_args()
var current: Control = null
var _demo: Node = null
var transport: Node = null
var cultivator_id: String = "c_demo"
var player_element: String = "wood"
var weapon: String = "sword"
var _opening: bool = false
var _map_art: Texture2D = preload("res://assets/pixel_campaign/map_origin.png")
var _feedback: Label
var _menu: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu = VBoxContainer.new()
	_menu.position = Vector2(120, 140)
	_menu.add_theme_constant_override("separation", 20)
	add_child(_menu)
	var title := Label.new()
	title.text = "战斗与渡劫演示入口"
	title.add_theme_font_size_override("font_size", 32)
	_menu.add_child(title)
	var hint := Label.new()
	hint.text = "照生试炼 · WASD 移动 / 左键或 J 普攻 / Q 术法 / R 法宝 / Space 闪避"
	_menu.add_child(hint)
	var choices := HBoxContainer.new()
	_menu.add_child(choices)
	var root_choice := OptionButton.new()
	for item in [["木 · 续航", "wood"], ["火 · 爆发", "fire"], ["土 · 护盾", "earth"], ["金 · 远程", "metal"], ["水 · 控制", "water"]]:
		root_choice.add_item(item[0])
		root_choice.set_item_metadata(root_choice.item_count - 1, item[1])
	root_choice.item_selected.connect(func(index: int) -> void: player_element = str(root_choice.get_item_metadata(index)))
	choices.add_child(root_choice)
	var weapon_choice := OptionButton.new()
	weapon_choice.add_item("试用法器 · 近战剑")
	weapon_choice.add_item("试用法器 · 远程符")
	weapon_choice.item_selected.connect(func(index: int) -> void: weapon = "sword" if index == 0 else "talisman")
	choices.add_child(weapon_choice)
	for item in [["苍梧林 · 木", "trial_wood"], ["丹霞岭 · 火", "trial_fire"], ["白羽关 · 金", "trial_metal"]]:
		var trial_button := Button.new()
		trial_button.text = item[0]
		var encounter_id: String = item[1]
		trial_button.pressed.connect(func() -> void: launch_trial(encounter_id))
		_menu.add_child(trial_button)
	_feedback = Label.new()
	_feedback.text = "离线演示模式" if demo_authority else "三关需配置游戏接口；可用演示启动器试玩"
	_menu.add_child(_feedback)
	for spec in [["单敌人关卡", "level"], ["Boss 关卡（三阶段）", "boss"], ["Boss 关卡（带 AI 队友）", "boss_party"], ["渡劫台", "platform"]]:
		var button := Button.new()
		button.text = spec[0]
		var kind: String = spec[1]
		button.pressed.connect(func() -> void: open(kind))
		_menu.add_child(button)

func open(kind: String) -> bool:
	if current != null or _opening:
		return false
	var scene: Control
	match kind:
		"level":
			scene = LEVEL_SCENE.instantiate()
		"boss":
			scene = LEVEL_SCENE.instantiate()
			scene.boss_mode = true
		"boss_party":
			scene = LEVEL_SCENE.instantiate()
			scene.boss_mode = true
			scene.allies_enabled = true
		"platform":
			scene = PLATFORM_SCENE.instantiate()
			if demo_authority:
				_demo = DemoKernel.new()
				add_child(_demo)
				if not _demo.setup(scene.cultivator_id):
					_demo.queue_free()
					_demo = null
					scene.queue_free()
					return false
				scene.kernel = _demo
				var banner := Label.new()
				banner.text = "演示替身确认，非真实家属确认"
				banner.position = Vector2(60, 170)
				banner.add_theme_color_override("font_color", Color(1.0, 0.6, 0.4))
				scene.add_child(banner)
		_:
			return false
	scene.left.connect(close)
	current = scene
	_menu.visible = false
	add_child(scene)
	return true

func close() -> void:
	if current == null:
		return
	current.queue_free()
	current = null
	if _demo != null:
		_demo.queue_free()
		_demo = null
	_menu.visible = true

## B 主界面可以注入 transport/cultivator_id 复用此入口，UI 只调用门面命令。
func launch_trial(encounter_id: String) -> void:
	if current != null or _opening:
		return
	_opening = true
	var gateway: Node = transport
	if gateway == null and demo_authority:
		_demo = DemoKernel.new()
		_demo.player_element = player_element
		add_child(_demo)
		if not _demo.setup(cultivator_id):
			_feedback.text = "演示运行时启动失败，可重试"
			_opening = false
			return
		gateway = _demo
	if gateway == null:
		gateway = get_node_or_null("/root/GameKernel")
	var response: Dictionary = await gateway.dispatch("combat.start", {"cultivator_id": cultivator_id, "encounter_id": encounter_id})
	_opening = false
	if not response.ok:
		_feedback.text = str(response.code) + " · " + str(response.message)
		if _demo != null:
			_demo.queue_free()
			_demo = null
		return
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/combat/encounters.json"))
	for config in parsed.encounters:
		if config.id != encounter_id:
			continue
		var scene: Control = load("res://scenes/combat/trial.tscn").instantiate()
		scene.encounter = config
		scene.kernel = gateway
		scene.session_id = response.data.session_id
		scene.player_snapshot = response.data.player.duplicate(true)
		scene.weapon = weapon
		scene.left.connect(close)
		current = scene
		_menu.hide()
		add_child(scene)
		return
	_feedback.text = "未知关卡配置"

func _draw() -> void:
	draw_texture_rect(_map_art, Rect2(Vector2.ZERO, size), false, Color(0.28, 0.32, 0.32))
	draw_style_box(_panel_style(), Rect2(85, 100, 1265, 720))

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.1, 0.14, 0.94)
	style.border_color = Color("#a79767")
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	return style
