extends RefCounted
## Fictional gameplay catalogue; medical metadata never participates in diagnosis.
const PATH = "res://data/campaign_bosses.json"
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
	return {"雷诀":"落雷：对近处目标造成高伤害", "镇心":"守心：更长护盾，成功抵挡后反击", "分流":"灵泉：恢复少量护元并击退危区"}

static func minions() -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign_minions.json"))
	return parsed.get("minions",[]) if parsed is Dictionary else []

static func minion(id: String) -> Dictionary:
	for row in minions():
		if row.id == id:
			return row.duplicate(true)
	return {}

static func minions_for(region: String) -> Array:
	return minions().filter(func(row): return row.element == region)

static func people() -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign_minions.json"))
	return parsed.get("npcs",[]) if parsed is Dictionary else []

static func person(id: String) -> Dictionary:
	for row in people():
		if row.id == id:
			return row.duplicate(true)
	return {}
