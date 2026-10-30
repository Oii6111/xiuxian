extends RefCounted
## 轻量 DTO 校验，不实现完整 JSON Schema。跨系统只传 JSON 值，不传 Node/Resource。
const Result = preload("res://scripts/kernel/result.gd")

static func valid_fields(fields: Dictionary) -> bool:
	for field in fields:
		if not field is String or field.is_empty() or fields[field] not in ["string", "bool", "integer", "number", "array", "object"]:
			return false
	return true

static func is_json(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING, TYPE_INT:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_ARRAY:
			for item in value:
				if not is_json(item):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if not key is String or not is_json(value[key]):
					return false
			return true
	return false

## 所有声明字段必填，拒绝额外字段，避免把整个原始健康对象传进游戏命令。
static func validate(payload: Dictionary, fields: Dictionary) -> Dictionary:
	if payload.size() != fields.size() or not is_json(payload):
		return Result.failure("INVALID_PAYLOAD", "字段不匹配或包含非 JSON 数据")
	for field in fields:
		if not payload.has(field) or not matches(payload[field], str(fields[field])):
			return Result.failure("INVALID_PAYLOAD", "字段类型错误：" + str(field))
	return Result.success()

static func matches(value: Variant, kind: String) -> bool:
	match kind:
		"string":
			return value is String and not value.strip_edges().is_empty()
		"bool":
			return value is bool
		"integer":
			# JSON 读回的数字可能是 float，只接受无小数的有限数值。
			return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))
		"number":
			return (value is int or value is float) and is_finite(float(value))
		"array":
			return value is Array
		"object":
			return value is Dictionary
	return false
