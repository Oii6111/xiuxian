extends SceneTree
const Runtime = preload("res://scripts/kernel/runtime.gd")
const Memory = preload("res://scripts/kernel/adapters/memory_persistence.gd")
const Binding = preload("res://scripts/combat/service_binding.gd")
const Result = preload("res://scripts/kernel/result.gd")
const Demo = preload("res://scripts/combat/demo_kernel.gd")
var assertions: int = 0
var failures: Array = []

class Api:
	extends Node
	var contract: Dictionary
	var start_calls: int = 0
	var finish_calls: int = 0
	var fail_finish: bool = true
	var seen: Array = []
	func invoke(command: String, payload: Dictionary) -> Dictionary:
		seen.append({"command": command, "payload": payload.duplicate(true)})
		var fields: Dictionary = {}
		for module in contract.modules:
			if module.commands.has(command): fields = module.commands[command]
		var checked: Dictionary = preload("res://scripts/kernel/contracts.gd").validate(payload, fields)
		if not checked.ok:
			printerr("BAD DTO ", payload, " schema ", fields, " reason ", checked)
			return checked
		match command:
			"combat.start":
				start_calls += 1
				return {"ok": true, "code": "OK", "message": "", "data": {"session_id": "server-issued-17", "player": _stats(), "enemy": _stats()}}
			"combat.finish":
				finish_calls += 1
				return {"ok": not fail_finish, "code": "NETWORK_ERROR" if fail_finish else "OK", "data": {}, "message": ""}
			"lifecycle.request_change":
				return {"ok": true, "code": "OK", "message": "", "data": {"confirmation_token": "family-ticket"}}
			"lifecycle.confirm_change":
				return {"ok": true, "code": "OK", "message": "", "data": {"state": "tribulation", "complete": true, "version": 2}}
			"lifecycle.update_stage":
				return {"ok": true, "code": "OK", "message": "", "data": {"version": 3}}
		return {"ok": false, "code": "UNKNOWN_COMMAND", "data": {}, "message": ""}
	func _stats() -> Dictionary:
		return {"hp": 100, "attack": 20, "defense": 4, "crit_rate": 0.0, "element": "wood"}

func _init() -> void:
	call_deferred("_run")

func expect(value: bool, label: String) -> void:
	assertions += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)

func _run() -> void:
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/kernel/contracts.json"))
	var examples: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/combat/integration_examples.json"))
	var validator = preload("res://scripts/kernel/contracts.gd")
	for name in ["combat.start", "combat.finish", "lifecycle.request_change", "lifecycle.confirm_change", "lifecycle.update_stage"]:
		var fields: Dictionary = {}
		for descriptor in contract.modules:
			if descriptor.commands.has(name):
				fields = descriptor.commands[name]
		expect(validator.validate(examples[name].request, fields).ok, "example request validates: " + name)
		for kind in ["success", "failure"]:
			expect(preload("res://scripts/kernel/command_router.gd").valid_result(examples[name][kind]), "example Result validates: " + name + ":" + kind)
	var runtime := Runtime.new()
	var memory := Memory.new()
	runtime.start(contract, memory)
	var combat: RefCounted = runtime._modules.combat
	var lifecycle: RefCounted = runtime._modules.lifecycle
	lifecycle.apply_authoritative("c1", "cultivating", 1)
	var api := Api.new()
	api.contract = contract
	root.add_child(api)
	var binding := Binding.new()
	binding.configure(combat, lifecycle, api, func(_cid: String, _eid: String) -> Dictionary: return Result.success({"player": api._stats(), "enemy": api._stats()}))
	var started: Dictionary = await runtime.dispatch("combat.start", {"cultivator_id": "c1", "encounter_id": "trial_wood"})
	expect(started.ok and started.data.session_id == "server-issued-17", "server signs the session identifier")
	var report: Dictionary = {"session_id": started.data.session_id, "won": true, "duration_seconds": 35.0}
	var failed: Dictionary = await runtime.dispatch("combat.finish", report)
	expect(not failed.ok and not combat.snapshot().sessions[report.session_id].finished, "failed authority finish leaves projection unfinished")
	var altered: Dictionary = report.duplicate(true)
	altered.won = false
	expect((await runtime.dispatch("combat.finish", altered)).code == "RESULT_CONFLICT", "retry cannot change the already submitted outcome")
	api.fail_finish = false
	var success: Dictionary = await runtime.dispatch("combat.finish", report)
	var replay: Dictionary = await runtime.dispatch("combat.finish", report)
	expect(success.ok and replay.data.replayed and api.finish_calls == 2, "one retry and no extra send after completion")
	expect(not combat.snapshot().has("spirit_stones"), "combat has no resource balances")
	var request: Dictionary = await runtime.dispatch("lifecycle.request_change", {"cultivator_id": "c1", "target_state": "tribulation"})
	expect(request.ok, "binding fields: " + JSON.stringify(request))
	if not request.ok:
		printerr(JSON.stringify(api.seen))
		quit(1)
		return
	var confirmed: Dictionary = await runtime.dispatch("lifecycle.confirm_change", {"cultivator_id": "c1", "confirmation_token": request.data.confirmation_token, "request_id": "r1"})
	expect(confirmed.ok and not lifecycle.allows_combat("c1"), "authority result blocks battle on tribulation")
	var stage: Dictionary = await runtime.dispatch("lifecycle.update_stage", {"cultivator_id": "c1", "stage_id": "cardio.admission", "confirmation_token": "stage-ticket"})
	expect(stage.ok, "stage adapter matches declared fields")
	expect(lifecycle.apply_authoritative("c1", "cultivating", 3).code == "STALE_VERSION", "same-version conflicting snapshot rejected")
	expect(runtime.save().ok, "projections save")
	runtime.shutdown()
	expect(runtime.start(contract, memory).ok and runtime.snapshot("combat").sessions["server-issued-17"].finished, "restart restores completed session projection")
	runtime.shutdown()
	api.queue_free()
	await process_frame
	var demo: Node = Demo.new()
	root.add_child(demo)
	demo.setup("elder")
	var life: RefCounted = demo.runtime._modules.lifecycle
	life.apply_authoritative("elder", "seclusion", 9)
	var ticket: Dictionary = await demo.dispatch("lifecycle.request_change", {"cultivator_id": "elder", "target_state": "ascended"})
	var click: Dictionary = {"cultivator_id": "elder", "confirmation_token": ticket.data.confirmation_token, "request_id": "same-click"}
	var first: Dictionary = await demo.dispatch("lifecycle.confirm_change", click)
	var duplicate: Dictionary = await demo.dispatch("lifecycle.confirm_change", click)
	expect(not first.data.complete and not duplicate.data.complete and life.snapshot().cultivators.elder.state == "seclusion", "repeated first confirmation cannot substitute for the second")
	click.request_id = "second-click"
	expect((await demo.dispatch("lifecycle.confirm_change", click)).data.complete, "second distinct confirmation completes")
	expect(not JSON.stringify(life.snapshot()).contains(ticket.data.confirmation_token), "token stays out of persisted projection")
	demo.queue_free()
	await process_frame
	print("A_SERVICES_TEST: %d assertions; %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)