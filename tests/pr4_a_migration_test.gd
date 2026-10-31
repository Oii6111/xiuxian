extends SceneTree
const State = preload("res://scripts/game_state.gd")
const Roster = preload("res://scripts/family_roster.gd")
const Patterns = preload("res://scripts/systems/combat/pr4_patterns.gd")
const Boss = preload("res://scripts/boss_rules.gd")
const Catalogue = preload("res://scripts/trial_catalogue.gd")
var assertions: int = 0
var failures: Array = []
func _init() -> void:
	call_deferred("_run")
func expect(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)

func _person(mother: bool) -> Dictionary:
	return {"name": "测试母亲" if mother else "测试父亲", "relation": "母亲" if mother else "父亲", "age": 65, "sex": "女" if mother else "男", "title": "母亲修仙者" if mother else "父亲修仙者", "avatar": "female" if mother else "male", "mode": "family", "consent": true}

func _pure_checks() -> void:
	var state = State.new()
	state.persist_enabled = false
	state.load_data({"schema": 6, "recovery_status": "active"})
	expect(state.lifecycle_record().state == "tribulation" and not state.allows_battle(), "old confirmed recovery imports as tribulation")
	var restored_healthy = State.new()
	restored_healthy.persist_enabled = false
	restored_healthy.load_data({"schema":6, "lifecycle_v2":restored_healthy.LifecycleRecord.fresh()})
	expect(restored_healthy.begin_recovery(true) and not restored_healthy.allows_battle(), "old explicit confirmation API also updates restored lifecycle projection")
	expect(restored_healthy.confirm_recovery(true, true) and restored_healthy.allows_battle(), "old recovery completion restores combat gate")
	var bad_schema: Dictionary = state.lifecycle_record()
	bad_schema.schema = true
	expect(not state.LifecycleRecord.valid(bad_schema), "boolean cannot impersonate a lifecycle schema number")
	var illegal: Dictionary = restored_healthy.lifecycle_record()
	illegal.state = "ascended"
	illegal.version += 1
	expect(not restored_healthy.commit_lifecycle(illegal, int(illegal.version) - 1).ok and restored_healthy.allows_battle(), "persistence boundary also rejects illegal state jumps")
	var invalid: Dictionary = state.lifecycle_record()
	invalid["raw_report"] = "private"
	var corrupt = State.new()
	corrupt.persist_enabled = false
	corrupt.load_data({"schema": 6, "lifecycle_v2": invalid})
	expect(not corrupt.allows_battle() and not corrupt.save_game(), "bad life data blocks battle and overwrite")
	for kind in range(4):
		var shape: Dictionary = Patterns.build(kind, 0, Vector2(200, 500), Vector2(600, 500), Vector2(140, 80))
		var polygons: Array = Patterns.polygons(shape)
		expect(not polygons.is_empty(), "each pattern has visible geometry")
		for point in [Vector2(600, 500), Vector2(640, 500), Vector2(690, 500), Vector2(200, 200)]:
			var drawn: bool = false
			for polygon in polygons:
				drawn = drawn or Geometry2D.is_point_in_polygon(point, polygon)
			expect(Patterns.hits(shape, point) == drawn, "warning and damage geometry agree")
	var healthy = State.new()
	healthy.persist_enabled = false
	healthy.apply_health_profile(healthy.HealthProfile.mock(40, 1))
	var battle = Boss.new(healthy, 0, 10, "attack", false, Catalogue.entry("b03"))
	var initial_stats: Dictionary = battle.stats.duplicate(true)
	battle.boss_hp = int(battle.boss_max_hp * 0.6)
	battle._sync_stage()
	expect(battle.stage_index == 1 and battle.active_adds() == 2, "phase two summons adds")
	battle.boss_hp = int(battle.boss_max_hp * 0.25)
	battle._sync_stage()
	expect(battle.stage_index == 2 and battle.active_adds() <= 4, "phase three and summon cap")
	for _frame in range(180):
		if battle.phase == "windup":
			break
		battle.step(1.0/60, Vector2(600,550))
	var warning: Dictionary = battle.warning_profile()
	battle.target_position = Vector2(200, 650)
	expect(battle.warning_profile() == warning, "telegraph is locked and cannot chase the player")
	expect(battle.stats == initial_stats, "phase transitions do not change player gear snapshot")
	healthy.lifecycle_v2 = healthy.LifecycleRecord.fresh("seclusion")
	expect(Boss.new(healthy).finished and not healthy.begin_named_boss("b00").ok, "rules and state both reject noncultivating battle")
	expect(battle.step(0.1, Vector2.ZERO).get("event") == "state_changed" and battle.finished and not battle.won, "in-flight state update halts the fight without a victory")

func _village_flow() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.family.persist_enabled = false
	var father: Dictionary = scene.family.add_member(_person(false))
	var mother: Dictionary = scene.family.add_member(_person(true))
	expect(father.ok and mother.ok, "two elders can be created in actual PR4 roster")
	var dad = scene.family.state_for(father.id)
	var mom = scene.family.state_for(mother.id)
	dad.apply_health_profile(dad.HealthProfile.mock(40, 1))
	mom.apply_health_profile(mom.HealthProfile.mock(50, 1))
	dad.equipment.qi = 700
	dad.equipment.inventory = [{"id":"gear_000001", "template":0, "rarity":2}]
	dad.equipment.next_id = 2
	dad.equip_item("gear_000001")
	expect(scene.ui.activate_family(father.id), "real UI selects father")
	scene.ui.start_corridor_boss("b03")
	await process_frame
	expect(is_instance_valid(scene.ui.combat) and scene.ui.combat.rules.stats == dad.battle_stats(), "PR4 combat consumes exact final gear snapshot")
	var entered = scene.ui.combat
	var frozen_attack: int = entered.rules.stats.attack
	dad.equipment.inventory.append({"id":"gear_000002", "template":0, "rarity":4})
	dad.equipment.next_id = 3
	dad.equipment.draw_count = 2
	dad.equip_item("gear_000002")
	expect(entered.rules.stats.attack == frozen_attack, "equipping during an entered fixture cannot mutate current stats")
	expect(not scene.ui.activate_family(mother.id) and scene.state == dad, "real UI blocks changing elder during battle")
	scene.ui.close_modal()
	await process_frame
	scene.ui.start_corridor_boss("b03")
	await process_frame
	expect(scene.ui.combat.rules.stats.attack > frozen_attack and mom.equipment.inventory.is_empty(), "new battle gets improved gear and other elder stays isolated")
	scene.ui.close_modal()
	await process_frame
	scene.ui.start_companion_practice()
	await process_frame
	var training: Control = scene.ui.combat
	expect(training.mode == "practice" and training.companion != null, "AI support is available through the actual PR4 practice entrance")
	var hp_before: int = training.rules.boss_hp
	var contribution_before: int = dad.contribution
	var mana_before: float = training.rules.mp
	training._process(1.9)
	expect(training.rules.boss_hp < hp_before and training.rules.mp == mana_before, "companion attacks without consuming the player's mana")
	expect(dad.contribution == contribution_before and dad.cleared_bosses.is_empty(), "companion practice grants no progression or contribution")
	scene.ui.close_modal()
	await process_frame
	scene.ui.start_battle()
	await process_frame
	var interrupted_view: Control = scene.ui.combat
	var original_life: Dictionary = dad.lifecycle_v2.duplicate(true)
	dad.lifecycle_v2 = dad.LifecycleRecord.fresh("seclusion")
	interrupted_view._process(0.01)
	expect(not is_instance_valid(scene.ui.combat), "live scene exits when its character becomes ineligible")
	dad.lifecycle_v2 = original_life
	await process_frame
	var wallet: int = dad.equipment.qi
	var gear: Dictionary = dad.equipment.duplicate(true)
	var baseline: Dictionary = dad.health_attributes.duplicate(true)
	scene.ui.open_recovery()
	await process_frame
	var panel: Control = scene.ui.lifecycle_panel
	expect(panel != null and panel.cultivator_id.contains(father.id), "village lifecycle panel is bound to actual elder")
	panel.request_confirmation("begin")
	expect(not scene.ui.activate_family(mother.id), "cannot switch role while family dialog is open")
	panel.cancel_pending()
	panel._dialog.hide()
	expect(dad.lifecycle_record().state == "cultivating", "cancel keeps father cultivating")
	panel.request_confirmation("begin")
	await panel.confirm_pending()
	expect(dad.lifecycle_record().state == "tribulation" and mom.lifecycle_record().state == "cultivating", "confirmed state saved only for father")
	await panel.update_stage("admission")
	await panel.update_stage("emergency")
	panel.light_lamp()
	expect(dad.lifecycle_record().stage_index == 1 and dad.lifecycle_record().lamps == 1, "stage and lamp are in elder record")
	scene.ui.close_modal()
	await process_frame
	scene.ui.start_battle()
	expect(not is_instance_valid(scene.ui.combat), "practice also blocks the hospitalized elder")
	scene.ui.start_corridor_boss("b00")
	expect(not is_instance_valid(scene.ui.combat), "named arena blocks the hospitalized elder")
	scene.ui.open_recovery()
	await process_frame
	panel = scene.ui.lifecycle_panel
	expect(panel.lamps == 1 and panel._entry().stage_index == 1, "reopening restores stage and lamps")
	var before: Dictionary = dad.lifecycle_record()
	var real_save: Callable = dad.family_save
	dad.persist_enabled = true
	dad.family_save = func() -> bool: return false
	panel.request_confirmation("seclusion")
	await panel.confirm_pending()
	expect(dad.lifecycle_record() == before and panel.status.contains("SAVE_FAILED"), "failed save rolls lifecycle back")
	dad.persist_enabled = false
	dad.family_save = real_save
	panel.request_confirmation("seclusion")
	await panel.confirm_pending()
	expect(dad.lifecycle_record().state == "seclusion" and not panel.celebrating, "successful retry enters seclusion without celebration")
	scene.ui.close_modal()
	await process_frame
	scene.ui.open_record()
	expect(not is_instance_valid(scene.ui.lifecycle_panel) and scene.ui.modal_open, "seclusion shows companionship rather than health tasks")
	scene.ui.close_modal()
	expect(scene.ui.activate_family(mother.id), "mother can be selected after closing panel")
	scene.ui.open_recovery()
	await process_frame
	var template_panel: Control = scene.ui.lifecycle_panel
	var selector: OptionButton = template_panel.find_children("*", "OptionButton", true, false)[0]
	selector.select(1)
	selector.item_selected.emit(1)
	expect(mom.lifecycle_record().template_id == "fracture", "template selection persists without entering tribulation")
	scene.ui.close_modal()
	await process_frame
	scene.ui.open_recovery()
	await process_frame
	expect(scene.ui.lifecycle_panel.template_id == "fracture", "reopening restores selected template before admission")
	scene.ui.close_modal()
	await process_frame
	scene.ui.start_battle()
	await process_frame
	expect(is_instance_valid(scene.ui.combat) and scene.ui.combat.rules.state == mom, "healthy mother can still practice")
	scene.ui.close_modal()
	await process_frame
	scene.ui.activate_family(father.id)
	scene.ui.open_recovery()
	await process_frame
	panel = scene.ui.lifecycle_panel
	panel.request_confirmation("ascend")
	await panel.confirm_pending()
	expect(dad.lifecycle_record().state == "seclusion", "first ascension click keeps persisted state")
	var abandoned: String = panel.ascending_token
	panel.cancel_pending()
	panel._dialog.hide()
	var canceled: Dictionary = await scene.ui.lifecycle_gateway.dispatch("lifecycle.confirm_change", {"cultivator_id":panel.cultivator_id, "confirmation_token":abandoned, "request_id":"canceled-token"})
	expect(not canceled.ok and dad.lifecycle_record().state == "seclusion", "canceled ascension token cannot complete afterward")
	panel.request_confirmation("ascend")
	await panel.confirm_pending()
	expect(dad.lifecycle_record().state == "seclusion", "fresh ascension request needs two confirmations again")
	await panel.confirm_pending()
	expect(dad.lifecycle_record().state == "ascended" and not panel.celebrating, "second click ascends without celebration")
	expect(dad.equipment == gear and dad.equipment.qi == wallet and dad.health_attributes == baseline, "life changes never mint currency or mutate gear/health")
	var captured: Node = scene.ui.lifecycle_gateway
	var captured_id: String = captured.actor_id
	scene.ui.close_modal()
	scene.ui.activate_family(mother.id)
	var stale: Dictionary = await captured.dispatch("lifecycle.request_change", {"cultivator_id":captured_id,"target_state":"tribulation"})
	expect(stale.code == "ROLE_CHANGED" and mom.lifecycle_record().state == "cultivating", "stale panel cannot change newly selected elder")
	await process_frame
	var path := "res://work/pr4-integration/lifecycle-family-fixture.json"
	scene.family.persist_enabled = true
	scene.family.save_file_override = path
	expect(scene.family.save_game(), "full family including new lifecycle persists")
	var restored = Roster.new()
	restored.persist_enabled = false
	restored.save_file_override = path
	restored.load_game(restored.owner_state)
	expect(restored.state_for(father.id).lifecycle_record().state == "ascended" and restored.state_for(mother.id).lifecycle_record().state == "cultivating", "restart restores distinct elder states")
	expect(restored.state_for(father.id).equipment == gear and restored.state_for(father.id).lifecycle_record().lamps == 1, "restart preserves gear and lamps")
	restored.dispose()
	scene.family.persist_enabled = false
	scene.queue_free()
	await process_frame

func _run() -> void:
	_pure_checks()
	await _village_flow()
	print("PR4_A_MIGRATION_TEST: %d assertions; %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)