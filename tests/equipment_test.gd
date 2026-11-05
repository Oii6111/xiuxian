extends SceneTree
const State = preload("res://scripts/game_state.gd")
const Rules = preload("res://scripts/equipment_rules.gd")
const Boss = preload("res://scripts/boss_rules.gd")
var passed = 0
var failed = 0

class ClockState extends State:
	var date_value = "2026-10-01"
	func today() -> String:
		return date_value

func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS: ", message)
	else:
		failed += 1
		push_error(message)

func fresh(score: int = 40):
	var state = ClockState.new()
	state.persist_enabled = false
	state.apply_health_profile(state.HealthProfile.mock(score, 1))
	return state

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var state = fresh()
	check(state.equipment.qi == 0, "A new wallet starts empty, separate from legacy battle qi")
	check(not state.record_task("medication", false).ok and state.equipment.qi == 0, "Unconfirmed habit cannot mint wish currency")
	for day in range(1, 8):
		state.date_value = "2026-10-%02d" % day
		check(state.record_task("planned_record", true).rewarded, "Daily habit earns currency on day %d" % day)
		check(not state.record_task("planned_record", true).ok, "Repeated habit cannot duplicate day %d" % day)
		check(not state.record_task("medication", true).rewarded, "Second habit shares day %d reward" % day)
	check(state.equipment.qi == 700 and state.qi == 24, "Seven days fund exactly one ten-pull without changing battle resources")
	state.date_value = "2026-10-12"
	check(state.equipment.qi == 700, "Missed days do not reset currency")
	var origin = state.equipment.initial_score
	state.apply_health_profile(state.HealthProfile.mock(95, 2))
	check(state.equipment.initial_score == origin, "Better health never lowers the locked initial support")
	var low = Rules.probabilities(0)
	var high = Rules.probabilities(100)
	check(is_equal_approx(float(low.reduce(func(a, b): return a + b, 0.0)), 100.0) and is_equal_approx(float(high.reduce(func(a, b): return a + b, 0.0)), 100.0), "Both endpoint probability tables sum to 100 percent")
	check(low[2] > high[2] and low[3] > high[3] and low[4] > high[4], "Lower initial stats improve epic, legendary and mythic chances")
	var starter = fresh()
	starter.equipment.starter_ten_pulls = 1
	starter.equipment_rng.seed = 7
	var starter_result = starter.draw_equipment(10, "starter-ten")
	check(starter_result.ok and starter_result.starter_bonus and starter_result.cost == 0 and starter.equipment.qi == 0, "Starter grant delivers a free ten-pull without spending qi")
	check(starter.equipment.starter_ten_pulls == 0 and starter.equipment.inventory.size() == 10, "Starter grant is consumed exactly once")
	check(starter.draw_equipment(10, "starter-ten") == starter_result and not starter.draw_equipment(10, "starter-again").ok, "Starter receipt is idempotent and cannot be reused")
	var r1 = RandomNumberGenerator.new()
	var r2 = RandomNumberGenerator.new()
	r1.seed = 1024
	r2.seed = 1024
	var rare_low = 0
	var rare_high = 0
	for i in range(10000):
		rare_low += int(Rules.roll_rarity(0, r1) >= 2)
		rare_high += int(Rules.roll_rarity(100, r2) >= 2)
	check(rare_low > rare_high + 1500, "Seeded sampling follows the intended support distribution")
	state.equipment_rng.seed = 7
	var result = state.draw_equipment(10, "week-one")
	check(result.ok and result.items.size() == 10 and state.equipment.qi == 0, "Ten-pull debits 700 and delivers ten separate items")
	var best = 0
	var ids = {}
	for item in result.items:
		best = maxi(best, item.rarity)
		ids[item.id] = true
	check(best >= 2 and ids.size() == 10, "Ten-pull includes an epic or better with unique item IDs")
	check(state.draw_equipment(10, "week-one") == result and state.equipment.inventory.size() == 10, "Same request retries return the same receipt without a second debit")
	check(not state.draw_equipment(1, "week-one").ok, "An idempotency key cannot change its draw count")
	check(not state.draw_equipment(1, "empty-wallet").ok and state.equipment.inventory.size() == 10, "Insufficient funds do not grant any equipment")
	# Find a deterministic seed where natural ten cards are below epic, and verify the floor.
	var guarantee_test = fresh(100)
	var found_floor = false
	for seed_value in range(100):
		guarantee_test.equipment = Rules.fresh()
		guarantee_test.lock_equipment_origin()
		guarantee_test.equipment.qi = 700
		guarantee_test.equipment_rng.seed = seed_value
		var pull = guarantee_test.draw_equipment(10, "floor")
		if pull.guaranteed:
			found_floor = int(pull.items[-1].rarity) == 2
			break
	check(found_floor, "A naturally low-quality ten-pull upgrades its last card to epic")
	# Equipment composition and in-battle snapshot isolation.
	state.equipment.inventory.append({"id": "gear_999991", "template": 3, "rarity": 1})
	var health_before = state.health_attributes.duplicate(true)
	var baseline_stamina = state.battle_stats().max_stamina
	var in_progress = Boss.new(state)
	check(state.equip_item("gear_999991").ok and state.battle_stats().max_stamina == baseline_stamina + 10, "Fine boots add ten stamina to battle stats")
	check(in_progress.max_stamina == baseline_stamina and Boss.new(state).max_stamina == baseline_stamina + 10, "An active battle stays unchanged; the next battle sees equipped gear")
	check(state.health_attributes == health_before and state.equipment.initial_score == origin, "Gear never rewrites health attributes or draw support")
	check(state.unequip_item("boots").ok and state.battle_stats().max_stamina == baseline_stamina, "Unequipping removes only the equipment bonus")
	state.equipment.inventory.append({"id": "gear_999992", "template": 1, "rarity": 4})
	var defense_before = state.battle_stats()
	state.equip_item("gear_999992")
	check(state.battle_stats().damage_multiplier < defense_before.damage_multiplier and state.battle_stats().shield > defense_before.shield, "Defensive robes affect damage reduction and the existing shield")
	check(not state.equip_item("not-owned").ok, "A nonexistent item cannot be equipped")
	# A failed atomic write must leave both wallet and inventory untouched.
	var broken = fresh()
	broken.persist_enabled = true
	broken.save_file_override = "res://output/missing-equipment-test-directory/save.json"
	broken.equipment.qi = 700
	var before = broken.equipment.duplicate(true)
	check(not broken.draw_equipment(10, "failed-write").ok and broken.equipment == before, "Failed saving rolls back debit, inventory, receipt and item counter")
	check(not broken.record_task("planned_record", true).ok and broken.equipment == before and not broken.task_done("planned_record"), "Failed daily saving rolls back the habit and reward")
	# Save/restart and schema-five migration use isolated test files.
	var fixture = "res://output/equipment-test-%d.json" % OS.get_process_id()
	state.save_file_override = fixture
	state.persist_enabled = true
	check(state.save_game(), "Equipment progress can be saved")
	var loaded = fresh()
	loaded.save_file_override = fixture
	loaded.load_game()
	check(loaded.equipment == Rules.normalize(state.equipment), "Wallet, original support, inventory and equipped slots survive restart")
	var restored_receipt = loaded.draw_equipment(10, "week-one")
	check(restored_receipt.get("items", []) == result.items and loaded.equipment.qi == 0, "Committed draw receipt remains idempotent after restart")
	var legacy = FileAccess.open(fixture, FileAccess.WRITE)
	legacy.store_string(JSON.stringify({"schema": 5, "cultivation": 137, "cleared_bosses": ["b04"], "health_profile_id": "old-profile", "health_revision": 1, "health_attributes": {"life": 30, "attack": 40, "defense": 50, "spirit": 60, "stamina": 70}, "rewarded_days": ["2026-10-01"]}))
	legacy.close()
	var migrated = fresh()
	migrated.persist_enabled = true
	migrated.save_file_override = fixture
	migrated.load_game()
	check(migrated.cultivation == 137 and migrated.boss_cleared("b04") and migrated.equipment.initial_score == 50, "Schema-five migration preserves progression and locks the existing profile")
	check(migrated.equipment.qi == 100 and migrated.equipment.inventory.is_empty(), "Migration credits today's existing record once, without inventing equipment")
	migrated.save_game()
	var migrated_again = fresh()
	migrated_again.save_file_override = fixture
	migrated_again.load_game()
	check(migrated_again.equipment.qi == 100, "A migrated save cannot claim the upgrade credit repeatedly")
	for path in [fixture, fixture.trim_suffix(".json") + "-before-equipment-v6.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# Exercise the real map interaction, buttons, results and equipment detail.
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.state = fresh()
	scene.state.equipment.qi = 700
	scene.ui.refresh()
	var gacha_site = {}
	for site in scene.sites:
		if site.id == "gacha":
			gacha_site = site
	check(not gacha_site.is_empty() and scene.can_walk(gacha_site.position), "Treasure Pavilion is a real reachable main-map destination")
	scene.player.position = gacha_site.position
	scene._process(0)
	var interact = InputEventAction.new()
	interact.action = "interact"
	interact.pressed = true
	scene._unhandled_input(interact)
	await process_frame
	check(is_instance_valid(scene.ui.treasure) and scene.ui.modal_open and scene.player.blocked, "E interaction opens the actual wish panel and blocks town movement")
	var treasure = scene.ui.treasure
	treasure.ten_button.pressed.emit()
	check(treasure.busy and scene.state.equipment.inventory.size() == 10 and scene.state.equipment.qi == 0, "The real ten-pull button commits ten rewards before revealing")
	treasure.summon(10)
	check(scene.state.equipment.inventory.size() == 10, "Repeated input during reveal cannot perform a second pull")
	treasure.finish_reveal()
	check(treasure.result_cards.size() == 10 and not treasure.busy, "Skipping reveals all ten already-saved cards")
	var reveal_fx = treasure.result_cards[0].get_node_or_null("GachaRevealFX")
	check(reveal_fx != null and str(reveal_fx.get("state")) == "revealed", "Each result card carries a staged rarity reveal effect")
	treasure.result_cards[0].pressed.emit()
	await process_frame
	check(treasure.tab == "bag" and not treasure.selected_id.is_empty(), "A result card opens the matching inventory detail")
	var equip_button: Button
	for button in treasure.find_children("*", "Button", true, false):
		if button.text == "穿戴装备":
			equip_button = button
	check(equip_button != null, "Inventory detail exposes the actual equip action")
	if equip_button:
		equip_button.pressed.emit()
	check(scene.state.equipment.equipped.size() == 1, "Inventory equip button updates the character's equipment")
	scene.ui.close_modal()
	scene.ui.open_treasure()
	check(scene.ui.treasure.result_cards.size() == 10 and scene.state.equipment.qi == 0, "Reopening restores the last results without another draw")
	scene.ui.close_modal()
	check(not scene.player.blocked, "Closing the pavilion restores village movement")
	scene.queue_free()
	await process_frame
	print("EQUIPMENT TESTS: ", passed, " passed, ", failed, " failed")
	quit(0 if failed == 0 else 1)
