extends Node
## Read-only task projection. This module never writes GameState or awards currency.
signal changed
const Http = preload("res://scripts/companion_client.gd")
var game: Node
var endpoint = ""
var read_token = ""
var request: HTTPRequest
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

func _ready() -> void:
	endpoint = OS.get_environment("XIUXIAN_COMPANION_TASK_URL").strip_edges()
	read_token = OS.get_environment("XIUXIAN_COMPANION_TASK_READ_TOKEN").strip_edges()
	if "--wechat-link-demo" in OS.get_cmdline_user_args():
		poll_seconds = 1.0

func scope() -> String:
	return str(game.family.account.id) + ":" + str(game.account_api.generation) + ":" + endpoint + ":" + read_token.sha256_text()

func configured() -> bool:
	return not endpoint.is_empty() and not read_token.is_empty() and Http.endpoint_allowed(endpoint)

func manages(id: String) -> bool:
	if not configured() or not game.account_ready:
		return false
	if not owner_scope.is_empty() and owner_scope != scope():
		return false
	return members.has(id) or ("--wechat-link-demo" in OS.get_cmdline_user_args() and id == "wechat-demo-father")

func status_text() -> String:
	var prefix = "本地文字联调" if "--wechat-link-demo" in OS.get_cmdline_user_args() else "微信记录"
	if connected:
		return prefix + " · 最近同步 " + last_sync
	return prefix + "等待同步" + (" · 上次 " + last_sync if not last_sync.is_empty() else "")

func clear_state() -> void:
	generation += 1
	if is_instance_valid(request):
		request.cancel_request()
		request.queue_free()
	request = null
	members.clear()
	revision = -1
	business_date = ""
	connected = false
	busy = false
	last_sync = ""
	timer = 0.0
	owner_scope = ""

func _process(delta: float) -> void:
	if not game.account_ready:
		if not owner_scope.is_empty():
			clear_state()
		return
	if not configured():
		return
	if owner_scope != scope():
		clear_state()
		owner_scope = scope()
	timer -= delta
	if timer <= 0 and not busy:
		refresh_now()

func refresh_now() -> void:
	if not configured() or not game.account_ready or busy:
		return
	if owner_scope != scope():
		clear_state()
		owner_scope = scope()
	timer = poll_seconds
	generation += 1
	var current = generation
	if is_instance_valid(request):
		request.queue_free()
	request = HTTPRequest.new()
	request.timeout = 5
	request.body_size_limit = 65536
	request.max_redirects = 0
	request.use_threads = true
	request.request_completed.connect(on_response.bind(current, owner_scope))
	add_child(request)
	busy = true
	var error = request.request(endpoint, PackedStringArray(["Accept: application/json", "X-Companion-Read-Token: " + read_token]))
	if error != OK:
		busy = false
		connected = false
		changed.emit()
		if is_instance_valid(game.ui):
			game.ui.refresh()

func clean_snapshot(value: Variant) -> Dictionary:
	if not value is Dictionary or value.get("schema_version") != 1 or value.get("account_id", "") != str(game.family.account.id) or not value.get("members") is Array:
		return {}
	if value.get("mode", "") == "local_demo" and "--wechat-link-demo" not in OS.get_cmdline_user_args():
		return {}
	if value.get("mode", "") not in ["live", "local_demo"] or int(value.get("revision", -1)) < 0:
		return {}
	if value.members.size() > 3 or not value.get("revision") is float and not value.get("revision") is int:
		return {}
	var date = str(value.get("business_date", ""))
	var pattern = RegEx.new()
	pattern.compile("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
	if pattern.search(date) == null:
		return {}
	var result: Dictionary = {}
	for person in value.members:
		if not person is Dictionary or not person.get("tasks") is Array or person.tasks.size() > 100:
			return {}
		var id = str(person.get("game_member_id", ""))
		var state = game.family.state_for(id)
		if state == null or (id != "self" and state.family_identity.get("consent", false) != true):
			continue
		var tasks: Array = []
		var ids = {}
		for item in person.tasks:
			if not item is Dictionary or not item.get("title") is String or item.get("status", "") not in ["pending", "completed", "cancelled"] or item.get("business_date", "") != date:
				return {}
			var task_id = str(item.get("task_id", ""))
			if task_id.is_empty() or ids.has(task_id):
				return {}
			ids[task_id] = true
			tasks.append({"id": task_id, "title": str(item.title).left(64), "status": {"pending": "unrecorded", "completed": "confirmed", "cancelled": "cancelled"}[item.status], "completion_method": str(item.get("completion_method", "")).left(40)})
		result[id] = tasks
	return {"members": result, "revision": int(value.revision), "business_date": date}

func on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, own_generation: int, own_scope: String) -> void:
	if own_generation != generation or own_scope != scope() or not game.account_ready:
		return
	busy = false
	var data: Dictionary = {}
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		data = clean_snapshot(JSON.parse_string(body.get_string_from_utf8()))
	if data.is_empty():
		connected = false
		changed.emit()
		if is_instance_valid(game.ui):
			game.ui.refresh()
		return
	if int(data.revision) < revision and data.business_date == business_date:
		return
	var had_snapshot = revision >= 0
	var completed_labels: Array[String] = []
	var new_labels: Array[String] = []
	for id in data.members:
		var old = {}
		for task in members.get(id, []):
			old[task.id] = task.status
		for task in data.members[id]:
			if had_snapshot and old.get(task.id, "") != "confirmed" and task.status == "confirmed":
				var state = game.family.state_for(id)
				completed_labels.append(str(state.family_identity.get("relation", "家人")))
			elif had_snapshot and not old.has(task.id) and task.status == "unrecorded":
				var state = game.family.state_for(id)
				new_labels.append(str(state.family_identity.get("relation", "家人")))
	members = data.members
	revision = data.revision
	business_date = data.business_date
	connected = true
	last_sync = Time.get_time_string_from_system()
	changed.emit()
	if is_instance_valid(game.ui):
		game.ui.refresh()
	if not completed_labels.is_empty():
		var text = "、".join(completed_labels) + "已在微信反馈完成今天的安排啦。"
		if is_instance_valid(game.companion_actor):
			game.companion_actor.say("收到微信完成反馈啦", "celebrate")
		game.companion_api.append_message("assistant", text, [{"id": "record", "label": "查看微信记录"}], "wechat_sync")
		game.companion_api.reply_received.emit({"reply": text, "animation": "celebrate"})
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
