extends "res://scripts/kernel/system_module.gd"
## 角色养成：童子/修仙者关系、灵根、装备、境界、资源与抽卡结果的客户端投影。
## 每位修仙者独立持有灵石/经验/材料/装备/保底；功德属于童子。
## 所有写操作只请求后端，成功后才 commit 服务端快照；严禁本地抽卡或发奖。

func _init() -> void:
	super("growth")

const WRITES = ["growth.create", "growth.create_member", "growth.update_member", "growth.equip", "growth.unequip", "growth.draw"]
var _session: int = 0
# 写请求超时后用同一幂等键重试；只有确定结果（成功或业务拒绝）才释放。
var _pending_keys: Dictionary = {}

func state_version() -> int:
	return 2

func initial_state() -> Dictionary:
	return {"revision": 0, "account_revision": -1, "cultivators": []}

func validate_state(state: Dictionary) -> bool:
	if state.size() != 3 or not Contracts.is_json(state) or not state.get("cultivators") is Array:
		return false
	if not Contracts.matches(state.get("revision"), "integer") or state.revision < 0 or not Contracts.matches(state.get("account_revision"), "integer"):
		return false
	for cultivator in state.cultivators:
		if not cultivator is Dictionary or not cultivator.get("cultivator_id") is String or not cultivator.get("resources") is Dictionary:
			return false
	return true

func migrate_state(from_version: int, state: Dictionary) -> Dictionary:
	if from_version != 1 or not Contracts.validate(state, {"revision": "integer"}).ok or state.revision < 0:
		return Result.failure("MIGRATION_REQUIRED", "养成旧状态不合法")
	var migrated: Dictionary = initial_state()
	migrated.revision = state.revision
	return Result.success({"state": migrated})

func on_backend_changed() -> void:
	_session += 1
	_pending_keys.clear()
	if _context != null:
		var state: Dictionary = initial_state()
		state.revision = snapshot().revision + 1
		commit(state)

func cultivator(cultivator_id: String) -> Dictionary:
	for item in snapshot().cultivators:
		if item.cultivator_id == cultivator_id:
			return item
	return {}

func execute(command: String, payload: Dictionary) -> Dictionary:
	var session: int = _session
	var key: String = ""
	if command in WRITES and not payload.has("request_id"):
		var signature: String = command + ":" + JSON.stringify(payload, "", true)
		if not _pending_keys.has(signature):
			_pending_keys[signature] = Crypto.new().generate_random_bytes(16).hex_encode()
		key = _pending_keys[signature]
	var result: Dictionary = await request_backend(command, payload, key)
	if not key.is_empty() and result.code not in ["NETWORK_ERROR", "INTERNAL_ERROR", "BACKEND_UNAVAILABLE"]:
		_pending_keys.erase(command + ":" + JSON.stringify(payload, "", true))
	if not result.ok:
		return result
	if _context == null or session != _session:
		return Result.failure("SESSION_CHANGED", "请求期间账号已切换，结果未写入当前投影")
	var data: Dictionary = result.data
	var state: Dictionary = snapshot()
	if command == "growth.list":
		if not data.get("cultivators") is Array or not Contracts.matches(data.get("revision"), "integer"):
			return Result.failure("INVALID_RESPONSE", "养成快照不符合契约")
		# 乱序到达的旧快照不能回滚更新的余额或穿戴。
		if int(data.revision) < int(state.account_revision):
			return Result.success(data)
		state.cultivators = data.cultivators.duplicate(true)
		state.account_revision = int(data.revision)
	else:
		var character: Variant = data.get("character", data)
		if not character is Dictionary or not character.get("cultivator_id") is String:
			return Result.failure("INVALID_RESPONSE", "角色快照不符合契约")
		_replace(state, character)
	state.revision = int(state.revision) + 1
	var committed: Dictionary = commit(state)
	if not committed.ok:
		return committed
	if command in WRITES:
		var changed_id: String = str(data.get("character", data).get("cultivator_id", ""))
		_context.events.publish("growth.changed", {"cultivator_id": changed_id})
	return Result.success(data)

## 实时快照与 HTTP 写回执共用：只按账号 revision 前进。
func apply_account_snapshot(data: Dictionary) -> Dictionary:
	if _context == null or not data.get("cultivators") is Array or not Contracts.matches(data.get("revision"), "integer"):
		return Result.failure("INVALID_RESPONSE", "养成快照不符合契约")
	var state: Dictionary = snapshot()
	if int(data.revision) < int(state.account_revision):
		return Result.success(state)
	state.cultivators = data.cultivators.duplicate(true)
	state.account_revision = int(data.revision)
	state.revision = int(state.revision) + 1
	return commit(state)

func _replace(state: Dictionary, character: Dictionary) -> void:
	for index in range(state.cultivators.size()):
		if state.cultivators[index].cultivator_id == character.cultivator_id:
			state.cultivators[index] = character.duplicate(true)
			return
	state.cultivators.append(character.duplicate(true))
