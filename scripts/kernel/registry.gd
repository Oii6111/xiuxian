extends RefCounted
## 配置由装配层读文件后注入；查询返回副本，系统不能修改公共配置。
const Result = preload("res://scripts/kernel/result.gd")
const Contracts = preload("res://scripts/kernel/contracts.gd")
var _tables: Dictionary = {}

func register_table(table_id: String, rows: Array) -> Dictionary:
	if table_id.is_empty() or _tables.has(table_id):
		return Result.failure("DUPLICATE_TABLE", "配置表为空或已注册")
	var indexed: Dictionary = {}
	for row in rows:
		if not row is Dictionary or not Contracts.is_json(row):
			return Result.failure("INVALID_CONFIG", "配置行必须是 JSON 对象")
		var identifier: Variant = row.get("id")
		if not identifier is String or identifier.is_empty() or indexed.has(identifier):
			return Result.failure("INVALID_CONFIG", "配置 id 缺失或重复")
		indexed[identifier] = row.duplicate(true)
	_tables[table_id] = indexed
	return Result.success()

func get_entry(table_id: String, entry_id: String) -> Dictionary:
	return _tables.get(table_id, {}).get(entry_id, {}).duplicate(true)

func list_entries(table_id: String) -> Array:
	return _tables.get(table_id, {}).values().duplicate(true)
