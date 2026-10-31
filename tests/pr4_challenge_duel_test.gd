extends SceneTree
const Boss = preload("res://scripts/boss_rules.gd")
const State = preload("res://scripts/game_state.gd")
const Catalogue = preload("res://scripts/trial_catalogue.gd")
const Driver = preload("res://tests/helpers/pr4_duel_driver.gd")
var checks: int = 0
var failures: Array = []
func _init() -> void: call_deferred("_run")
func expect(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures.append(title)
		printerr("FAIL: ",title)
func _run() -> void:
	var report: Array = []
	var totals := {"early":{"active_wins":0,"reckless_wins":0,"active_damage":0,"reckless_damage":0},"later":{"active_wins":0,"reckless_wins":0,"active_damage":0,"reckless_damage":0}}
	for id in ["b00","b03","b06","b10","b15","b19"]:
		var group: String = "early" if id in ["b00","b03"] else "later"
		for active in [true,false]:
			var state = State.new()
			state.persist_enabled = false
			state.apply_health_profile(state.HealthProfile.mock(40,1))
			Driver.equip_progression(state,int(id.substr(1))+1)
			state.complete_boss("b00",{"time":60})
			state.complete_boss("b01",{"time":60})
			var resources: Dictionary = state.to_data().duplicate(true)
			var rules = Boss.new(state,0,10,"attack",false,Catalogue.entry(id))
			var result: Dictionary = Driver.run(rules,active)
			result.merge({"rank":rules.combat_rank,"boss":id,"strategy":"active" if active else "attack_only"})
			report.append(result)
			var results: Dictionary = totals[group]
			results["active_wins" if active else "reckless_wins"] += 1 if result.won else 0
			results["active_damage" if active else "reckless_damage"] += int(result.damage)
			expect(result.finished,"full fight reaches win/defeat "+id+str(active))
			expect(state.equipment==resources.equipment and state.health_attributes==resources.health_attributes and state.lifecycle_record()==resources.lifecycle_v2,"combat preserves wallet and health "+id)
	expect(totals.early.active_wins==2,"opening encounters are clearable with normal controls")
	expect(totals.later.active_wins>=3,"later encounters remain clearable through movement and the four skills")
	expect(totals.later.reckless_wins<=1,"later encounters punish sustained attack-only trading")
	expect(totals.later.active_damage<totals.later.reckless_damage,"reading attacks and using defense materially reduces damage")
	var file := FileAccess.open("res://work/action-assets/progression-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"totals":totals,"battles":report,"note":"100 base HP; authentic progression equipment; private collision-aware solver; not a human hidden-telegraph difficulty benchmark"},"  "))
	file.close()
	print("PR4_CHALLENGE_DUEL_TEST: %d assertions; %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
