extends SceneTree
## Full twenty-boss fights using delayed impact, cast slowdown and gradual dodge movement.
const State = preload("res://scripts/game_state.gd")
const Boss = preload("res://scripts/boss_rules.gd")
const Catalogue = preload("res://scripts/trial_catalogue.gd")
const Driver = preload("res://tests/helpers/pr4_duel_driver.gd")
var failures: Array = []
var checks: int = 0
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: ",message)
func _init() -> void: call_deferred("_run")
func _run() -> void:
	var state = State.new()
	state.persist_enabled = false
	state.apply_health_profile(state.HealthProfile.mock(40,1))
	var report: Array = []
	for row in Catalogue.all():
		Driver.equip_progression(state,int(row.index)+1)
		var rules = Boss.new(state,0,10,"attack",false,row)
		var currency: int = state.equipment.qi
		var attributes: Dictionary = state.health_attributes.duplicate(true)
		var clear_before: int = state.cleared_bosses.size()
		var battle: Dictionary = Driver.run(rules,true)
		expect(rules.won,row.id+" completes full duel with timed attacks and gradual rolls")
		expect(battle.attacks>=3 and battle.moves.size()>=2,row.id+" multiple actual attacks before clear")
		expect(battle.stages.size()==3,row.id+" exercises all three phases")
		expect(state.cleared_bosses.size()==clear_before+1,row.id+" clear recorded once")
		expect(state.equipment.qi==currency and state.health_attributes==attributes,row.id+" wallet and health untouched")
		battle.id = row.id
		battle.name = row.name
		report.append(battle)
	var file = FileAccess.open("res://work/boss-polish/duel-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"note":"100 base HP plus authentic rank equipment; private collision-aware engineering solver, not human difficulty validation","battles":report},"  "))
	file.close()
	print("PR4_BOSS_DUEL_TEST: %d assertions; %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
