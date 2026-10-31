extends Node
## Read-only task projection from C (quests.family_today). Never writes balances or awards currency.
signal changed
var game: Node
var members: Dictionary = {}
var revision = -1
var business_date = ""
var connected = false
var busy = false
var timer = 0.0
var generation = 0
var owner_scope = ""
var last_sync = ""
var poll_seconds = 15.0

func scope() -> String:
	return str(game.family.account.id) + ":" + str(game.account_api.generation)

func configured() -> bool:
	return game.account_ready and game.account_api.is_authenticated() and game.family.is_remote()

func manages(id: String) -> bool:
	return configured() and owner_scope == scope() and id != "self" and game.family.state_for(id) != null

func status_text() -> String:
	if connected:
		return "微信记录 · 最近同步 " + last_sync
	return "微信记录等待同步" + (" · 上次 " + last_sync if not last_sync.is_empty() else "")

func clear_state() -> void:
	generation += 1
	members.clear()
	revision = -1
	business_date = ""
	connected = false
	busy = false
	last_sync = ""
	timer = 0.0
	owner_scope = ""

func _process(delta: float) -> void:
	if not configured():
		if not owner_scope.is_empty():
			clear_state()
		return
	if owner_scope != scope():
		clear_state()
		owner_scope = scope()
	timer -= delta
	if timer <= 0 and not busy:
		refresh_now()

func refresh_now() -> void:
	if not configured() or busy:
		return
	if owner_scope != scope():
		clear_state()
		owner_scope = scope()
	timer = poll_seconds
	generation += 1
	var current = generation
	busy = true
	var result = await GameKernel.dispatch("quests.family_today", {"date": game.state.today()})
	if current != generation or owner_scope != scope():
		return
	busy = false
	if not result.ok:
		connected = false
		changed.emit()
		return
	var had_snapshot = revision >= 0
	var completed_labels: Array[String] = []
	var new_labels: Array[String] = []
	var next: Dictionary = {}
	for person in result.data.members:
		var id = game.family.id_for_cultivator(str(person.cultivator_id))
		if id.is_empty() or id == "self":
			continue
		var tasks: Array = []
		var old = {}
		for task in members.get(id, []):
			old[task.id] = task.status
		var relation = str(game.family.state_for(id).family_identity.get("relation", "家人"))
		for task in person.tasks:
			var status = "confirmed" if task.status == "settled" else ("cancelled" if task.status == "rejected" else "unrecorded")
			tasks.append({"id": str(task.task_instance_id), "title": str(task.title).left(64), "status": status, "completion_method": str(task.get("completion_method", "")).left(40)})
			if had_snapshot and old.get(task.task_instance_id, "") != "confirmed" and status == "confirmed":
				completed_labels.append(relation)
			elif had_snapshot and not old.has(task.task_instance_id):
				new_labels.append(relation)
		next[id] = tasks
	members = next
	revision = int(result.data.revision)
	business_date = str(result.data.business_date)
	connected = true
	last_sync = Time.get_time_string_from_system()
	changed.emit()
	if is_instance_valid(game.ui):
		game.ui.refresh()
	if not completed_labels.is_empty():
		var text = "、".join(completed_labels) + "已在微信反馈完成今天的安排啦。"
		game.companion_actor.say("收到微信完成反馈啦", "celebrate")
		game.companion_api.append_message("assistant", text, [{"id": "record", "label": "查看微信记录"}], "wechat_sync")
		game.companion_api.reply_received.emit({"reply": text, "animation": "celebrate"})
		game.account_api.sync_family(game.family)
	elif not new_labels.is_empty():
		var text = "、".join(new_labels) + "有了新的已确认安排，可以看看今天的任务。"
		game.companion_actor.say("收到新的微信安排啦")
		game.companion_api.append_message("assistant", text, [{"id": "record", "label": "查看微信记录"}], "wechat_sync")
		game.companion_api.reply_received.emit({"reply": text, "animation": "talk"})

func overlay(context: Dictionary) -> void:
	for person in context.characters:
		if manages(str(person.member_id)):
			person.tasks = members.get(person.member_id, []).duplicate(true)
			person.task_source = "wechat"
			person.sync_status = status_text()
			person.reward_recorded = false
			person.sync_ready = connected
			if not business_date.is_empty():
				context.as_of_date = business_date

func _exit_tree() -> void:
	clear_state()
