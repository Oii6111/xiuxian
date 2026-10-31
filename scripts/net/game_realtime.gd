extends Node
## 标准 WebSocket：票据鉴权、心跳与重连快照。B 消费信号投影到自己的模块。
## 这里不写其他模块的 Store，不持久化会话，也不承接微信长轮询。
signal snapshot_received(snapshot: Dictionary)
signal snapshot_invalidated
signal connection_changed(state: String)
const Result = preload("res://scripts/kernel/result.gd")
const Contracts = preload("res://scripts/kernel/contracts.gd")
var _api: Node
var _peer: WebSocketPeer
var _enabled: bool = false
var _connecting: bool = false
var _connected: bool = false
var _epoch: int = 0
var _attempts: int = 0
var _retry_at: int = 0
var _connect_deadline: int = 0
var _last_revision: int = -1
var _awaiting_snapshot: bool = false

func _ready() -> void:
	set_process(false)

func connect_stream(api: Node) -> Dictionary:
	disconnect_stream()
	if not is_instance_valid(api) or not api.has_method("request_api"):
		return Result.failure("INVALID_BACKEND", "需要 GameApi 适配器")
	_api = api
	_api.session_changed.connect(_on_session_changed)
	_enabled = true
	set_process(true)
	return await _connect_once()

func disconnect_stream() -> void:
	_epoch += 1
	_enabled = false
	_connecting = false
	_connected = false
	_attempts = 0
	_last_revision = -1
	_awaiting_snapshot = false
	if is_instance_valid(_api) and _api.session_changed.is_connected(_on_session_changed):
		_api.session_changed.disconnect(_on_session_changed)
	_api = null
	if _peer != null:
		_peer.close()
	_peer = null
	set_process(false)
	snapshot_invalidated.emit()
	connection_changed.emit("disconnected")

func _on_session_changed() -> void:
	# 换账号或退出立即清空旧快照；新登录完成后由调用者显式重新连接。
	disconnect_stream()

func _connect_once() -> Dictionary:
	_connecting = true
	var epoch: int = _epoch
	connection_changed.emit("connecting")
	var result: Dictionary = await _api.request_api("/api/v2/realtime/ticket", HTTPClient.METHOD_POST)
	if epoch != _epoch or not _enabled:
		return Result.failure("SESSION_CHANGED", "连接请求已取消")
	_connecting = false
	if not result.ok:
		if result.code == "UNAUTHORIZED":
			disconnect_stream()
			connection_changed.emit("unauthorized")
		else:
			_schedule_retry()
		return result
	if not result.data.get("ticket") is String or result.data.ticket.is_empty():
		_schedule_retry()
		return Result.failure("INVALID_RESPONSE", "连接票据缺失")
	var address: String = _api.base_url.trim_suffix("/")
	if address.begins_with("https://"):
		address = "wss://" + address.trim_prefix("https://")
	elif address.begins_with("http://"):
		address = "ws://" + address.trim_prefix("http://")
	else:
		disconnect_stream()
		return Result.failure("INVALID_URL", "后端地址必须使用 HTTP 或 HTTPS")
	_peer = WebSocketPeer.new()
	_peer.inbound_buffer_size = 1048576
	_connect_deadline = Time.get_ticks_msec() + 10000
	var error: Error = _peer.connect_to_url(address + "/api/v2/realtime?ticket=" + result.data.ticket.uri_encode())
	if error != OK:
		_schedule_retry()
		return Result.failure("NETWORK_ERROR", "WebSocket 无法启动")
	return Result.success()

func _process(_delta: float) -> void:
	if not _enabled:
		return
	if _peer == null:
		if not _connecting and Time.get_ticks_msec() >= _retry_at:
			_connect_once()
		return
	_peer.poll()
	var state: int = _peer.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _connected:
			_connected = true
			_attempts = 0
			connection_changed.emit("connected")
		while _peer != null and _peer.get_available_packet_count() > 0:
			_receive(_peer.get_packet().get_string_from_utf8())
	elif state == WebSocketPeer.STATE_CLOSED:
		_schedule_retry()
	elif state == WebSocketPeer.STATE_CONNECTING and Time.get_ticks_msec() >= _connect_deadline:
		_schedule_retry()

func _receive(text: String) -> void:
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		_schedule_retry()
		return
	var message: Dictionary = parser.data
	if message.get("version") != 1:
		_schedule_retry()
		return
	if message.get("type") == "pong":
		return
	if not Contracts.matches(message.get("revision"), "integer") or message.revision < 0:
		_schedule_retry()
		return
	if message.get("type") == "snapshot":
		if not message.get("data") is Dictionary or message.data.get("revision") != message.revision:
			_schedule_retry()
			return
		if message.revision >= _last_revision:
			_last_revision = int(message.revision)
			_awaiting_snapshot = false
			snapshot_received.emit(message.data.duplicate(true))
	elif message.get("type") == "state_changed" and message.revision > _last_revision:
		# 事件仅作失效通知；包括版本跳跃在内，统一获取完整权威快照。
		if not _awaiting_snapshot:
			_awaiting_snapshot = true
			_peer.send_text(JSON.stringify({"type": "resync"}))
	else:
		if message.get("type") != "state_changed":
			_schedule_retry()

func _schedule_retry() -> void:
	if _peer != null:
		_peer.close()
	_peer = null
	_connected = false
	_awaiting_snapshot = false
	_attempts += 1
	_retry_at = Time.get_ticks_msec() + mini(30000, 1000 * int(pow(2, mini(_attempts - 1, 5))))
	connection_changed.emit("reconnecting")

func _exit_tree() -> void:
	disconnect_stream()
