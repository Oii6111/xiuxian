extends RefCounted
## PR4 每角色可持久化的生命周期投影。不保存确认令牌、原始报告、健康读数或自由文本。
const Rules = preload("res://scripts/systems/lifecycle/lifecycle_rules.gd")
const Contracts = preload("res://scripts/kernel/contracts.gd")

static func fresh(state: String = "cultivating") -> Dictionary:
	return {"schema": 1, "state": state, "version": 1, "template_id": "", "stage_index": -1, "lamps": 0, "history": [], "last_event_id": ""}

static func valid(record: Variant) -> bool:
	# 空字符串允许；显式白名单而不是通用 string（通用契约要求非空）。
	if not record is Dictionary or record.size() != 8 or not Contracts.is_json(record):
		return false
	for key in ["schema", "state", "version", "template_id", "stage_index", "lamps", "history", "last_event_id"]:
		if not record.has(key):
			return false
	if not Contracts.matches(record.schema, "integer") or record.schema != 1 or not record.state is String or not Rules.is_state(record.state):
		return false
	if not Contracts.matches(record.version, "integer") or record.version < 1:
		return false
	if not record.template_id is String or not record.last_event_id is String or not Contracts.matches(record.stage_index, "integer"):
		return false
	if not Contracts.matches(record.lamps, "integer") or record.lamps < 0 or record.lamps > 24:
		return false
	if record.template_id == "":
		if record.stage_index != -1:
			return false
	elif record.state not in ["cultivating", "tribulation"] or not Rules.TEMPLATES.has(record.template_id) or record.stage_index < -1 or record.stage_index >= Rules.TEMPLATES[record.template_id].stages.size() or (record.state == "cultivating" and record.stage_index != -1):
		return false
	if not record.history is Array or record.history.size() > 64:
		return false
	for event in record.history:
		if not event is Dictionary or event.size() != 4 or not Contracts.validate(event, {"id": "string", "at": "integer", "state": "string", "stage_id": "string"}).ok:
			return false
		if not Rules.is_state(event.state) or event.at < 0:
			return false
	return true

static func with_event(record: Dictionary, event_id: String, observed_at: int, stage_id: String = "state") -> Dictionary:
	var updated: Dictionary = record.duplicate(true)
	updated["last_event_id"] = event_id
	updated.history.append({"id": event_id, "at": observed_at, "state": updated.state, "stage_id": stage_id})
	if updated.history.size() > 64:
		updated.history.pop_front()
	return updated
