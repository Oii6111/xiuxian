extends SceneTree
## Seclusion flow test: tribulation -> seclusion -> cultivating, one confirmation each, no celebration.
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
	hub.demo_authority = true
	root.add_child(hub)
	await process_frame
	hub.open("platform")
	var platform: Control = hub.current
	await process_frame
	await platform.seclusion_step()
	expect(platform.current_state() == "cultivating" and platform.status == "渡劫中才能转入闭关", "seclusion needs an active tribulation")
	await platform.begin_tribulation()
	await platform.seclusion_step()
	expect(platform.current_state() == "seclusion" and platform.status.contains("闭关"), "confirmation moves tribulation into seclusion")
	expect(not platform.celebrating, "seclusion never celebrates")
	platform.request_confirmation("ascend")
	platform.cancel_pending()
	expect(platform.current_state() == "seclusion", "canceling ascension from seclusion preserves state")
	await platform.seclusion_step()
	expect(platform.current_state() == "cultivating" and platform.status.contains("出关"), "second confirmation ends seclusion")
	expect(not platform.celebrating, "leaving seclusion never celebrates")
	hub.close()
	hub.queue_free()
	await process_frame
	print("SECLUSION_FLOW_TEST: %d assertions; %d failures" % [_assertions, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
