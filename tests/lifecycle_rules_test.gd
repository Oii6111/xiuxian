extends SceneTree
## 生命周期纯规则测试：只加载规则脚本，不依赖内核、存档或网络。
const Rules = preload("res://scripts/systems/lifecycle/lifecycle_rules.gd")
var _assertions: int = 0
var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func expect(condition: bool, description: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(description)
		printerr("FAIL: ", description)

func _run() -> void:
	_test_transitions()
	_test_confirmations()
	_test_stages()
	print("LIFECYCLE_RULES_TEST: %d assertions; %d failures" % [_assertions, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _test_transitions() -> void:
	expect(Rules.can_transition("cultivating", "tribulation"), "admission starts tribulation")
	expect(Rules.can_transition("tribulation", "cultivating"), "recovery returns to cultivating")
	expect(Rules.can_transition("tribulation", "seclusion"), "long-term care enters seclusion")
	expect(Rules.can_transition("tribulation", "ascended"), "tribulation may end in ascension")
	expect(Rules.can_transition("seclusion", "cultivating"), "seclusion can end")
	expect(Rules.can_transition("seclusion", "ascended"), "seclusion may end in ascension")
	expect(not Rules.can_transition("cultivating", "ascended"), "cultivating cannot jump to ascension")
	expect(not Rules.can_transition("cultivating", "seclusion"), "cultivating cannot jump to seclusion")
	expect(not Rules.can_transition("cultivating", "cultivating"), "same-state transition rejected")
	for target in Rules.STATES:
		expect(not Rules.can_transition("ascended", target), "ascended is terminal: " + target)
	expect(not Rules.can_transition("unknown", "cultivating"), "unknown source state rejected")
	expect(not Rules.can_transition("cultivating", "unknown"), "unknown target state rejected")
	expect(Rules.is_state("seclusion") and not Rules.is_state("dead"), "state vocabulary is closed")
	expect(Rules.allows_combat("cultivating"), "cultivating may fight")
	for blocked in ["tribulation", "seclusion", "ascended", "unknown"]:
		expect(not Rules.allows_combat(blocked), "combat blocked in state: " + blocked)

func _test_confirmations() -> void:
	expect(Rules.confirmations_required("ascended") == 2, "ascension needs two confirmations")
	for target in ["tribulation", "cultivating", "seclusion"]:
		expect(Rules.confirmations_required(target) == 1, "single confirmation for: " + target)

func _test_stages() -> void:
	var parsed: Dictionary = Rules.parse_stage("cardio.emergency")
	expect(parsed.get("template_id") == "cardio" and parsed.get("index") == 1, "stage id parses to template and index")
	expect(Rules.parse_stage("cardio.nothing").is_empty(), "unknown stage rejected")
	expect(Rules.parse_stage("nothing.admission").is_empty(), "unknown template rejected")
	expect(Rules.parse_stage("cardio").is_empty() and Rules.parse_stage("a.b.c").is_empty(), "malformed stage id rejected")
	expect(Rules.stage_id("fracture", "surgery") == "fracture.surgery", "stage id builder")
	for template_id in Rules.TEMPLATES:
		var stages: Array = Rules.TEMPLATES[template_id].stages
		expect(stages.size() == 5 and stages[0] == "admission" and stages[4] == "discharge", "template shape: " + template_id)
		expect(Rules.can_move_stage(template_id, 0, 1), "forward stage allowed: " + template_id)
		expect(Rules.can_move_stage(template_id, 3, 2), "stage may regress: " + template_id)
		expect(not Rules.can_move_stage(template_id, 2, 2), "repeat stage rejected: " + template_id)
		expect(not Rules.can_move_stage(template_id, 0, 5) and not Rules.can_move_stage(template_id, -1, 0), "out-of-range stage rejected: " + template_id)
		expect(Rules.is_final_stage(template_id, 4) and not Rules.is_final_stage(template_id, 3), "final stage is discharge: " + template_id)
	expect(not Rules.can_move_stage("missing", 0, 1) and not Rules.is_final_stage("missing", 0), "unknown template cannot move")
