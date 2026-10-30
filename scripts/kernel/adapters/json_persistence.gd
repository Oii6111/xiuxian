extends RefCounted
## L0 的 IO 适配器是文件访问边界；领域、规则和玩法模块不得自行读写文件。
## 使用独立 v2 文件，Web 上 user:// 由 Godot 映射到 IndexedDB。
const Result = preload("res://scripts/kernel/result.gd")
var _path: String

func _init(path: String = "user://kernel_v2.json") -> void:
	_path = path

func read_document() -> Dictionary:
	if not FileAccess.file_exists(_path):
		return Result.failure("NOT_FOUND", "尚无内核存档")
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		return Result.failure("IO_ERROR", "无法读取内核存档")
	var parser := JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not parser.data is Dictionary:
		return Result.failure("CORRUPT_SAVE", "内核存档损坏，原文件已保留")
	return Result.success({"document": parser.data})

func write_document(document: Dictionary) -> Dictionary:
	var folder: String = ProjectSettings.globalize_path(_path.get_base_dir())
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		return Result.failure("IO_ERROR", "无法创建存档目录")
	var temporary: String = _path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return Result.failure("IO_ERROR", "无法创建临时存档")
	file.store_string(JSON.stringify(document, "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		return Result.failure("IO_ERROR", "临时存档写入失败")
	if FileAccess.file_exists(_path):
		if DirAccess.copy_absolute(_path, _path + ".bak") != OK:
			return Result.failure("IO_ERROR", "旧存档备份失败，停止覆盖")
	# 不采用先删除正式文件的回退策略；重命名失败时保留旧文件和临时文件。
	if DirAccess.rename_absolute(temporary, _path) != OK:
		return Result.failure("IO_ERROR", "替换存档失败，旧存档仍保留")
	return Result.success()
