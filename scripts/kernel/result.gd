extends RefCounted
## 内核与系统统一返回值；失败不使用空字典或假成功。

static func success(data: Dictionary = {}) -> Dictionary:
	return {"ok": true, "code": "OK", "message": "", "data": data.duplicate(true)}

static func failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message, "data": {}}
