"""Local prototype boundary; not the authoritative C v2 game contract.

Full baseline files and medical explanations remain in the health service.
"""
from copy import deepcopy

STAT_KEYS = ("hp_max", "hp_current", "attack", "defense", "spirit", "stamina", "insight", "mind", "speed", "luck")
META_KEYS = ("baseline_id", "baseline_version", "mapping_version", "rules_revision", "baseline_locked", "supplementable", "recognition_mode", "display_name")

def for_game(baseline):
    result = {key: deepcopy(baseline[key]) for key in META_KEYS if key in baseline}
    result["projection_version"] = "legacy-pixel-v1"
    result["character_state"] = {key: baseline["character_state"][key] for key in STAT_KEYS}
    result["readiness"] = baseline["readiness"]
    return result
