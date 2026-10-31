extends SceneTree
const State = preload("res://scripts/game_state.gd")
const Roster = preload("res://scripts/family_roster.gd")
const ProjectionAdapter = preload("res://scripts/health_baseline.gd")
const Privacy = preload("res://scripts/game_save_privacy.gd")
const Legacy = preload("res://scripts/legacy_saves.gd")
var passed = 0
var failed = 0
var base = ""

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
		print("PASS: ", label)
	else:
		failed += 1
		push_error(label)

func write_json(path: String, data: Dictionary) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

func has_private_text(text: String) -> bool:
	for word in ["高血压", "氨氯地平", "attribute_notes", "source_document", "evidence", "medical-secret"]:
		if text.contains(word):
			return true
	return false

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	base = "user://privacy-legacy-test-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base))
	var payload = JSON.parse_string(FileAccess.get_file_as_string("res://health-entry/sample-baseline.json"))
	payload.attribute_notes = {"spirit": "灵力 = 48（高血压病史 −5、氨氯地平 +3）"}
	payload.evidence = {"private": "medical-secret"}
	payload.source_document = {"history": "高血压"}
	var state = State.new()
	state.persist_enabled = false
	state.complete_boss("b00", {"time": 12})
	state.equipment.qi = 135
	check(state.apply_health_baseline(payload).ok, "Legacy baseline is adapted without importing clinical explanations")
	check(not has_private_text(JSON.stringify(state.health_baseline)), "Game memory contains only whitelisted projection fields")
	state.health_baseline.attribute_notes = payload.attribute_notes
	state.health_baseline.evidence = payload.evidence
	check(not has_private_text(JSON.stringify(state.to_data())), "Serialization redacts even a directly mutated in-memory baseline")
	var dirty = state.to_data()
	dirty.health_baseline = payload
	var single = base.path_join("standalone.json")
	write_json(single, dirty)
	var loaded = State.new()
	loaded.save_file_override = single
	loaded.load_game()
	check(not has_private_text(FileAccess.get_file_as_string(single)), "Loading rewrites an existing standalone game save without medical fields")
	var cleaned_digest = FileAccess.get_file_as_string(single).sha256_text()
	check(not Privacy.read(single, true, true).changed and FileAccess.get_file_as_string(single).sha256_text() == cleaned_digest, "Redaction is idempotent across JSON float/integer round trips")
	check(loaded.boss_cleared("b00") and loaded.equipment.qi == 135 and loaded.battle_stats().max_hp == 80, "Redaction retains Boss clears, wallet and battle stats")
	var source = Legacy.runtime_candidates(base)
	var old_path = source[1]
	write_json(old_path, dirty)
	var original_hash = FileAccess.get_file_as_string(old_path).sha256_text()
	var account = {"id": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "display_name": "测试账号", "avatar": "male"}
	var roster = Roster.new()
	roster.cache_root_override = base.path_join("accounts")
	roster.legacy_candidates_override = source
	var opened = roster.open_account(account)
	check(opened.ok and opened.needs_import, "Exported original filename is discovered when the newer filename is absent")
	var snapshot = roster.legacy_snapshot()
	check(snapshot.ok and snapshot.path == old_path and snapshot.fingerprint == original_hash, "Ownership fingerprint uses the pinned actual legacy source and survives redaction")
	check(not has_private_text(FileAccess.get_file_as_string(old_path)), "Legacy source is cleaned before ownership claim and backup")
	# A newer file appearing later must not switch the selected source mid-import.
	var competing = State.new()
	competing.equipment.qi = 999
	write_json(source[0], competing.to_data())
	check(roster.legacy_path() == old_path, "Discovery cannot drift to another filename between claim and import")
	check(roster.import_legacy() and roster.owner_state.equipment.qi == 135, "Import reads the same original file rather than newly appearing current saves")
	var backup = old_path.trim_suffix(".json") + "-before-accounts-v8.json"
	check(FileAccess.file_exists(backup) and not has_private_text(FileAccess.get_file_as_string(backup)), "Backup uses the actual old path and contains no medical explanation")
	check(not has_private_text(FileAccess.get_file_as_string(roster.save_path())), "Imported account cache stores only a game projection")
	var cached = JSON.parse_string(FileAccess.get_file_as_string(roster.save_path()))
	cached.owner.progress.health_baseline = payload
	write_json(roster.save_path(), cached)
	var again = Roster.new()
	again.cache_root_override = roster.cache_root_override
	again.legacy_candidates_override = source
	check(again.open_account(account).ok and not has_private_text(FileAccess.get_file_as_string(again.save_path())), "Existing account caches are cleaned on login")
	check(again.owner_state.equipment.qi == 135, "Cleaning an account cache does not reset existing progress")
	check(Legacy.candidates(false) == PackedStringArray(["user://songfeng_pixel_progress.json", "user://family_cultivation_demo.json"]), "Export discovery shares both historical filenames")
	var empty_identity = {"id": "cccccccccccccccccccccccccccccccc", "display_name": "空账号"}
	var empty = Roster.new()
	empty.cache_root_override = roster.cache_root_override
	empty.legacy_candidates_override = PackedStringArray([old_path])
	empty.open_account(empty_identity)
	var empty_data = empty.to_data()
	empty_data.erase("legacy_choice_made")
	write_json(empty.save_path(), empty_data)
	var recover = Roster.new()
	recover.cache_root_override = roster.cache_root_override
	recover.legacy_candidates_override = PackedStringArray([old_path])
	var recovery = recover.open_account(empty_identity)
	check(recovery.ok and recovery.needs_import and recover.owner_state.equipment.qi == 0, "Previously-created empty account caches offer explicit legacy recovery")
	check(recover.import_legacy() and recover.owner_state.equipment.qi == 135, "Empty-account recovery restores old progress only after confirmation")
	var reopened = Roster.new()
	reopened.cache_root_override = roster.cache_root_override
	reopened.legacy_candidates_override = PackedStringArray([old_path])
	check(not reopened.open_account(empty_identity).needs_import and reopened.owner_state.equipment.qi == 135, "A completed import is not offered again on subsequent login")
	empty.dispose()
	recover.dispose()
	reopened.dispose()
	var changed = Roster.new()
	changed.cache_root_override = base.path_join("other-accounts")
	changed.legacy_candidates_override = PackedStringArray([old_path])
	changed.open_account({"id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "display_name": "另一个账号"})
	dirty.cultivation += 1
	write_json(old_path, dirty)
	check(not changed.legacy_snapshot().ok and not changed.import_legacy(), "A legacy file changed after discovery is rejected before import")
	var during_read = Roster.new()
	during_read.persist_enabled = false
	during_read.save_file_override = old_path
	during_read.load_game(State.new(), "mismatched-source-digest")
	check(during_read.load_blocked and during_read.owner_state.equipment.qi == 0, "Import reader verifies the pinned digest before applying any progress")
	during_read.dispose()
	roster.dispose()
	again.dispose()
	changed.dispose()
	# Remove only files created in this process-specific fixture directory.
	for directory in [base.path_join("accounts"), base.path_join("other-accounts")]:
		if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory)):
			continue
		for name in DirAccess.get_files_at(directory):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(directory.path_join(name)))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
	for name in DirAccess.get_files_at(base):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(base.path_join(name)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(base))
	print("PRIVACY / LEGACY RESULT: ", passed, " passed, ", failed, " failed")
	quit(0 if failed == 0 else 1)
