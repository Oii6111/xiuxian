extends RefCounted
## Local, fictional demonstration data. No clinical interpretation or network AI.

const SAVE_PATH = "res://output/local-save.json"

func save_path() -> String:
	if save_file_override != "":
		return save_file_override
	return SAVE_PATH if OS.has_feature("editor") else "user://family_cultivation_demo.json"
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
var player_name: String = "家族守护者"
var longterm_enabled: bool = true
var medication_required: bool = true
var daily_tasks: Dictionary = {}
var recovery_status: String = "not_started"
var trial_cleared: bool = false
var persist_enabled: bool = true

func choose_avatar(id: String, nickname: String) -> void:
	avatar_id = "female" if id == "female" else "male"
	player_name = nickname.strip_edges().left(10)
	if player_name == "":
		player_name = "家族守护者"
	profile_created = true

func task_done(task: String, day: String = "") -> bool:
	var key = today() if day == "" else day
	return daily_tasks.get(key, {}).get(task, false) == true

func record_task(task: String, consent: bool) -> Dictionary:
	if not consent:
		return {"ok": false, "rewarded": false, "message": "请先由家属确认并授权本次演示记录。"}
	if task not in ["medication", "planned_record"]:
		return {"ok": false, "rewarded": false, "message": "未知计划任务。"}
	if task == "medication" and (not longterm_enabled or not medication_required):
		return {"ok": false, "rewarded": false, "message": "当前未启用个人用药计划，无需记录服药。"}
	if task_done(task):
		return {"ok": false, "rewarded": false, "message": "今天这项计划已经确认，无需重复记录。"}
	var day = today()
	if not daily_tasks.has(day):
		daily_tasks[day] = {}
	daily_tasks[day][task] = true
	var rewarded = false
	var message = "今日记录已保存。主行为奖励已领取，修行积累不会重复计数。"
	if day not in rewarded_days:
		var result = confirm_event({"event_id": "plan_" + day + "_" + task, "plan_id": "daily_plan", "observed_day": day, "review_status": "confirmed", "consent_scope": "family_game", "source": "family_confirmation"})
		rewarded = result.ok
		message = result.message
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

func begin_boss(use_support: bool) -> Dictionary:
	refresh_boss_day()
	if boss_attempts >= 3:
		return {"ok": false, "message": "今日三次出战已用完，普通渡劫试炼仍可体验。"}
	if use_support and charms <= 0:
		return {"ok": false, "message": "暂无守护符，可不带支援直接出战。"}
	boss_attempts += 1
	if use_support:
		charms -= 1
	return {"ok": true, "support_damage": 20 if use_support else 0}

func today() -> String:
	return Time.get_date_string_from_system()

func confirm_event(event: Dictionary) -> Dictionary:
	if event.get("review_status", "") != "confirmed":
		return {"ok": false, "message": "请先确认演示记录，再领取奖励。"}
	if event.get("event_id", "") == "" or event.get("plan_id", "") != "daily_plan":
		return {"ok": false, "message": "记录缺少事件编号或不属于当前个人计划。"}
	if event.get("consent_scope", "") != "family_game":
		return {"ok": false, "message": "这条记录尚未获得家族游戏使用授权。"}
	if event["event_id"] in confirmed_events:
		return {"ok": false, "message": "这条记录已经领取过奖励。"}
	if event.get("observed_day", "") != today():
		return {"ok": false, "message": "快速演示只结算今日的计划记录。"}
	if today() in rewarded_days:
		return {"ok": false, "message": "今日主行为奖励已领取。无需重复记录，仍可继续探索和试炼。"}
	confirmed_events.append(event["event_id"])
	rewarded_days.append(today())
	last_reward_day = today()
	cultivation += 10
	qi += 4
	charms += 1
	seals += 1
	days += 1
	return {"ok": true, "message": "家人的坚持，化作你的守护。\n修为 +10  ·  灵气 +4  ·  守护符 +1  ·  灵印 +1"}

func realm() -> String:
	return "筑基中期" if cultivation >= 100 else "筑基初期"

func save_game() -> void:
	if not persist_enabled:
		return
	var file = FileAccess.open(save_path(), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"schema": 2, "cultivation": cultivation, "qi": qi, "charms": charms, "seals": seals, "days": days, "rewarded_days": rewarded_days, "confirmed_events": confirmed_events, "contribution": contribution, "boss_attempts": boss_attempts, "boss_day": boss_day, "last_reward_day": last_reward_day, "profile_created": profile_created, "avatar_id": avatar_id, "player_name": player_name, "longterm_enabled": longterm_enabled, "medication_required": medication_required, "daily_tasks": daily_tasks, "recovery_status": recovery_status, "trial_cleared": trial_cleared}))

func load_game() -> void:
	if not FileAccess.file_exists(save_path()):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path()))
	if not data is Dictionary:
		return
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

func reset_demo() -> void:
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
