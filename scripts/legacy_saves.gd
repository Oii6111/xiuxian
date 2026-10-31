extends RefCounted
## One resolver for discovery, ownership claims, backups and import.
const EDITOR_SAVE = "res://output/local-save.json"
const CURRENT_NAME = "songfeng_pixel_progress.json"
const ORIGINAL_NAME = "family_cultivation_demo.json"

static func primary(editor: bool) -> String:
	return EDITOR_SAVE if editor else "user://" + CURRENT_NAME

static func runtime_candidates(root: String = "user://") -> PackedStringArray:
	return PackedStringArray([root.path_join(CURRENT_NAME), root.path_join(ORIGINAL_NAME)])

static func candidates(editor: bool) -> PackedStringArray:
	return PackedStringArray([EDITOR_SAVE]) if editor else runtime_candidates()

static func resolve(paths: PackedStringArray) -> String:
	for path in paths:
		if FileAccess.file_exists(path):
			return path
	return ""
