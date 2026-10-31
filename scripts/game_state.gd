extends RefCounted
## Game state stores confirmed game attributes; report analysis runs in the loopback bridge.

const TrialCatalogue = preload("res://scripts/trial_catalogue.gd")
const HealthProfile = preload("res://scripts/health_profile.gd")
const HealthBaseline = preload("res://scripts/health_baseline.gd")
const Equipment = preload("res://scripts/equipment_rules.gd")

const Privacy = preload("res://scripts/game_save_privacy.gd")
const LegacySaves = preload("res://scripts/legacy_saves.gd")
const SAVE_PATH = LegacySaves.EDITOR_SAVE
const DAILY_CULTIVATION = 10
const DAILY_SEALS = 1

func save_path() -> String:
	if save_file_override != "":
		return save_file_override
	return LegacySaves.primary(OS.has_feature("editor"))
var save_file_override: String = ""
var cultivation: int = 80
var qi: int = 24
var charms: int = 2
var seals: int = 8
var days: int = 28
var rewarded_days: Array = []
var confirmed_events: Array = []
var contribution: int = 0
var boss_attempts: int = 0
var boss_day: String = ""
var last_reward_day: String = ""
var profile_created: bool = false
var avatar_id: String = "male"
var player_name: String = "松风"
var longterm_enabled: bool = true
var medication_required: bool = true
var daily_tasks: Dictionary = {}
var recovery_status: String = "not_started"
var trial_cleared: bool = false
var persist_enabled: bool = true
var equipment: Dictionary = Equipment.fresh()
var equipment_rng = RandomNumberGenerator.new()
# Each elder owns this complete state. The roster commits both elders to one atomic save.
var family_member_id: String = ""
var family_identity: Dictionary = {}
var family_save: Callable = Callable()
# 正式模式：已登录 C 的角色 ID。非空时资源、装备与奖励只由服务端确认，本地只是读模型缓存。
var cultivator_id: String = ""
const REMOTE_RARITIES = ["common", "fine", "epic", "legendary", "mythic"]
const REMOTE_ONLY = "正式账号的灵气、装备与每日奖励由游戏服务确认，请稍后重试。"

func _init() -> void:
	equipment_rng.randomize()

const ATTRIBUTE_KEYS = HealthProfile.KEYS
const ATTRIBUTE_LABELS = HealthProfile.LABELS
const TIERS = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
var health_attributes: Dictionary = {"life": 40, "attack": 40, "defense": 40, "spirit": 40, "stamina": 40}
var health_baseline: Dictionary = {}
var health_profile_id: String = ""
var health_revision: int = 0
var health_source: String = "未导入 · 使用模拟基准"
var health_simulated: bool = true
var selected_track: String = "attack"
var selected_tier: int = 10
var cleared_stages: Array = []
var best_records: Dictionary = {}
var selected_boss_id: String = "b00"
var cleared_bosses: Array = []
var boss_records: Dictionary = {}

func apply_health_profile(payload: Dictionary) -> Dictionary:
	if not health_baseline.is_empty():
		return {"ok": false, "message": "初始档案已锁定，请通过补充报告生成新的档案。"}
	var result = HealthProfile.validate(payload)
	if not result.ok:
		return result
	if result.profile_id == health_profile_id and result.revision <= health_revision:
		return {"ok": false, "message": "这份档案已导入，或版本早于当前档案。"}
	health_attributes = result.attributes.duplicate(true)
	health_profile_id = result.profile_id
	health_revision = result.revision
	health_source = result.source
	health_simulated = result.simulated
	lock_equipment_origin()
	return {"ok": true, "message": "健康属性已更新，下一场挑战生效。已通关进度完整保留。"}

func save_health_profile(payload: Dictionary) -> Dictionary:
	var before = health_snapshot()
	var result = apply_health_profile(payload)
	if not result.ok:
		return result
	if not save_game():
		restore_health_snapshot(before)
		return {"ok": false, "message": "存档写入失败，原有属性已保留，请重试。"}
	return result

func health_snapshot() -> Dictionary:
	return {"player_name": player_name, "health_baseline": health_baseline.duplicate(true), "health_attributes": health_attributes.duplicate(true), "health_profile_id": health_profile_id, "health_revision": health_revision, "health_source": health_source, "health_simulated": health_simulated, "equipment": equipment.duplicate(true), "family_identity": family_identity.duplicate(true)}

func restore_health_snapshot(snapshot: Dictionary) -> void:
	for key in snapshot:
		set(key, snapshot[key])

func apply_health_baseline(payload: Dictionary) -> Dictionary:
	var result = HealthBaseline.validate(payload)
	if not result.ok:
		return result
	if result.baseline.baseline_id == health_profile_id:
		return {"ok": false, "message": "这份初始档案已经导入。"}
	health_baseline = result.baseline.duplicate(true)
	health_attributes = HealthBaseline.attributes(health_baseline)
	health_profile_id = health_baseline.baseline_id
	health_revision += 1
	if not str(health_baseline.get("display_name", "")).strip_edges().is_empty():
		if family_member_id.is_empty():
			player_name = str(health_baseline.display_name).left(10)
		else:
			family_identity.name = str(health_baseline.display_name).left(10)
	health_simulated = health_baseline.recognition_mode in ["sample", "demo"]
	health_source = HealthBaseline.source_label(health_baseline)
	lock_equipment_origin()
	return {"ok": true, "message": "初始属性已确认，已通关进度完整保留。"}

func base_battle_stats() -> Dictionary:
	if not health_baseline.is_empty():
		return HealthBaseline.battle_stats(health_baseline)
	return HealthProfile.battle_stats(health_attributes)

func battle_stats() -> Dictionary:
	var stats = base_battle_stats()
	var extra = Equipment.bonuses(equipment)
	stats.max_hp += extra.life
	stats.attack += extra.attack
	stats.max_mp += extra.spirit
	stats.max_stamina += extra.stamina
	var resistance = 100.0 / float(stats.damage_multiplier) - 100.0
	stats.damage_multiplier = 100.0 / (100.0 + resistance + extra.defense * 0.8)
	stats.shield += extra.defense * 2
	return stats

func lock_equipment_origin() -> void:
	# First confirmed profile only. Better health and equipped gear never reduce this support.
	if float(equipment.initial_score) < 0 and not health_profile_id.is_empty():
		equipment.initial_score = Equipment.initial_score(health_attributes)
		equipment.initial_profile_id = health_profile_id

func is_remote() -> bool:
	return not cultivator_id.is_empty()

## 用 C 的角色快照覆盖本地读模型：钱包、修为、灵印、累计日、装备实例与冻结的初始支持值。
func apply_remote(character: Dictionary) -> void:
	if str(character.get("cultivator_id", "")) != cultivator_id:
		return
	var remote_baseline = character.get("baseline")
	if remote_baseline is Dictionary and str(remote_baseline.get("baseline_id", "")) != health_profile_id:
		var payload = {"baseline_id": remote_baseline.get("baseline_id"), "baseline_version": "char_baseline_v1", "baseline_locked": true, "recognition_mode": remote_baseline.get("recognition_mode"), "mapping_version": remote_baseline.get("mapping_version", ""), "character_state": remote_baseline.get("character_state"), "readiness": remote_baseline.get("readiness"), "display_name": ""}
		var checked = HealthBaseline.validate(payload)
		if checked.ok:
			health_baseline = checked.baseline.duplicate(true)
			health_attributes = HealthBaseline.attributes(health_baseline)
			health_profile_id = health_baseline.baseline_id
			health_revision += 1
			health_simulated = health_baseline.recognition_mode in ["sample", "demo"]
			health_source = HealthBaseline.source_label(health_baseline)
	var resources = character.get("resources", {})
	equipment.qi = int(resources.get("spirit_stones", 0))
	cultivation = int(resources.get("realm_xp", 0))
	seals = int(resources.get("seals", 0))
	days = int(character.get("days", 0))
	equipment.draw_count = int(character.get("draw_count", 0))
	var score = character.get("initial_score")
	equipment.initial_score = float(score) if score != null else -1.0
	equipment.initial_profile_id = str(character.get("initial_profile_id", ""))
	var inventory = []
	var equipped = {}
	for item in character.get("equipment", []):
		if not item is Dictionary or item.get("catalogue_version") != Equipment.CATALOGUE_VERSION:
			continue
		var template = int(str(item.get("catalogue_id", "")).trim_prefix("pixel:"))
		var rarity = REMOTE_RARITIES.find(str(item.get("rarity", "")))
		if not str(item.get("catalogue_id", "")).begins_with("pixel:") or template < 0 or template >= Equipment.TEMPLATES.size() or rarity < 0:
			continue
		var entry = {"id": str(item.equipment_id), "template": template, "rarity": rarity}
		inventory.append(entry)
		if int(item.get("equipped", 0)) == 1:
			equipped[Equipment.TEMPLATES[template].slot] = entry.id
	equipment.inventory = inventory
	equipment.equipped = equipped

func draw_equipment(count: int, request_id: String) -> Dictionary:
	if is_remote():
		return {"ok": false, "message": REMOTE_ONLY}
	if request_id.is_empty() or count not in [1, 10]:
		return {"ok": false, "message": "祈愿请求无效。"}
	if equipment.receipts.has(request_id):
		var previous = equipment.receipts[request_id]
		if int(previous.count) != count:
			return {"ok": false, "message": "请求编号与抽取次数不一致。"}
		return previous.duplicate(true)
	if float(equipment.initial_score) < 0:
		return {"ok": false, "message": "请先确认一份基础档案，再来聚宝阁祈愿。"}
	var cost = Equipment.SINGLE_COST * count
	if int(equipment.qi) < cost:
		return {"ok": false, "message": "灵气不足，还差 %d。每日有效习惯记录可获得 100 灵气。" % (cost - int(equipment.qi))}
	var before = equipment.duplicate(true)
	var items = []
	var best_rarity = 0
	for i in range(count):
		var rarity = Equipment.roll_rarity(float(equipment.initial_score), equipment_rng)
		best_rarity = maxi(best_rarity, rarity)
		items.append(Equipment.make_item(int(equipment.next_id) + i, rarity, equipment_rng))
	var guaranteed = count == 10 and best_rarity < 2
	if guaranteed:
		# Upgrade the last card, never downgrade a naturally rolled legendary/mythic.
		items[-1].rarity = 2
	equipment.qi -= cost
	equipment.next_id += count
	equipment.draw_count += count
	equipment.inventory.append_array(items)
	var receipt = {"ok": true, "request_id": request_id, "count": count, "cost": cost, "items": items.duplicate(true), "guaranteed": guaranteed}
	equipment.receipts[request_id] = receipt
	equipment.last_request = request_id
	# Save the debit, items and receipt together BEFORE any reveal animation.
	if not save_game():
		equipment = before
		return {"ok": false, "message": "存档写入失败，灵气未扣除。请检查存档目录后重试。"}
	return receipt.duplicate(true)

func equip_item(item_id: String) -> Dictionary:
	if is_remote():
		return {"ok": false, "message": REMOTE_ONLY}
	for item in equipment.inventory:
		if item.id == item_id:
			var info = Equipment.detail(item)
			var before = equipment.duplicate(true)
			equipment.equipped[info.slot] = info.id
			if not save_game():
				equipment = before
				return {"ok": false, "message": "存档失败，已保留原来的穿戴。"}
			return {"ok": true, "message": "已穿戴「%s」，下一场战斗生效。" % info.name}
	return {"ok": false, "message": "这件装备不在行囊中。"}

func unequip_item(slot: String) -> Dictionary:
	if is_remote():
		return {"ok": false, "message": REMOTE_ONLY}
	if slot not in Equipment.SLOTS:
		return {"ok": false, "message": "装备槽位无效。"}
	var before = equipment.duplicate(true)
	equipment.equipped.erase(slot)
	if not save_game():
		equipment = before
		return {"ok": false, "message": "存档失败，已保留原来的穿戴。"}
	return {"ok": true, "message": "已卸下装备，下一场战斗生效。"}

func stage_key(track: String, tier: int) -> String:
	return track + "_" + str(tier)

func stage_cleared(track: String, tier: int) -> bool:
	return stage_key(track, tier) in cleared_stages

func next_tier(track: String = "") -> int:
	var key = selected_track if track == "" else track
	for tier in TIERS:
		if not stage_cleared(key, tier):
			return tier
	return 100

func stage_available(track: String, tier: int) -> bool:
	return track in ATTRIBUTE_KEYS and tier in TIERS and tier <= next_tier(track)

func heal_unlocked() -> bool:
	return cleared_bosses.size() >= 2 or cleared_stages.size() >= 2

func complete_stage(track: String, tier: int, record: Dictionary = {}) -> bool:
	if not stage_available(track, tier):
		return false
	var key = stage_key(track, tier)
	var first_clear = key not in cleared_stages
	if first_clear:
		cleared_stages.append(key)
	if not record.is_empty() and (not best_records.has(key) or float(record.get("time", INF)) < float(best_records[key].get("time", INF))):
		best_records[key] = record.duplicate(true)
	return first_clear

func boss_cleared(id: String) -> bool:
	return id in cleared_bosses

func begin_named_boss(id: String) -> Dictionary:
	var encounter = TrialCatalogue.entry(id)
	if encounter.is_empty():
		return {"ok": false, "message": "没有找到这位祟兽。"}
	selected_boss_id = id
	selected_tier = int(encounter.tier)
	refresh_boss_day()
	boss_attempts += 1
	return {"ok": true, "encounter": encounter}

func complete_boss(id: String, record: Dictionary = {}) -> bool:
	if TrialCatalogue.entry(id).is_empty():
		return false
	var first_clear = id not in cleared_bosses
	if first_clear:
		cleared_bosses.append(id)
	if not record.is_empty() and (not boss_records.has(id) or float(record.get("time", INF)) < float(boss_records[id].get("time", INF))):
		boss_records[id] = record.duplicate(true)
	return first_clear

func choose_avatar(id: String, nickname: String) -> void:
	avatar_id = "female" if id == "female" else "male"
	player_name = nickname.strip_edges().left(10)
	if player_name == "":
		player_name = "家族守护者"
	profile_created = true
	if not family_member_id.is_empty():
		family_identity.title = player_name
		family_identity.avatar = avatar_id

func member_label() -> String:
	if family_identity.is_empty():
		return player_name
	var name = str(family_identity.get("name", "家人"))
	var relation = str(family_identity.get("relation", ""))
	return name + ("（" + relation + "）" if not relation.is_empty() else "")

func task_done(task: String, day: String = "") -> bool:
	var key = today() if day == "" else day
	return daily_tasks.get(key, {}).get(task, false) == true

func record_task(task: String, consent: bool) -> Dictionary:
	if is_remote():
		return {"ok": false, "rewarded": false, "message": "正式账号的每日记录由老人微信反馈、核验后自动结算，游戏内不再本地发放奖励。"}
	if not consent:
		return {"ok": false, "rewarded": false, "message": "请先由家属确认并授权本次演示记录。"}
	if task not in ["medication", "planned_record"]:
		return {"ok": false, "rewarded": false, "message": "未知计划任务。"}
	if task == "medication" and (not longterm_enabled or not medication_required):
		return {"ok": false, "rewarded": false, "message": "当前未启用个人用药计划，无需记录服药。"}
	var day = today()
	if task_done(task, day):
		return {"ok": false, "rewarded": false, "message": "今天这项计划已经确认，无需重复记录。"}
	var previous_tasks = daily_tasks.duplicate(true)
	if not daily_tasks.has(day):
		daily_tasks[day] = {}
	daily_tasks[day][task] = true
	var rewarded = false
	var message = "今日记录已保存。主行为奖励已领取，修行积累不会重复计数。"
	if day not in rewarded_days:
		var result = confirm_event({"event_id": "plan_" + day + "_" + task, "plan_id": "daily_plan", "observed_day": day, "review_status": "confirmed", "consent_scope": "family_game", "source": "family_confirmation"})
		if not result.ok:
			daily_tasks = previous_tasks
			return result
		rewarded = result.ok
		message = result.message
	elif not save_game():
		daily_tasks = previous_tasks
		return {"ok": false, "rewarded": false, "message": "记录保存失败，请重试。"}
	return {"ok": true, "rewarded": rewarded, "message": message}

func begin_recovery(confirmed: bool) -> bool:
	if not confirmed:
		return false
	recovery_status = "active"
	trial_cleared = false
	return true

func confirm_recovery(confirmed: bool, reliable_source: bool) -> bool:
	if not confirmed or not reliable_source or recovery_status != "active":
		return false
	recovery_status = "recovered"
	return true

func refresh_boss_day() -> void:
	if boss_day != today():
		boss_day = today()
		boss_attempts = 0

func begin_boss(_use_support: bool = false, tier: int = 0, track: String = "") -> Dictionary:
	var requested_track = selected_track if track == "" else track
	var requested_tier = next_tier(requested_track) if tier == 0 else tier
	if not stage_available(requested_track, requested_tier):
		return {"ok": false, "message": "请先通关这条试炼线的上一档。"}
	selected_track = requested_track
	selected_tier = requested_tier
	refresh_boss_day()
	boss_attempts += 1
	return {"ok": true, "support_damage": 0}

static func reward_day(unix_seconds: int) -> String:
	# Natural reward days follow Beijing time, including on overseas hosts.
	return Time.get_date_string_from_unix_time(unix_seconds + 8 * 3600)

func today() -> String:
	return reward_day(int(Time.get_unix_time_from_system()))

func confirm_event(event: Dictionary) -> Dictionary:
	if is_remote():
		return {"ok": false, "rewarded": false, "message": REMOTE_ONLY}
	var day = today()
	if event.get("review_status", "") != "confirmed":
		return {"ok": false, "message": "请先确认演示记录，再领取奖励。"}
	if event.get("event_id", "") == "" or event.get("plan_id", "") != "daily_plan":
		return {"ok": false, "message": "记录缺少事件编号或不属于当前个人计划。"}
	if event.get("consent_scope", "") != "family_game":
		return {"ok": false, "message": "这条记录尚未获得家族游戏使用授权。"}
	if event["event_id"] in confirmed_events:
		return {"ok": false, "message": "这条记录已经领取过奖励。"}
	if event.get("observed_day", "") != day:
		return {"ok": false, "message": "快速演示只结算今日的计划记录。"}
	if day in rewarded_days:
		return {"ok": false, "message": "今日主行为奖励已领取。无需重复记录，仍可继续探索和试炼。"}
	var before = {"cultivation": cultivation, "seals": seals, "days": days, "last_reward_day": last_reward_day, "confirmed_events": confirmed_events.duplicate(), "rewarded_days": rewarded_days.duplicate(), "equipment": equipment.duplicate(true)}
	confirmed_events.append(event["event_id"])
	rewarded_days.append(day)
	last_reward_day = day
	cultivation += DAILY_CULTIVATION
	seals += DAILY_SEALS
	days += 1
	equipment.qi += Equipment.DAILY_QI
	if not save_game():
		for key in before:
			set(key, before[key])
		return {"ok": false, "rewarded": false, "message": "记录保存失败，奖励尚未发放，请重试。"}
	return {"ok": true, "message": "家人的坚持，化作你的守护。\n修为 +10  ·  灵印 +1  ·  灵气 +100"}

func realm() -> String:
	var highest = 0
	for track in ATTRIBUTE_KEYS:
		for tier in TIERS:
			if stage_cleared(track, tier):
				highest = maxi(highest, tier)
	if highest >= 100 or cleared_bosses.size() >= 20:
		return "化神圆满"
	var realm_index = maxi(mini(4, int(highest / 20)), mini(4, int(cleared_bosses.size() / 4)))
	return ["炼气", "筑基", "结丹", "元婴", "化神"][realm_index]

func to_data() -> Dictionary:
	return Privacy.clean({"schema": 6, "cultivator_id": cultivator_id, "equipment": equipment, "health_baseline": health_baseline, "selected_boss_id": selected_boss_id, "cleared_bosses": cleared_bosses, "boss_records": boss_records, "health_attributes": health_attributes, "health_profile_id": health_profile_id, "health_revision": health_revision, "health_source": health_source, "health_simulated": health_simulated, "selected_track": selected_track, "selected_tier": selected_tier, "cleared_stages": cleared_stages, "best_records": best_records, "cultivation": cultivation, "qi": qi, "charms": charms, "seals": seals, "days": days, "rewarded_days": rewarded_days, "confirmed_events": confirmed_events, "contribution": contribution, "boss_attempts": boss_attempts, "boss_day": boss_day, "last_reward_day": last_reward_day, "profile_created": profile_created, "avatar_id": avatar_id, "player_name": player_name, "longterm_enabled": longterm_enabled, "medication_required": medication_required, "daily_tasks": daily_tasks, "recovery_status": recovery_status, "trial_cleared": trial_cleared})

func save_game() -> bool:
	if not persist_enabled:
		return true
	if family_save.is_valid():
		return family_save.call()
	var temporary_path = save_path() + ".tmp"
	var file = FileAccess.open(temporary_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(to_data()))

		file.flush()
		var write_error = file.get_error()
		file.close()
		if write_error != OK:
			return false
		return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary_path), ProjectSettings.globalize_path(save_path())) == OK
	return false

func load_game() -> void:
	var candidates = PackedStringArray([save_file_override]) if not save_file_override.is_empty() else LegacySaves.candidates(OS.has_feature("editor"))
	var source_path = LegacySaves.resolve(candidates)
	if source_path.is_empty():
		return
	var document = Privacy.read(source_path, persist_enabled, true)
	if not document.ok:
		push_error(document.message)
		return
	var original_text = document.text
	var data = document.data
	if int(data.get("schema", 1)) < 6 and persist_enabled:
		var equipment_backup = source_path.trim_suffix(".json") + "-before-equipment-v6.json"
		if not FileAccess.file_exists(equipment_backup):
			var backup = FileAccess.open(equipment_backup, FileAccess.WRITE)
			if backup:
				backup.store_string(original_text)
	if int(data.get("schema", 1)) < 4 and persist_enabled:
		var backup_path = source_path.trim_suffix(".json") + "-before-corridor-v4.json"
		if not FileAccess.file_exists(backup_path):
			var backup_file = FileAccess.open(backup_path, FileAccess.WRITE)
			if backup_file:
				backup_file.store_string(original_text)
	if int(data.get("schema", 1)) == 4 and persist_enabled:
		var health_backup = source_path.trim_suffix(".json") + "-before-health-v5.json"
		if not FileAccess.file_exists(health_backup):
			var backup_file = FileAccess.open(health_backup, FileAccess.WRITE)
			if backup_file:
				backup_file.store_string(original_text)
	load_data(data)

func load_data(data: Dictionary) -> void:
	data = Privacy.clean(data)
	health_baseline.clear()
	var saved_profile = HealthProfile.validate({"profile_id": data.get("health_profile_id", ""), "revision": data.get("health_revision", 0), "source": data.get("health_source", "external"), "simulated": data.get("health_simulated", false), "attributes": data.get("health_attributes", {})})
	if saved_profile.ok:
		health_attributes = saved_profile.attributes
		health_profile_id = saved_profile.profile_id
		health_revision = saved_profile.revision
		health_source = saved_profile.source
		health_simulated = saved_profile.simulated
	var saved_baseline = data.get("health_baseline", {})
	if saved_baseline is Dictionary and not saved_baseline.is_empty():
		var normalized = HealthBaseline.validate(saved_baseline)
		if normalized.ok:
			health_baseline = normalized.baseline
			health_attributes = HealthBaseline.attributes(health_baseline)
			health_profile_id = health_baseline.baseline_id
			health_revision = maxi(1, int(data.get("health_revision", 1)))
			health_simulated = health_baseline.recognition_mode in ["sample", "demo"]
			health_source = HealthBaseline.source_label(health_baseline)
	selected_boss_id = str(data.get("selected_boss_id", "b00"))
	if TrialCatalogue.entry(selected_boss_id).is_empty():
		selected_boss_id = "b00"
	cleared_bosses.clear()
	var saved_bosses = data.get("cleared_bosses", [])
	if saved_bosses is Array:
		for boss in TrialCatalogue.all():
			if boss.id in saved_bosses:
				cleared_bosses.append(boss.id)
	boss_records.clear()
	var saved_records = data.get("boss_records", {})
	if saved_records is Dictionary:
		for id in cleared_bosses:
			if saved_records.get(id) is Dictionary:
				boss_records[id] = saved_records[id].duplicate(true)
	selected_track = str(data.get("selected_track", "attack"))
	if selected_track not in ATTRIBUTE_KEYS:
		selected_track = "attack"
	selected_tier = int(data.get("selected_tier", 10))
	if selected_tier not in TIERS:
		selected_tier = 10
	cleared_stages.clear()
	var saved_clears = data.get("cleared_stages", [])
	if saved_clears is Array:
		for track in ATTRIBUTE_KEYS:
			for tier in TIERS:
				var key = stage_key(track, tier)
				if key not in saved_clears:
					break
				cleared_stages.append(key)
	best_records = data.get("best_records", {}) if data.get("best_records", {}) is Dictionary else {}
	cultivation = int(data.get("cultivation", 80))
	qi = int(data.get("qi", 24))
	charms = int(data.get("charms", 2))
	seals = int(data.get("seals", 8))
	days = int(data.get("days", 28))
	rewarded_days = data.get("rewarded_days", [])
	confirmed_events = data.get("confirmed_events", [])
	contribution = int(data.get("contribution", 0))
	boss_attempts = int(data.get("boss_attempts", 0))
	boss_day = str(data.get("boss_day", ""))
	last_reward_day = str(data.get("last_reward_day", ""))
	profile_created = bool(data.get("profile_created", false))
	avatar_id = "female" if data.get("avatar_id", "male") == "female" else "male"
	player_name = str(data.get("player_name", "家族守护者")).left(10)
	longterm_enabled = bool(data.get("longterm_enabled", true))
	medication_required = bool(data.get("medication_required", true))
	daily_tasks = data.get("daily_tasks", {}) if data.get("daily_tasks", {}) is Dictionary else {}
	recovery_status = str(data.get("recovery_status", "not_started"))
	trial_cleared = bool(data.get("trial_cleared", false))
	equipment = Equipment.normalize(data.get("equipment", {}))
	cultivator_id = str(data.get("cultivator_id", ""))
	lock_equipment_origin()
	# Upgrade only today's already-confirmed habit, without retroactive historical rewards.
	if int(data.get("schema", 1)) < 6 and today() in rewarded_days:
		equipment.qi = Equipment.DAILY_QI

func reset_demo() -> void:
	equipment = Equipment.fresh()
	health_baseline.clear()
	health_attributes = {"life": 40, "attack": 40, "defense": 40, "spirit": 40, "stamina": 40}
	health_profile_id = ""
	health_revision = 0
	health_source = "未导入 · 使用模拟基准"
	health_simulated = true
	selected_track = "attack"
	selected_tier = 10
	selected_boss_id = "b00"
	cleared_bosses.clear()
	boss_records.clear()
	cleared_stages.clear()
	best_records.clear()
	cultivation = 80
	qi = 24
	charms = 2
	seals = 8
	days = 28
	rewarded_days.clear()
	confirmed_events.clear()
	contribution = 0
	boss_attempts = 0
	boss_day = ""
	last_reward_day = ""
	daily_tasks.clear()
	longterm_enabled = true
	medication_required = true
	recovery_status = "not_started"
	trial_cleared = false
	save_game()
