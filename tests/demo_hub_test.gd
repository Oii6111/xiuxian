extends SceneTree
## 演示入口测试：无界面实例化 demo_hub.tscn，只调用其公开接口。
const HubScene = preload("res://scenes/combat/demo_hub.tscn")
var _assertions: int = 0
var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func expect(condition: bool, description: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(description)
		printerr("FAIL: ", description)

func _run() -> void:
	var hub: Control = HubScene.instantiate()
	root.add_child(hub)
	await process_frame
	expect(hub.current == null and hub._menu.visible, "hub starts on the menu")
	expect(not hub.open("unknown") and hub.current == null, "unknown target is rejected")
	expect(hub.open("level") and hub.current != null and not hub._menu.visible, "level opens and hides the menu")
	expect(not hub.current.boss_mode, "plain level keeps boss mode off")
	expect(not hub.open("boss"), "cannot open a second scene while one is open")
	hub.current.left.emit()
	await process_frame
	expect(hub.current == null and hub._menu.visible, "leaving returns to the menu")
	expect(hub.open("boss") and hub.current.boss_mode, "boss target enables boss mode")
	expect(not hub.current.allies_enabled, "plain boss target has no teammate")
	hub.close()
	await process_frame
	expect(hub.open("boss_party") and hub.current.boss_mode and hub.current.allies_enabled, "boss_party target enables boss mode and the teammate")
	hub.close()
	hub.close()
	await process_frame
	expect(hub.current == null, "closing twice is harmless")
	expect(hub.open("platform") and hub.current != null, "tribulation platform opens")
	hub.current.left.emit()
	await process_frame
	expect(hub.get_child_count() == 1, "no scene is left behind after leaving")
	hub.queue_free()
	await process_frame
	print("DEMO_HUB_TEST: %d assertions; %d failures" % [_assertions, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
