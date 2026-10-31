extends SceneTree
## Machine-readable handoff to C. This file does not enable a backend or grant assets.
const Equipment = preload("res://scripts/equipment_rules.gd")
const State = preload("res://scripts/game_state.gd")
const Boss = preload("res://scripts/boss_rules.gd")
const Catalogue = preload("res://scripts/trial_catalogue.gd")
const PATH = "res://data/pixel-game-rules.v1.json"

static func rules() -> Dictionary:
	var bosses = []
	for encounter in Catalogue.all():
		bosses.append({"id": encounter.id, "tier": encounter.tier})
	return {
		"schema_version": 1,
		"rules_version": Equipment.RULES_VERSION,
		"catalogue_version": Equipment.CATALOGUE_VERSION,
		"authority": "local_prototype_only",
		"family": {"owner_count": 1, "max_elders": 2, "resources_per_character": true, "companion_scope": "account"},
		"resources": {"wish_qi": {"local_path": "equipment.qi", "initial": 0, "proposed_c_field": "spirit_stones", "mapping_requires_c_approval": true}, "legacy_qi": {"local_path": "qi", "separate_from_wish_qi": true}, "seals": {"local_path": "seals", "scope": "character"}},
		"daily_reward": {"group": "daily_plan", "tasks": ["medication", "planned_record"], "timezone": "Asia/Shanghai", "qi": Equipment.DAILY_QI, "cultivation": State.DAILY_CULTIVATION, "seals": State.DAILY_SEALS, "days": 1, "once_per_character_per_day": true, "days_are_cumulative": true},
		"equipment": {"single_cost": Equipment.SINGLE_COST, "ten_cost": Equipment.TEN_COST, "rarities": Equipment.RARITIES, "slots": Equipment.SLOTS, "templates": Equipment.TEMPLATES, "high_score_weights": Equipment.HIGH_WEIGHTS, "low_score_weights": Equipment.LOW_WEIGHTS, "support": "1 - clamp(mean(clamp_each_initial_attribute_0_100), 0, 100) / 100", "weights": "lerp(high_score_weights, low_score_weights, support)", "sampling": "uniform_slot_then_uniform_template_in_slot", "ten_guarantee": {"minimum_rarity_index": 2, "upgrade_last_only_if_all_below_minimum": true}, "keep_duplicate_instances": true, "cumulative_pity": false, "bonuses_apply": "next_battle"},
		"combat": {"bosses": bosses, "skill_costs": {"sword_mp": Boss.SWORD_COST, "shield_mp": Boss.SHIELD_COST, "dodge_stamina": Boss.DODGE_COST, "heal_mp": Boss.HEAL_COST}, "basic_hit_mp_regen": 5, "heal_unlock_distinct_clears": 2, "realm_step_distinct_bosses": 4, "practice_grants_progress": false, "per_frame_network": false, "named_boss_daily_limit": null}
	}

func _initialize() -> void:
	verify.call_deferred()

func verify() -> void:
	var expected = rules()
	if "--write" in OS.get_cmdline_user_args():
		var file = FileAccess.open(PATH, FileAccess.WRITE)
		if file == null:
			push_error("Cannot write local rule manifest")
			quit(1)
			return
		file.store_string(JSON.stringify(expected, "\t", true) + "\n")
		file.close()
		print("WROTE: ", PATH)
		quit(0)
		return
	var actual = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	# JSON represents numbers differently; compare their canonical serialized form.
	if JSON.stringify(actual) != JSON.stringify(JSON.parse_string(JSON.stringify(expected))):
		push_error("Local rule manifest differs from game code; regenerate and review before merge")
		quit(1)
		return
	print("RULE MANIFEST: matches live game constants")
	quit(0)
