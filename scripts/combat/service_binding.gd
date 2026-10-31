extends RefCounted
## A/C 装配接缝：参数均由装配根显式提供；UI 使用 GameKernel，不能访问模块内部。
## api 为 scripts/net/game_api.gd 或相同 invoke 签名的权威适配器。
var _api: Node

func configure(combat: RefCounted, lifecycle: RefCounted, api: Node, snapshot_provider: Callable) -> void:
	_api = api
	combat.set_gate(Callable(lifecycle, "allows_combat"))
	combat.set_provider(snapshot_provider)
	combat.set_gateway(Callable(api, "invoke"))
	lifecycle.set_authority(Callable(self, "_lifecycle"))

func _lifecycle(operation: String, payload: Dictionary) -> Dictionary:
	var command: String = "lifecycle." + operation
	var body: Dictionary = {"cultivator_id": payload.cultivator_id}
	match operation:
		"request_change":
			body["target_state"] = payload.target_state
		"confirm_change":
			body["confirmation_token"] = payload.confirmation_token
			body["request_id"] = payload.request_id
		"update_stage":
			body["stage_id"] = payload.stage_id
			body["confirmation_token"] = payload.confirmation_token
	return await _api.invoke(command, body)
