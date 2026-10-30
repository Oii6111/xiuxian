extends RefCounted
## 唯一装配根：创建服务、注册模块，按反向顺序释放依赖。
## 运行时不依赖 SceneTree，可在 headless 测试中直接启动。
const Result = preload("res://scripts/kernel/result.gd")
const Clock = preload("res://scripts/kernel/clock.gd")
const Events = preload("res://scripts/kernel/event_bus.gd")
const RandomStreams = preload("res://scripts/kernel/random_streams.gd")
const Registry = preload("res://scripts/kernel/registry.gd")
const Store = preload("res://scripts/kernel/store.gd")
const Audit = preload("res://scripts/kernel/audit.gd")
const Context = preload("res://scripts/kernel/system_context.gd")
const Router = preload("res://scripts/kernel/command_router.gd")
const MODULE_SCRIPTS: Array = [
	preload("res://scripts/systems/growth/module.gd"),
	preload("res://scripts/systems/combat/module.gd"),
	preload("res://scripts/systems/quests/module.gd"),
	preload("res://scripts/systems/lifecycle/module.gd"),
	preload("res://scripts/systems/story/module.gd"),
	preload("res://scripts/systems/social/module.gd"),
	preload("res://scripts/systems/season/module.gd")
]
var services: RefCounted
var _router: RefCounted
var _modules: Dictionary = {}
var _started: bool = false

func start(contract: Dictionary, persistence: RefCounted, clock_source: Callable = Callable(), seed_value: int = 1) -> Dictionary:
	if services != null:
		return Result.failure("ALREADY_STARTED", "请先关闭现有运行时")
	if contract.get("version") != 1 or not contract.get("modules") is Array or not contract.get("events") is Array:
		return Result.failure("INVALID_CONFIG", "不支持的内核契约")
	services = Context.new()
	services.clock = Clock.new(clock_source)
	services.events = Events.new()
	services.random = RandomStreams.new(seed_value)
	services.registry = Registry.new()
	services.store = Store.new(persistence)
	services.audit = Audit.new(services.clock)
	_router = Router.new(services.audit)
	var registered: Dictionary = services.registry.register_table("modules", contract.modules)
	if not registered.ok:
		return _abort(registered)
	registered = services.registry.register_table("events", contract.events)
	if not registered.ok:
		return _abort(registered)
	for table_id in ["enums", "resource_owners"]:
		if not contract.get(table_id) is Dictionary:
			return _abort(Result.failure("INVALID_CONFIG", "缺少共享词汇表"))
		var rows: Array = []
		for identifier in contract[table_id]:
			rows.append({"id": identifier, "value": contract[table_id][identifier]})
		registered = services.registry.register_table(table_id, rows)
		if not registered.ok:
			return _abort(registered)
	for event in contract.events:
		if not event.get("fields") is Dictionary:
			return _abort(Result.failure("INVALID_CONFIG", "事件缺少字段定义"))
		registered = services.events.define_topic(event.id, event.fields)
		if not registered.ok:
			return _abort(registered)
	for module_script in MODULE_SCRIPTS:
		var module: RefCounted = module_script.new()
		var descriptor: Dictionary = services.registry.get_entry("modules", module.module_id)
		if not descriptor.get("commands") is Dictionary:
			return _abort(Result.failure("INVALID_CONFIG", "系统缺少命令定义"))
		module.start(services)
		_modules[module.module_id] = module
		registered = services.store.register_section(module.module_id, module.state_version(), module.initial_state(), module.validate_state, module.migrate_state)
		if not registered.ok:
			return _abort(registered)
		for command in descriptor.commands:
			if not command is String or not command.begins_with(module.module_id + ".") or not descriptor.commands[command] is Dictionary:
				return _abort(Result.failure("INVALID_CONFIG", "命令必须位于系统命名空间内"))
			registered = _router.register(command, descriptor.commands[command], module.execute)
			if not registered.ok:
				return _abort(registered)
	if _modules.size() != contract.modules.size():
		return _abort(Result.failure("INVALID_CONFIG", "存在未装配的系统"))
	var loaded: Dictionary = services.store.load_save()
	if not loaded.ok:
		# 载入失败的 Store 保留写保护；允许 UI 展示错误和默认只读快照。
		services.audit.record("kernel.load", loaded.code)
		return loaded
	_started = true
	var announced: Dictionary = services.events.publish("kernel.ready", {"modules": module_ids()})
	if not announced.ok:
		return _abort(announced)
	return Result.success({"modules": module_ids(), "restored": loaded.data.restored})

func module_ids() -> Array:
	return _modules.keys()

func snapshot(module_id: String) -> Dictionary:
	return _modules[module_id].snapshot() if _modules.has(module_id) else {}

func dispatch(command: String, payload: Dictionary = {}) -> Dictionary:
	if not _started:
		return Result.failure("NOT_READY", "内核尚未成功启动")
	return await _router.dispatch(command, payload)

func save() -> Dictionary:
	if not _started:
		return Result.failure("NOT_READY", "内核尚未成功启动")
	return services.store.save()

func shutdown() -> void:
	_started = false
	var identifiers: Array = _modules.keys()
	identifiers.reverse()
	for identifier in identifiers:
		_modules[identifier].stop()
	_modules.clear()
	if _router != null:
		_router.clear()
	if services != null:
		services.events.clear()
	# module.stop 已切断 context 引用，避免存档校验 Callable 形成引用环。
	_router = null
	services = null

func _abort(result: Dictionary) -> Dictionary:
	shutdown()
	return result
