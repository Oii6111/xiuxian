extends Node
## UI 的唯一内核入口。全局只保留这一层薄门面，业务不堆在 Autoload 中。
const Runtime = preload("res://scripts/kernel/runtime.gd")
const Persistence = preload("res://scripts/kernel/adapters/json_persistence.gd")
const MemoryPersistence = preload("res://scripts/kernel/adapters/memory_persistence.gd")
const Result = preload("res://scripts/kernel/result.gd")
const CONTRACT_PATH: String = "res://data/kernel/contracts.json"
var _runtime: RefCounted
var _status: Dictionary = Result.failure("NOT_READY", "内核尚未启动")

func _ready() -> void:
	var file := FileAccess.open(CONTRACT_PATH, FileAccess.READ)
	if file == null:
		_status = Result.failure("CONFIG_MISSING", "找不到内核契约配置")
		return
	var parser := JSON.new()
	var parsed: Error = parser.parse(file.get_as_text())
	file.close()
	if parsed != OK or not parser.data is Dictionary:
		_status = Result.failure("INVALID_CONFIG", "内核契约 JSON 无效")
		return
	_runtime = Runtime.new()
	var persistence: RefCounted = MemoryPersistence.new() if "--kernel-ephemeral" in OS.get_cmdline_user_args() else Persistence.new()
	_status = _runtime.start(parser.data, persistence)

func status() -> Dictionary:
	return _status.duplicate(true)

func module_ids() -> Array:
	return _runtime.module_ids() if _runtime != null else []

func snapshot(module_id: String) -> Dictionary:
	return _runtime.snapshot(module_id) if _runtime != null else {}

func dispatch(command: String, payload: Dictionary = {}) -> Dictionary:
	if not _status.ok:
		return _status.duplicate(true)
	return await _runtime.dispatch(command, payload)

func subscribe(topic: String, callback: Callable) -> int:
	if not _status.ok:
		return -1
	return _runtime.services.events.subscribe(topic, callback)

func unsubscribe(token: int) -> void:
	if _runtime != null and _runtime.services != null:
		_runtime.services.events.unsubscribe(token)

## 显式保存；旧场景启动不会自动覆盖 v2 文件，也不读取旧仙村存档。
func save() -> Dictionary:
	return _runtime.save() if _runtime != null else _status.duplicate(true)

func _exit_tree() -> void:
	if _runtime != null:
		_runtime.shutdown()
