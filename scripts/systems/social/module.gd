extends "res://scripts/kernel/system_module.gd"
## 社交：社群、世界频道、世界 Boss 协作与 friendly_duel_v1 房间投影。
## 后端负责账号归属、可见性、幂等和权限；这里仅保存公开 DTO，不保存健康或账本字段。

func _init() -> void:
	super("social")

func state_version() -> int:
	return 2

func initial_state() -> Dictionary:
	return {"revision": 0, "visibility": "public", "active_cultivator_id": "", "profile": {}, "communities": [], "current_community_id": "", "feed": {}, "pvp_rooms": [], "world": {}}

func validate_state(state: Dictionary) -> bool:
	if not state.get("revision") is int or int(state.revision) < 0:
		return false
	for key in ["visibility", "active_cultivator_id", "current_community_id"]:
		if not state.get(key) is String:
			return false
	for key in ["profile", "feed", "world"]:
		if not state.get(key) is Dictionary or not Contracts.is_json(state[key]):
			return false
	for key in ["communities", "pvp_rooms"]:
		if not state.get(key) is Array or not Contracts.is_json(state[key]):
			return false
	return Contracts.is_json(state)

func migrate_state(from_version: int, old_state: Dictionary) -> Dictionary:
	if from_version == 1:
		var migrated: Dictionary = initial_state()
		migrated.revision = int(old_state.get("revision", 0))
		return Result.success({"state": migrated})
	return super.migrate_state(from_version, old_state)

func execute(command: String, payload: Dictionary) -> Dictionary:
	var supported := [
		"social.visit", "social.bless", "social.set_visibility",
		"social.community.list", "social.community.create", "social.community.join", "social.community.leave",
		"social.community.members", "social.community.feed", "social.community.post", "social.community.comment", "social.community.react",
		"social.pvp.create", "social.pvp.join", "social.pvp.list", "social.pvp.finish",
		"social.world.list", "social.world.post", "social.world.boss", "social.world.boss.contribute"
	]
	if command not in supported:
		return Result.failure("NOT_IMPLEMENTED", "该社交命令尚未接入：" + command)
	var key := str(payload.get("request_id", ""))
	var result: Dictionary = await request_backend(command, payload, key)
	if not result.ok:
		return result
	var projected: Dictionary = _project(command, payload, result.data)
	var committed: Dictionary = commit(projected)
	if not committed.ok:
		return committed
	if command.begins_with("social.world."):
		_context.events.publish("world.changed", {"scope": "world"})
	elif command.begins_with("social.community.") or command.begins_with("social.pvp."):
		_context.events.publish("social.feed_changed", {"community_id": str(payload.get("community_id", projected.get("current_community_id", "")))})
	else:
		_context.events.publish("social.changed", {"cultivator_id": str(payload.get("cultivator_id", ""))})
	return result

func on_backend_changed() -> void:
	if _context == null:
		return
	var cleared: Dictionary = initial_state()
	cleared.revision = snapshot().get("revision", 0) + 1
	commit(cleared)

func _project(command: String, payload: Dictionary, data: Dictionary) -> Dictionary:
	var state: Dictionary = snapshot()
	state.revision = int(state.get("revision", 0)) + 1
	if command == "social.visit":
		state.profile = data.duplicate(true)
		state.active_cultivator_id = str(payload.get("cultivator_id", ""))
	elif command == "social.set_visibility":
		state.visibility = str(data.get("visibility", payload.get("scope", "public")))
		state.active_cultivator_id = str(payload.get("cultivator_id", ""))
	elif command == "social.community.list":
		state.communities = data.get("communities", []).duplicate(true)
	elif command == "social.community.feed":
		state.current_community_id = str(payload.get("community_id", ""))
		state.feed = data.duplicate(true)
	elif command == "social.community.members":
		state.feed = {"community_id": payload.get("community_id", ""), "members": data.get("members", []).duplicate(true)}
	elif command.begins_with("social.community."):
		var community_data: Dictionary = data.get("community", {})
		state.current_community_id = str(payload.get("community_id", community_data.get("community_id", "")))
		if data.has("community"):
			state.feed = data.duplicate(true)
	elif command == "social.pvp.list":
		state.pvp_rooms = data.get("matches", []).duplicate(true)
	elif command.begins_with("social.pvp."):
		if data.has("match"):
			var pvp_match: Dictionary = data.get("match", {})
			var rooms: Array = state.pvp_rooms
			var replaced := false
			for index in range(rooms.size()):
				if rooms[index] is Dictionary and rooms[index].get("match_id") == pvp_match.get("match_id"):
					rooms[index] = pvp_match.duplicate(true)
					replaced = true
			if not replaced:
				rooms.append(pvp_match.duplicate(true))
			state.pvp_rooms = rooms
	elif command == "social.world.list":
		state.world = data.duplicate(true)
	elif command == "social.world.boss":
		state.world = data.duplicate(true)
	elif command == "social.world.post":
		state.world = data.duplicate(true)
	elif command == "social.world.boss.contribute":
		state.world = data.get("boss", data).duplicate(true)
	return state
