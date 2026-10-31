extends RefCounted
## 每个系统继承此基类：独占一个状态区，暴露命令、快照与事实事件。
## 初始只保存框架版本标记；具体领域状态由系统负责人增加并提供迁移。
const Result = preload("res://scripts/kernel/result.gd")
const Contracts = preload("res://scripts/kernel/contracts.gd")
var module_id: String
var _context: RefCounted
var _subscriptions: Array[int] = []

func _init(identifier: String = "") -> void:
	module_id = identifier

func state_version() -> int:
	return 1

func initial_state() -> Dictionary:
	return {"revision": 0}

func validate_state(state: Dictionary) -> bool:
	return Contracts.validate(state, {"revision": "integer"}).ok and state.revision >= 0

## 签名固定：返回 Result.success({"state": 新状态})；不得在迁移中写文件或发事件。
func migrate_state(_from_version: int, _state: Dictionary) -> Dictionary:
	return Result.failure("MIGRATION_REQUIRED", "尚未提供系统状态迁移：" + module_id)

func start(context: RefCounted) -> void:
	_context = context

## 账号或传输变化时，各系统只清理自己的账号相关投影。
func on_backend_changed() -> void:
	pass

## 子类可改为异步方法并 await 后端；调用方始终 await dispatch。
## 未实现必须显式失败，尤其不能伪造抽卡结果、奖励或家属确认。
func execute(_command: String, _payload: Dictionary) -> Dictionary:
	return Result.failure("NOT_IMPLEMENTED", "该系统仅有框架，业务尚未实现：" + module_id)

func snapshot() -> Dictionary:
	return _context.store.snapshot(module_id)

## 系统通过注入的传输访问服务端，不寻找全局节点、不持有其他系统实例。
func request_backend(command: String, payload: Dictionary, idempotency_key: String = "") -> Dictionary:
	if _context == null or not is_instance_valid(_context.backend):
		return Result.failure("BACKEND_UNAVAILABLE", "尚未注入后端适配器")
	return await _context.backend.invoke(command, payload, idempotency_key)

## 系统只写自己的状态。先提交，再通知 UI；事件不夹带整个状态对象。
func commit(state: Dictionary) -> Dictionary:
	var result: Dictionary = _context.store.replace(module_id, state)
	if result.ok:
		_context.events.publish("kernel.state_changed", {"module_id": module_id})
	return result

func listen(topic: String, callback: Callable) -> int:
	var token: int = _context.events.subscribe(topic, callback)
	if token >= 0:
		_subscriptions.append(token)
	return token

func stop() -> void:
	for token in _subscriptions:
		_context.events.unsubscribe(token)
	_subscriptions.clear()
	_context = null
