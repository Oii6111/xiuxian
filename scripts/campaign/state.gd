extends RefCounted
const Catalogue = preload("res://scripts/campaign/catalogue.gd")
const SAVE_PATH = "user://five_realms_v3.json"
var persist_enabled: bool = true
var save_override: String = ""
var data: Dictionary = {}
var load_warning: String = ""

func _init() -> void:
	data = defaults()

func defaults() -> Dictionary:
	return {"schema":3,"name":"守灯者","avatar":"male","xp":0,"materials":0,"clears":[],"seals":[],"settled":[],"pending":{},"investigated":[],"buildings":[],"home_choice":"门灯","skill":"雷诀","difficulty":"story","simulated_health":"unknown","encounter_seq":0,"visits":0,"story_flags":[],"legacy":{},"minion_lore":[],"tracked_region":"","best_records":{}}

func path() -> String:
	if save_override != "":
		return save_override
	var custom = OS.get_environment("XIUXIAN_SAVE_DIR")
	if custom != "":
		DirAccess.make_dir_recursive_absolute(custom)
		return custom.path_join("five_realms_v3.json")
	if OS.has_feature("windows") and DirAccess.dir_exists_absolute("D:/"):
		var folder = "D:/Projects/Codex/user-data/xiuxian"
		DirAccess.make_dir_recursive_absolute(folder)
		return folder.path_join("five_realms_v3.json")
	return SAVE_PATH

func load_game() -> void:
	if not persist_enabled:
		return
	if not FileAccess.file_exists(path()):
		_import_legacy()
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path()))
	if not parsed is Dictionary or int(parsed.get("schema", 0)) != 3:
		load_warning = "存档格式异常，已保留原文件；本次从安全初始状态开始。"
		persist_enabled = false
		return
	for key in defaults():
		if not parsed.has(key):
			continue
		if typeof(data[key]) == TYPE_INT and (typeof(parsed[key]) == TYPE_FLOAT or typeof(parsed[key]) == TYPE_INT):
			data[key] = int(parsed[key])
		elif typeof(parsed[key]) == typeof(data[key]):
			data[key] = parsed[key]
	data.clears = data.clears.filter(func(id): return not Catalogue.entry(str(id)).is_empty())
	data.seals = []
	for core in Catalogue.cores():
		if core in data.clears:
			data.seals.append(Catalogue.entry(core).fictional_element)
	if data.skill not in Catalogue.skills():
		data.skill = "雷诀"
	if data.difficulty not in ["story", "standard"]:
		data.difficulty = "story"
	if data.simulated_health not in ["unknown", "steady", "tired"]:
		data.simulated_health = "unknown"
	data.xp = maxi(0, int(data.xp))
	data.materials = maxi(0, int(data.materials))
	# An interrupted battle has no reward; no family resources were reserved.
	data.pending = {}

func _import_legacy() -> void:
	var old_path = "res://output/local-save.json" if OS.has_feature("editor") else "user://family_cultivation_demo.json"
	if not FileAccess.file_exists(old_path):
		return
	var old = JSON.parse_string(FileAccess.get_file_as_string(old_path))
	if old is Dictionary:
		data.name = str(old.get("player_name", "守灯者"))
		data.avatar = str(old.get("avatar_id", "male"))
		data.legacy = {"cultivation":old.get("cultivation",80),"qi":old.get("qi",24),"recovery_status":old.get("recovery_status","not_started")}
		# The old file is never overwritten. Legacy clinical status is archival only.

func save_game() -> void:
	if not persist_enabled:
		return
	var target = path()
	var temp = target + ".tmp"
	var file = FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		load_warning = "暂时无法保存，请检查目录权限。"
		return
	file.store_string(JSON.stringify(data))
	file.close()
	if FileAccess.file_exists(target):
		DirAccess.copy_absolute(target, target + ".bak")
	var err = DirAccess.rename_absolute(temp, target)
	if err != OK:
		# Some filesystems do not replace an existing destination on rename.
		var copied = DirAccess.copy_absolute(temp, target)
		if copied == OK:
			DirAccess.remove_absolute(temp)
		else:
			load_warning = "存档未能更新，已有备份保留。"

func availability(id: String) -> String:
	var row = Catalogue.entry(id)
	if row.is_empty():
		return "未知篇章"
	if id == "b00":
		return ""
	if "b00" not in data.clears:
		return "先完成照生乡的听雷教学"
	if id == "b19" and data.seals.size() < 5:
		return "需要五域主祟的五枚归衡印（%d/5）" % data.seals.size()
	if id == "b18" and data.seals.is_empty():
		return "恢复任意一域后开放"
	return ""

func investigate(id: String) -> void:
	if id not in data.investigated:
		data.investigated.append(id)
	save_game()

func begin(id: String) -> Dictionary:
	var reason = availability(id)
	if reason != "":
		return {"ok":false,"message":reason}
	data.encounter_seq += 1
	var token = "%s-%d-%d" % [id, data.encounter_seq, Time.get_ticks_usec()]
	data.pending[token] = id
	save_game()
	return {"ok":true,"token":token,"snapshot":snapshot()}

func snapshot() -> Dictionary:
	# Explicitly simulated presets; never interpreted from a medical value.
	var kind = data.simulated_health
	return {"status":kind,"attack":1.10 if kind == "steady" else (0.95 if kind == "tired" else 1.0),"stamina":1.05 if kind == "steady" else (0.95 if kind == "tired" else 1.0),"version":1,"simulated":true}

func settle(token: String, id: String, won: bool, mode: String, metrics: Dictionary = {}) -> Dictionary:
	if token in data.settled or data.pending.get(token, "") != id:
		return {"ok":false,"message":"这次挑战已结算或不属于当前场次"}
	data.pending.erase(token)
	data.settled.append(token)
	if data.settled.size() > 256:
		data.settled.pop_front()
	if not won:
		save_game()
		return {"ok":true,"first":false,"xp":0,"materials":0,"message":"本次暂歇，没有失去修为。可立即重试。"}
	var first = id not in data.clears
	var xp = (80 if id == "b00" else 120) if first else 0
	var materials = (6 if id in Catalogue.cores() else 3) if first else 0
	if first:
		data.clears.append(id)
		data.xp += xp
		data.materials += materials
		if id in Catalogue.cores():
			var element = Catalogue.entry(id).fictional_element
			if element not in data.seals:
				data.seals.append(element)
			for mob in Catalogue.minions_for(element):
				if mob.id not in data.minion_lore:
					data.minion_lore.append(mob.id)
	var record_key = id+"|"+mode+"|"+str(metrics.get("preset","unknown"))+"|"+str(metrics.get("skill","雷诀"))
	var new_best = false
	if float(metrics.get("seconds",0)) > 0:
		var old = data.best_records.get(record_key,{})
		if old.is_empty() or float(metrics.seconds) < float(old.seconds):
			data.best_records[record_key] = metrics.duplicate(true)
			new_best = true
	if data.seals.size() == 5 and "five_seals" not in data.story_flags:
		data.story_flags.append("five_seals")
	save_game()
	return {"ok":true,"first":first,"xp":xp,"materials":materials,"message":"首通获得固定奖励，故乡留下新的变化。" if first else "回响挑战完成。主线奖励不重复发放，练习不限次。","mode":mode,"new_best":new_best,"seconds":metrics.get("seconds",0)}

func abandon(token: String) -> void:
	data.pending.erase(token)
	save_game()

func build(item: String) -> bool:
	if item in data.buildings or data.materials < 3:
		return false
	data.materials -= 3
	data.buildings.append(item)
	save_game()
	return true

func realm() -> String:
	var xp = int(data.xp)
	return "元婴" if xp >= 1800 else ("金丹" if xp >= 900 else ("筑基" if xp >= 300 else "炼气"))

func next_goal() -> String:
	if "b00" not in data.clears:
		return "先在听雷台学会观察、护盾与反击"
	if data.seals.size() == 5:
		return "五印已齐，前往常生台" if "b19" not in data.clears else "长夜已退，去看看故乡与旁篇"
	if str(data.tracked_region) != "":
		return "已记下委托："+Catalogue.region_name(str(data.tracked_region))+" · 五印 %d/5" % data.seals.size()
	return "自选五域，收集归衡印（%d/5）" % data.seals.size()

func record_minion(id: String) -> void:
	if not Catalogue.minion(id).is_empty() and id not in data.minion_lore:
		data.minion_lore.append(id)
		save_game()

func track(region: String) -> void:
	data.tracked_region = region
	save_game()
