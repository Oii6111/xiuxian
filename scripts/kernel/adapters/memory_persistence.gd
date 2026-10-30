extends RefCounted
## 测试、演示与无存档会话使用；接口与本地 JSON 适配器完全相同。
const Result = preload("res://scripts/kernel/result.gd")
var _document: Dictionary = {}

func read_document() -> Dictionary:
	if _document.is_empty():
		return Result.failure("NOT_FOUND", "尚无存档")
	return Result.success({"document": _document})

func write_document(document: Dictionary) -> Dictionary:
	_document = document.duplicate(true)
	return Result.success()
