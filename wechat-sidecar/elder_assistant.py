"""老人端健康助手：微信消息编排、确认式记录和生活建议。

这个模块故意与游戏 UI 解耦：老人侧只接收聊天、语音、图片、提醒和生活建议，
不会返回任何“修仙/属性/任务”字段。确认后的结构化健康事件可以通过可选的
HEALTH_EVENT_SINK_URL 转发给家庭端或其它内部系统。

安全边界：
* 先做本地红旗症状拦截，再考虑调用 LLM；LLM 不负责创建健康事件。
* 图片识别只产生“候选事实”，必须让老人确认后才写入事件表。
* 不根据药盒照片推断剂量，不建议停药、加药、换药；药品信息不清晰时要求重拍。
* 只保存结构化摘要和图片哈希，不在本地数据库保存原始图片。

可选的 OpenClaw Gateway 只作为对话润色层，配置 OPENCLAW_GATEWAY_URL 后启用；
未配置时仍可用确定性的 demo 回复跑通全流程。
"""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import random
import re
import sqlite3
import time
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import requests
from flask import jsonify, request

import model_provider
import medical_rag
import recognizer


BASE_DIR = Path(__file__).resolve().parent
DB_PATH = Path(os.environ.get("ELDER_DB_PATH", str(BASE_DIR / "bot_data" / "elder_assistant.sqlite3")))
POLICY_PATH = Path(os.environ.get("HEALTH_POLICY_PATH", str(BASE_DIR / "knowledge" / "health_policy_demo.json")))


def _now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def _new_id(prefix: str) -> str:
    return f"{prefix}_{time.strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:8]}"


def _json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def _load_json(value: Optional[str], default: Any) -> Any:
    if not value:
        return default
    try:
        return json.loads(value)
    except (TypeError, ValueError):
        return default


@contextmanager
def _db():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(DB_PATH), timeout=10)
    conn.row_factory = sqlite3.Row
    try:
        with conn:
            yield conn
    finally:
        conn.close()


def init_db() -> None:
    with _db() as conn:
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS sessions (
                session_id TEXT PRIMARY KEY,
                elder_id TEXT NOT NULL,
                channel TEXT NOT NULL,
                sender_id TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS pending_events (
                event_id TEXT PRIMARY KEY,
                elder_id TEXT NOT NULL,
                session_id TEXT NOT NULL,
                event_type TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                summary TEXT NOT NULL,
                risk_level TEXT NOT NULL,
                family_share INTEGER NOT NULL DEFAULT 0,
                status TEXT NOT NULL DEFAULT 'pending_confirmation',
                created_at TEXT NOT NULL,
                expires_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS health_events (
                event_id TEXT PRIMARY KEY,
                elder_id TEXT NOT NULL,
                event_type TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                risk_level TEXT NOT NULL,
                family_share INTEGER NOT NULL DEFAULT 0,
                source TEXT NOT NULL,
                created_at TEXT NOT NULL,
                synced_at TEXT
            );
            CREATE TABLE IF NOT EXISTS reminders (
                reminder_id TEXT PRIMARY KEY,
                elder_id TEXT NOT NULL,
                label TEXT NOT NULL,
                schedule_json TEXT NOT NULL,
                enabled INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS medication_courses (
                course_id TEXT PRIMARY KEY,
                elder_id TEXT NOT NULL,
                drug_name TEXT NOT NULL,
                duration_days INTEGER,
                times_per_day TEXT,
                when_take TEXT,
                start_date TEXT,
                end_date TEXT,
                status TEXT NOT NULL DEFAULT 'pending_duration',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS family_links (
                link_id TEXT PRIMARY KEY,
                elder_id TEXT NOT NULL,
                family_user_id TEXT NOT NULL,
                code TEXT NOT NULL UNIQUE,
                status TEXT NOT NULL DEFAULT 'pending',
                created_at TEXT NOT NULL,
                expires_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS memory_facts (
                elder_id TEXT NOT NULL,
                key TEXT NOT NULL,
                value TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                PRIMARY KEY (elder_id, key)
            );
            CREATE TABLE IF NOT EXISTS chat_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                elder_id TEXT NOT NULL,
                role TEXT NOT NULL,
                text TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_chat_elder ON chat_history(elder_id, id);
            CREATE INDEX IF NOT EXISTS idx_pending_elder ON pending_events(elder_id, status);
            CREATE INDEX IF NOT EXISTS idx_events_elder ON health_events(elder_id, created_at);
            CREATE INDEX IF NOT EXISTS idx_reminders_elder ON reminders(elder_id, enabled);
            CREATE INDEX IF NOT EXISTS idx_courses_elder ON medication_courses(elder_id, status);
            """
        )


def _policy_rows() -> List[Dict[str, Any]]:
    try:
        raw = json.loads(POLICY_PATH.read_text(encoding="utf-8"))
        return raw if isinstance(raw, list) else []
    except (OSError, ValueError):
        return []


def retrieve_policies(query: str, limit: int = 3) -> List[Dict[str, Any]]:
    """轻量 demo 检索；生产环境替换为 BM25 + 向量检索，并保留来源版本。"""
    text = (query or "").lower()
    scored: List[Tuple[int, Dict[str, Any]]] = []
    for row in _policy_rows():
        keywords = [str(v).lower() for v in (row.get("keywords") or [])]
        score = sum(1 for word in keywords if word and word in text)
        if score:
            scored.append((score, row))
    scored.sort(key=lambda item: item[0], reverse=True)
    return [row for _, row in scored[:limit]]


_EMERGENCY_PATTERNS = [
    (r"胸痛|胸口剧痛|胸闷加重|压榨感", "可能存在需要马上处理的胸部不适"),
    (r"呼吸困难|喘不上气|憋气|口唇发紫", "可能存在严重呼吸不适"),
    (r"昏迷|叫不醒|失去意识|突然倒地", "意识状态异常"),
    (r"嘴歪|脸歪|说话含糊|一侧无力|手脚无力|突然看不清", "可能存在突发神经系统症状"),
    (r"大出血|止不住血|呕血|黑便", "可能存在明显出血"),
    (r"严重过敏|喉咙肿|舌头肿|全身起疹.*喘", "可能存在严重过敏反应"),
]

_URGENT_PATTERNS = [
    r"高烧不退|持续呕吐|反复晕厥|明显脱水|严重头痛|意识模糊",
]


def detect_risk(text: str) -> Tuple[str, Optional[str]]:
    value = str(text or "").strip()
    for pattern, reason in _EMERGENCY_PATTERNS:
        if re.search(pattern, value, re.I):
            return "emergency", reason
    if any(re.search(pattern, value, re.I) for pattern in _URGENT_PATTERNS):
        return "urgent", "症状需要尽快联系家属或医疗机构确认"
    return "routine", None


def _source_hash(attachment: Dict[str, Any]) -> str:
    raw = str(attachment.get("data_url") or attachment.get("url") or "")
    return hashlib.sha256(raw.encode("utf-8", errors="ignore")).hexdigest()[:16]


def _safe_attachments(value: Any) -> List[Dict[str, Any]]:
    if not isinstance(value, list):
        return []
    out: List[Dict[str, Any]] = []
    for item in value[:6]:
        if not isinstance(item, dict):
            continue
        kind = str(item.get("kind") or "image").lower()
        data_url = str(item.get("data_url") or "")
        if data_url and len(data_url) > 16 * 1024 * 1024:
            continue
        out.append(
            {
                "kind": kind,
                "filename": str(item.get("filename") or "资料"),
                "mime_type": str(item.get("mime_type") or ""),
                "document_type": str(item.get("document_type") or "").lower(),
                "data_url": data_url,
                # 允许 OpenClaw 适配器传入已经完成的语音转写；不保存音频本体。
                "transcript": str(item.get("transcript") or "").strip(),
            }
        )
    return out


def _extract_measurements(text: str) -> Dict[str, Any]:
    value = str(text or "")
    facts: Dict[str, Any] = {}
    match = re.search(r"(?:血压|bp)\s*[:：]?\s*(\d{2,3})\s*[/／]\s*(\d{2,3})", value, re.I)
    if match:
        facts["blood_pressure"] = {"systolic": int(match.group(1)), "diastolic": int(match.group(2)), "unit": "mmHg"}
    glucose = re.search(r"(?:血糖|空腹血糖|餐后血糖)\s*[:：]?\s*(\d+(?:\.\d+)?)\s*(mmol/L)?", value, re.I)
    if glucose:
        facts["blood_glucose"] = {"value": float(glucose.group(1)), "unit": glucose.group(2) or "mmol/L"}
    pulse = re.search(r"(?:心率|脉搏)\s*[:：]?\s*(\d{2,3})\s*(?:次/分|bpm)?", value, re.I)
    if pulse:
        facts["pulse"] = {"value": int(pulse.group(1)), "unit": "次/分"}
    return facts


# 判断“老人重新说一种药”的措辞：_intent 与用药疗程补全共用，避免两处正则不一致。
# 注意：不含“吃的是”——“吃的是面条/米饭”是饭不是药，得和“吃的是阿莫西林”区分开。
_MEDICATION_STATEMENT_RE = r"在吃|吃着|一直吃|还在吃|正在吃|药是|医生.{0,6}开.{0,6}药|要吃.{0,3}天|疗程|连吃"

# 老人说“药吃完了/停药了”等：作废还在提醒的疗程，别再提醒（先于 meal_log 判断）。
_MEDICATION_STOP_RE = r"药吃完了|药吃没了|停药|药停了|药不吃了|不吃.{0,3}药|.{0,3}药.{0,3}不吃了"

# “吃的是X”里 X 落进这些常见食物时，当成记一顿饭，而不是误开一个疗程。
_COMMON_FOODS = frozenset({
    "饭", "米饭", "面条", "面", "馒头", "包子", "饺子", "馄饨", "粥", "菜", "青菜", "白菜",
    "肉", "鱼", "蛋", "鸡蛋", "豆腐", "水果", "苹果", "香蕉", "汤", "火锅", "烧烤", "点心",
})


def _intent(text: str, attachments: List[Dict[str, Any]]) -> str:
    value = str(text or "").strip()
    if attachments and all(str(a.get("kind") or "").lower() in {"voice", "audio"} for a in attachments):
        if value:
            return _intent(value, [])
        return "voice"
    if attachments:
        return "photo_review"
    if re.search(r"提醒|闹钟|几点|时间到了|药还没吃", value):
        return "reminder_help"
    if re.search(r"吃过药|吃完药|药吃了|已经服药|按时服药|刚吃药", value):
        return "medication_taken"
    if re.search(_MEDICATION_STATEMENT_RE, value):
        return "medication_course"
    # “吃的是X”：X 是药名（如阿莫西林）→ 疗程；X 是常见食物（如面条）→ 记一顿饭。
    m = re.search(r"吃的是\s*([^\s，。,.？?！]{1,20})", value)
    if m and m.group(1).strip() not in _COMMON_FOODS:
        return "medication_course"
    if re.search(_MEDICATION_STOP_RE, value):
        return "medication_stop"
    if re.search(r"吃了|吃过|刚吃|吃的是|吃完了", value):
        return "meal_log"
    if _extract_measurements(value):
        return "measurement"
    if re.search(r"晕|眩|发飘|走不稳|站不稳|没力气|乏力|恶心|咳嗽|疼|痛|不舒服|难受|发热|睡不着", value):
        return "symptom"
    if re.search(r"火锅|烧烤|饮酒|吃什么|吃饭|晚饭|午饭|早餐|菜|水果|甜|咸", value):
        return "lifestyle"
    return "chat"


def _quick_replies(intent: str, risk_level: str = "routine") -> List[Dict[str, str]]:
    if risk_level == "emergency":
        return [{"label": "我已联系急救", "value": "已联系急救"}, {"label": "联系子女", "value": "联系子女"}]
    if intent == "medication_taken":
        return [{"label": "是，吃了", "value": "confirm"}, {"label": "还没吃", "value": "reject"}]
    if intent == "meal_log":
        return [{"label": "对，记下", "value": "confirm"}, {"label": "不用记", "value": "reject"}]
    if intent == "photo_review":
        return [{"label": "对", "value": "confirm"}, {"label": "不对", "value": "reject"}]
    if intent == "measurement":
        return [{"label": "对，记下", "value": "confirm"}, {"label": "再量一次", "value": "reject"}]
    return [{"label": "好的", "value": "好的"}, {"label": "联系家人", "value": "联系家人"}]


# 老人端人设：先像家人朋友一样正常聊天，别每句都追问身体。
_ELDER_PERSONA = (
    "你是陪老人聊天的小助手，先像家人朋友一样正常聊天，用短句，亲切自然。"
    "老人问什么，就直接、清楚地回答什么；手里有照片/体检/药盒识别出的信息，就照着事实说，不要说自己“看不清/看个大概/不一定准”。"
    "不要主动说药是干什么用的，等老人问“干什么用/治什么”再说。"
    "结尾不要加“对就说对/不对就说不对/是否确认”这类话。"
    "别每句都加“听医生的/遵医嘱/别自己加量减量”这类套话；只有情况危险时才提醒打 120 或联系家人。"
    "记忆里记着的“最近不舒服/在吃的药”是之前聊过的，除非老人这次又主动提起来，否则别每回都翻出来追问。"
    "老人只是打招呼、闲聊、问你是谁，就轻松回应，别急着问身体。"
    "被问“你是谁/是什么模型”时，就说“我就是陪你说话的小助手”，说完顺着对方刚才的话题聊，别转去问身体。"
    "别用“记录、确认、候选、事件、摘要、整理”这类后台词，别像填表。"
    "可以偶尔用“呀、啦、呢、嘞”显得亲近，但别太腻。"
    "不下诊断、不改药/停药/加药、不凭药盒猜剂量。"
    "不聊游戏、修仙、属性、任务。"
)

# 没有模型时的确定性兜底，随机换着说，避免每次都一句机械话。
_DEFAULT_WARM_REPLIES = [
    "你好呀，我在这儿呢。想聊点什么？",
    "在呢，你说，我听着。",
    "哎，你来啦。随便聊聊，不用那么正式。",
]


def _emergency_reply(reason: Optional[str]) -> str:
    return (
        f"我听到你说“{reason or '有比较严重的不舒服'}”。现在先别等聊天回复，马上请身边的人拨打 120，"
        "或到最近的急诊；不要自己开车。若能做到，请把门打开、坐下或侧躺，并把正在吃的药交给家人。"
    )


def _default_lifestyle_reply(text: str, policies: List[Dict[str, Any]], known_context: Optional[List[Dict[str, Any]]] = None) -> str:
    value = str(text or "")
    context = known_context or []
    has_high_bp = False
    for item in context:
        raw_facts = item.get("facts") if isinstance(item, dict) else None
        bp = raw_facts.get("blood_pressure") if isinstance(raw_facts, dict) else None
        if isinstance(bp, dict) and isinstance(bp.get("systolic"), (int, float)) and bp["systolic"] >= 140:
            has_high_bp = True
            break
    has_glucose = any(
        "blood_glucose" in (item.get("facts") or {})
        for item in context
        if isinstance(item.get("facts"), dict)
    )
    if re.search(r"火锅|烧烤|咸|重口", value):
        if has_high_bp:
            return (
                "可以吃一点，今天给你一个小交换：汤和蘸料少一点，先吃蔬菜，慢慢吃。"
                "我看到你最近记录过血压偏高，但不会替你改药；饮水量按医生原来的方案来。"
            )
        return (
            "可以吃一点，给你一个不扫兴的小办法：先吃蔬菜和清汤，蘸料少放盐，慢慢吃；"
            "如果医生以前交代过限盐、限水或有特殊饮食要求，以医生的方案为准。"
        )
    if re.search(r"饮酒|酒", value):
        return "今天就先少喝点。如果正在吃药或最近不太舒服，先问下家人或医生能不能喝；喝点茶水代替也行。"
    if re.search(r"吃什么|吃饭|晚饭|午饭|早餐|菜|水果", value):
        if has_glucose:
            return "拍张饭菜的照片我看看呀。今天饮料先选无糖的，药和活动还按医生原来说的来，不用自己改。"
        return "拍张饭菜的照片我看看呀，帮你瞧瞧哪样能多吃、哪样少一点，不用称克数。"
    if policies:
        return str(policies[0].get("elder_reply") or policies[0].get("text") or "我记住啦，按平时医生交代的来。")
    return random.choice(_DEFAULT_WARM_REPLIES)


def _prompt_for_gateway(
    text: str,
    facts: Dict[str, Any],
    policies: List[Dict[str, Any]],
) -> str:
    citations = [
        {"title": p.get("title"), "source": p.get("source"), "text": p.get("text"), "caution": p.get("caution")}
        for p in policies
    ]
    return (
        _ELDER_PERSONA + "\n"
        "给建议时优先给一个马上能做的小动作，同时医生交代过的限制（比如限盐/限水）优先。\n"
        f"用户原话：{text}\n已确认事实：{_json(facts)}\n参考规则：{_json(citations)}\n"
        "直接说给老人听的话就行，别输出别的。"
    )


def _call_openclaw(text: str, facts: Dict[str, Any], policies: List[Dict[str, Any]], elder_id: str) -> Optional[str]:
    base = os.environ.get("OPENCLAW_GATEWAY_URL", "").strip().rstrip("/")
    token = os.environ.get("OPENCLAW_GATEWAY_TOKEN", "").strip()
    if not base or not token:
        return None
    body = {
        "model": os.environ.get("OPENCLAW_MODEL", "openclaw/elder-health"),
        "user": f"elder:{elder_id}",
        "messages": [
            {"role": "system", "content": _ELDER_PERSONA},
            {"role": "user", "content": _prompt_for_gateway(text, facts, policies)},
        ],
        "temperature": 0.2,
    }
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "x-openclaw-message-channel": "openclaw-weixin",
    }
    agent_id = os.environ.get("OPENCLAW_AGENT_ID", "elder-health").strip()
    if agent_id:
        headers["x-openclaw-agent-id"] = agent_id
    try:
        response = requests.post(f"{base}/v1/chat/completions", headers=headers, json=body, timeout=30)
        if response.status_code != 200:
            return None
        payload = response.json()
        content = payload.get("choices", [{}])[0].get("message", {}).get("content")
        if isinstance(content, list):
            content = "".join(str(part.get("text", "")) for part in content if isinstance(part, dict))
        if isinstance(content, str) and content.strip():
            return content.strip()[:1200]
    except (OSError, requests.RequestException, ValueError, KeyError, IndexError):
        return None
    return None


# ---- 多模型路由：图片→Qwen-VL（recognizer 已做），医疗文本→DeepSeek，闲聊→DeepSeek ----

def _route_for(intent: str) -> str:
    if intent in {"symptom", "photo_review"}:
        return "medical"
    return "chat"


def _chat_config(route: str) -> Tuple[Optional[str], Optional[str], str, float]:
    """按路由取模型配置，统一走 model_provider.text_config()。"""
    return model_provider.text_config(route)


def _build_user_prompt(text: str, facts: Dict[str, Any], policies: List[Dict[str, Any]], memory_text: str, history_text: str = "") -> str:
    citations = [
        {"title": p.get("title"), "source": p.get("source"), "text": p.get("text"), "caution": p.get("caution")}
        for p in policies
    ]
    parts = [f"用户原话：{text}", f"已确认事实：{_json(facts)}"]
    if memory_text:
        parts.append(f"你对他/她已有的记忆：\n{memory_text}")
    if history_text:
        parts.append(f"最近几轮对话：\n{history_text}")
    parts.append(f"参考规则：{_json(citations)}")
    parts.append("直接说给老人听的话，用短句。")
    return "\n".join(parts)


def _openai_chat(base_url: str, api_key: str, model: str, system: str, user: str, temperature: float) -> Optional[str]:
    content = model_provider.chat(
        base_url, api_key, model,
        [{"role": "system", "content": system}, {"role": "user", "content": user}],
        temperature,
    )
    return content.strip()[:2000] if isinstance(content, str) and content.strip() else None


def _call_route(route: str, text: str, facts: Dict[str, Any], policies: List[Dict[str, Any]], elder_id: str, memory_text: str = "") -> Optional[str]:
    """按路由调用文本模型；默认关闭，需 HEALTH_CHAT_ENABLED=true。"""
    if os.environ.get("HEALTH_CHAT_ENABLED", "false").lower() not in {"1", "true", "yes", "on"}:
        return None
    base, key, model, temp = _chat_config(route)
    system = _ELDER_PERSONA
    if route == "medical":
        system = _ELDER_PERSONA + "这段是医疗内容：回答要准确、说人话，别加“听医生的/遵医嘱”这类套话；不诊断、不替代医生。"
    history_text = ""
    turns = _recent_turns(elder_id, limit=6)
    if turns:
        history_text = "\n".join(f"{'老人' if role == 'user' else '助手'}：{t}" for role, t in turns)
    return _openai_chat(base or "", key or "", model, system, _build_user_prompt(text, facts, policies, memory_text, history_text), temp)


def _recognized_meds(facts: Dict[str, Any]) -> List[Dict[str, str]]:
    """把视觉识别出的药品整理成 [{label, purpose}]；读不出药名就返回空。"""
    meds: List[Dict[str, str]] = []
    doc = facts.get("medical_document") if isinstance(facts.get("medical_document"), dict) else {}
    for m in (doc.get("medications") or []):
        if not isinstance(m, dict):
            continue
        name = str(m.get("name") or "").strip()
        if not name:
            continue
        brand = str(m.get("brand") or "").strip()
        purpose = str(m.get("purpose") or "").strip()
        label = f"{brand}（{name}）" if brand and brand != name else name
        meds.append({"label": label, "purpose": purpose})
    cand = facts.get("medication_candidate") if isinstance(facts.get("medication_candidate"), dict) else {}
    for m in (cand.get("items") or []):
        if not isinstance(m, dict):
            continue
        name = str(m.get("generic_name") or m.get("brand_name") or "").strip()
        if name:
            meds.append({"label": name, "purpose": ""})
    return meds


def _photo_reply(facts: Dict[str, Any]) -> Optional[str]:
    """照片识别成功后直接、自然地把药名念出来：不啰嗦、不追确认、不说用途（用途等老人问再说）。"""
    meds = _recognized_meds(facts)
    if meds:
        names = "、".join(m["label"] for m in meds)
        return f"这是{names}。"
    doc = facts.get("medical_document") if isinstance(facts.get("medical_document"), dict) else {}
    summary = str(doc.get("summary") or "").strip()
    if summary:
        return f"这上面是：{summary}"
    return None


def _meds_purpose_reply(meds: List[Dict[str, str]]) -> Optional[str]:
    """老人问“干什么用/治什么”时，优先按医学词典答，词典没有就用识别出的用途。"""
    parts = []
    for m in meds:
        label = str(m.get("label") or "").strip()
        if not label:
            continue
        kb_purpose = medical_rag.purpose_of(label)
        if kb_purpose:
            parts.append(f"{label}是{kb_purpose}")
            continue
        purpose = str(m.get("purpose") or "").split("（")[0].split("(")[0].strip("，。 ")
        if purpose:
            parts.append(f"{label}是{purpose}的")
    if not parts:
        return None
    return "，".join(parts) + "。"


def _kb_answer(text: str, recalled_meds: List[Dict[str, str]]) -> Optional[str]:
    """医学小词典（轻量 RAG）：药用途 + 疾病科普，命中就按词典准确答，不靠模型现编。"""
    # 1) 问“这药/某药干什么用”：优先最近识别出的药（词典兜底），再按文本里的药名查词典。
    if re.search(r"干什么用|什么用|治什么|治啥|干嘛用|有什么用|作用|功效|主治", text):
        reply = _meds_purpose_reply(recalled_meds)
        if reply:
            return reply
        name, entry = medical_rag.lookup_drug(text)
        if name:
            return medical_rag.drug_purpose_reply(name, entry)
    # 2) 问疾病基本信息：文本里出现病名 + 像在问/想了解，就按词典科普。
    name, entry = medical_rag.lookup_disease(text)
    if name and re.search(r"是什么|什么是|什么意思|啥意思|要注意|注意什么|怎么办|严重|要紧|危险|能治|会不会|科普|讲讲|该咋办|有啥影响", text):
        return medical_rag.disease_reply(name, entry)
    return None


def _recall_meds(elder_id: str) -> List[Dict[str, str]]:
    """取回最近一次照片识别出的药（含用途），供“干什么用”追问直接回答。"""
    raw = _recall(elder_id).get("最近识别的药", "")
    if not raw:
        return []
    try:
        meds = json.loads(raw)
        if isinstance(meds, list):
            return [m for m in meds if isinstance(m, dict)]
    except ValueError:
        return []
    return []


def _recognize_photo(attachments: List[Dict[str, Any]], text: str) -> Tuple[Dict[str, Any], str, Optional[str]]:
    """返回 (facts, status, error)。status 为 recognized / needs_model / failed。"""
    images = [
        a for a in attachments
        if a.get("data_url") and (a.get("kind") in {"image", "photo"} or str(a.get("mime_type", "")).startswith("image/"))
    ]
    if not images:
        # OpenClaw 的语音消息常带 transcript；没有转写就不假装听懂。
        transcript = " ".join(a.get("transcript", "") for a in attachments if a.get("transcript"))
        if transcript:
            return {"voice_transcript": transcript}, "no_media", None
        if attachments:
            if any(a.get("kind") == "file" for a in attachments):
                return {"media_count": len(attachments)}, "unsupported_media", "这个文件我先收着了，不过我现在只会看图片；麻烦把报告或药盒拍成照片发给我。"
            return {"media_count": len(attachments)}, "unsupported_media", "目前请把报告或药盒拍成图片发送"
        return {}, "no_media", None
    urls = [a["data_url"] for a in images]
    media_meta = {"media_count": len(images), "media_hashes": [_source_hash(a) for a in images]}
    document_type = " ".join([str(a.get("document_type") or "") for a in images] + [text]).lower()
    try:
        if re.search(r"药盒|药品|药物|说明书|medicine|medication", document_type):
            result = recognizer.recognize_medication_image(urls, filename=images[0].get("filename", "medication"))
            return {**media_meta, "medication_candidate": result}, "recognized", None
        result = recognizer.recognize_medical_report(urls, filename=images[0].get("filename", "health"))
        return {**media_meta, "medical_document": result}, "recognized", None
    except RuntimeError as exc:
        # 没有配置模型时返回可理解的状态，不伪造识别结果。
        if "未配置" in str(exc):
            return media_meta, "needs_model", str(exc)
        return media_meta, "failed", str(exc)
    except Exception as exc:  # noqa: BLE001
        return media_meta, "failed", str(exc)


def _candidate_from_intent(intent: str, text: str, facts: Dict[str, Any], recognition_status: str) -> Optional[Dict[str, Any]]:
    if intent == "medication_taken":
        return {"event_type": "medication_taken", "facts": {"statement": "用户表示已服药", **facts}, "summary": "记录今天已按你说的完成服药"}
    if intent == "meal_log":
        return {"event_type": "meal_log", "facts": {"meal": text}, "summary": "记录你刚才说的这顿饭吃了什么"}
    if intent == "measurement" and facts:
        return {"event_type": "measurement", "facts": facts, "summary": "记录你刚才报出的测量结果"}
    if intent == "photo_review" and recognition_status == "recognized":
        return {"event_type": "photo_observation", "facts": facts, "summary": "记录这次照片识别出的健康资料候选信息"}
    if intent == "symptom":
        return {"event_type": "symptom_reported", "facts": {"text": text}, "summary": "记录你刚刚说的不舒服"}
    return None


def _save_session(elder_id: str, channel: str, sender_id: str, channel_account_id: str = "") -> str:
    session_id = _new_id("ses")
    now = _now()
    with _db() as conn:
        conn.execute(
            "INSERT INTO sessions(session_id, elder_id, channel, sender_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
            (session_id, elder_id, channel, sender_id, now, now),
        )
        conn.execute("INSERT INTO game_session_identity VALUES (?, ?)", (session_id, channel_account_id))
    return session_id


def _save_pending(
    elder_id: str,
    session_id: str,
    candidate: Dict[str, Any],
    risk_level: str,
    family_share: bool,
) -> str:
    event_id = _new_id("pending")
    now = _now()
    expires = datetime.fromtimestamp(time.time() + 24 * 3600, tz=timezone.utc).replace(microsecond=0).isoformat()
    with _db() as conn:
        conn.execute(
            """INSERT INTO pending_events(event_id, elder_id, session_id, event_type, payload_json, summary,
               risk_level, family_share, status, created_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending_confirmation', ?, ?)""",
            (
                event_id,
                elder_id,
                session_id,
                candidate["event_type"],
                _json(candidate.get("facts") or {}),
                candidate.get("summary") or "记录这条健康信息",
                risk_level,
                1 if family_share else 0,
                now,
                expires,
            ),
        )
    return event_id


def _send_event_sink(event: Dict[str, Any]) -> Optional[str]:
    if not event.get("family_share"):
        return None
    url = os.environ.get("HEALTH_EVENT_SINK_URL", "").strip()
    if not url:
        return None
    headers = {"Content-Type": "application/json"}
    token = os.environ.get("HEALTH_EVENT_SINK_TOKEN", "").strip()
    if token:
        headers["X-Health-Internal-Token"] = token
    try:
        response = requests.post(url, json=event, headers=headers, timeout=8)
        if 200 <= response.status_code < 300:
            return "synced"
        return f"http_{response.status_code}"
    except requests.RequestException:
        return "unreachable"


# ---- 长期记忆：持久化事实 + 对话历史，让模型“记得”这位老人 ----

def _remember(elder_id: str, key: str, value: str) -> None:
    with _db() as conn:
        conn.execute(
            "INSERT INTO memory_facts(elder_id, key, value, updated_at) VALUES (?, ?, ?, ?) "
            "ON CONFLICT(elder_id, key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at",
            (elder_id, key, str(value)[:500], _now()),
        )


def _recall(elder_id: str) -> Dict[str, str]:
    with _db() as conn:
        rows = conn.execute("SELECT key, value FROM memory_facts WHERE elder_id = ?", (elder_id,)).fetchall()
    return {row["key"]: row["value"] for row in rows}


def _memory_text(elder_id: str) -> str:
    facts = _recall(elder_id)
    if not facts:
        return ""
    return "\n".join(f"- {k}：{v}" for k, v in sorted(facts.items()))


def _save_turn(elder_id: str, role: str, text: str) -> None:
    if not text:
        return
    with _db() as conn:
        conn.execute(
            "INSERT INTO chat_history(elder_id, role, text, created_at) VALUES (?, ?, ?, ?)",
            (elder_id, role, str(text)[:2000], _now()),
        )


def _recent_turns(elder_id: str, limit: int = 8) -> List[Tuple[str, str]]:
    with _db() as conn:
        rows = conn.execute(
            "SELECT role, text FROM chat_history WHERE elder_id = ? ORDER BY id DESC LIMIT ?",
            (elder_id, max(1, min(limit, 20))),
        ).fetchall()
    return [(row["role"], row["text"]) for row in reversed(rows)]


def _remember_from_event(elder_id: str, event: Dict[str, Any]) -> None:
    """确认事件后，抽取几条稳定事实进长期记忆，供下次对话使用。"""
    event_type = event.get("event_type")
    facts = event.get("facts") if isinstance(event.get("facts"), dict) else {}
    if event_type == "medication_taken":
        _remember(elder_id, "最近服药", "今天已按提醒吃过药")
    elif event_type == "measurement":
        bp = facts.get("blood_pressure")
        if isinstance(bp, dict) and bp.get("systolic") is not None:
            _remember(elder_id, "最近血压", f"{bp.get('systolic')}/{bp.get('diastolic')}")
        glu = facts.get("blood_glucose")
        if isinstance(glu, dict) and glu.get("value") is not None:
            _remember(elder_id, "最近血糖", str(glu.get("value")))
    elif event_type == "meal_log":
        _remember(elder_id, "最近一顿", str(facts.get("meal") or "")[:200])
    elif event_type == "photo_observation":
        candidate = facts.get("medication_candidate")
        if isinstance(candidate, dict):
            names = [
                str(item.get("generic_name") or item.get("brand_name") or "")
                for item in (candidate.get("items") or [])
                if isinstance(item, dict)
            ]
            names = [n for n in names if n]
            if names:
                _remember(elder_id, "在吃的药", "、".join(names[:8]))
    elif event_type == "symptom_reported":
        _remember(elder_id, "最近不舒服", str(facts.get("text") or "")[:200])


# ---- 用药疗程：记住在吃什么药 → 问疗程 → 接下来几天主动提醒 ----

_CN_NUM = {"零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9}


def _cn_to_int(s: str) -> Optional[int]:
    s = str(s).strip()
    if not s:
        return None
    if s.isdigit():
        return int(s)
    if s == "十":
        return 10
    if s in _CN_NUM:
        return _CN_NUM[s]
    if len(s) == 2 and s.endswith("十"):
        return _CN_NUM.get(s[0], 0) * 10
    if len(s) == 2 and s.startswith("十"):
        return 10 + _CN_NUM.get(s[1], 0)
    return None


def _extract_drug_name(text: str) -> str:
    value = str(text or "").strip()
    for pat in (
        r"(?:在吃|吃着|一直吃|还在吃|正在吃)\s*([^\s，。,.？?！]{1,20})",
        r"(?:医生.{0,6}开(?:了)?|开了)\s*([^\s，。,.？?！]{1,20})",
        r"(?:吃的是|药是|叫)\s*([^\s，。,.？?！]{1,20})",
    ):
        m = re.search(pat, value)
        if m:
            name = m.group(1).strip()
            if name and not re.search(r"^(药|这个|那个|些)$", name):
                return name
    return "这个药"


def _parse_course_answer(text: str) -> Dict[str, Any]:
    """解析老人对疗程追问的回答：天数 / 每天次数 / 饭前饭后。"""
    value = str(text or "").strip()
    days = None
    m = re.search(r"(?:先吃|要?吃|连吃|共|得?吃)\s*([一二两三四五六七八九十\d]+)\s*天", value)
    if m:
        days = _cn_to_int(m.group(1))
    else:
        # 兜底：光说“七天”，但排除“一天”（它常是“一天三次”的次数，不是天数）。
        m = re.search(r"([二两三四五六七八九十\d]+)\s*天", value)
        if m:
            days = _cn_to_int(m.group(1))
    if days is None:
        if re.search(r"一周|一个星期", value):
            days = 7
        elif re.search(r"半个月", value):
            days = 15
        elif re.search(r"一个月", value):
            days = 30
    freq = None
    m = re.search(r"(?:一天|每天|一日)\s*([一二两三四五六七八九十\d]+)\s*次", value)
    if m:
        freq = f"{m.group(1)}次/天"
    elif re.search(r"三次", value):
        freq = "3次/天"
    elif re.search(r"两次", value):
        freq = "2次/天"
    elif re.search(r"一次", value):
        freq = "1次/天"
    when = None
    if re.search(r"饭后", value):
        when = "饭后"
    elif re.search(r"饭前", value):
        when = "饭前"
    elif re.search(r"空腹", value):
        when = "空腹"
    return {"days": days, "freq": freq, "when": when}


def _create_course(elder_id: str, drug: str) -> str:
    course_id = _new_id("course")
    now = _now()
    with _db() as conn:
        conn.execute(
            "INSERT INTO medication_courses(course_id, elder_id, drug_name, status, created_at, updated_at) "
            "VALUES (?, ?, ?, 'pending_duration', ?, ?)",
            (course_id, elder_id, drug, now, now),
        )
    return course_id


def _pending_course(elder_id: str) -> Optional[Dict[str, Any]]:
    with _db() as conn:
        row = conn.execute(
            "SELECT * FROM medication_courses WHERE elder_id = ? AND status = 'pending_duration' "
            "ORDER BY created_at DESC LIMIT 1",
            (elder_id,),
        ).fetchone()
    return dict(row) if row else None


def _cancel_course(elder_id: str, course: Dict[str, Any]) -> None:
    """老人改口说另一种药时，把上一轮没答完的疗程作废，避免串药名。"""
    with _db() as conn:
        conn.execute(
            "UPDATE medication_courses SET status = 'cancelled', updated_at = ? WHERE course_id = ?",
            (_now(), course["course_id"]),
        )


def _stop_active_course(elder_id: str) -> Optional[str]:
    """老人说药吃完了/停药了：把还在提醒的 active 疗程改成 completed，返回药名（没有则 None）。

    只对“老人此前明确说过现在在吃”的药下手——用药提醒本来就只来自 active 疗程，
    所以从源头作废它们，就绝不会再冒出主动的用药提醒。"""
    with _db() as conn:
        row = conn.execute(
            "SELECT drug_name FROM medication_courses WHERE elder_id = ? AND status = 'active' "
            "ORDER BY created_at DESC LIMIT 1",
            (elder_id,),
        ).fetchone()
    if not row:
        return None
    drug = str(row["drug_name"])
    with _db() as conn:
        conn.execute(
            "UPDATE medication_courses SET status = 'completed', updated_at = ? "
            "WHERE elder_id = ? AND status = 'active'",
            (_now(), elder_id),
        )
    return drug


def _complete_course(elder_id: str, course: Dict[str, Any], ans: Dict[str, Any]) -> str:
    drug = course.get("drug_name") or "这个药"
    days = ans.get("days") or 7
    freq = ans.get("freq") or "按医生说的次数"
    when = ans.get("when") or "按医嘱"
    today = datetime.now().astimezone().strftime("%Y-%m-%d")
    end = datetime.fromtimestamp(time.time() + (days - 1) * 24 * 3600, tz=timezone.utc).strftime("%Y-%m-%d")
    now = _now()
    with _db() as conn:
        conn.execute(
            "UPDATE medication_courses SET duration_days = ?, times_per_day = ?, when_take = ?, "
            "start_date = ?, end_date = ?, status = 'active', updated_at = ? WHERE course_id = ?",
            (days, freq, when, today, end, now, course["course_id"]),
        )
    _remember(elder_id, "用药疗程", f"{drug}：{freq}，{when}，共{days}天")
    return (
        f"好嘞，记下了：{drug}，{freq}，{when}，先吃{days}天。"
        "从今天起我每天到点就提醒你，你就按医生说的吃。哪天药量有变化或者不想吃了，跟我说一声。"
    )


def _course_times(course: Dict[str, Any]) -> List[str]:
    """根据饭前/饭后和每天次数，给出每天该提醒的具体时间点。"""
    base = ["08:00", "12:00", "18:00"]
    if "饭前" in (course.get("when_take") or ""):
        base = ["07:30", "11:30", "17:30"]
    freq = course.get("times_per_day") or "3次/天"
    n = 3
    m = re.search(r"([一二两三四五六七八九十\d]+)", freq)
    if m:
        parsed = _cn_to_int(m.group(1))
        if parsed:
            n = parsed
    if n <= 1:
        return base[:1]
    if n == 2:
        return [base[0], base[2]]
    return base


def due_courses(elder_id: str, at: Optional[str] = None) -> List[Dict[str, Any]]:
    """返回当前时间点仍在疗程内、且到点该提醒的用药。"""
    stamp = at or datetime.now().astimezone().strftime("%H:%M")
    today = datetime.now().astimezone().strftime("%Y-%m-%d")
    with _db() as conn:
        rows = conn.execute(
            "SELECT * FROM medication_courses WHERE elder_id = ? AND status = 'active' AND end_date >= ?",
            (elder_id, today),
        ).fetchall()
    result = []
    for row in rows:
        course = dict(row)
        if stamp in _course_times(course):
            result.append({
                "course_id": course["course_id"],
                "drug_name": course["drug_name"],
                "when_take": course.get("when_take") or "",
                "times_per_day": course.get("times_per_day") or "",
                "end_date": course.get("end_date") or "",
            })
    return result


def active_care_tip(elder_id: str) -> str:
    """病期关怀尾巴：有正在吃的药或最近不舒服时，提醒清淡、按时吃药、多休息。"""
    with _db() as conn:
        row = conn.execute(
            "SELECT drug_name FROM medication_courses WHERE elder_id = ? AND status = 'active' "
            "ORDER BY created_at DESC LIMIT 1",
            (elder_id,),
        ).fetchone()
    if row:
        return f"这两天按时吃「{row['drug_name']}」，吃清淡点、多休息。"
    recent_ill = _recall(elder_id).get("最近不舒服")
    if recent_ill:
        return "这两天先吃清淡点、多休息，不舒服就跟家里人说。"
    return ""


def _recent_context(elder_id: str, limit: int = 12) -> List[Dict[str, Any]]:
    """只取已确认事件的结构化摘要，给生活建议做保守个性化；不读原始图片。"""
    with _db() as conn:
        rows = conn.execute(
            "SELECT event_type, payload_json, created_at FROM health_events WHERE elder_id = ? "
            "ORDER BY created_at DESC LIMIT ?",
            (elder_id, max(1, min(limit, 30))),
        ).fetchall()
    result: List[Dict[str, Any]] = []
    for row in rows:
        raw = _load_json(row["payload_json"], {})
        facts: Dict[str, Any] = {}
        if isinstance(raw, dict):
            for key in ("blood_pressure", "blood_glucose", "pulse", "statement", "text"):
                if key in raw:
                    facts[key] = raw[key]
            candidate = raw.get("medication_candidate")
            if isinstance(candidate, dict):
                # 只带药品候选的短字段，去掉整段原始可见文字和说明书长文本。
                items = []
                for item in (candidate.get("items", [])[:8] if isinstance(candidate.get("items"), list) else []):
                    if isinstance(item, dict):
                        items.append({k: item.get(k) for k in ("generic_name", "brand_name", "strength", "confidence")})
                if items:
                    facts["medication_candidate"] = {"items": items}
        result.append({"event_type": row["event_type"], "facts": facts, "created_at": row["created_at"]})
    return result


def confirm_pending(event_id: str, decision: str) -> Dict[str, Any]:
    decision = str(decision or "").lower().strip()
    accepted = decision in {"confirm", "confirmed", "yes", "是", "对", "记录", "好的"}
    with _db() as conn:
        conn.execute("BEGIN IMMEDIATE")
        row = conn.execute("SELECT * FROM pending_events WHERE event_id = ?", (event_id,)).fetchone()
        if not row:
            return {"ok": False, "message": "这条待确认信息已不存在或已过期"}
        if row["status"] != "pending_confirmation":
            return {"ok": False, "message": "这条信息已经处理过了", "status": row["status"]}
        if row["expires_at"] <= _now():
            return {"ok": False, "status": "expired", "message": "这条待确认信息已过期"}
        if not accepted:
            conn.execute("UPDATE pending_events SET status = 'rejected' WHERE event_id = ?", (event_id,))
            return {"ok": True, "status": "rejected", "reply": "好，那这条就先不记了。要不再拍张清楚点的，或者你直接跟我说说咋回事。"}

        event = {
            "event_id": _new_id("health"),
            "elder_id": row["elder_id"],
            "event_type": row["event_type"],
            "facts": _load_json(row["payload_json"], {}),
            "risk_level": row["risk_level"],
            "family_share": bool(row["family_share"]),
            "source": "openclaw-weixin",
            "occurred_at": row["created_at"],
        }
        conn.execute("UPDATE pending_events SET status = 'confirmed' WHERE event_id = ?", (event_id,))
        conn.execute(
            """INSERT INTO health_events(event_id, elder_id, event_type, payload_json, risk_level, family_share,
               source, created_at, synced_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                event["event_id"],
                event["elder_id"],
                event["event_type"],
                _json(event["facts"]),
                event["risk_level"],
                1 if event["family_share"] else 0,
                event["source"],
                event["occurred_at"],
                None,
            ),
        )
        conn.execute("""INSERT INTO game_event_identity(event_id, sender_id, channel_account_id)
            SELECT ?, sessions.sender_id, game_session_identity.channel_account_id
            FROM sessions JOIN game_session_identity USING(session_id) WHERE session_id = ?""",
            (event["event_id"], row["session_id"]))
    _remember_from_event(event["elder_id"], event)
    sync_status = _send_event_sink(event)
    if sync_status == "synced":
        with _db() as conn:
            conn.execute("UPDATE health_events SET synced_at = ? WHERE event_id = ?", (_now(), event["event_id"]))
    return {
        "ok": True,
        "status": "confirmed",
        "event": event,
        "sink_status": sync_status or "local_only",
        "reply": "记好啦。以后就跟平常聊天一样告诉我就行，不用填表。",
    }


def _latest_pending(elder_id: str) -> Optional[str]:
    with _db() as conn:
        row = conn.execute(
            "SELECT event_id FROM pending_events WHERE elder_id = ? AND status = 'pending_confirmation' "
            "AND expires_at > ? ORDER BY created_at DESC LIMIT 1",
            (elder_id, _now()),
        ).fetchone()
    return row["event_id"] if row else None


def handle_message(payload: Dict[str, Any]) -> Dict[str, Any]:
    elder_id = str(payload.get("elder_id") or "elder_demo_001").strip()[:120]
    sender_id = str(payload.get("sender_id") or "").strip()[:120]
    channel = str(payload.get("channel") or "openclaw-weixin").strip()[:80]
    text = str(payload.get("text") or "").strip()[:4000]
    attachments = _safe_attachments(payload.get("attachments"))
    consent = payload.get("consent") if isinstance(payload.get("consent"), dict) else {}
    family_share = bool(consent.get("family_share", False))
    if not text:
        text = " ".join(a.get("transcript", "") for a in attachments if a.get("transcript")).strip()

    session_id = _save_session(elder_id, channel, sender_id, str(payload.get("channel_account_id") or ""))
    # 老人提到要去看病/复查/挂号：记下来，供任务桥接器判断「复查/复诊」提醒要不要发。
    if not attachments and re.search(r"复查|复诊|去看病|看医生|去医院|挂号|约了医生|要去看", text):
        _remember(elder_id, "要去看病", text)
    # 老人端按钮/语音常常只会传“是/不对”，把它解释为最近一条待确认记录。
    if not attachments and text.lower() in {"是", "对", "确认", "好的", "记录", "识别没问题", "yes", "confirm", "不对", "取消", "不要", "否", "no", "reject"}:
        pending_id = _latest_pending(elder_id)
        if pending_id:
            decision = "confirm" if text.lower() in {"是", "对", "确认", "好的", "记录", "识别没问题", "yes", "confirm"} else "reject"
            result = confirm_pending(pending_id, decision)
            reply_text = result.get("reply") or result.get("message")
            _save_turn(elder_id, "user", text)
            _save_turn(elder_id, "assistant", reply_text)
            return {
                "session_id": session_id,
                "mode": "elder_only",
                "reply": reply_text,
                "risk_level": "routine",
                "needs_confirmation": False,
                "confirmation": result,
                "quick_replies": _quick_replies("chat"),
            }
    # 用药疗程补全：上一轮问了“吃几天/几次/饭前饭后”，这轮答上来就建疗程 + 自动提醒。
    if not attachments:
        course = _pending_course(elder_id)
        if course:
            # 老人要是直接说“我最近在吃XX药 / 我吃的是XX药”，是重新说一种药，
            # 别拿上一轮没答完的疗程来补；作废旧疗程，让下面按新药重开。
            if re.search(_MEDICATION_STATEMENT_RE, text):
                _cancel_course(elder_id, course)
            else:
                ans = _parse_course_answer(text)
                if ans.get("days") or ans.get("freq"):
                    reply = _complete_course(elder_id, course, ans)
                    _save_turn(elder_id, "user", text)
                    _save_turn(elder_id, "assistant", reply)
                    return {
                        "session_id": session_id,
                        "mode": "elder_only",
                        "intent": "medication_course",
                        "reply": reply,
                        "risk_level": "routine",
                        "needs_confirmation": False,
                        "quick_replies": _quick_replies("chat"),
                    }

    # 医学小词典（轻量 RAG）：问药用途 / 问疾病基本信息，命中就按词典准确答，不靠模型现编。
    if not attachments:
        kb_reply = _kb_answer(text, _recall_meds(elder_id))
        if kb_reply:
            _save_turn(elder_id, "user", text)
            _save_turn(elder_id, "assistant", kb_reply)
            return {
                "session_id": session_id,
                "mode": "elder_only",
                "intent": "medical_kb",
                "reply": kb_reply,
                "risk_level": "routine",
                "needs_confirmation": False,
                "quick_replies": _quick_replies("chat"),
            }

    # 老人说“药吃完了/停药了”：作废还在提醒的疗程，从此不再主动提醒用药。
    if not attachments and re.search(_MEDICATION_STOP_RE, text):
        drug = _stop_active_course(elder_id)
        if drug:
            reply = f"好，那「{drug}」我就不提醒啦。要是后面又开始吃，跟我说一声。"
        else:
            reply = "好嘞，那我先不提醒啦。要是后面又开始吃药，跟我说一声。"
        _save_turn(elder_id, "user", text)
        _save_turn(elder_id, "assistant", reply)
        return {
            "session_id": session_id,
            "mode": "elder_only",
            "intent": "medication_stop",
            "reply": reply,
            "risk_level": "routine",
            "needs_confirmation": False,
            "quick_replies": _quick_replies("chat"),
        }

    risk_level, risk_reason = detect_risk(text)
    if risk_level == "emergency":
        return {
            "session_id": session_id,
            "mode": "elder_only",
            "reply": _emergency_reply(risk_reason),
            "risk_level": "emergency",
            "needs_confirmation": False,
            "quick_replies": _quick_replies("emergency", "emergency"),
            "safety_action": "call_120_now",
            "citations": [],
        }

    intent = _intent(text, attachments)
    facts: Dict[str, Any] = _extract_measurements(text)
    recognition_status = "not_requested"
    recognition_error: Optional[str] = None
    if intent == "photo_review":
        recognized, recognition_status, recognition_error = _recognize_photo(attachments, text)
        facts.update(recognized)
        if recognition_status == "recognized":
            meds = _recognized_meds(facts)
            if meds:
                _remember(elder_id, "最近识别的药", json.dumps(meds, ensure_ascii=False))

    policies = retrieve_policies(f"{text} {intent} {json.dumps(facts, ensure_ascii=False)}")
    known_context = _recent_context(elder_id) if intent in {"lifestyle", "chat"} else []
    if known_context:
        facts["known_context"] = known_context
    candidate = _candidate_from_intent(intent, text, facts, recognition_status)
    pending_event_id: Optional[str] = None
    memory_text = _memory_text(elder_id)

    if intent == "photo_review" and recognition_status == "needs_model":
        reply = "照片收到了，但识别服务还没打开。我不会猜药名或检查结果；请管理员先配置识别模型，或暂时把报告上的文字发给我。"
    elif intent == "photo_review" and recognition_status == "failed":
        reply = "这张照片我没看清，先别按照片里的内容吃药。请在光线足的地方把整页拍平，文字和药名都拍完整，再发一次。"
    elif intent == "photo_review" and recognition_status == "unsupported_media":
        reply = "我收到的是文件或音频，目前请把体检报告/病历/药盒拍成清楚的图片再发给我。"
    elif intent == "reminder_help":
        reply = "行呀。你跟我说句“每天早上八点提醒我吃药”，我到点就提醒你，不用填表。"
    elif intent == "voice":
        reply = "刚才那句我没太听清。你再说一遍，或者按住语音慢慢说；要是不舒服得厉害，直接叫家人或打 120。"
    elif intent == "medication_course":
        # 重新说一种药时，把上一轮没答完的疗程一并作废，防止新药名和旧疗程串了。
        stale = _pending_course(elder_id)
        if stale:
            _cancel_course(elder_id, stale)
        drug = _extract_drug_name(text)
        _create_course(elder_id, drug)
        _remember(elder_id, "在吃的药", drug)
        reply = (
            f"好，我记下你最近在吃「{drug}」。你跟我说三件事，我后面每天到点就提醒你："
            "这药一天吃几次？饭前还是饭后？要吃几天？"
        )
    elif candidate:
        pending_event_id = _save_pending(elder_id, session_id, candidate, risk_level, family_share)
        # 照片识别：直接、自然地把药名念出来，不追确认、不说用途（用途等老人问再说）。
        if intent == "photo_review" and recognition_status == "recognized":
            reply = _photo_reply(facts) or "我先把照片里看到的跟你说。"
        else:
            # 其它确认项让模型自己生成回复（带记忆），失败才退回安全的固定话术。
            reply = _call_openclaw(text, facts, policies, elder_id) or _call_route(
                _route_for(intent), text, facts, policies, elder_id, memory_text
            )
            if not reply:
                if intent == "medication_taken":
                    reply = "好，你说今天已经吃过药了，我记下啦；要是还没吃，也跟我说一声。"
                elif intent == "meal_log":
                    reply = "好嘞，你刚说的这顿饭我记下啦。"
                elif intent == "measurement":
                    reply = "这个数我听到了，我记下啦；要是没量准，先再量一次。"
                else:
                    reply = "我大概听明白了。"
        if risk_level == "urgent":
            reply = "你说的情况建议尽快联系家人或医疗机构确认。" + reply
    else:
        reply = (
            _call_openclaw(text, facts, policies, elder_id)
            or _call_route(_route_for(intent), text, facts, policies, elder_id, memory_text)
            or _default_lifestyle_reply(text, policies, known_context)
        )

    _save_turn(elder_id, "user", text)
    _save_turn(elder_id, "assistant", reply)

    return {
        "session_id": session_id,
        "mode": "elder_only",
        "intent": intent,
        "reply": reply,
        "risk_level": risk_level,
        "needs_confirmation": bool(pending_event_id),
        "pending_event": {
            "event_id": pending_event_id,
            "summary": candidate.get("summary") if candidate else None,
            "expires_in_hours": 24,
        } if pending_event_id else None,
        "facts": facts,
        "recognition": {"status": recognition_status, "error": recognition_error},
        "quick_replies": _quick_replies(intent, risk_level),
        "suggestions": [
            {"title": p.get("title"), "text": p.get("elder_reply") or p.get("text"), "source": p.get("source")}
            for p in policies
        ],
        "citations": [
            {"title": p.get("title"), "source": p.get("source"), "version": p.get("version")}
            for p in policies
        ],
        "privacy": {"family_share": family_share, "raw_media_stored": False},
    }


def list_events(elder_id: str, limit: int = 50) -> List[Dict[str, Any]]:
    with _db() as conn:
        rows = conn.execute(
            "SELECT * FROM health_events WHERE elder_id = ? ORDER BY created_at DESC LIMIT ?",
            (elder_id, max(1, min(limit, 200))),
        ).fetchall()
    return [
        {
            "event_id": row["event_id"],
            "elder_id": row["elder_id"],
            "event_type": row["event_type"],
            "facts": _load_json(row["payload_json"], {}),
            "risk_level": row["risk_level"],
            "family_share": bool(row["family_share"]),
            "source": row["source"],
            "created_at": row["created_at"],
            "synced_at": row["synced_at"],
        }
        for row in rows
    ]


def upsert_reminder(payload: Dict[str, Any]) -> Dict[str, Any]:
    elder_id = str(payload.get("elder_id") or "elder_demo_001").strip()[:120]
    label = str(payload.get("label") or "健康提醒").strip()[:120]
    schedule = payload.get("schedule") if isinstance(payload.get("schedule"), dict) else {}
    if not schedule.get("times"):
        raise ValueError("schedule.times 至少填写一个时间，例如 ['08:00']")
    reminder_id = str(payload.get("reminder_id") or _new_id("rem")).strip()
    now = _now()
    with _db() as conn:
        conn.execute(
            """INSERT INTO reminders(reminder_id, elder_id, label, schedule_json, enabled, created_at, updated_at)
               VALUES (?, ?, ?, ?, ?, ?, ?)
               ON CONFLICT(reminder_id) DO UPDATE SET label=excluded.label, schedule_json=excluded.schedule_json,
               enabled=excluded.enabled, updated_at=excluded.updated_at""",
            (reminder_id, elder_id, label, _json(schedule), 1 if payload.get("enabled", True) else 0, now, now),
        )
    return {"reminder_id": reminder_id, "elder_id": elder_id, "label": label, "schedule": schedule, "enabled": bool(payload.get("enabled", True))}


def list_reminders(elder_id: str) -> List[Dict[str, Any]]:
    with _db() as conn:
        rows = conn.execute("SELECT * FROM reminders WHERE elder_id = ? ORDER BY created_at", (elder_id,)).fetchall()
    return [
        {
            "reminder_id": row["reminder_id"],
            "elder_id": row["elder_id"],
            "label": row["label"],
            "schedule": _load_json(row["schedule_json"], {}),
            "enabled": bool(row["enabled"]),
            "created_at": row["created_at"],
            "updated_at": row["updated_at"],
        }
        for row in rows
    ]


def due_reminders(elder_id: str, at: Optional[str] = None) -> List[Dict[str, Any]]:
    """返回当前分钟应触达的提醒；实际发送由 Gateway/cron 调度器完成。"""
    stamp = at or datetime.now().astimezone().strftime("%H:%M")
    result: List[Dict[str, Any]] = []
    for reminder in list_reminders(elder_id):
        if not reminder["enabled"]:
            continue
        times = reminder.get("schedule", {}).get("times") or []
        normalized = {str(item)[:5] for item in times}
        if stamp in normalized:
            result.append(reminder)
    return result


def create_family_link(payload: Dict[str, Any]) -> Dict[str, Any]:
    elder_id = str(payload.get("elder_id") or "").strip()[:120]
    family_user_id = str(payload.get("family_user_id") or "").strip()[:120]
    if not elder_id or not family_user_id:
        raise ValueError("elder_id 和 family_user_id 必填")
    link_id = _new_id("link")
    code = uuid.uuid4().hex[:8].upper()
    now = _now()
    expires = datetime.fromtimestamp(time.time() + 30 * 60, tz=timezone.utc).replace(microsecond=0).isoformat()
    with _db() as conn:
        conn.execute(
            "INSERT INTO family_links(link_id, elder_id, family_user_id, code, status, created_at, expires_at) VALUES (?, ?, ?, ?, 'pending', ?, ?)",
            (link_id, elder_id, family_user_id, code, now, expires),
        )
    return {"link_id": link_id, "code": code, "expires_at": expires, "status": "pending"}


def confirm_family_link(payload: Dict[str, Any]) -> Dict[str, Any]:
    link_id = str(payload.get("link_id") or "").strip()
    code = str(payload.get("code") or "").strip().upper()
    if not link_id or not code:
        raise ValueError("link_id 和 code 必填")
    with _db() as conn:
        row = conn.execute("SELECT * FROM family_links WHERE link_id = ? AND code = ?", (link_id, code)).fetchone()
        if not row:
            return {"ok": False, "message": "绑定码不正确"}
        if row["status"] != "pending":
            return {"ok": False, "message": "这个绑定码已经处理过了", "status": row["status"]}
        if row["expires_at"] <= _now():
            conn.execute("UPDATE family_links SET status = 'expired' WHERE link_id = ?", (link_id,))
            return {"ok": False, "message": "绑定码已过期"}
        conn.execute("UPDATE family_links SET status = 'confirmed' WHERE link_id = ?", (link_id,))
    return {"ok": True, "status": "confirmed", "elder_id": row["elder_id"], "family_user_id": row["family_user_id"]}


def _ilink_gateway_status() -> Dict[str, Any]:
    try:
        import ilink_gateway

        return ilink_gateway.status()
    except Exception:  # noqa: BLE001 - 健康检查不能因为网关未启动而失败
        return {"configured": False, "polling": False, "bots": []}


def register_elder_assistant_routes(app) -> None:
    init_db()
    # 只追加 D 数据库的身份引用表；旧记录缺少来源时不允许自动进入游戏。
    with _db() as conn:
        conn.execute("CREATE TABLE IF NOT EXISTS game_session_identity (session_id TEXT PRIMARY KEY, channel_account_id TEXT NOT NULL)")
        conn.execute("CREATE TABLE IF NOT EXISTS game_event_identity (event_id TEXT PRIMARY KEY, sender_id TEXT NOT NULL, channel_account_id TEXT NOT NULL)")
    from game_integration import register_game_routes
    register_game_routes(app, _db)
    from ilink_binding import register_binding_routes
    register_binding_routes(app, _db)

    @app.before_request
    def _elder_sidecar_auth():
        expected = os.environ.get("ELDER_SIDECAR_TOKEN", "").strip()
        if not request.path.startswith("/api/v1/elder"):
            return None
        if not expected:
            return jsonify({"message": "Configure ELDER_SIDECAR_TOKEN before accepting health data"}), 503
        provided = request.headers.get("X-Elder-Sidecar-Token", "")
        if not provided:
            auth = request.headers.get("Authorization", "")
            if auth.lower().startswith("bearer "):
                provided = auth[7:].strip()
        if not hmac.compare_digest(provided, expected):
            return jsonify({"message": "elder sidecar authentication required"}), 401
        return None

    @app.get("/api/v1/elder/health")
    def elder_health():
        key, base_url, model = recognizer.load_config()
        return {
            "ok": True,
            "mode": "elder_only",
            "ilink_gateway": _ilink_gateway_status(),
            "text_fallback_enabled": os.environ.get("HEALTH_CHAT_ENABLED", "false").lower() in {"1", "true", "yes", "on"},
            "text_fallback_model": os.environ.get("HEALTH_CHAT_MODEL", "qwen-plus"),
            "vision_configured": bool(key),
            "vision_provider": recognizer.provider_label(base_url) if key else "",
            "vision_model": model if key else "",
            "event_sink_configured": bool(os.environ.get("HEALTH_EVENT_SINK_URL")),
            "raw_media_storage": False,
        }

    @app.post("/api/v1/elder/message")
    def elder_message():
        payload = request.get_json(silent=True) or {}
        return jsonify(handle_message(payload))

    @app.post("/api/v1/elder/confirm")
    def elder_confirm():
        payload = request.get_json(silent=True) or {}
        event_id = str(payload.get("event_id") or "").strip()
        if not event_id:
            return jsonify({"ok": False, "message": "缺少 event_id"}), 400
        return jsonify(confirm_pending(event_id, str(payload.get("decision") or "")))

    @app.get("/api/v1/elder/events")
    def elder_events():
        elder_id = str(request.args.get("elder_id") or "elder_demo_001")
        try:
            limit = int(request.args.get("limit", "50"))
        except ValueError:
            limit = 50
        return jsonify({"elder_id": elder_id, "events": list_events(elder_id, limit)})

    @app.post("/api/v1/elder/reminders")
    def elder_reminder_upsert():
        try:
            return jsonify(upsert_reminder(request.get_json(silent=True) or {}))
        except ValueError as exc:
            return jsonify({"message": str(exc)}), 400

    @app.get("/api/v1/elder/reminders")
    def elder_reminder_list():
        elder_id = str(request.args.get("elder_id") or "elder_demo_001")
        return jsonify({"elder_id": elder_id, "reminders": list_reminders(elder_id)})

    @app.get("/api/v1/elder/reminders/due")
    def elder_reminder_due():
        elder_id = str(request.args.get("elder_id") or "elder_demo_001")
        return jsonify({"elder_id": elder_id, "at": request.args.get("at") or datetime.now().astimezone().strftime("%H:%M"), "reminders": due_reminders(elder_id, request.args.get("at"))})

    @app.post("/api/v1/elder/family-link")
    def elder_family_link():
        try:
            return jsonify(create_family_link(request.get_json(silent=True) or {}))
        except ValueError as exc:
            return jsonify({"message": str(exc)}), 400

    @app.post("/api/v1/elder/family-link/confirm")
    def elder_family_link_confirm():
        try:
            return jsonify(confirm_family_link(request.get_json(silent=True) or {}))
        except ValueError as exc:
            return jsonify({"message": str(exc)}), 400

