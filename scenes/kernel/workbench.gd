extends Control
## 开发者接入示例：只读快照、发送 Intent、订阅后按令牌退订。
## 在编辑器打开 workbench.tscn 按 F6；这不是正式游戏界面。
var _output: Label
var _subscription: int = -1

func _ready() -> void:
	var column := VBoxContainer.new()
	column.position = Vector2(48, 40)
	column.add_theme_constant_override("separation", 16)
	add_child(column)
	var title := Label.new()
	title.text = "家族修真录 v2 · 内核接入工作台"
	title.add_theme_font_size_override("font_size", 28)
	column.add_child(title)
	_output = Label.new()
	column.add_child(_output)
	var probe := Button.new()
	probe.text = "检查命令契约（预期返回 NOT_IMPLEMENTED）"
	probe.pressed.connect(_probe_command)
	column.add_child(probe)
	_subscription = GameKernel.subscribe("kernel.state_changed", _on_state_changed)
	_refresh()

func _refresh() -> void:
	var result: Dictionary = GameKernel.status()
	_output.text = "启动：%s\n" % result.code
	for identifier in GameKernel.module_ids():
		_output.text += "%s  %s\n" % [identifier, JSON.stringify(GameKernel.snapshot(identifier))]
	if not result.ok:
		_output.text += result.message

func _probe_command() -> void:
	var result: Dictionary = await GameKernel.dispatch("growth.create", {"name": "示例修仙者", "element": "water"})
	_refresh()
	_output.text += "\n命令返回：%s · %s" % [result.code, result.message]

func _on_state_changed(_event: Dictionary) -> void:
	_refresh()

func _exit_tree() -> void:
	GameKernel.unsubscribe(_subscription)
