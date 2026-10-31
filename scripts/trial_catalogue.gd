extends RefCounted
## Curated art/name mapping only. No remote campaign scripts or medical rules.
const Assets = preload("res://scripts/pixel_assets.gd")
const PATH = "res://data/trial_bosses.json"
static var _entries: Array = []

static func all() -> Array:
	if _entries.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			_entries = parsed.get("bosses", [])
	return _entries

static func entry(id: String) -> Dictionary:
	for row in all():
		if row.id == id:
			return row.duplicate(true)
	return {}

static func boss_texture(id: String) -> Texture2D:
	var row = entry(id)
	if row.is_empty():
		return null
	var frames = Assets.frames(row.sheet, 2, 2, 0.2, true)
	return frames[int(row.cell)] if frames.size() == 4 else null

static func scene_path(id: String) -> String:
	return "res://scenes/trials/" + id + ".tscn" if not entry(id).is_empty() else ""

static func at(index: int) -> Dictionary:
	return all()[clampi(index, 0, all().size() - 1)].duplicate(true)
