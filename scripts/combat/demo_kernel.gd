extends Node
## 仅供离线演示：隔离的内存运行时 + 明确标注的替身确认通道。
## 不触碰全局 GameKernel、不读写玩家存档，也不会进入 lifecycle 模块本身；
## 替身确认不是真实家属确认，演示界面必须常驻提示。
const Runtime = preload("res://scripts/kernel/runtime.gd")
const Memory = preload("res://scripts/kernel/adapters/memory_persistence.gd")
const Result = preload("res://scripts/kernel/result.gd")
var runtime: RefCounted
var player_element: String = "wood"
var _version: int = 10
var _confirms: Dictionary = {}
var _tokens: Dictionary = {}
var _replies: Dictionary = {}
var _serial: int = 0

## 启动隔离运行时，写入一位处于修行状态的演示修仙者，并注入替身确认通道。
func setup(cultivator_id: String) -> bool:
	var contract: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/kernel/contracts.json"))
	if not contract is Dictionary:
		return false
	runtime = Runtime.new()
	if not runtime.start(contract, Memory.new()).ok:
		runtime = null
		return false
	# 演示用：直接取模块实例注入，这是演示壳独有的做法，正式装配不应这样访问。
	var module: RefCounted = runtime._modules["lifecycle"]
	module.apply_authoritative(cultivator_id, "cultivating", 1)
	module.set_authority(Callable(self, "_authority"))
	var combat: RefCounted = runtime._modules["combat"]
	combat.set_gate(Callable(module, "allows_combat"))
	combat.set_provider(Callable(self, "_combat_snapshot"))
	return true

func dispatch(command: String, payload: Dictionary) -> Dictionary:
	if runtime == null:
		return Result.failure("NOT_READY", "演示运行时未启动")
	return await runtime.dispatch(command, payload)

func snapshot(module_id: String) -> Dictionary:
	return runtime.snapshot(module_id) if runtime != null else {}

## 替身：飞升需要两次确认，其余一次即完成；版本单调递增。
func _authority(operation: String, payload: Dictionary) -> Dictionary:
	match operation:
		"request_change":
			_serial += 1
			var token: String = "demo-%d" % _serial
			_tokens[token] = {"owner": payload.cultivator_id, "target": payload.target_state, "expires": Time.get_ticks_msec() + 300000, "count": 0}
			return Result.success({"confirmation_token": token})
		"confirm_change":
			var key: String = str(payload.cultivator_id) + ":" + str(payload.request_id)
			if _replies.has(key):
				return Result.success(_replies[key])
			var ticket: Dictionary = _tokens.get(payload.confirmation_token, {})
			if ticket.is_empty() or ticket.owner != payload.cultivator_id or ticket.target != payload.target_state:
				return Result.failure("FORBIDDEN", "确认令牌归属不匹配")
			if Time.get_ticks_msec() > ticket.expires:
				return Result.failure("TOKEN_EXPIRED", "确认已过期，请重新发起")
			var needed: int = 2 if payload.target_state == "ascended" else 1
			ticket.count += 1
			if ticket.count < needed:
				_replies[key] = {"complete": false, "remaining": needed - ticket.count, "state": payload.target_state}
			else:
				_version += 1
				_replies[key] = {"complete": true, "state": payload.target_state, "version": _version}
				_tokens.erase(payload.confirmation_token)
			return Result.success(_replies[key])
		"update_stage":
			_version += 1
			return Result.success({"version": _version})
	return Result.failure("UNKNOWN_OPERATION", "未知操作")

func _exit_tree() -> void:
	if runtime != null:
		runtime.shutdown()
		runtime = null

## 显式演示数据，联调时由 B/C 提供同一接口的权威快照。
func _combat_snapshot(_cultivator_id: String, encounter_id: String) -> Dictionary:
	if encounter_id not in ["trial_wood", "trial_fire", "trial_metal"]:
		return Result.failure("UNKNOWN_ENCOUNTER", "未知关卡")
	return Result.success({
		"player": {"hp": 300, "attack": 28, "defense": 8, "crit_rate": 0.15, "element": player_element},
		"enemy": {"hp": 230, "attack": 16, "defense": 4, "crit_rate": 0.0, "element": encounter_id.trim_prefix("trial_")}
	})
