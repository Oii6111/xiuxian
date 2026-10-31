extends SceneTree
## 渡劫台场景测试：真实 Runtime + 替身服务端确认通道，不联网、不读玩家存档。
## 场景通过 kernel 引用调用 lifecycle.*，这里用一个包装对象把 Runtime 暴露成同样的 dispatch/snapshot 接口。
const Runtime = preload("res://scripts/kernel/runtime.gd")
const Memory = preload("res://scripts/kernel/adapters/memory_persistence.gd")
const Result = preload("res://scripts/kernel/result.gd")
const PlatformScene = preload("res://scenes/tribulation/platform.tscn")
var _assertions: int = 0
var _failures: Array[String] = []
var _runtime: RefCounted
var _version: int = 10
var _celebrations: Array = []

class KernelFacade:
	extends Node
	var runtime: RefCounted
	func dispatch(command: String, payload: Dictionary) -> Dictionary:
		return await runtime.dispatch(command, payload)
	func snapshot(module_id: String) -> Dictionary:
		return runtime.snapshot(module_id)

func _init() -> void:
	call_deferred("_run")

func expect(condition: bool, description: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(description)
		printerr("FAIL: ", description)

## 替身服务端：一次确认即可完成（非飞升），版本单调递增。
func _authority(operation: String, payload: Dictionary) -> Dictionary:
	match operation:
		"request_change":
			return Result.success({"confirmation_token": "token-" + str(payload.cultivator_id)})
		"confirm_change":
			_version += 1
			return Result.success({"complete": true, "state": payload.target_state, "version": _version})
		"update_stage":
			_version += 1
			return Result.success({"version": _version})
	return Result.failure("UNKNOWN_OPERATION", "未知操作")

func _on_celebrated(cultivator_id: String) -> void:
	_celebrations.append(cultivator_id)

func _run() -> void:
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/kernel/contracts.json"))
	_runtime = Runtime.new()
	var started: Dictionary = _runtime.start(contract, Memory.new())
	expect(started.ok, "runtime boots")
	if not started.ok:
		quit(1)
		return
	var module: RefCounted = _runtime._modules["lifecycle"]
	module.apply_authoritative("c_demo", "cultivating", 1)
	var facade := KernelFacade.new()
	facade.runtime = _runtime
	root.add_child(facade)
	var scene: Control = PlatformScene.instantiate()
	scene.kernel = facade
	scene.celebrated.connect(_on_celebrated)
	root.add_child(scene)
	await process_frame
	# 没有服务端确认通道：明确失败，状态不变。
	await scene.begin_tribulation()
	expect(scene.status.contains("BACKEND_UNAVAILABLE") and scene.current_state() == "cultivating", "no authority means no local confirmation")
	await scene.celebrate()
	expect(scene.status == "尚未进入渡劫" and not scene.celebrating, "cannot celebrate before tribulation")
	module.set_authority(Callable(self, "_authority"))
	scene.light_lamp()
	expect(scene.lamps == 0, "lamps need an active tribulation")
	await scene.begin_tribulation()
	expect(scene.current_state() == "tribulation" and scene.status == "渡劫台亮起", "authority confirms tribulation")
	scene.light_lamp()
	scene.light_lamp()
	expect(scene.lamps == 2 and scene.current_state() == "tribulation", "lamps are visual only and never change state")
	await scene.update_stage("admission")
	await scene.update_stage("emergency")
	expect(scene.status == "落下一重雷劫", "forward stage drops a thunder trial")
	await scene.update_stage("admission")
	expect(scene.status == "劫云再聚，家人与你同在", "regression uses gentle wording")
	await scene.update_stage("discharge")
	expect(scene.status.contains("另行确认") and scene.current_state() == "tribulation", "reaching discharge does not settle automatically")
	expect(_celebrations.is_empty() and not scene.celebrating, "no celebration before family confirmation")
	await scene.celebrate()
	expect(scene.current_state() == "cultivating" and scene.celebrating and _celebrations == ["c_demo"], "family confirmation settles and celebrates once")
	scene.queue_free()
	facade.queue_free()
	await process_frame
	_runtime.shutdown()
	print("TRIBULATION_PLATFORM_TEST: %d assertions; %d failures" % [_assertions, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
