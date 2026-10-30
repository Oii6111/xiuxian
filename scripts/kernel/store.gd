extends RefCounted
## 模块状态仓库：读副本、校验后写、按模块版本迁移、整份载入原子提交。
## 本地仅保存游戏缓存，不能作为正式奖励/抽卡的服务端权威账本。
const Result = preload("res://scripts/kernel/result.gd")
const Contracts = preload("res://scripts/kernel/contracts.gd")
const FORMAT_VERSION: int = 1
var _adapter: RefCounted
var _definitions: Dictionary = {}
var _states: Dictionary = {}
var _writes_blocked: bool = false

func _init(persistence: RefCounted) -> void:
	_adapter = persistence

func register_section(section_id: String, version: int, defaults: Dictionary, validator: Callable, migrator: Callable = Callable()) -> Dictionary:
	if section_id.is_empty() or _definitions.has(section_id) or version < 1 or not validator.is_valid():
		return Result.failure("INVALID_SECTION", "状态区名称、版本或校验器无效")
	if not Contracts.is_json(defaults) or not validator.call(defaults.duplicate(true)):
		return Result.failure("INVALID_STATE", "默认状态未通过校验")
	_definitions[section_id] = {"version": version, "validate": validator, "migrate": migrator}
	_states[section_id] = defaults.duplicate(true)
	return Result.success()

func snapshot(section_id: String) -> Dictionary:
	return _states.get(section_id, {}).duplicate(true)

func replace(section_id: String, state: Dictionary) -> Dictionary:
	if not _definitions.has(section_id):
		return Result.failure("UNKNOWN_SECTION", "未注册状态区")
	if not Contracts.is_json(state) or not _definitions[section_id].validate.call(state.duplicate(true)):
		return Result.failure("INVALID_STATE", "状态校验失败")
	_states[section_id] = state.duplicate(true)
	return Result.success()

func save() -> Dictionary:
	if _writes_blocked:
		return Result.failure("SAVE_BLOCKED", "载入失败后禁止覆盖原存档，请先修复存档")
	var sections: Dictionary = {}
	for section_id in _definitions:
		sections[section_id] = {"version": _definitions[section_id].version, "state": snapshot(section_id)}
	return _adapter.write_document({"format_version": FORMAT_VERSION, "sections": sections})

func load_save() -> Dictionary:
	var loaded: Dictionary = _adapter.read_document()
	if not loaded.ok:
		if loaded.code == "NOT_FOUND":
			return Result.success({"restored": false})
		_writes_blocked = true
		return loaded
	var checked: Dictionary = _decode(loaded.data.document)
	if not checked.ok:
		_writes_blocked = true
		return checked
	_states = checked.data.states.duplicate(true)
	_writes_blocked = false
	return Result.success({"restored": true})

func _decode(document: Dictionary) -> Dictionary:
	if document.get("format_version") != FORMAT_VERSION or not document.get("sections") is Dictionary:
		return Result.failure("SAVE_VERSION", "不支持的内核存档格式")
	var staged: Dictionary = _states.duplicate(true)
	for section_id in document.sections:
		# 未知模块可能来自较新的客户端，禁止静默丢弃其数据。
		if not _definitions.has(section_id):
			return Result.failure("UNKNOWN_SECTION", "存档含未注册系统：" + str(section_id))
		var section: Variant = document.sections[section_id]
		if not section is Dictionary or not section.get("state") is Dictionary or not Contracts.matches(section.get("version"), "integer"):
			return Result.failure("CORRUPT_SAVE", "模块存档结构错误")
		var definition: Dictionary = _definitions[section_id]
		var version: int = int(section.version)
		var state: Dictionary = section.state.duplicate(true)
		if version < 1 or version > definition.version:
			return Result.failure("SAVE_VERSION", "模块存档版本不受支持")
		if version < definition.version:
			if not definition.migrate.is_valid():
				return Result.failure("MIGRATION_REQUIRED", "模块需要迁移：" + str(section_id))
			var migrated: Dictionary = definition.migrate.call(version, state)
			if not migrated.get("ok", false) or not migrated.get("data", {}).get("state") is Dictionary:
				return Result.failure("MIGRATION_FAILED", "模块迁移失败：" + str(section_id))
			state = migrated.data.state
		if not Contracts.is_json(state) or not definition.validate.call(state.duplicate(true)):
			return Result.failure("INVALID_STATE", "模块存档校验失败：" + str(section_id))
		staged[section_id] = state.duplicate(true)
	return Result.success({"states": staged})
