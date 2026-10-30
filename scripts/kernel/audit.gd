extends RefCounted
## 有界内存审计，只记录动作名称、错误码与时间；禁止保存命令 payload。
var _clock: RefCounted
var _capacity: int
var _entries: Array = []

func _init(clock_service: RefCounted, capacity: int = 200) -> void:
	_clock = clock_service
	_capacity = maxi(1, capacity)

func record(operation: String, code: String) -> void:
	_entries.append({"operation": operation, "code": code, "at_unix": _clock.now_unix()})
	if _entries.size() > _capacity:
		_entries.pop_front()

func snapshot() -> Array:
	return _entries.duplicate(true)
