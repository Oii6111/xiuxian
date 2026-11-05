extends RefCounted
## Pure game rules. Initial health-derived scores are frozen separately from gear bonuses.
const RULES_VERSION = "pixel-local-v1"
const CATALOGUE_VERSION = "pixel-equipment-v1"
const DAILY_QI = 100
const SINGLE_COST = 70
const TEN_COST = 700
const RARITIES = ["普通", "精良", "史诗", "传说", "神话"]
const COLORS = [Color("e5e4df"), Color("66b8ff"), Color("b68aff"), Color("ffd36b"), Color("ff697b")]
const SLOTS = ["weapon", "robe", "boots", "amulet"]
const SLOT_NAMES = {"weapon": "武器", "robe": "衣服", "boots": "鞋子", "amulet": "饰品"}
const STAT_NAMES = {"life": "生命上限", "attack": "攻击", "defense": "防御", "spirit": "灵力上限", "stamina": "体力上限"}
const HIGH_WEIGHTS = [55.0, 30.0, 11.0, 3.5, 0.5]
const LOW_WEIGHTS = [35.0, 33.0, 22.0, 8.0, 2.0]
const TEMPLATES = [
	{"slot": "weapon", "stat": "attack", "names": ["青竹剑", "听风剑", "流云剑", "太初剑", "九霄神剑"], "values": [3, 6, 10, 16, 24]},
	{"slot": "robe", "stat": "defense", "names": ["素布衣", "云纹衣", "玄羽袍", "金霞仙衣", "太虚神袍"], "values": [3, 6, 10, 16, 24]},
	{"slot": "robe", "stat": "life", "names": ["护身衫", "青玉衫", "长生衣", "不灭仙衣", "万象神衣"], "values": [8, 16, 26, 40, 60]},
	{"slot": "boots", "stat": "stamina", "names": ["布履", "踏风靴", "逐月靴", "凌霄仙履", "踏虚神履"], "values": [5, 10, 15, 22, 30]},
	{"slot": "amulet", "stat": "spirit", "names": ["凝气佩", "凝神佩", "星河佩", "天元仙佩", "混元神佩"], "values": [5, 10, 15, 22, 30]}
]

static func fresh() -> Dictionary:
	# Track the onboarding grant separately from the qi wallet so it cannot be
	# recreated by changing the wallet balance or replaying the UI.
	return {"qi": 0, "initial_score": -1.0, "initial_profile_id": "", "inventory": [], "equipped": {}, "next_id": 1, "draw_count": 0, "receipts": {}, "last_request": "", "starter_ten_pulls": 0}

static func initial_score(attributes: Dictionary) -> float:
	var total = 0.0
	for key in ["life", "attack", "defense", "spirit", "stamina"]:
		# Current baselines use 0..100. Legacy HP above 100 is capped for this game rule.
		total += clampf(float(attributes.get(key, 50)), 0.0, 100.0)
	return total / 5.0

static func probabilities(score: float) -> Array:
	var support = 1.0 - clampf(score, 0.0, 100.0) / 100.0
	var weights = []
	for i in range(5):
		weights.append(lerpf(HIGH_WEIGHTS[i], LOW_WEIGHTS[i], support))
	return weights

static func roll_rarity(score: float, rng: RandomNumberGenerator) -> int:
	var roll = rng.randf() * 100.0
	var cumulative = 0.0
	var weights = probabilities(score)
	for i in range(5):
		cumulative += weights[i]
		if roll < cumulative:
			return i
	return 4

static func make_item(number: int, rarity: int, rng: RandomNumberGenerator) -> Dictionary:
	var slot = SLOTS[rng.randi_range(0, SLOTS.size() - 1)]
	var candidates = []
	for i in range(TEMPLATES.size()):
		if TEMPLATES[i].slot == slot:
			candidates.append(i)
	return {"id": "gear_%06d" % number, "template": candidates[rng.randi_range(0, candidates.size() - 1)], "rarity": clampi(rarity, 0, 4)}

static func detail(item: Dictionary) -> Dictionary:
	var template = TEMPLATES[int(item.template)]
	var rarity = int(item.rarity)
	return {"id": str(item.id), "slot": template.slot, "stat": template.stat, "amount": template.values[rarity], "name": template.names[rarity], "rarity": rarity, "quality": RARITIES[rarity], "color": COLORS[rarity]}

static func bonus_text(item: Dictionary) -> String:
	var info = detail(item)
	return "%s +%d" % [STAT_NAMES[info.stat], info.amount]

static func bonuses(state: Dictionary) -> Dictionary:
	var result = {"life": 0, "attack": 0, "defense": 0, "spirit": 0, "stamina": 0}
	for item in state.inventory:
		var info = detail(item)
		if state.equipped.get(info.slot, "") == info.id:
			result[info.stat] += info.amount
	return result

static func normalize(payload) -> Dictionary:
	var result = fresh()
	if not payload is Dictionary:
		return result
	result.qi = maxi(0, int(payload.get("qi", 0)))
	result.starter_ten_pulls = clampi(int(payload.get("starter_ten_pulls", 0)), 0, 1)
	result.initial_score = clampf(float(payload.get("initial_score", -1.0)), -1.0, 100.0)
	result.initial_profile_id = str(payload.get("initial_profile_id", ""))
	var ids = {}
	var inventory = payload.get("inventory", [])
	if inventory is Array:
		for item in inventory:
			if not item is Dictionary or typeof(item.get("template")) not in [TYPE_FLOAT, TYPE_INT]:
				continue
			var template = int(item.get("template", -1))
			var rarity = int(item.get("rarity", -1))
			var id = str(item.get("id", ""))
			if template < 0 or template >= TEMPLATES.size() or rarity < 0 or rarity > 4 or not id.begins_with("gear_") or ids.has(id):
				continue
			result.inventory.append({"id": id, "template": template, "rarity": rarity})
			ids[id] = true
			result.next_id = maxi(result.next_id, int(id.trim_prefix("gear_")) + 1)
	var equipped = payload.get("equipped", {})
	if equipped is Dictionary:
		for item in result.inventory:
			var info = detail(item)
			if equipped.get(info.slot, "") == info.id:
				result.equipped[info.slot] = info.id
	result.next_id = maxi(result.next_id, int(payload.get("next_id", 1)))
	result.draw_count = maxi(result.inventory.size(), int(payload.get("draw_count", 0)))
	# Receipts make retrying the same local operation safe, including after a restart.
	var receipts = payload.get("receipts", {})
	if receipts is Dictionary:
		for request in receipts:
			var receipt = receipts[request]
			if not receipt is Dictionary or not receipt.get("items") is Array or not valid_draw_count(receipt.get("count")):
				continue
			var items = []
			var receipt_ids = {}
			for item in receipt.items:
				if item is Dictionary and ids.has(str(item.get("id", ""))) and not receipt_ids.has(str(item.get("id", ""))):
					for owned in result.inventory:
						if owned.id == item.id:
							items.append(owned.duplicate())
							receipt_ids[owned.id] = true
			if items.size() == int(receipt.count):
				var restored_cost = maxi(0, int(receipt.get("cost", SINGLE_COST * int(receipt.count))))
				result.receipts[str(request)] = {"ok": true, "request_id": str(request), "count": int(receipt.count), "cost": restored_cost, "items": items, "guaranteed": receipt.get("guaranteed", false) == true, "starter_bonus": receipt.get("starter_bonus", false) == true}
	var last_request = str(payload.get("last_request", ""))
	if result.receipts.has(last_request):
		result.last_request = last_request
	return result

static func valid_draw_count(value) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) in [1.0, 10.0]
