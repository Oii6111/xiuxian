"""Validate the current body-system mapping, retaining only confirmed game fields."""
import math
STATS = ("hp_max", "hp_current", "attack", "defense", "spirit", "stamina", "insight", "mind", "speed", "luck")
EVIDENCE = ("data_completeness", "plan_coverage", "family_support", "function_capacity", "routine_stability", "self_reported_energy", "knowledge_tasks", "tech_readiness")

def number(value, lo, hi, label):
    if type(value) not in (int, float) or not math.isfinite(value) or not lo <= value <= hi:
        raise ValueError(f"初始属性 {label} 缺失或超出范围。")
    return round(value)

def normalize_baseline(payload):
    stats = payload.get("character_state")
    if not isinstance(stats, dict):
        raise ValueError("缺少角色初始属性。")
    stats = {key: number(stats.get(key), 40 if key.startswith("hp_") else 0, 100, key) for key in STATS}
    if stats["hp_current"] != stats["hp_max"]:
        raise ValueError("初始化时生命应为满值。")
    evidence = payload.get("evidence", {})
    notes = payload.get("attribute_notes", {})
    if not isinstance(evidence, dict) or not isinstance(notes, dict):
        raise ValueError("资料特征或属性说明格式错误。")
    evidence = {key: number(value, 0, 100, key) for key, value in evidence.items() if key in EVIDENCE}
    notes = {key: str(value)[:3000] for key, value in notes.items() if key in STATS}
    mode = payload.get("recognition_mode")
    if mode not in ("live", "text", "sample", "demo"):
        raise ValueError("未知识别模式。")
    return dict(baseline_version="char_baseline_v1", mapping_version="body_system_v2", rules_revision="1f356a0" if mode in ("live", "text") else "",
                character_state=stats, evidence=evidence, attribute_notes=notes,
                readiness=number(payload.get("readiness"), 0, 100, "readiness"),
                baseline_locked=True, supplementable=True,
                input_mode="text" if mode == "text" else "report", source_priority="medical_report",
                recognition_mode="sample" if mode == "demo" else mode,
                display_name=str(payload.get("display_name") or "")[:10],
                provider=str(payload.get("provider") or "")[:80], model=str(payload.get("model") or "")[:100])
