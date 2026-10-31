extends Node
## 账号控制器：B 的登录/注册界面接 C 的统一账号。接口与原 account_client 相同，界面不变。
## 会话令牌只在内存中；注册成功后自动登录，并在 C 建立“本人”角色（昵称、形象）。
## 业务读写通过 GameKernel → 各模块 → GameApi；这里只管身份、实时连接与家族投影同步。
signal completed(action: String, response: Dictionary)
signal progress(message: String)
signal family_synced
const GameApi = preload("res://scripts/net/game_api.gd")
const GameRealtime = preload("res://scripts/net/game_realtime.gd")
const DEFAULT_URL = "http://127.0.0.1:8080"
var api: Node
var realtime: Node
var service_url = DEFAULT_URL:
	set(value):
		var normalized = value.strip_edges().trim_suffix("/")
		if normalized != service_url:
			service_url = normalized
			reset_session()
var generation = 0
var account: Dictionary = {}
var busy = false
var allow_autostart = true
var started_server_pid = -1
var tried_start = false
var token: String:
	get:
		return api.bearer_token if is_instance_valid(api) else ""

func _ready() -> void:
	for name in ["XIUXIAN_BACKEND_URL", "XIUXIAN_ACCOUNT_URL"]:
		if OS.has_environment(name):
			service_url = OS.get_environment(name)
			break
	if OS.has_feature("web"):
		# 网页由游戏服务直接托管：同源访问，无需配置地址。
		service_url = str(JavaScriptBridge.eval("location.origin"))
	api = GameApi.new()
	api.name = "GameApi"
	add_child(api)
	api.base_url = service_url
	realtime = GameRealtime.new()
	realtime.name = "GameRealtime"
	add_child(realtime)

func kernel() -> Node:
	return get_tree().root.get_node_or_null("GameKernel") if is_inside_tree() else null

func is_authenticated() -> bool:
	return not api.bearer_token.is_empty() and not account.is_empty() and api.base_url == service_url

static func endpoint_allowed(url: String) -> bool:
	if OS.has_feature("web") and url == str(JavaScriptBridge.eval("location.origin")):
		return true
	var pattern = RegEx.new()
	pattern.compile("^(http://(127\\.0\\.0\\.1|localhost|\\[::1\\])|https://[a-zA-Z0-9.-]+)(:[0-9]{1,5})?$")
	return pattern.search(url) != null

func authenticate(action: String, payload: Dictionary) -> void:
	if busy or action not in ["register", "login"]:
		return
	if not endpoint_allowed(service_url):
		completed.emit(action, {"ok": false, "message": "请使用本机 HTTP 或远程 HTTPS 游戏服务根地址。"})
		return
	_begin()
	var own = generation
	tried_start = false
	progress.emit("正在连接游戏服务…")
	var username = str(payload.get("username", ""))
	var password = str(payload.get("password", ""))
	if action == "register":
		progress.emit("正在注册账号…")
		var registered = await _with_autostart(func(): return await api.register_account(username, password))
		if own != generation:
			return
		if not registered.ok:
			_finish(action, _failure(registered))
			return
	progress.emit("正在登录…")
	var logged_in = await _with_autostart(func(): return await api.login(username, password))
	if own != generation:
		return
	if not logged_in.ok:
		_finish(action, _failure(logged_in))
		return
	var identity = {"id": str(logged_in.data.account_id), "username": str(logged_in.data.username), "display_name": str(payload.get("display_name", "")), "avatar": "female" if payload.get("avatar", "male") == "female" else "male"}
	var core = kernel()
	if core != null:
		core.configure_backend(api)
	var listed = await core.dispatch("growth.list", {}) if core != null else {"ok": false, "code": "NOT_READY", "message": "内核未启动"}
	if own != generation:
		return
	if not listed.ok:
		_finish(action, _failure(listed))
		return
	var own_role = {}
	for item in listed.data.cultivators:
		if item.get("role") == "self":
			own_role = item
	if own_role.is_empty():
		# 本人角色的创建键与账号绑定：注册超时后重试登录也不会建出第二个本人。
		var display = identity.display_name if not identity.display_name.is_empty() else identity.username.left(10)
		var created = await core.dispatch("growth.create_member", {"role": "self", "name": display.left(10), "profile": {"title": display.left(10), "avatar": identity.avatar}, "request_id": "self-" + identity.id})
		if own != generation:
			return
		if not created.ok:
			_finish(action, _failure(created))
			return
		own_role = created.data
	identity.display_name = str(own_role.get("name", identity.username))
	identity.avatar = str(own_role.get("profile", {}).get("avatar", "male"))
	account = identity
	realtime.connect_stream(api)
	_finish(action, {"ok": true, "account": account.duplicate(true)})

func claim_legacy(fingerprint: String) -> void:
	if busy or not is_authenticated():
		return
	_begin(false)
	var own = generation
	progress.emit("正在保留旧进度…")
	var result = await api.request_api("/api/v2/legacy/claim", HTTPClient.METHOD_POST, {"fingerprint": fingerprint})
	if own != generation:
		return
	_finish("claim-legacy", {"ok": true} if result.ok else _failure(result))

func logout() -> void:
	if busy:
		return
	_begin(false)
	var own = generation
	progress.emit("正在退出账号…")
	await api.logout()
	if own != generation:
		return
	_clear()
	_finish("logout", {"ok": true})

## 读取 C 的全量角色快照，按 cultivator_id 对应到本地家族角色并刷新钱包、装备、初始投影。
func sync_family(roster: RefCounted) -> Dictionary:
	var core = kernel()
	if core == null or not is_authenticated():
		return {"ok": false, "code": "UNAUTHORIZED", "message": "尚未登录游戏服务"}
	var own = generation
	var listed = await core.dispatch("growth.list", {})
	if own != generation:
		return {"ok": false, "code": "SESSION_CHANGED", "message": "账号已切换"}
	if not listed.ok:
		return listed
	var result = await roster.apply_remote(listed.data.cultivators, core)
	if own == generation and result.ok:
		family_synced.emit()
	return result

func reset_session() -> void:
	generation += 1
	_clear()
	if is_instance_valid(api):
		api.base_url = service_url
	if busy:
		_finish(account.get("pending_action", "login"), {"ok": false, "code": "SESSION_CHANGED", "message": "游戏服务已切换，请重新登录。"})
	busy = false

func _begin(clear_identity: bool = true) -> void:
	generation += 1
	busy = true
	if clear_identity:
		_clear()

func _clear() -> void:
	account.clear()
	if is_instance_valid(realtime):
		realtime.disconnect_stream()
	if is_instance_valid(api):
		api.bearer_token = ""

func _finish(action: String, response: Dictionary) -> void:
	busy = false
	completed.emit(action, response)

func _with_autostart(call: Callable) -> Dictionary:
	var result: Dictionary = await call.call()
	if result.code != "NETWORK_ERROR" or tried_start or not allow_autostart or not service_url.begins_with("http://127.0.0.1:"):
		return result
	tried_start = true
	if not _start_local_server():
		return result
	progress.emit("正在准备本机游戏服务…")
	var deadline = Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.5).timeout
		result = await call.call()
		if result.code != "NETWORK_ERROR":
			return result
	return result

## 本机试玩：首次登录时启动 C 的 Node 服务（与 npm run dev 相同入口）。
func _start_local_server() -> bool:
	var server = ProjectSettings.globalize_path("res://server")
	var cli = server.path_join("node_modules/tsx/dist/cli.mjs")
	if not FileAccess.file_exists(cli):
		return false
	var node = OS.get_environment("XIUXIAN_NODE") if OS.has_environment("XIUXIAN_NODE") else "node"
	var port = service_url.get_slice(":", 2)
	OS.set_environment("PORT", port)
	started_server_pid = OS.create_process(node, PackedStringArray([cli, server.path_join("src/main.ts")]), false)
	return started_server_pid > 0

static func _failure(result: Dictionary) -> Dictionary:
	var messages = {
		"NETWORK_ERROR": "游戏服务未连接，请在 server 目录运行 npm run dev 后重试。注册超时后也可以尝试登录。",
		"INVALID_CREDENTIALS": "用户名或密码错误。",
		"USERNAME_TAKEN": "用户名已存在，请直接登录或换一个用户名。",
		"RATE_LIMITED": "尝试次数过多，请稍后再试。",
	}
	return {"ok": false, "code": str(result.get("code", "")), "message": messages.get(result.get("code", ""), str(result.get("message", "操作失败，请重试。")))}

func _exit_tree() -> void:
	generation += 1
	if started_server_pid > 0:
		OS.kill(started_server_pid)
		started_server_pid = -1
