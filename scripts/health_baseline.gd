extends RefCounted
## The interface outputs game units. Body-system mapping v2 replaces five elements.
const STATS = ["hp_max", "hp_current", "attack", "defense", "spirit", "stamina", "insight", "mind", "speed", "luck"]
const EVIDENCE = ["data_completeness", "plan_coverage", "family_support", "function_capacity", "routine_stability", "self_reported_energy", "knowledge_tasks", "tech_readiness"]

static func valid_number(value, low: float, high: float) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func validate(payload: Dictionary) -> Dictionary:
	if str(payload.get("baseline_id", "")).is_empty() or payload.get("baseline_locked") != true or payload.get("baseline_version") != "char_baseline_v1":
		return {"ok": false, "message": "初始档案尚未确认，或版本不受支持。"}
	if payload.get("recognition_mode") not in ["live", "text", "sample", "demo"]:
		return {"ok": false, "message": "缺少档案识别模式。"}
	var stats = payload.get("character_state")
	var evidence = payload.get("evidence", {})
	var notes = payload.get("attribute_notes", {})
	if not stats is Dictionary or not evidence is Dictionary or not notes is Dictionary:
		return {"ok": false, "message": "初始属性或建模依据格式错误。"}
	var clean_stats = {}
	for key in STATS:
		# Older saved interface baselines used HP >100; retain their saved capability.
		var high = 10000 if key.begins_with("hp_") and payload.get("mapping_version") != "body_system_v2" else 100
		if not valid_number(stats.get(key), 1 if key == "hp_max" else 0, high):
			return {"ok": false, "message": "初始属性缺失或超出范围：" + key}
		clean_stats[key] = roundi(float(stats[key]))
	if clean_stats.hp_current != clean_stats.hp_max:
		return {"ok": false, "message": "初始生命应为满值。"}
	var clean_evidence = {}
	for key in evidence:
		if key in EVIDENCE:
			if not valid_number(evidence[key], 0, 100):
				return {"ok": false, "message": "资料特征超出范围。"}
			clean_evidence[key] = roundi(float(evidence[key]))
	var clean_notes = {}
	for key in STATS:
		if notes.has(key):
			clean_notes[key] = str(notes[key]).left(3000)
	if not valid_number(payload.get("readiness"), 0, 100):
		return {"ok": false, "message": "守护准备度格式错误。"}
	# Retain only the confirmed display name; omit source document and image data.
	var baseline = {"baseline_id": str(payload.baseline_id).left(100), "baseline_version": "char_baseline_v1", "mapping_version": str(payload.get("mapping_version", "legacy")), "rules_revision": str(payload.get("rules_revision", "")).left(40), "baseline_locked": true, "supplementable": true, "character_state": clean_stats, "evidence": clean_evidence, "attribute_notes": clean_notes, "readiness": roundi(float(payload.readiness)), "recognition_mode": payload.recognition_mode, "display_name": str(payload.get("display_name", "")).left(10), "provider": str(payload.get("provider", "")).left(80), "model": str(payload.get("model", "")).left(100), "synced_at": str(payload.get("synced_at", "")).left(40)}
	return {"ok": true, "baseline": baseline}

static func attributes(baseline: Dictionary) -> Dictionary:
	var stats = baseline.character_state
	return {"life": stats.hp_max, "attack": stats.attack, "defense": stats.defense, "spirit": stats.spirit, "stamina": stats.stamina}

static func battle_stats(baseline: Dictionary) -> Dictionary:
	var s = baseline.character_state
	return {"max_hp": s.hp_max, "attack": s.attack, "damage_multiplier": 100.0 / (100.0 + float(s.defense) * 0.8), "max_mp": s.spirit, "max_stamina": s.stamina, "shield": 35 + int(s.defense) * 2}
