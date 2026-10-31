extends SceneTree
const Simulation = preload("res://scripts/systems/combat/encounter_sim.gd")
const Fight = preload("res://scripts/systems/combat/combat_fight.gd")
const Hub = preload("res://scenes/combat/demo_hub.tscn")
const Level = preload("res://scenes/combat/level.tscn")
const Runtime = preload("res://scripts/kernel/runtime.gd")
const Memory = preload("res://scripts/kernel/adapters/memory_persistence.gd")
const Result = preload("res://scripts/kernel/result.gd")
var checks: int = 0
var failures: Array[String] = []

class FlakyTransport:
	extends Node
	var calls: int = 0
	var payloads: Array = []
	func dispatch(_command: String, payload: Dictionary) -> Dictionary:
		calls += 1
		payloads.append(payload.duplicate(true))
		return {"ok": calls > 1, "code": "OK" if calls > 1 else "NETWORK_ERROR", "data": {}, "message": ""}

func _init() -> void:
	call_deferred("_run")

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)

func stats(element: String = "wood") -> Dictionary:
	return {"hp": 300, "attack": 28, "defense": 8, "crit_rate": 0.0, "element": element}

func _skills() -> void:
	var private_stats: Dictionary = stats()
	private_stats["blood_glucose"] = 8
	expect(not preload("res://scripts/systems/combat/combat_rules.gd").valid_snapshot(private_stats), "health fields cannot enter a combat snapshot")
	var fractional: Dictionary = stats()
	fractional.hp = 0.2
	expect(not preload("res://scripts/systems/combat/combat_rules.gd").valid_snapshot(fractional), "subinteger hp cannot create an already-dead valid fight")
	for element in ["wood", "fire", "earth", "metal", "water"]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 4
		var fight := Fight.new(stats(element), stats("metal"), rng)
		fight.player_hp = 100
		var hit: Dictionary = fight.cast_skill()
		expect(hit.ok and hit.damage > 0, "skill works: " + element)
		expect(not fight.cast_skill().ok, "Q cannot be spammed: " + element)
		expect(not fight.cast_skill(true).ok, "R requires full energy")
		match element:
			"wood": expect(fight.player_hp == 145, "wood heals exactly 15 percent")
			"earth": expect(fight.shield == 90, "earth grants shield")
			"water": expect(fight.slow_left == 3, "water slows")
		fight.energy = 100
		expect(fight.cast_skill(true).ok and fight.energy == 0, "R spends energy once")
		fight.player_hp = 50
		fight.companion_step(10)
		var healed: int = fight.player_hp
		fight.companion_step(10)
		expect(healed == 110 and fight.player_hp == healed and fight.shield > 0, "support heals once and shields")
		fight.step(NAN)
		expect(is_finite(fight.elapsed), "nonfinite delta rejected")

func _waves() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/combat/encounters.json"))
	expect(data.encounters.size() == 3, "three configured encounters")
	for config in data.encounters:
		var sim := Simulation.new(stats(), config)
		expect(sim.wave == 0 and sim.enemies.size() == 2, "first wave spawns both actors")
		var before: Vector2 = sim.enemies[0].pos
		sim.paused = true
		sim.step(4)
		expect(sim.enemies[0].pos == before and sim.fight.elapsed == 0, "paused rules do not advance")
		sim.paused = false
		sim.enemies[0].wait = 0
		sim.step(0.01)
		var locked: Vector2 = sim.enemies[0].target
		sim.player_pos += Vector2(0, 250)
		sim.step(0.86)
		expect(sim.enemies[0].target == locked and sim.fight.player_hp == 300, "rush warning locks target and walking away evades")
		var iterations: int = 0
		while not sim.finished and iterations < 300:
			var target: Dictionary = sim.target_at(sim.player_pos)
			if target.is_empty(): break
			sim.player_pos = target.pos + Vector2(60, 0)
			sim.attack(target.pos)
			sim.fight.step(0.6)
			iterations += 1
		expect(sim.finished and sim.won and sim.wave == 3 and iterations < 300, "complete two waves plus boss: " + config.id)
		expect(sim.fight.result().won and sim.fight.elapsed > 0, "final fight result contains whole-session time")

func _cancel_and_seclude() -> void:
	var hub: Control = Hub.instantiate()
	hub.demo_authority = true
	root.add_child(hub)
	await process_frame
	hub.open("platform")
	var scene: Control = hub.current
	scene.request_confirmation("begin")
	expect(scene._dialog.visible and scene.current_state() == "cultivating", "click alone only opens family dialog")
	scene.cancel_pending()
	scene._dialog.hide()
	expect(scene.current_state() == "cultivating", "cancel before confirm preserves state")
	scene.request_confirmation("begin")
	await scene.confirm_pending()
	expect(scene.current_state() == "tribulation", "explicit confirm enters tribulation")
	scene.request_confirmation("seclusion")
	await scene.confirm_pending()
	expect(scene.current_state() == "seclusion" and not scene.celebrating, "closed retreat has no celebration")
	scene.request_confirmation("ascend")
	await scene.confirm_pending()
	expect(scene.current_state() == "seclusion" and scene._dialog.visible, "first ascension needs a second independent click")
	scene.cancel_pending()
	scene._dialog.hide()
	scene.request_confirmation("ascend")
	await scene.confirm_pending()
	expect(scene.current_state() == "seclusion", "canceling discards first attempt; new request needs two confirmations")
	await scene.confirm_pending()
	expect(scene.current_state() == "ascended" and not scene.celebrating, "ascension from seclusion succeeds on second click")
	hub.close()
	hub.queue_free()
	await process_frame

func _trial_launch_and_exit() -> void:
	var hub: Control = Hub.instantiate()
	hub.demo_authority = true
	root.add_child(hub)
	await process_frame
	await hub.launch_trial("trial_fire")
	await process_frame
	expect(hub.current != null and not hub.current.session_id.is_empty(), "entry starts a real module session before mounting trial")
	if hub.current != null:
		hub.current.set_process(false)
		var scene: Control = hub.current
		var demo: Node = hub._demo
		var sid: String = scene.session_id
		await scene.request_leave()
		expect(demo.snapshot("combat").sessions[sid].finished and not demo.snapshot("combat").sessions[sid].won, "exit closes session as non-victory")
		await process_frame
		expect(hub.current == null, "exit returns to entry")
	await hub.launch_trial("trial_metal")
	expect(hub.current != null, "can enter another trial after exit")
	hub.close()
	hub.queue_free()
	await process_frame

func _retry() -> void:
	var transport := FlakyTransport.new()
	root.add_child(transport)
	var scene: Control = Level.instantiate()
	scene.session_id = "retry_session"
	scene.kernel = transport
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	scene.fight.finished = true
	scene.fight.won = true
	scene.ended = true
	await scene._report()
	expect(not scene.report_ok and transport.calls == 1, "failed report stays retryable")
	await scene.retry_report()
	await scene.retry_report()
	expect(scene.report_ok and transport.calls == 2 and transport.payloads[0] == transport.payloads[1], "retry uses same session and result, successful report only once")
	scene.queue_free()
	transport.queue_free()
	await process_frame

func _retry_exit() -> void:
	var transport := FlakyTransport.new()
	root.add_child(transport)
	var scene: Control = Level.instantiate()
	scene.session_id = "exit-retry"
	scene.kernel = transport
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	var exits: Array = []
	scene.left.connect(func() -> void: exits.append(true))
	await scene.request_leave()
	expect(exits.is_empty() and scene.ended and not scene.report_ok, "failed exit report keeps retry controls and session context")
	await scene.request_leave()
	expect(exits.size() == 1 and scene.report_ok and transport.payloads[0] == transport.payloads[1], "second exit retries unchanged outcome and returns after success")
	scene.queue_free()
	transport.queue_free()
	await process_frame

func _migration() -> void:
	var combat: RefCounted = load("res://scripts/systems/combat/module.gd").new()
	var lifecycle: RefCounted = load("res://scripts/systems/lifecycle/module.gd").new()
	for module in [combat, lifecycle]:
		var migrated: Dictionary = module.migrate_state(1, {"revision": 0})
		expect(module.state_version() == 2 and migrated.ok and module.validate_state(migrated.data.state), "v1 skeleton save migrates without corruption")
		expect(not module.migrate_state(1, {"revision": -1}).ok, "bad prior save rejected")

func _run() -> void:
	_skills()
	_waves()
	_migration()
	await _cancel_and_seclude()
	await _trial_launch_and_exit()
	await _retry()
	await _retry_exit()
	print("A_ACCEPTANCE_TEST: %d assertions; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)