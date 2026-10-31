extends SceneTree
## 内核契约测试：不依赖真实后端、不读玩家存档，文件测试仅写 work/kernel/。
const Runtime = preload("res://scripts/kernel/runtime.gd")
const Result = preload("res://scripts/kernel/result.gd")
const Contracts = preload("res://scripts/kernel/contracts.gd")
const Clock = preload("res://scripts/kernel/clock.gd")
const RandomStreams = preload("res://scripts/kernel/random_streams.gd")
const EventBus = preload("res://scripts/kernel/event_bus.gd")
const Registry = preload("res://scripts/kernel/registry.gd")
const Store = preload("res://scripts/kernel/store.gd")
const Memory = preload("res://scripts/kernel/adapters/memory_persistence.gd")
const JsonPersistence = preload("res://scripts/kernel/adapters/json_persistence.gd")
const Router = preload("res://scripts/kernel/command_router.gd")
const Audit = preload("res://scripts/kernel/audit.gd")
const GameApi = preload("res://scripts/net/game_api.gd")
var _assertions: int = 0
var _failures: Array[String] = []

## 验证团队扩展协议，不实现任何实际玩法；状态沿用基类的 revision。
class ProbeModule:
	extends "res://scripts/kernel/system_module.gd"
	var notifications: int = 0

	func _init() -> void:
		super("probe")

	func start(context: RefCounted) -> void:
		super(context)
		listen("kernel.state_changed", _on_changed)

	func execute(_command: String, _payload: Dictionary) -> Dictionary:
		var state: Dictionary = snapshot()
		state.revision += 1
		return commit(state)

	func _on_changed(_payload: Dictionary) -> void:
		notifications += 1

func _init() -> void:
	call_deferred("_run")

func expect(condition: bool, description: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(description)
		printerr("FAIL: ", description)

func _run() -> void:
	_test_contracts()
	_test_clock_and_random()
	_test_events_and_registry()
	_test_store()
	_test_file_persistence()
	await _test_router()
	await _test_runtime()
	print("KERNEL_TEST: %d assertions; %d failures" % [_assertions, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _test_contracts() -> void:
	var original: Dictionary = {"nested": {"value": 1}}
	var result: Dictionary = Result.success(original)
	original.nested.value = 2
	expect(result.data.nested.value == 1, "Result owns a deep copy")
	expect(Contracts.validate({"count": 2.0}, {"count": "integer"}).ok, "JSON integer floats accepted")
	expect(not Contracts.validate({"count": 2.1}, {"count": "integer"}).ok, "fractional count rejected")
	expect(not Contracts.validate({"count": true}, {"count": "integer"}).ok, "boolean is not an integer")
	expect(not Contracts.is_json({"node": self}), "engine objects cannot enter DTOs")
	expect(not Contracts.is_json({"value": INF}), "non-finite numbers rejected")
	expect(not Contracts.valid_fields({"count": "typo"}), "unknown contract field types rejected")
	expect(not Contracts.validate({"id": "x", "blood_glucose": 7}, {"id": "string"}).ok, "extra private fields rejected")

func _test_clock_and_random() -> void:
	var clock := Clock.new(func() -> int: return 0)
	expect(clock.now_unix() == 0, "clock is injectable")
	expect(clock.day_key(57599) == "1970-01-01", "UTC+8 before day boundary")
	expect(clock.day_key(57600) == "1970-01-02", "UTC+8 day boundary")
	expect(clock.week_key(0) == "1969-12-29", "week key is the local Monday date")
	var first := RandomStreams.new(42)
	var second := RandomStreams.new(42)
	first.stream("ui").randi()
	for sample in range(5):
		expect(first.stream("combat").randi() == second.stream("combat").randi(), "independent deterministic random stream %d" % sample)

func _test_events_and_registry() -> void:
	var bus := EventBus.new()
	expect(bus.define_topic("changed", {"items": "array"}).ok, "topic registered")
	expect(not bus.define_topic("changed", {}).ok, "duplicate topic rejected")
	var received: Array = []
	bus.subscribe("changed", func(payload: Dictionary) -> void: payload.items.append("listener edit"))
	var token: int = bus.subscribe("changed", func(payload: Dictionary) -> void: received.append(payload))
	var payload: Dictionary = {"items": ["original"]}
	expect(bus.publish("changed", payload).ok, "typed event published")
	expect(received[0].items == ["original"] and payload.items == ["original"], "listeners and publisher cannot mutate each other")
	bus.unsubscribe(token)
	bus.publish("changed", payload)
	expect(received.size() == 1, "subscription token disconnects listener")
	expect(not bus.publish("unknown", {}).ok, "unknown event rejected")
	expect(not bus.publish("changed", {"items": "wrong"}).ok, "invalid event payload rejected")
	bus.clear()
	var registry := Registry.new()
	var rows: Array = [{"id": "sample", "options": [1]}]
	expect(registry.register_table("test", rows).ok, "configuration registered")
	rows[0].options.append(2)
	var readback: Dictionary = registry.get_entry("test", "sample")
	readback.options.append(3)
	expect(registry.get_entry("test", "sample").options == [1], "registry owns immutable snapshots")
	expect(not registry.register_table("duplicates", [{"id": "x"}, {"id": "x"}]).ok, "duplicate config IDs rejected")

func _valid_counter(state: Dictionary) -> bool:
	return Contracts.validate(state, {"count": "integer"}).ok and state.count >= 0

func _test_store() -> void:
	var persistence := Memory.new()
	var store := Store.new(persistence)
	expect(store.register_section("first", 1, {"count": 0}, _valid_counter).ok, "state section registered")
	store.register_section("second", 1, {"count": 0}, _valid_counter)
	expect(store.load_save().ok, "missing save starts from defaults")
	store.replace("first", {"count": 3})
	var view: Dictionary = store.snapshot("first")
	view.count = 100
	expect(store.snapshot("first").count == 3, "read snapshot cannot mutate state")
	expect(not store.replace("first", {"count": -1}).ok, "invalid state rejected")
	expect(store.save().ok, "save uses adapter")
	store.replace("first", {"count": 4})
	expect(store.load_save().ok and store.snapshot("first").count == 3, "save restores validated state")
	var document: Dictionary = persistence.read_document().data.document
	document.sections.first.state.count = 10
	document.sections.second.state.count = -1
	persistence.write_document(document)
	expect(not store.load_save().ok, "invalid section aborts load")
	expect(store.snapshot("first").count == 3, "failed load does not partially replace earlier sections")
	expect(store.save().code == "SAVE_BLOCKED", "corrupt save cannot be overwritten")
	var upgraded := Store.new(persistence)
	upgraded.register_section("first", 2, {"count": 0}, _valid_counter, func(_version: int, state: Dictionary) -> Dictionary:
		return Result.success({"state": {"count": state.count + 1}}))
	upgraded.register_section("second", 1, {"count": 0}, _valid_counter)
	document.sections.second.state.count = 0
	persistence.write_document(document)
	expect(upgraded.load_save().ok and upgraded.snapshot("first").count == 11, "per-module migration runs before validation")
	document.sections.first.version = 99
	persistence.write_document(document)
	expect(upgraded.load_save().code == "SAVE_VERSION", "future module versions rejected")
	document.sections.first.version = 1
	document.sections["future_module"] = {"version": 1, "state": {}}
	persistence.write_document(document)
	expect(upgraded.load_save().code == "UNKNOWN_SECTION", "unknown modules are not silently discarded")

func _test_file_persistence() -> void:
	var path: String = "res://work/kernel/test-%d.json" % Time.get_ticks_usec()
	var persistence := JsonPersistence.new(path)
	var store := Store.new(persistence)
	store.register_section("counter", 1, {"count": 0}, _valid_counter)
	expect(store.load_save().ok and store.save().ok, "file adapter creates a new save")
	store.replace("counter", {"count": 8})
	expect(store.save().ok, "file adapter replaces an existing save")
	expect(FileAccess.file_exists(path + ".bak"), "previous file backed up")
	expect(store.load_save().ok and store.snapshot("counter").count == 8, "JSON round trip keeps numeric state")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	expect(store.load_save().code == "CORRUPT_SAVE", "broken JSON reported")
	expect(store.save().code == "SAVE_BLOCKED" and FileAccess.get_file_as_string(path) == "{broken", "broken file preserved")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)

func _test_router() -> void:
	var audit := Audit.new(Clock.new(), 2)
	var router := Router.new(audit)
	var state: Dictionary = {"count": 0}
	router.register("example.increment", {"amount": "integer"}, func(_command: String, payload: Dictionary) -> Dictionary:
		state.count += payload.amount
		return Result.success(state))
	var valid: Dictionary = await router.dispatch("example.increment", {"amount": 2})
	expect(valid.ok and state.count == 2, "command reaches its handler")
	var invalid: Dictionary = await router.dispatch("example.increment", {"amount": "2"})
	expect(not invalid.ok and state.count == 2, "validation happens before mutation")
	router.register("example.invalid", {}, func(_command: String, _payload: Dictionary) -> Dictionary: return {})
	var malformed: Dictionary = await router.dispatch("example.invalid")
	expect(malformed.code == "INVALID_RESULT", "handler must return Result")
	expect(audit.snapshot().size() == 2 and not audit.snapshot()[0].has("payload"), "audit bounded and excludes payloads")
	router.register("example.async", {}, _delayed_response)
	var delayed: Dictionary = await router.dispatch("example.async")
	expect(delayed.ok and delayed.data.delayed, "router awaits asynchronous handlers")
	router.clear()

func _delayed_response(_command: String, _payload: Dictionary) -> Dictionary:
	await process_frame
	return Result.success({"delayed": true})

func _test_runtime() -> void:
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/kernel/contracts.json"))
	var runtime := Runtime.new()
	var persistence := Memory.new()
	var startup: Dictionary = runtime.start(contract, persistence)
	expect(startup.ok and runtime.module_ids().size() == 7, "seven v2 modules boot together")
	if not startup.ok:
		runtime.shutdown()
		return
	expect(runtime.start(contract, persistence).code == "ALREADY_STARTED", "duplicate startup rejected")
	expect(runtime.services.registry.get_entry("resource_owners", "merit").value == "attendant", "resource ownership contract is available to modules")
	for descriptor in contract.modules:
		for command in descriptor.commands:
			var payload: Dictionary = {}
			for field in descriptor.commands[command]:
				match descriptor.commands[command][field]:
					"string": payload[field] = "example"
					"integer", "number": payload[field] = 1
					"bool": payload[field] = true
					"object": payload[field] = {}
			var response: Dictionary = await runtime.dispatch(command, payload)
			# growth/quests/season 已接入 C：离线时明确失败，绝不本地成功；其余模块仍等待负责人接入。
			var expected_code: String = "BACKEND_UNAVAILABLE" if command.get_slice(".", 0) in ["season", "growth", "quests"] else "NOT_IMPLEMENTED"
			expect(response.code == expected_code, "offline system boundary: " + command)
	var unknown: Dictionary = await runtime.dispatch("not.a.command")
	expect(unknown.code == "UNKNOWN_COMMAND", "unknown command rejected")
	expect(runtime.save().ok, "runtime saves registered sections together")
	runtime.shutdown()
	expect(runtime.start(contract, persistence).ok, "runtime can restart without stale subscriptions")
	var probe := ProbeModule.new()
	probe.start(runtime.services)
	runtime.services.store.register_section("probe", probe.state_version(), probe.initial_state(), probe.validate_state)
	expect(probe.execute("probe.advance", {}).ok and probe.snapshot().revision == 1, "extension module commits through its own section")
	expect(probe.notifications == 1, "successful commit emits state notification")
	expect(not probe.commit({"revision": -1}).ok and probe.notifications == 1, "rejected state does not emit a success event")
	probe.stop()
	runtime.services.events.publish("kernel.state_changed", {"module_id": "probe"})
	expect(probe.notifications == 1, "module stop removes its subscriptions")
	runtime.shutdown()
	var invalid_contract: Dictionary = contract.duplicate(true)
	invalid_contract.modules.append({"id": "missing", "commands": {}})
	expect(not runtime.start(invalid_contract, persistence).ok and runtime.services == null, "failed assembly releases services")
	var api := GameApi.new()
	var unavailable: Dictionary = await api.invoke("growth.draw", {})
	expect(unavailable.code == "BACKEND_UNAVAILABLE", "no backend never means local reward success")
	api.free()
	# 验证真实 Autoload + F6 场景能启动，而不仅是独立服务单测。
	var kernel: Node = root.get_node("GameKernel")
	expect(kernel.status().ok, "autoload boots")
	var scene: Control = load("res://scenes/kernel/workbench.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await scene._probe_command()
	expect(scene._output.text.contains("BACKEND_UNAVAILABLE"), "workbench exercises the real command path")
	scene.queue_free()
	await process_frame
