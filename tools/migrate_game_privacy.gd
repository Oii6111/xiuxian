extends SceneTree
const Privacy = preload("res://scripts/game_save_privacy.gd")
var checked = 0
var changed = 0
var failed = 0

func _initialize() -> void:
	run.call_deferred()

func scan(directory: String, account_files: bool) -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory)):
		return
	for name in DirAccess.get_files_at(directory):
		if not name.ends_with(".json"):
			continue
		var path = directory.path_join(name)
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary:
			continue
		var game_document = data.has("health_attributes") or data.has("health_baseline") or (data.has("members") and int(data.get("schema", 0)) in [7, 8])
		if not game_document:
			continue
		checked += 1
		var result = Privacy.read(path, true, not account_files)
		if not result.ok:
			failed += 1
		elif result.changed:
			changed += 1

func run() -> void:
	# Only game-owned save roots; health-entry/baselines and account databases are excluded.
	scan("res://output", false)
	scan("res://output/accounts", true)
	scan("user://", false)
	scan("user://accounts", true)
	print("GAME SAVE PRIVACY MIGRATION: checked=", checked, " cleaned=", changed, " failed=", failed)
	quit(0 if failed == 0 else 1)
