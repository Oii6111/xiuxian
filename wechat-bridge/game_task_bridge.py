"""老人端 ↔ 游戏「任务板块」桥接器（D 侧，微信/健康侧）。

这个脚本独立于 sidecar 运行，把游戏后端派发的健康任务变成给老人的定时提醒，
再把老人的回复/照片回传成游戏里的任务完成。它**不自己编提醒**——提醒来源是
游戏里的任务板块（`quests.assign`），这里只负责「到点推送 + 回传完成」。

三个职责，对应游戏后端（C 实现）的三组内部接口：

1. 出站提醒：轮询 `GET /internal/v1/bindings/:id/tasks`，按模板默认时间把
   「今日待办」推给老人微信。
2. 入站完成：老人回复/拍照后，sidecar 调 `complete_task_from_reply()`，
   核对归属后提交 `POST /internal/v1/task-results`，游戏自动结算发灵石。
3. 结算回执：轮询 `POST /internal/v1/notifications/claim`，把「今天的记录
   已记上」回推给老人，再 ack。

运行前，游戏侧需要先配好 `HEALTH_SERVICE_TOKEN`（32 位随机值，双方共用），
并在游戏里完成一次绑定，把返回的 `binding_id` 填到下面的环境变量里。
详见 docs/TASK_REMINDER_BRIDGE.md。

环境变量：
    GAME_API_BASE         游戏后端地址（默认 http://127.0.0.1:8080）
    HEALTH_SERVICE_TOKEN  内部服务凭证（与游戏侧 .env 里的一致，必填）
    BINDING_ID            单个老人的绑定 id
    ELDER_BINDINGS        可选，JSON 映射 {"elder_id": "binding_..."}，多老人用
    ELDER_ID              老人 ID（默认 elder_demo_001），用于查「该不该提醒」的聊天事实
    OPENCLAW_SEND_CHANNEL 出站通道（默认 openclaw-weixin）
    OPENCLAW_SEND_TARGET  老人微信接收地址（ilink_user_id）
    OPENCLAW_BIN          openclaw 可执行文件路径
    OPENCLAW_DRY_RUN      1 时只打印、不发送、不提交
    BRIDGE_STATE          幂等去重状态文件路径
"""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

BASE_DIR = Path(__file__).resolve().parent
STATE_PATH = Path(os.environ.get("BRIDGE_STATE", str(BASE_DIR / "bot_data" / "task_bridge_state.json")))
ELDER_DB = BASE_DIR / "bot_data" / "elder_assistant.sqlite3"  # 与 sidecar 共用，判断「该不该提醒」
TZ_OFFSET = 8 * 3600  # 游戏与老人统一用 UTC+8

# ---------------------------------------------------------------------------
# 健康行为任务模板：id 必须与游戏侧 server/src/game/rules.ts 的 integrationTemplates
# 保持一致。这里只负责「默认提醒时间 + 话术」，奖励与凭证级别以游戏侧 rules.ts 为准。
# ---------------------------------------------------------------------------
TASK_TEMPLATES: Dict[str, Dict[str, Any]] = {
    "daily_medication_record": {
        "title": "按时吃药",
        "event_type": "medication_record",
        "reminders": [
            {"time": "08:00", "text": "早上好呀，到点吃药啦。吃完回我一声，我帮你记上。"},
            {"time": "12:00", "text": "中午啦，记得吃这顿的药。吃完跟我说一声。"},
            {"time": "18:00", "text": "晚上啦，该吃药了。吃完回我一声。"},
        ],
    },
    "daily_exercise_record": {
        "title": "出门活动",
        "event_type": "exercise_record",
        "reminders": [
            {"time": "09:00", "text": "今天天气不错，出门走走、晒晒太阳，腿脚更利索。走完跟我说一声。"},
        ],
    },
    "daily_move_reminder": {
        "title": "别久坐，起来活动",
        "event_type": "move_record",
        "reminders": [
            {"time": "10:30", "text": "坐了好一会儿啦，起来伸个懒腰、走两步，喝口水。"},
            {"time": "15:00", "text": "下午啦，别一直坐着，起来活动活动腿脚、扭扭腰。"},
            {"time": "16:30", "text": "坐久了对腰腿不好，起来走两圈、伸伸胳膊。"},
        ],
    },
    "daily_bp_record": {
        "title": "量血压",
        "event_type": "bp_record",
        "reminders": [
            {"time": "08:00", "text": "到点量血压啦，量好把血压计屏幕拍张照发我。"},
        ],
    },
    "daily_hydration_reminder": {
        "title": "喝口水",
        "event_type": "hydration_record",
        "reminders": [
            {"time": "11:00", "text": "记得喝口水呀，一小口一小口慢慢喝。"},
            {"time": "14:00", "text": "下午啦，再喝口水润润嗓子。"},
        ],
    },
    "followup_visit_record": {
        "title": "复查/复诊",
        "event_type": "followup_record",
        "reminders": [
            {"time": "09:00", "text": "今天有复查，别忘了带好病历和检查单，出门注意安全。"},
        ],
    },
}

# 与游戏侧一致的“凭证级别”，回传时据回复内容选择。
VERIFICATION_TEXT = "self_report"
VERIFICATION_PHOTO = "photo"


def _now() -> int:
    return int(time.time())


def _now_hhmm() -> str:
    return datetime.now(timezone.utc).astimezone().strftime("%H:%M")


def _today_utc8() -> str:
    return datetime.fromtimestamp(_now() + TZ_OFFSET, tz=timezone.utc).strftime("%Y-%m-%d")


# ---------------------------------------------------------------------------
# 提醒门槛：游戏不能聊天，所以「该不该提醒」由我们这边据聊天得知的事实判断。
# 游戏只负责派任务类别（吃药/量血压/复查…），我们这边决定这一刻要不要真的推。
# ---------------------------------------------------------------------------
def _elder_db():
    import sqlite3

    conn = sqlite3.connect(str(ELDER_DB))
    conn.row_factory = sqlite3.Row
    return conn


def _has_active_medication(elder_id: str) -> bool:
    """聊天里确认过「现在在吃药」（有未结束的 active 疗程）才允许提醒吃药。"""
    try:
        conn = _elder_db()
        row = conn.execute(
            "SELECT 1 FROM medication_courses WHERE elder_id = ? AND status = 'active' AND end_date >= ? LIMIT 1",
            (elder_id, _today_utc8()),
        ).fetchone()
        conn.close()
        return row is not None
    except Exception:  # noqa: BLE001 — 库不存在/表未建时当作“不知道在吃药”，不发
        return False


def _has_upcoming_visit(elder_id: str) -> bool:
    """聊天里得知过「要去看病/复查」才允许提醒复查。"""
    try:
        conn = _elder_db()
        row = conn.execute(
            "SELECT 1 FROM memory_facts WHERE elder_id = ? AND key = '要去看病' LIMIT 1",
            (elder_id,),
        ).fetchone()
        conn.close()
        return row is not None
    except Exception:  # noqa: BLE001
        return False


def _gate(template_id: str, elder_id: str) -> bool:
    if template_id == "daily_medication_record":
        return _has_active_medication(elder_id)
    if template_id == "followup_visit_record":
        return _has_upcoming_visit(elder_id)
    return True  # 运动 / 久坐 / 量血压 / 喝水：无聊天门槛


def _openclaw_bin() -> str:
    configured = os.environ.get("OPENCLAW_BIN", "").strip()
    if configured:
        return configured
    local_bat = BASE_DIR / "openclaw.bat"
    if local_bat.exists():
        return str(local_bat)
    return "openclaw"


def _run(args: List[str]) -> subprocess.CompletedProcess:
    bin_ = _openclaw_bin()
    if os.name == "nt":
        cmdline = subprocess.list2cmdline([bin_, *args])
        return subprocess.run(cmdline, shell=True, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=60)
    return subprocess.run([bin_, *args], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=60)


def send_wechat(target: str, text: str) -> Dict[str, Any]:
    """通过 openclaw message send 出站发送一条消息给老人。"""
    channel = os.environ.get("OPENCLAW_SEND_CHANNEL", "openclaw-weixin").strip() or "openclaw-weixin"
    account = os.environ.get("OPENCLAW_SEND_ACCOUNT", "").strip()
    args = ["message", "send", "--channel", channel, "--target", target, "--message", text]
    if account:
        args = ["message", "send", "--account", account, "--channel", channel, "--target", target, "--message", text]
    if os.environ.get("OPENCLAW_DRY_RUN", "").strip().lower() in {"1", "true", "yes", "on"}:
        print(f"[dry-run] {_openclaw_bin()} " + subprocess.list2cmdline(args))
        return {"ok": True, "dry_run": True}
    try:
        proc = _run(args)
        return {"ok": proc.returncode == 0, "returncode": proc.returncode, "stdout": proc.stdout, "stderr": proc.stderr}
    except Exception as exc:  # noqa: BLE001 — 单条发送失败不能拖垮整个轮询
        return {"ok": False, "error": str(exc)}


# ---------------------------------------------------------------------------
# 游戏后端内部接口（D 用 HEALTH_SERVICE_TOKEN 认证）
# ---------------------------------------------------------------------------
def _game_base() -> str:
    return os.environ.get("GAME_API_BASE", "http://127.0.0.1:8080").rstrip("/")


def _auth_headers() -> Dict[str, str]:
    token = os.environ.get("HEALTH_SERVICE_TOKEN", "").strip()
    return {"Authorization": "Bearer " + token, "Content-Type": "application/json"}


def game_get(path: str) -> Dict[str, Any]:
    import urllib.request

    req = urllib.request.Request(_game_base() + path, headers=_auth_headers(), method="GET")
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read().decode("utf-8"))


def game_post(path: str, body: Dict[str, Any]) -> Dict[str, Any]:
    import urllib.request

    req = urllib.request.Request(
        _game_base() + path,
        data=json.dumps(body).encode("utf-8"),
        headers=_auth_headers(),
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read().decode("utf-8"))


def pending(binding_id: str) -> Dict[str, Any]:
    """返回 {binding, tasks}，tasks 已过滤掉 settled。consent_version 在 binding 上。"""
    try:
        result = game_get(f"/internal/v1/bindings/{binding_id}/tasks")
    except Exception as exc:  # noqa: BLE001 — 后端未起/未配时静默跳过
        print(f"[warn] 拉取待办失败：{exc}")
        return {"binding": {}, "tasks": []}
    data = result.get("data") or {}
    tasks = [t for t in (data.get("tasks") or []) if str(t.get("status") or "") != "settled"]
    return {"binding": data.get("binding") or {}, "tasks": tasks}


def pending_tasks(binding_id: str) -> List[Dict[str, Any]]:
    """返回该绑定当前未结算的待办任务（游戏侧已经按 window_end 过滤过一次）。"""
    return pending(binding_id)["tasks"]


def _reminder_slots(template_id: str) -> List[Dict[str, str]]:
    return TASK_TEMPLATES.get(template_id, {}).get("reminders", [])


def due_reminders(tasks: List[Dict[str, Any]], stamp: str, elder_id: str) -> List[Tuple[Dict[str, Any], str]]:
    """在当前分钟到点的提醒，返回 (task, 提醒话术) 列表。过不了门槛的任务不发。"""
    due: List[Tuple[Dict[str, Any], str]] = []
    for task in tasks:
        template_id = str(task.get("template_id") or "")
        if not _gate(template_id, elder_id):
            continue
        for slot in _reminder_slots(template_id):
            if str(slot.get("time") or "")[:5] == stamp:
                due.append((task, str(slot.get("text") or "到点啦，记得完成今天的小任务。").strip()))
    return due


# ---------------------------------------------------------------------------
# 入站：老人回复 → 游戏任务完成
# ---------------------------------------------------------------------------
def _stable_event_id(binding_id: str, task_id: str, message_id: str) -> str:
    raw = f"{binding_id}|{task_id}|{message_id or ''}|{_today_utc8()}".encode("utf-8")
    return "evt_" + hashlib.sha256(raw).hexdigest()[:24]


def _match_task(tasks: List[Dict[str, Any]], text: str) -> Optional[Dict[str, Any]]:
    """把老人的一句话匹配到最可能的待办任务；匹配不到就退回唯一/最近那条。"""
    value = str(text or "").strip()
    if not tasks:
        return None
    if len(tasks) == 1:
        return tasks[0]
    keyword_to_template = {
        "吃药|药|服药|吃过了|吃了药": "daily_medication_record",
        "血压|量血压": "daily_bp_record",
        "血糖|测血糖": "daily_glucose_record",
        "散步|走了|走路|运动|锻炼|步数": "daily_exercise_record",
        "喝水|渴": "daily_hydration_reminder",
        "复查|医院|复诊|挂号": "followup_visit_record",
    }
    import re as _re

    for pattern, template_id in keyword_to_template.items():
        if _re.search(pattern, value):
            for task in tasks:
                if str(task.get("template_id") or "") == template_id:
                    return task
    # 兜底：拿 window_start 最近、还没结算的那条。
    active = [t for t in tasks if str(t.get("status") or "") not in {"settled", "verified"}]
    if active:
        return min(active, key=lambda t: int(t.get("window_start") or 0))
    return tasks[0]


def complete_task_from_reply(
    binding_id: str,
    text: str,
    has_photo: bool,
    message_id: str = "",
) -> Dict[str, Any]:
    """sidecar 在老人回复时调用：匹配待办、提交验证结果，返回游戏侧结算结果。

    只提交最小事实（哪个任务、哪种凭证、什么时间），不传原图、不传诊断。
    游戏侧据此自动结算发灵石；「已记上」回执由下面的 claim_notifications 补发。
    """
    bundle = pending(binding_id)
    tasks = bundle["tasks"]
    task = _match_task(tasks, text)
    if not task:
        return {"ok": False, "reason": "no_pending_task"}
    # consent_version 在绑定上（任务的 taskView 不带），回传时必须与绑定当前版本一致。
    consent_version = int((bundle.get("binding") or {}).get("consent_version") or 1)
    verification = VERIFICATION_PHOTO if has_photo else VERIFICATION_TEXT
    # 该模板允许的凭证级别由游戏侧 rules.ts 决定；这里先按“有图=photo、纯文字=self_report”。
    payload = {
        "event_id": _stable_event_id(binding_id, str(task["task_instance_id"]), message_id),
        "task_instance_id": str(task["task_instance_id"]),
        "cultivator_id": str(task["cultivator_id"]),
        "binding_id": binding_id,
        "consent_version": consent_version,
        "verification_level": verification,
        "source": verification,
        "channel": "wechat_ilink",
        "observed_at": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
        "rule_version": str(task.get("rule_version") or "integration-v1"),
    }
    if os.environ.get("OPENCLAW_DRY_RUN", "").strip().lower() in {"1", "true", "yes", "on"}:
        print(f"[dry-run] POST /internal/v1/task-results {json.dumps(payload, ensure_ascii=False)}")
        return {"ok": True, "dry_run": True, "payload": payload}
    try:
        result = game_post("/internal/v1/task-results", payload)
        return {"ok": True, "data": result.get("data") or result}
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "error": str(exc)}


# ---------------------------------------------------------------------------
# 结算回执：把「已记上」回推给老人
# ---------------------------------------------------------------------------
def claim_notifications(target: str) -> int:
    """领取游戏侧的结算通知，回推给老人并 ack。返回成功回执的条数。"""
    try:
        result = game_post("/internal/v1/notifications/claim", {"limit": 10})
    except Exception as exc:  # noqa: BLE001
        print(f"[warn] 领取通知失败：{exc}")
        return 0
    notifications = ((result.get("data") or {}).get("notifications")) or []
    acked = 0
    for note in notifications:
        nid = note.get("notification_id")
        lease = note.get("lease_token")
        payload = note.get("payload") or {}
        stones = payload.get("spirit_stones")
        # 只回“已记上”，不报灵石多少、不评价健康。
        text = "今天的记录已记上啦，家人那边也同步看到了。"
        if isinstance(stones, int) and stones > 0:
            text = "今天的记录已记上啦，家人那边也同步看到了。"
        if target:
            sent = send_wechat(target, text)
            if not sent.get("ok") and not sent.get("dry_run"):
                try:
                    game_post(f"/internal/v1/notifications/{nid}/nack", {"lease_token": lease})
                    continue
                except Exception:  # noqa: BLE001
                    continue
        try:
            game_post(f"/internal/v1/notifications/{nid}/ack", {"lease_token": lease})
            acked += 1
        except Exception as exc:  # noqa: BLE001
            print(f"[warn] ack 失败：{exc}")
    return acked


# ---------------------------------------------------------------------------
# 状态与主循环
# ---------------------------------------------------------------------------
def _load_state() -> Dict[str, Any]:
    if STATE_PATH.exists():
        try:
            return json.loads(STATE_PATH.read_text(encoding="utf-8"))
        except (ValueError, OSError):
            return {}
    return {}


def _save_state(state: Dict[str, Any]) -> None:
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")


def tick(binding_id: str, target: str, elder_id: str, state: Dict[str, Any]) -> int:
    """一轮：拉待办 → 到点推提醒 → 领结算回执。返回本轮发送的消息条数。"""
    sent = 0
    stamp = _now_hhmm()
    today = _today_utc8()
    for task, text in due_reminders(pending_tasks(binding_id), stamp, elder_id):
        key = f"{task['task_instance_id']}:{today}:{stamp}"
        if state.get("sent", {}).get(key):
            continue
        if not target:
            print(f"[skip] 未配置 OPENCLAW_SEND_TARGET，跳过：{text}")
            state.setdefault("sent", {})[key] = True
            continue
        print(f"[send] {text}")
        result = send_wechat(target, text)
        if result.get("ok") or result.get("dry_run"):
            state.setdefault("sent", {})[key] = True
            sent += 1
        else:
            print(f"[error] 发送失败：{result}")
    claim_notifications(target)
    return sent


def main() -> int:
    binding_id = os.environ.get("BINDING_ID", "").strip()
    elder_bindings = os.environ.get("ELDER_BINDINGS", "").strip()
    elder_id = os.environ.get("ELDER_ID", "elder_demo_001").strip() or "elder_demo_001"
    target = os.environ.get("OPENCLAW_SEND_TARGET", "").strip()
    once = "--once" in sys.argv

    print(f"[bridge] binding_id={'<已配置>' if binding_id else '<未配置>'} elder_id={elder_id} target={'<已配置>' if target else '<未配置>'} once={once}")
    if not binding_id and not elder_bindings:
        print("[warn] 未配置 BINDING_ID；游戏侧完成绑定后把 binding_id 填进环境变量。")
    state = _load_state()
    while True:
        try:
            if binding_id:
                tick(binding_id, target, elder_id, state)
            elif elder_bindings:
                for entry in json.loads(elder_bindings):
                    tick(str(entry["binding_id"]), target, elder_id, state)
        except Exception as exc:  # noqa: BLE001
            print(f"[error] tick 异常：{exc}")
        _save_state(state)
        if once:
            break
        time.sleep(60)


if __name__ == "__main__":
    raise SystemExit(main())
