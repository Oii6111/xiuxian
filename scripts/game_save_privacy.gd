extends RefCounted
## Applied only to game saves, never to the independent health-domain repository.
const HealthProjection = preload("res://scripts/health_baseline.gd")
const FORBIDDEN = ["attribute_notes", "evidence", "source_document", "health_drafts", "data_url", "data_urls", "history_text", "medications_text", "clinical_notes", "report_path", "chosen_path", "chosen_paths", "password", "token", "access_token", "refresh_token"]

static func clean(value):
	if value is Dictionary:
		var output = {}
		for key in value:
			if key in FORBIDDEN:
				continue
			if key == "health_baseline":
				output[key] = projection(value[key])
			else:
				output[key] = clean(value[key])
		if output.has("health_attributes") and output.has("health_source"):
			var baseline = output.get("health_baseline", {})
			output.health_source = HealthProjection.source_label(baseline) if not baseline.is_empty() else ("模拟游戏属性" if output.get("health_simulated", false) else "已确认游戏属性")
		return output
	if value is Array:
		var output = []
		for entry in value:
			output.append(clean(entry))
		return output
	return value

static func projection(value) -> Dictionary:
	if not value is Dictionary or value.is_empty():
		return {}
	var checked = HealthProjection.validate(value)
	return checked.baseline if checked.ok else {}

static func write_atomic(path: String, text: String) -> bool:
	var temporary = path + ".privacy.tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	var error = file.get_error()
	file.close()
	if error != OK:
		return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path)) == OK

static func equivalent(a, b) -> bool:
	# JSON reloads all numbers as float; that alone must not trigger another migration.
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return float(a) == float(b)
	if typeof(a) != typeof(b):
		return false
	if a is Dictionary:
		if a.size() != b.size():
			return false
		for key in a:
			if not b.has(key) or not equivalent(a[key], b[key]):
				return false
		return true
	if a is Array:
		if a.size() != b.size():
			return false
		for index in range(a.size()):
			if not equivalent(a[index], b[index]):
				return false
		return true
	return a == b

static func read(path: String, persist: bool, legacy: bool = false) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {"ok": false, "message": "没有找到存档。"}
	var original = FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(original)
	if not data is Dictionary:
		return {"ok": false, "message": "存档格式异常，原文件已保留。"}
	var sanitized = clean(data)
	var changed = not equivalent(sanitized, data)
	if changed and legacy and not sanitized.has("legacy_import_fingerprint"):
		# Keep pre-migration ownership claims stable after removing medical fields.
		sanitized.legacy_import_fingerprint = original.sha256_text()
	var text = JSON.stringify(sanitized) if changed else original
	if changed and persist and not write_atomic(path, text):
		return {"ok": false, "message": "无法清理旧存档中的健康资料，原文件已保留。"}
	return {"ok": true, "data": sanitized, "text": text, "changed": changed, "digest": text.sha256_text(), "disk_digest": (text if changed and persist else original).sha256_text()}
