"""健康资料 → 游戏初始状态的确定性规则引擎。

原则：
- 识别由 LLM 完成，数值只由这里的确定性规则计算，LLM 不直接写 XP/战力/境界。
- 只采用「常规」健康资料：体检指标按关键词白名单筛选，罕见/非常规专科指标自动舍去。
- 体检指标 + 病史 + 长期用药共同决定五行主题与对应属性；异常只触发“待护持 + 护持任务”，
  不直接扣属性、不把老人角色写成残血。
- 未知特征用中性值 50。

完整的字段筛选与映射说明见同目录 MAPPING.md。
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


def _history_entries(document):
    out = []
    for h in (document.get("history") or []):
        if isinstance(h, dict):
            out.append(h)
        elif isinstance(h, str) and h.strip():
            out.append({"condition": h})
    return out


def _medication_entries(document):
    out = []
    for m in (document.get("medications") or []):
        if isinstance(m, dict):
            out.append(m)
        elif isinstance(m, str) and m.strip():
            out.append({"name": m})
    return out


# 五行主题：元素 → 名称 / 对应游戏属性 / 匹配关键词（覆盖体检指标、病史、用药）
ELEMENTS = {
    "metal": {
        "name": "金·护息", "stat": "防御",
        "keywords": ["血氧", "氧", "呼吸", "肺", "胸片", "肺功能", "呼吸频率",
                     "哮喘", "慢阻肺", "copd", "支气管炎", "肺炎", "肺气肿", "支气管扩张", "肺结节", "打鼾", "睡眠呼吸暂停",
                     "止咳", "平喘", "化痰", "吸入", "雾化", "沙丁胺醇", "布地奈德"],
    },
    "wood": {
        "name": "木·舒展", "stat": "身法",
        "keywords": ["血糖", "糖化", "hba1c", "空腹血糖", "餐后血糖", "血脂", "胆固醇", "甘油三酯",
                     "低密度", "高密度", "ldl", "hdl", "alt", "ast", "转氨酶", "肝", "脂肪肝", "胆", "ggt", "胆红素", "代谢",
                     "糖尿病", "高血糖", "高血脂", "肝炎", "肝硬化", "胆囊炎", "胆结石", "胆囊切除",
                     "降糖", "降脂", "二甲双胍", "胰岛素", "他汀", "格列美脲", "格列齐特", "阿卡波糖", "护肝", "保肝"],
    },
    "water": {
        "name": "水·藏养", "stat": "体力",
        "keywords": ["肾", "肌酐", "尿素", "尿酸", "尿常规", "尿检", "尿蛋白", "蛋白尿", "尿潜血", "尿液", "egfr", "骨", "钙", "骨密度", "尿素氮",
                     "肾病", "肾功能", "肾炎", "痛风", "前列腺", "骨质疏松", "透析", "膀胱", "结石",
                     "利尿", "护肾", "降尿酸", "别嘌醇", "补钙", "钙片"],
    },
    "fire": {
        "name": "火·心脉", "stat": "灵力",
        "keywords": ["血压", "收缩压", "舒张压", "心率", "脉搏", "心电", "心电图", "心脏", "心血管", "冠脉", "心肌",
                     "高血压", "冠心病", "心脏病", "心律", "房颤", "心衰", "心梗", "支架", "脑梗", "脑卒中", "中风", "脑血管", "动脉硬化",
                     "降压", "护心", "抗凝", "抗血小板", "阿司匹林", "硝酸", "稳心", "氨氯地平", "硝苯地平", "美托洛尔", "缬沙坦", "厄贝沙坦", "卡托普利"],
    },
    "earth": {
        "name": "土·纳养", "stat": "气血",
        "keywords": ["bmi", "体重", "身高", "营养", "肌力", "胃", "白蛋白", "血红蛋白", "总蛋白", "红细胞", "白细胞", "血小板", "血常规",
                     "贫血", "胃炎", "胃溃疡", "消化不良", "消瘦", "浮肿", "甲状腺", "营养不良", "缺铁",
                     "护胃", "补铁", "补血", "蛋白粉", "助消化", "养胃"],
    },
}


def _match(text, keywords):
    t = (text or "").lower()
    return any(k in t for k in keywords)


def _known_items(document):
    """只保留能映射到五行关键词的「常规」指标，罕见/非常规指标舍去。"""
    known = []
    for it in _items(document):
        label = str(it.get("label") or "").lower()
        if any(_match(label, meta["keywords"]) for meta in ELEMENTS.values()):
            known.append(it)
    return known


def _condition_status(h):
    return str(h.get("status") or "unknown").strip().lower()


def compute_evidence(document):
    """把识别结果归一化为 0–100 的特征；未知特征用中性值 50。"""
    items = _known_items(document)
    history = _history_entries(document)
    medications = _medication_entries(document)
    field_count = len(items) + len(history) + len(medications)
    data_completeness = clamp(45 + min(field_count, 40) * 1.2, 45, 96)

    # 活动能力：默认中性；报告/病史明确出现活动受限等才下调，只影响建模，不作医学结论。
    narrative = " ".join(
        [str(document.get("clinical_notes") or ""), str(document.get("summary") or "")]
        + [str(v) for h in history for v in h.values()]
    )
    function_capacity = NEUTRAL
    if re.search(r"活动受限|行动困难|行走困难|卧床|无法自理|活动能力减退|偏瘫|瘫痪|坐轮椅|失能", narrative):
        function_capacity = 40

    return {
        "data_completeness": data_completeness,
        "plan_coverage": NEUTRAL,
        "family_support": NEUTRAL,
        "function_capacity": function_capacity,
        "routine_stability": NEUTRAL,
        "self_reported_energy": NEUTRAL,
        "knowledge_tasks": NEUTRAL,
        "tech_readiness": NEUTRAL,
    }


def compute_five_elements(document):
    """体检指标 + 病史 + 用药 共同决定五行主题；异常只触发护持任务，不扣属性。"""
    items = _known_items(document)
    history = _history_entries(document)
    medications = _medication_entries(document)
    five, notes, tasks = {}, {}, []

    for key, meta in ELEMENTS.items():
        kws = meta["keywords"]
        matched_items = [it for it in items if _match(it.get("label"), kws)]
        abnormal_items = [it for it in matched_items if _is_abnormal(it)]
        matched_hist = [h for h in history if _match(" ".join(str(v) for v in h.values()), kws)]
        matched_med = [m for m in medications if _match(" ".join(str(v) for v in m.values()), kws)]
        ongoing_hist = [h for h in matched_hist if _condition_status(h) != "past"]

        if abnormal_items or ongoing_hist:
            state, resonance = "needs_care", 46
            n = len(abnormal_items) + len(ongoing_hist)
            note = f"{meta['stat']} / {n} 项需关注（指标异常或持续病史），已生成护持任务"
            tasks.append({
                "task_id": f"care_{key}_001",
                "title": f"{meta['name']} 护持",
                "detail": f"核对 {n} 项相关指标/病史，整理复诊问题",
                "status": "pending",
            })
        elif matched_items or matched_hist or matched_med:
            state, resonance = "stable", 60
            note = f"{meta['stat']} / 相关指标、病史或用药在可控范围"
        else:
            state, resonance = "unknown", NEUTRAL
            note = f"{meta['stat']} / 平和"

        five[key] = {"state": state, "resonance": resonance}
        notes[key] = note

    return five, notes, tasks


_RANGE = {
    "hp_max": (80, 100), "attack": (20, 80), "defense": (20, 90), "spirit": (20, 85),
    "stamina": (20, 90), "insight": (20, 90), "mind": (20, 80), "speed": (20, 80), "luck": (50, 50),
}
# 五行 → 对应的游戏属性（见 MAPPING.md）
_ELEMENT_STAT = {"metal": "defense", "wood": "speed", "water": "stamina", "fire": "spirit", "earth": "hp_max"}
_DELTA = {"stable": 6, "needs_care": -4, "unknown": 0}


def compute_character_state(ev, five):
    """按证据特征计算 10 个游戏属性，五行状态轻微修正对应属性（不扣成残血）。"""
    f = ev
    engagement = NEUTRAL
    state = {
        "hp_max": clamp(80 + 0.25 * f["function_capacity"] + 0.15 * f["data_completeness"], 80, 100),
        "attack": clamp(20 + 0.25 * f["function_capacity"] + 0.20 * f["routine_stability"] + 0.10 * f["family_support"], 20, 80),
        "defense": clamp(20 + 0.35 * f["plan_coverage"] + 0.25 * f["family_support"], 20, 90),
        "spirit": clamp(20 + 0.30 * f["data_completeness"] + 0.20 * f["routine_stability"] + 0.15 * f["plan_coverage"], 20, 85),
        "stamina": clamp(20 + 0.45 * f["function_capacity"] + 0.10 * f["self_reported_energy"], 20, 90),
        "insight": clamp(20 + 0.45 * f["data_completeness"] + 0.20 * f["knowledge_tasks"], 20, 90),
        "mind": clamp(20 + 0.40 * f["family_support"] + 0.20 * engagement, 20, 80),
        "speed": clamp(20 + 0.35 * f["function_capacity"] + 0.20 * f["tech_readiness"], 20, 80),
        "luck": NEUTRAL,
    }
    for ek, sk in _ELEMENT_STAT.items():
        st = (five.get(ek) or {}).get("state", "unknown")
        lo, hi = _RANGE[sk]
        state[sk] = clamp(state[sk] + _DELTA.get(st, 0), lo, hi)
    state["hp_current"] = state["hp_max"]
    return state


def estimate_confidence(document):
    """用未知字段占比估算整体置信度（模型未直接给 confidence 时使用）。"""
    items = _known_items(document)
    history = _history_entries(document)
    meds = _medication_entries(document)
    signals = len(items) + len(history) + len(meds)
    if not signals:
        return 60
    unknown = sum(1 for it in items if _status(it) in _UNKNOWN)
    return clamp(88 - (unknown / signals) * 30, 55, 96)


def build_projection(document):
    """识别结果 → 前端可合并的 game_projection。"""
    ev = compute_evidence(document)
    five, notes, tasks = compute_five_elements(document)
    character_state = compute_character_state(ev, five)
    readiness = clamp(0.45 * ev["data_completeness"] + 0.30 * ev["plan_coverage"] + 0.25 * ev["family_support"], 30, 99)

    evidence_out = {k: ev[k] for k in (
        "data_completeness", "plan_coverage", "family_support", "function_capacity",
        "routine_stability", "self_reported_energy", "knowledge_tasks", "tech_readiness",
    )}
    return {
        "evidence": evidence_out,
        "character_state": character_state,
        "five_elements": five,
        "element_notes": notes,
        "tasks": tasks,
        "readiness": readiness,
    }
