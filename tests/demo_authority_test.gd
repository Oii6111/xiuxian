extends SceneTree
## 演示替身确认测试：入口在 demo_authority 开启时，渡劫台能走完整流程；关闭时不创建替身。
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
	var plain: Control = HubScene.instantiate()
	root.add_child(plain)
	await process_frame
	expect(not plain.demo_authority and plain._demo == null, "substitute authority is off by default")
	plain.open("platform")
	expect(plain._demo == null and plain.current.kernel != plain, "default platform gets no substitute authority")
	plain.close()
	plain.queue_free()
	await process_frame
	var hub: Control = HubScene.instantiate()
	hub.demo_authority = true
	root.add_child(hub)
	await process_frame
	expect(hub.open("platform") and hub._demo != null, "demo mode creates an isolated runtime")
	var platform: Control = hub.current
	await process_frame
	expect(platform.current_state() == "cultivating", "demo cultivator starts cultivating")
	var labeled: bool = false
	for child in platform.get_children():
		if child is Label and child.text.contains("非真实家属确认"):
			labeled = true
	expect(labeled, "substitute confirmation is clearly labeled")
	await platform.begin_tribulation()
	expect(platform.current_state() == "tribulation", "substitute confirms entering tribulation")
	await platform.update_stage("admission")
	await platform.update_stage("discharge")
	expect(platform.current_state() == "tribulation" and platform.status.contains("另行确认"), "discharge does not settle by itself")
	await platform.celebrate()
	expect(platform.celebrating and platform.current_state() == "cultivating", "family confirmation step completes the celebration")
	# 再进一次渡劫，验证飞升需要两次确认且不触发庆典。
	platform.celebrating = false
	await platform.begin_tribulation()
	expect(platform.current_state() == "tribulation", "second tribulation starts")
	await platform.ascend_step()
	expect(platform.current_state() == "tribulation" and platform.status.contains("再次确认"), "first ascension confirmation does not change the state")
	await platform.ascend_step()
	expect(platform.current_state() == "ascended" and platform.status.contains("星"), "second confirmation completes ascension")
	expect(not platform.celebrating, "ascension never triggers the celebration")
	await platform.ascend_step()
	expect(platform.current_state() == "ascended" and platform.status == "尚未进入渡劫", "ascended is terminal and cannot ascend again")
	expect(root.get_node("GameKernel").snapshot("lifecycle").cultivators.is_empty(), "global kernel state is untouched")
	hub.close()
	await process_frame
	expect(hub._demo == null and hub.get_child_count() == 1, "closing frees the demo runtime")
	hub.queue_free()
	await process_frame
	print("DEMO_AUTHORITY_TEST: %d assertions; %d failures" % [_assertions, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
