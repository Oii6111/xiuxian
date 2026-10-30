"""健康资料 → 游戏初始状态的确定性规则引擎。

原则（与落地设计稿 13.x 一致）：
- 识别由 LLM 完成，数值只由这里的确定性规则计算，LLM 不直接写 XP/战力/境界。
- 未知特征用中性值 50；疾病/异常指标不直接扣战力、不把老人角色写成残血。
- 首次 HP_current = HP_max；异常只进入“关注主题 + 护持任务”，不变成惩罚。
"""
import re

NEUTRAL = 50

# 异常状态词表（模型返回的 status 会映射到这些枚举）
_ABNORMAL = {"abnormal", "high", "low", "positive", "abnormal_result", "偏高", "偏低", "异常", "阳性"}
_UNKNOWN = {"", "unknown", "none"}


def clamp(v, lo, hi):
    return max(lo, min(hi, round(v)))


def _items(document):
    groups = document.get("groups") or []
    out = []
    for g in groups:
        for it in (g.get("items") or []):
            if isinstance(it, dict):
                out.append(it)
    return out


def _status(item):
    return str(item.get("status") or "").strip().lower()


def _is_abnormal(item):
    return _status(item) in _ABNORMAL


def compute_evidence(document):
    """把识别结果归一化为 0–100 的特征；未知特征用中性值 50。"""
    items = _items(document)
    field_count = document.get("field_count") or len(items) or 0

    # 资料完整度：识别到的有效字段越多越完整（首次注册，无其它来源）
    data_completeness = clamp(45 + min(field_count, 40) * 1.2, 45, 96)

    # 活动能力：默认中性；只有报告明确出现“活动受限/行动困难”等才下调，
    # 且只影响建模，不作为医学结论。
    narrative = str(document.get("narrative") or "") + str(document.get("summary") or "")
    function_capacity = NEUTRAL
    if re.search(r"活动受限|行动困难|行走困难|卧床|无法自理|活动能力减退", narrative):
        function_capacity = 40

    return {
        "data_completeness": data_completeness,
        "plan_coverage": NEUTRAL,          # 尚未采集计划，首日为中性
        "family_support": NEUTRAL,
        "function_capacity": function_capacity,
        "routine_stability": NEUTRAL,
        "self_reported_energy": NEUTRAL,
        "knowledge_tasks": NEUTRAL,
        "tech_readiness": NEUTRAL,
        "attention_load": len([it for it in items if _is_abnormal(it)]),  # 内部用，不对外暴露
    }


def compute_character_state(ev):
    """按设计稿 13.4 的公式计算 10 个游戏属性。"""
    f = ev
    engagement = NEUTRAL  # 首日无互动数据，用中性值
    hp_max = clamp(80 + 0.25 * f["function_capacity"] + 0.15 * f["data_completeness"], 80, 130)
    attack = clamp(20 + 0.25 * f["function_capacity"] + 0.20 * f["routine_stability"] + 0.10 * f["family_support"], 20, 80)
    defense = clamp(20 + 0.35 * f["plan_coverage"] + 0.25 * f["family_support"], 20, 90)
    spirit = clamp(20 + 0.30 * f["data_completeness"] + 0.20 * f["routine_stability"] + 0.15 * f["plan_coverage"], 20, 85)
    stamina = clamp(20 + 0.45 * f["function_capacity"] + 0.10 * f["self_reported_energy"], 20, 90)
    insight = clamp(20 + 0.45 * f["data_completeness"] + 0.20 * f["knowledge_tasks"], 20, 90)
    mind = clamp(20 + 0.40 * f["family_support"] + 0.20 * engagement, 20, 80)
    speed = clamp(20 + 0.35 * f["function_capacity"] + 0.20 * f["tech_readiness"], 20, 80)
    luck = NEUTRAL  # 纯游戏属性，不与疾病/年龄绑定
    return {
        "hp_max": hp_max, "hp_current": hp_max,
        "attack": attack, "defense": defense, "spirit": spirit,
        "stamina": stamina, "insight": insight, "mind": mind,
        "speed": speed, "luck": luck,
    }


# 五行主题：元素 → (对应游戏属性, 用于匹配指标 label 的关键词)
ELEMENTS = {
    "metal": {"name": "金·护息", "stat": "防御", "keywords": ["血氧", "呼吸", "肺", "胸片", "睡眠", "皮肤", "氧", "肺功能"]},
    "wood":  {"name": "木·舒展", "stat": "身法", "keywords": ["血糖", "糖化", "HbA1c", "血脂", "胆固醇", "甘油三酯", "LDL", "HDL", "ALT", "AST", "肝", "代谢", "胆"]},
    "water": {"name": "水·藏养", "stat": "体力", "keywords": ["肾", "肌酐", "尿酸", "尿", "eGFR", "骨", "钙", "尿素"]},
    "fire":  {"name": "火·心脉", "stat": "灵力", "keywords": ["血压", "心率", "心电", "脉搏", "心血管", "心脏"]},
    "earth": {"name": "土·纳养", "stat": "气血", "keywords": ["BMI", "体重", "身高", "消化", "营养", "肌力", "胃", "蛋白"]},
}


def compute_five_elements(document):
    """把指标按主题分组，异常只触发“待护持 + 护持任务”，不扣属性。"""
    items = _items(document)
    five, notes, tasks = {}, {}, []
    for key, meta in ELEMENTS.items():
        matched = [it for it in items if any(k in str(it.get("label") or "") for k in meta["keywords"])]
        abnormals = [it for it in matched if _is_abnormal(it)]
        normals = [it for it in matched if not _is_abnormal(it)]
        if abnormals:
            state, resonance = "needs_care", 48
            note = f"{meta['stat']} / {len(abnormals)} 项需关注，已生成护持任务"
            tasks.append({
                "task_id": f"care_{key}_001",
                "title": f"{meta['name']} 护持",
                "detail": f"核对 {len(abnormals)} 项相关指标，整理复诊问题",
                "status": "pending",
            })
        elif normals:
            state, resonance = "stable", 58
            note = f"{meta['stat']} / 相关指标在参考范围内"
        else:
            state, resonance = "unknown", NEUTRAL
            note = f"{meta['stat']} / 未提供相关资料"
        five[key] = {"state": state, "resonance": resonance}
        notes[key] = note
    return five, notes, tasks


def estimate_confidence(document):
    """用未知字段占比估算整体置信度（模型未直接给 confidence 时使用）。"""
    items = _items(document)
    if not items:
        return 60
    unknown = sum(1 for it in items if _status(it) in _UNKNOWN)
    return clamp(88 - (unknown / len(items)) * 30, 55, 96)


def build_projection(document):
    """识别结果 → 前端可合并的 game_projection。"""
    ev = compute_evidence(document)
    character_state = compute_character_state(ev)
    five_elements, element_notes, tasks = compute_five_elements(document)
    readiness = clamp(0.45 * ev["data_completeness"] + 0.30 * ev["plan_coverage"] + 0.25 * ev["family_support"], 30, 99)

    # evidence 只输出前端认识的 8 个扁平字段；attention_load 等内部特征不暴露
    evidence_out = {k: ev[k] for k in (
        "data_completeness", "plan_coverage", "family_support", "function_capacity",
        "routine_stability", "self_reported_energy", "knowledge_tasks", "tech_readiness",
    )}
    return {
        "evidence": evidence_out,
        "character_state": character_state,
        "five_elements": five_elements,
        "element_notes": element_notes,
        "tasks": tasks,
        "readiness": readiness,
    }
