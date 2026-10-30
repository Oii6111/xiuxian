"""健康资料 → 游戏初始状态的确定性规则引擎。

原则：
- 识别由 LLM 完成，数值只由这里的确定性规则计算，LLM 不直接写 XP/战力/境界。
- 只采用「常规」健康资料：体检指标按身体系统关键词白名单筛选，罕见/非常规专科指标自动舍去。
- 每个身体系统直接对应一个游戏属性，用识别出的具体指标 / 病史 / 用药测算该属性：
  正常指标 +4、异常指标 −6、持续病史 −5、正在用药 +3，在系统基础分上加减。
- 未知特征用中性值；异常只做小幅调整，不把老人角色写成残血。

完整的字段筛选与映射说明见同目录 MAPPING.md。
"""
import re

NEUTRAL = 50

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


def _condition_status(h):
    return str(h.get("status") or "unknown").strip().lower()


# 核心对应关系：身体系统 → 游戏属性 + 关键词（覆盖体检指标、病史、用药）。
# 「识别出什么数据 → 影响哪个属性」只由这张表决定，改对应关系只改这里。
SYSTEMS = [
    {
        "name": "心脑血管", "attr": "spirit", "label": "灵力", "base": 50,
        "keywords": ["血压", "收缩压", "舒张压", "心率", "脉搏", "心电", "心电图", "心脏", "心血管", "冠脉", "心肌",
                     "高血压", "冠心病", "心脏病", "心律", "房颤", "心衰", "心梗", "支架", "脑梗", "脑卒中", "中风", "脑血管", "动脉硬化",
                     "降压", "护心", "抗凝", "抗血小板", "阿司匹林", "硝酸", "稳心", "氨氯地平", "硝苯地平", "美托洛尔", "缬沙坦", "厄贝沙坦", "卡托普利"],
    },
    {
        "name": "呼吸系统", "attr": "defense", "label": "防御", "base": 50,
        "keywords": ["血氧", "氧", "呼吸", "肺", "胸片", "肺功能", "呼吸频率",
                     "哮喘", "慢阻肺", "copd", "支气管炎", "肺炎", "肺气肿", "支气管扩张", "肺结节", "打鼾", "睡眠呼吸暂停",
                     "止咳", "平喘", "化痰", "吸入", "雾化", "沙丁胺醇", "布地奈德"],
    },
    {
        "name": "泌尿骨骼", "attr": "stamina", "label": "体力", "base": 50,
        "keywords": ["肾", "肌酐", "尿素", "尿酸", "尿常规", "尿检", "尿蛋白", "蛋白尿", "尿潜血", "尿液", "egfr", "骨", "钙", "骨密度", "尿素氮",
                     "肾病", "肾功能", "肾炎", "痛风", "前列腺", "骨质疏松", "透析", "膀胱", "结石",
                     "利尿", "护肾", "降尿酸", "别嘌醇", "补钙", "钙片"],
    },
    {
        "name": "代谢糖脂", "attr": "speed", "label": "身法", "base": 50,
        "keywords": ["血糖", "糖化", "hba1c", "空腹血糖", "餐后血糖", "血脂", "胆固醇", "甘油三酯",
                     "低密度", "高密度", "ldl", "hdl", "alt", "ast", "转氨酶", "肝", "脂肪肝", "胆", "ggt", "胆红素", "代谢",
                     "糖尿病", "高血糖", "高血脂", "肝炎", "肝硬化", "胆囊炎", "胆结石", "胆囊切除",
                     "降糖", "降脂", "二甲双胍", "胰岛素", "他汀", "格列美脲", "格列齐特", "阿卡波糖", "护肝", "保肝"],
    },
    {
        "name": "营养血象", "attr": "hp_max", "label": "气血", "base": 80,
        "keywords": ["bmi", "体重", "身高", "营养", "肌力", "胃", "白蛋白", "血红蛋白", "总蛋白", "红细胞", "白细胞", "血小板", "血常规",
                     "贫血", "胃炎", "胃溃疡", "消化不良", "消瘦", "浮肿", "甲状腺", "营养不良", "缺铁",
                     "护胃", "补铁", "补血", "蛋白粉", "助消化", "养胃"],
    },
]

_ATTR_RANGE = {
    "hp_max": (40, 100), "attack": (20, 80), "defense": (20, 90), "spirit": (20, 85),
    "stamina": (20, 90), "insight": (20, 90), "mind": (20, 80), "speed": (20, 80), "luck": (50, 50),
}


def _match(text, keywords):
    t = (text or "").lower()
    return any(k in t for k in keywords)


def _known_items(document):
    """只保留能命中身体系统关键词的「常规」指标，罕见/非常规指标舍去。"""
    known = []
    for it in _items(document):
        label = str(it.get("label") or "").lower()
        if any(_match(label, sys["keywords"]) for sys in SYSTEMS):
            known.append(it)
    return known


def compute_evidence(document):
    """归一化 0–100 的证据特征（资料完整度、活动能力等）。"""
    items = _known_items(document)
    history = _history_entries(document)
    medications = _medication_entries(document)
    field_count = len(items) + len(history) + len(medications)
    data_completeness = clamp(45 + min(field_count, 40) * 1.2, 45, 96)

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


def compute_system_scores(document):
    """用具体指标 / 病史 / 用药测算每个身体系统对应的属性。

    每个系统 = base + 正常指标×4 − 异常指标×6 − 持续病史×5 + 正在用药×3。
    返回 (scores, notes)：scores 是 attr→分数，notes 是 attr→具体由哪些数据算出。
    """
    items = _known_items(document)
    history = _history_entries(document)
    medications = _medication_entries(document)
    scores, notes = {}, {}
    for sys in SYSTEMS:
        attr = sys["attr"]
        matched = [it for it in items if _match(it.get("label"), sys["keywords"])]
        abnormal = [it for it in matched if _is_abnormal(it)]
        normal = [it for it in matched if not _is_abnormal(it)]
        hist = [h for h in history if _match(" ".join(str(v) for v in h.values()), sys["keywords"])]
        ongoing = [h for h in hist if _condition_status(h) != "past"]
        meds = [m for m in medications if _match(" ".join(str(v) for v in m.values()), sys["keywords"])]

        score = sys["base"] + 4 * len(normal) - 6 * len(abnormal) - 5 * len(ongoing) + 3 * len(meds)
        scores[attr] = score

        parts = []
        for it in abnormal:
            parts.append(f"{it.get('label', '指标')}异常 −6")
        for it in normal:
            parts.append(f"{it.get('label', '指标')}正常 +4")
        for h in ongoing:
            parts.append(f"{h.get('condition', '病史')}病史 −5")
        for m in meds:
            parts.append(f"{m.get('name', '用药')} +3")
        notes[attr] = f"{sys['label']} = {score}（" + ("、".join(parts) if parts else f"无相关常规数据，中性 {sys['base']}") + "）"
    return scores, notes


def compute_character_state(ev, scores):
    """按身体系统得分计算对应属性，其余属性由证据特征计算。"""
    f = ev
    state = {
        "attack": clamp(25 + 0.5 * f["function_capacity"], 20, 80),
        "insight": clamp(20 + 0.45 * f["data_completeness"] + 0.20 * f["knowledge_tasks"], 20, 90),
        "mind": clamp(30 + 0.40 * f["family_support"], 20, 80),
        "luck": NEUTRAL,
    }
    for sys in SYSTEMS:
        attr = sys["attr"]
        lo, hi = _ATTR_RANGE[attr]
        state[attr] = clamp(scores.get(attr, NEUTRAL), lo, hi)
    state["hp_current"] = state["hp_max"]
    return state


def estimate_confidence(document):
    """用未知字段占比估算整体置信度。"""
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
    scores, notes = compute_system_scores(document)
    character_state = compute_character_state(ev, scores)
    readiness = clamp(0.45 * ev["data_completeness"] + 0.30 * ev["plan_coverage"] + 0.25 * ev["family_support"], 30, 99)

    evidence_out = {k: ev[k] for k in (
        "data_completeness", "plan_coverage", "family_support", "function_capacity",
        "routine_stability", "self_reported_energy", "knowledge_tasks", "tech_readiness",
    )}
    return {
        "evidence": evidence_out,
        "character_state": character_state,
        "attribute_notes": notes,
        "readiness": readiness,
    }
