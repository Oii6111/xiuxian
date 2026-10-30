extends RefCounted
## Fictional gameplay catalogue; medical metadata never participates in diagnosis.
const PATH = "res://data/pixel_campaign_bosses.json"
static var _rows: Array = []

static func all() -> Array:
	if _rows.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			_rows = parsed.get("bosses", [])
	return _rows

static func entry(id: String) -> Dictionary:
	for row in all():
		if row.id == id:
			return row.duplicate(true)
	return {}

static func region_name(region: String) -> String:
	return {"序章":"照生乡", "水":"玄泽", "土":"稷野", "金":"白羽关", "火":"丹霞岭", "木":"苍梧林", "旁篇":"乡中旁篇", "共域":"相痕海", "终章":"常生台"}.get(region, region)

static func cores() -> Array:
	return ["b03", "b06", "b09", "b12", "b15"]

static func skills() -> Dictionary:
	return {"雷诀":"落雷：对近处目标造成高伤害", "镇心":"守心：更长护盾，成功抵挡后反击", "分流":"回护：恢复25护元并伤害目标，6秒冷却"}

static func minions() -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/pixel_campaign_minions.json"))
	return parsed.get("minions",[]) if parsed is Dictionary else []

static func minion(id: String) -> Dictionary:
	for row in minions():
		if row.id == id:
			return row.duplicate(true)
	return {}

static func minions_for(region: String) -> Array:
	return minions().filter(func(row): return row.element == region)

static func people() -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/pixel_campaign_minions.json"))
	return parsed.get("npcs",[]) if parsed is Dictionary else []

static func person(id: String) -> Dictionary:
	for row in people():
		if row.id == id:
			return row.duplicate(true)
	return {}

static func region_order(region: String) -> Array:
	return {"序章":["b00"],"木":["b01","b02","b03"],"火":["b04","b05","b06"],"土":["b07","b08","b09"],"金":["b10","b11","b12"],"水":["b13","b14","b15"],"旁篇":["b16","b17"],"共域":["b18"],"终章":["b19"]}.get(region,[]).duplicate()

static func predecessor(id: String) -> String:
	var row = entry(id)
	return str(row.get("prerequisite_boss",""))

static func reward_for(id: String) -> Dictionary:
	return {"xp":80 if id=="b00" else 120,"materials":6 if id in cores() else 3}
