extends SceneTree
## 使用 Node 工具启动的回环服务和内存数据库；不读取玩家存档或真实凭证。
const Api = preload("res://scripts/net/game_api.gd")
const Realtime = preload("res://scripts/net/game_realtime.gd")
const Runtime = preload("res://scripts/kernel/runtime.gd")
const Memory = preload("res://scripts/kernel/adapters/memory_persistence.gd")
var _assertions: int = 0
var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func expect(condition: bool, description: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(description)
		printerr("FAIL: ", description)

func _wait_for(condition: Callable, description: String) -> void:
	var deadline: int = Time.get_ticks_msec() + 5000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.01).timeout
	expect(condition.call(), description)

func _capture_snapshot(api: Node, responses: Array) -> void:
	responses.append(await api.fetch_snapshot())

func _run() -> void:
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/kernel/contracts.json"))
	var memory := Memory.new()
	var runtime := Runtime.new()
	expect(runtime.start(contract, memory).ok, "runtime starts for migration setup")
	expect(runtime.save().ok, "save initial module sections")
	var document: Dictionary = memory.read_document().data.document
	document.sections.season = {"version": 1, "state": {"revision": 7}}
	memory.write_document(document)
	runtime.shutdown()
	expect(runtime.start(contract, memory).ok, "v1 season save migrates")
	expect(runtime.snapshot("season").revision == 7 and runtime.snapshot("season").current.is_empty(), "season migration preserves revision and adds defaults")
	var unavailable: Dictionary = await runtime.dispatch("season.refresh", {"cultivator_id": "sample"})
	expect(unavailable.code == "BACKEND_UNAVAILABLE", "offline season does not fake server data")
	runtime.shutdown()
	var api := Api.new()
	root.add_child(api)
	api.base_url = OS.get_environment("XIUXIAN_TEST_BASE_URL")
	expect(not api.base_url.is_empty(), "local test server configured")
	var username: String = "godot_" + str(Time.get_ticks_usec())
	var registered: Dictionary = await api.register_account(username, "godot-local-test-password")
	expect(registered.ok, "real HTTP registration")
	var login: Dictionary = await api.login(username, "godot-local-test-password")
	expect(login.ok and not api.bearer_token.is_empty(), "real HTTP login")
	if not login.ok:
		api.queue_free()
		_finish()
		return
	var payload: Dictionary = {"name": "联调角色", "element": "water"}
	var created: Dictionary = await api.invoke("growth.create", payload, "godot-create")
	expect(created.ok, "real HTTP role creation")
	if not created.ok:
		api.queue_free()
		_finish()
		return
	var repeated: Dictionary = await api.invoke("growth.create", payload, "godot-create")
	expect(repeated == created, "HTTP retry reuses idempotency header")
	var kernel: Node = root.get_node("GameKernel")
	expect(kernel.configure_backend(api).ok, "inject backend through kernel facade")
	var season: Dictionary = await kernel.dispatch("season.refresh", {"cultivator_id": created.data.cultivator_id})
	expect(season.ok and season.data.current.id == "integration-2026-h2", "season module consumes real server calendar: " + JSON.stringify(season))
	expect(kernel.snapshot("season").cultivator_id == created.data.cultivator_id, "season projects only its own state")
	var snapshots: Array = []
	var invalidated: Array = []
	var realtime := Realtime.new()
	root.add_child(realtime)
	realtime.snapshot_received.connect(func(snapshot: Dictionary) -> void: snapshots.append(snapshot))
	realtime.snapshot_invalidated.connect(func() -> void: invalidated.append(true))
	var connected: Dictionary = await realtime.connect_stream(api)
	expect(connected.ok, "Godot WebSocket starts with one-time ticket")
	await _wait_for(func() -> bool: return not snapshots.is_empty(), "initial authoritative WebSocket snapshot")
	var second: Dictionary = await api.invoke("growth.create", {"name": "第二位老人", "element": "wood"}, "godot-second")
	expect(second.ok, "second role created")
	await _wait_for(func() -> bool: return not snapshots.is_empty() and snapshots.back().cultivators.size() == 2, "change notification resyncs a complete snapshot")
	realtime.disconnect_stream()
	snapshots.clear()
	var third: Dictionary = await api.invoke("growth.create", {"name": "重连测试", "element": "metal"}, "godot-third")
	expect(third.ok, "mutation while disconnected")
	await realtime.connect_stream(api)
	await _wait_for(func() -> bool: return not snapshots.is_empty() and snapshots.back().cultivators.size() == 3, "reconnect restores all missed state")
	var responses: Array = []
	_capture_snapshot(api, responses)
	api.bearer_token = "different-account-session"
	await _wait_for(func() -> bool: return not responses.is_empty(), "in-flight response completes after session switch")
	expect(responses[0].code == "SESSION_CHANGED", "old account HTTP response is discarded")
	expect(not invalidated.is_empty() and not realtime._enabled, "session switch invalidates realtime state")
	expect(kernel.snapshot("season").cultivator_id.is_empty(), "session switch clears old account season projection")
	api.bearer_token = login.data.token
	var snapshot: Dictionary = await api.fetch_snapshot()
	expect(snapshot.ok and snapshot.data.cultivators.size() == 3, "HTTP full snapshot fallback")
	var private_call: Dictionary = await api.request_api("/internal/v1/task-results", HTTPClient.METHOD_POST)
	expect(private_call.code == "INVALID_PATH", "Godot adapter cannot call health internal APIs")
	expect((await api.logout()).ok, "logout succeeds")
	expect(api.bearer_token.is_empty(), "client removes session token on logout")
	expect((await api.fetch_snapshot()).code == "UNAUTHORIZED", "logged-out snapshot rejected")
	kernel.configure_backend(null)
	realtime.queue_free()
	api.queue_free()
	await process_frame
	_finish()

func _finish() -> void:
	print("BACKEND_INTEGRATION_TEST: %d assertions; %d failures" % [_assertions, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
