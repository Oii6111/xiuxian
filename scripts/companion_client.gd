extends Node
## Optional HTTP adapter. Replies and navigation hints cannot mutate game progress.
signal reply_received(payload: Dictionary)
signal busy_changed(value: bool)
const Context = preload("res://scripts/companion_context.gd")
var game: Node
var endpoint_url = ""
var request: HTTPRequest
var history: Array = []
var busy = false
var conversation_id = ""
var pending_request_id = ""
var pending_scope = ""
var pending_endpoint_url = ""
var pending_account_generation = 0
var trusted_auth_origin = ""
var pending_message = ""
var pending_context: Dictionary = {}
var generation = 0
var online = false

func _ready() -> void:
	endpoint_url = OS.get_environment("XIUXIAN_COMPANION_API_URL").strip_edges()
	trusted_auth_origin = OS.get_environment("XIUXIAN_COMPANION_AUTH_ORIGIN").strip_edges().trim_suffix("/")
	if endpoint_url.is_empty():
		# 默认直接接灵宠聊天服务（deepseek-flash）。网页走同源，桌面走本机 8031。
		if OS.has_feature("web"):
			var origin = str(JavaScriptBridge.eval("location.origin")).strip_edges().trim_suffix("/")
			if not origin.is_empty():
				endpoint_url = origin + "/api/v1/companion/chat"
				trusted_auth_origin = origin
		else:
			endpoint_url = "http://127.0.0.1:8031/api/v1/companion/chat"
			trusted_auth_origin = "http://127.0.0.1:8031"
	create_request()
	reset_session()

func create_request() -> void:
	var timeout = request.timeout if is_instance_valid(request) else 15.0
	if is_instance_valid(request):
		request.cancel_request()
		request.queue_free()
	request = HTTPRequest.new()
	request.timeout = timeout
	request.body_size_limit = 65536
	request.max_redirects = 0
	request.use_threads = true
	request.request_completed.connect(on_response.bind(generation))
	add_child(request)

static func endpoint_allowed(url: String) -> bool:
	if "\n" in url or "\r" in url or "@" in url or "#" in url:
		return false
	if url.begins_with("https://"):
		return not url.get_slice("/", 2).is_empty()
	var local = RegEx.new()
	local.compile("^http://(127\\.0\\.0\\.1|localhost|\\[::1\\])(:[0-9]{1,5})?(/[^\\s]*)?$")
	return local.search(url) != null

static func origin(url: String) -> String:
	if not endpoint_allowed(url):
		return ""
	return url.get_slice("/", 0) + "//" + url.get_slice("/", 2)

func may_send_account_token() -> bool:
	# Sending a login token to a separately configured service requires an explicit origin.
	return not trusted_auth_origin.is_empty() and origin(endpoint_url) == trusted_auth_origin

func scope() -> String:
	return str(game.family.account.get("id", "")) + ":" + game.family.active_id

func reset_session() -> void:
	cancel_pending()
	history.clear()
	conversation_id = Crypto.new().generate_random_bytes(16).hex_encode()
	online = false

func set_busy(value: bool) -> void:
	busy = value
	busy_changed.emit(value)

func append_message(role: String, text: String, actions: Array = [], source: String = "local_guide") -> void:
	history.append({"role": role, "text": text, "actions": actions.duplicate(true), "source": source, "scope": scope()})
	while history.size() > 40:
		history.pop_front()

func send_message(message: String) -> bool:
	message = message.strip_edges().left(600)
	if busy or message.is_empty() or not game.account_ready:
		return false
	pending_scope = scope()
	pending_endpoint_url = endpoint_url
	pending_account_generation = game.account_api.generation
	pending_context = Context.snapshot(game)
	pending_message = message
	pending_request_id = Crypto.new().generate_random_bytes(16).hex_encode()
	append_message("user", message)
	set_busy(true)
	var own_generation = generation
	if endpoint_url.is_empty() or not endpoint_allowed(endpoint_url):
		deliver_local.call_deferred(own_generation, false)
		return true
	var payload = {"schema_version": 1, "request_id": pending_request_id, "conversation_id": conversation_id, "channel": "godot", "account_id": str(game.family.account.get("id", "")), "companion": game.family.companion.duplicate(true), "message": message, "context": pending_context}
	var headers = PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	if may_send_account_token() and not game.account_api.token.is_empty():
		headers.append("Authorization: Bearer " + game.account_api.token)
	create_request()
	var error = request.request(endpoint_url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		deliver_local.call_deferred(own_generation, true)
	return true

func deliver_local(own_generation: int, connection_failed: bool) -> void:
	if own_generation != generation or not busy:
		return
	if pending_scope != scope() or not game.account_ready or pending_endpoint_url != endpoint_url or pending_account_generation != game.account_api.generation:
		cancel_pending()
		return
	var result = Context.local_reply(pending_message, Context.snapshot(game), game.family.companion)
	if connection_failed:
		result.reply = "暂时没连上聊天伙伴，我先按游戏里的记录帮你看看。\n\n" + result.reply
	online = false
	deliver(result)

static func clean_response(value: Variant, request_id: String, session_id: String) -> Dictionary:
	if not value is Dictionary or value.get("request_id", "") != request_id or value.get("conversation_id", "") != session_id or not value.get("reply") is String:
		return {}
	var text = str(value.reply).strip_edges()
	if text.is_empty() or text.length() > 2000:
		return {}
	var actions: Array = []
	if value.get("actions", []) is Array:
		for item in value.get("actions", []):
			if item is Dictionary and item.get("id", "") in Context.ACTIONS and item.get("label") is String:
				actions.append({"id": str(item.id), "label": str(item.label).strip_edges().left(16)})
			if actions.size() >= 3:
				break
	var animation = str(value.get("animation", "talk"))
	return {"reply": text, "actions": actions, "animation": animation if animation in ["idle", "talk", "celebrate"] else "talk", "source": "chat_service"}

func on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, own_generation: int) -> void:
	if not busy or own_generation != generation:
		return
	if pending_scope != scope() or not game.account_ready or pending_endpoint_url != endpoint_url or pending_account_generation != game.account_api.generation:
		cancel_pending()
		return
	var response: Dictionary = {}
	if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300:
		response = clean_response(JSON.parse_string(body.get_string_from_utf8()), pending_request_id, conversation_id)
	if response.is_empty():
		deliver_local(generation, true)
		return
	online = true
	deliver(response)

func deliver(payload: Dictionary) -> void:
	append_message("assistant", payload.reply, payload.get("actions", []), payload.get("source", "local_guide"))
	set_busy(false)
	reply_received.emit(payload)

func cancel_pending() -> void:
	generation += 1
	if is_instance_valid(request):
		request.cancel_request()
	pending_request_id = ""
	pending_context.clear()
	pending_message = ""
	if busy:
		set_busy(false)

func _exit_tree() -> void:
	cancel_pending()
