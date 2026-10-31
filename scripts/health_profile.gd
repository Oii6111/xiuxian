extends RefCounted
## Adapter boundary: the future service supplies scores; this client never diagnoses.
const INITIAL_HP = 100
const KEYS = ["life", "attack", "defense", "spirit", "stamina"]
const LABELS = {"life": "生命", "attack": "攻击", "defense": "防御", "spirit": "灵力", "stamina": "体力"}

static func validate(payload: Dictionary) -> Dictionary:
	if str(payload.get("profile_id", "")).strip_edges().is_empty():
		return {"ok": false, "message": "档案缺少 profile_id。"}
	var revision = payload.get("revision", null)
	if typeof(revision) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(revision)) or float(revision) < 1 or float(revision) != floor(float(revision)):
		return {"ok": false, "message": "档案 revision 必须为正整数。"}
	var values = payload.get("attributes", null)
	if not values is Dictionary:
		return {"ok": false, "message": "档案需要包含五项 attributes。"}
	var normalized = {}
	for key in KEYS:
		var value = values.get(key, null)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < 0 or float(value) > 100:
			return {"ok": false, "message": LABELS[key] + "必须是 0—100 的数值。"}
		normalized[key] = int(round(float(value)))
	return {"ok": true, "attributes": normalized, "profile_id": str(payload.profile_id).left(100), "revision": int(revision), "source": str(payload.get("source", "external")).left(80), "simulated": payload.get("simulated", false) == true}

static func mock(score: int, revision: int) -> Dictionary:
	var values = {}
	for key in KEYS:
		values[key] = clampi(score, 0, 100)
	return {"profile_id": "demo-songfeng", "revision": revision, "source": "模拟健康档案", "simulated": true, "attributes": values}

static func battle_stats(values: Dictionary) -> Dictionary:
	# Temporary GAME scaling only. Medical-record-to-score quantification belongs to the service.
	return {"max_hp": INITIAL_HP, "attack": 18 + int(values.attack) * 2, "damage_multiplier": 100.0 / (100.0 + float(values.defense) * 0.8), "max_mp": 40 + int(values.spirit) * 2, "max_stamina": 50 + int(values.stamina) * 1.5, "shield": 35 + int(values.defense) * 2}
