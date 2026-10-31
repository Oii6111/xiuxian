"""D 游戏适配层：只有经审核的最小事实进入 C，默认 dry-run。"""
from __future__ import annotations
import hashlib
import json
import os
import sqlite3
import subprocess
import sys
import time
import urllib.error
import urllib.request
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import quote

BASE_DIR = Path(__file__).resolve().parent
UTC8 = timezone(timedelta(hours=8))
STATE_PATH = Path(os.environ.get("BRIDGE_STATE", str(BASE_DIR / "bot_data/bridge.sqlite3")))
ELDER_DB = Path(os.environ.get("ELDER_DB_PATH", str(BASE_DIR.parent / "wechat-sidecar/bot_data/elder_assistant.sqlite3")))
# C 已发布的模板是唯一来源；新增模板须发布新版本，不能修改旧任务规则。
TASK_TEMPLATES = {
    "daily_medication_record": {"time": "19:30", "text": "按您原来的用药安排完成后，跟我说一声就好；没吃或不确定也可以告诉我。"},
    "daily_planned_record": {"time": "10:00", "text": "今天的个人计划完成后，跟我说一声就记上。"},
    "daily_step_record": {"time": "09:00", "text": "如果今天已记录步数，可以把记录发来，确认后再同步给家人。"},
    "daily_measurement_record": {"time": "08:00", "text": "请按已有测量计划记录，方便时把记录发来；不需要额外增加测量。"},
}

class BridgeError(ValueError):
    pass

def dry_run():
    return os.environ.get("OPENCLAW_DRY_RUN", "1").lower() not in {"0", "false", "no", "off"}

def save_route(route):
    """扫码绑定成功后持久保存路由；与 ELDER_BINDINGS 合并校验，冲突时拒绝。"""
    with _store() as conn:
        conn.execute("INSERT OR REPLACE INTO routes(binding_id, payload) VALUES (?, ?)", (route["binding_id"], _canonical(route)))
    routes()

def routes():
    """映射由真实绑定流程配置；禁止一个默认接收者承接所有账号通知。"""
    entries = json.loads(os.environ.get("ELDER_BINDINGS", "[]"))
    if isinstance(entries, list) and STATE_PATH.exists():
        with _store() as conn:
            entries = entries + [json.loads(row["payload"]) for row in conn.execute("SELECT payload FROM routes")]
    if not isinstance(entries, list):
        raise BridgeError("ELDER_BINDINGS must be an array")
    required = {"binding_id", "elder_id", "sender_id", "channel_account_id", "target", "consent_version"}
    identifiers, elders, identities = set(), set(), set()
    for route in entries:
        if not isinstance(route, dict) or set(route) != required:
            raise BridgeError("Invalid binding route fields")
        if any(not isinstance(route[key], str) or not route[key].strip() for key in required - {"consent_version"}):
            raise BridgeError("Missing verified identity or target")
        if type(route["consent_version"]) is not int or route["consent_version"] < 1:
            raise BridgeError("Missing confirmed consent version")
        identity = (route["channel_account_id"], route["sender_id"])
        if route["binding_id"] in identifiers or route["elder_id"] in elders or identity in identities:
            raise BridgeError("Ambiguous binding route")
        identifiers.add(route["binding_id"])
        elders.add(route["elder_id"])
        identities.add(identity)
    return entries

def route_for_elder(elder_id):
    matches = [route for route in routes() if route["elder_id"] == elder_id]
    if len(matches) != 1:
        raise BridgeError("Unknown elder route")
    return matches[0]

def route_for(binding_id):
    matches = [route for route in routes() if route["binding_id"] == binding_id]
    if len(matches) != 1:
        raise BridgeError("Unknown binding route")
    return matches[0]

def game_request(method, path, body=None):
    token = os.environ.get("HEALTH_SERVICE_TOKEN", "").strip()
    if not token:
        raise BridgeError("HEALTH_SERVICE_TOKEN is required")
    base = os.environ.get("GAME_API_BASE", "http://127.0.0.1:8080").rstrip("/")
    req = urllib.request.Request(base + path, method=method,
        data=None if body is None else json.dumps(body).encode("utf-8"),
        headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    # 不通过系统代理，也不跟随重定向转发内部凭证。
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    try:
        with opener.open(req, timeout=8) as response:
            result = json.load(response)
    except urllib.error.HTTPError as error:
        try:
            code = json.loads(error.read()).get("code", "HTTP_ERROR")
        except (ValueError, AttributeError):
            code = "HTTP_ERROR"
        raise BridgeError(str(code)) from None
    if not isinstance(result, dict) or result.get("ok") is not True:
        raise BridgeError("INVALID_RESULT")
    return result["data"]

def enable_task(binding_id, template_id, date):
    """老人已确认当前适用的安排后，为该绑定启用当日任务；同一模板同一日重复调用返回原实例。"""
    route_for(binding_id)
    if template_id not in TASK_TEMPLATES:
        raise BridgeError("TEMPLATE_UNAVAILABLE")
    return game_post(f"/internal/v1/bindings/{quote(binding_id, safe='')}/tasks", {"template_id": template_id, "date": date})

def game_get(path):
    return game_request("GET", path)

def game_post(path, body):
    return game_request("POST", path, body)

def pending(binding_id):
    route = route_for(binding_id)
    data = game_get(f"/internal/v1/bindings/{quote(binding_id, safe='')}/tasks")
    binding = data["binding"]
    if (binding.get("binding_id") != binding_id or binding.get("status") != "active"
            or binding.get("consent_status") != "active" or not binding.get("connected")
            or binding.get("consent_version") != route["consent_version"]):
        raise BridgeError("CONSENT_OR_CONNECTION_INVALID")
    return data

@contextmanager
def _store():
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(STATE_PATH, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("CREATE TABLE IF NOT EXISTS results (event_id TEXT PRIMARY KEY, payload TEXT NOT NULL, sent INTEGER NOT NULL DEFAULT 0)")
    conn.execute("CREATE TABLE IF NOT EXISTS delivered (id TEXT PRIMARY KEY)")
    conn.execute("CREATE TABLE IF NOT EXISTS routes (binding_id TEXT PRIMARY KEY, payload TEXT NOT NULL)")
    try:
        with conn:
            yield conn
    finally:
        conn.close()

def _canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)

def submit_confirmed(binding_id, task_id, event_id, observed_at, verification_level, sender_id, channel_account_id):
    """仅供 D 审核器调用；事实 ID、完成时间及验证级别必须已确认并固定。"""
    route = route_for(binding_id)
    if (sender_id, channel_account_id) != (route["sender_id"], route["channel_account_id"]):
        raise BridgeError("IDENTITY_MISMATCH")
    if not event_id or not task_id:
        raise BridgeError("Stable event and task IDs are required")
    occurred = datetime.fromisoformat(observed_at.replace("Z", "+00:00"))
    if occurred.tzinfo is None:
        raise BridgeError("observed_at requires a timezone")
    canonical_time = occurred.astimezone(timezone.utc).isoformat(timespec="seconds")
    # 幂等键不包含日期；重试不会改变完成时间或重选另一条待办。
    stable_id = "evt_" + hashlib.sha256(_canonical([binding_id, event_id]).encode()).hexdigest()
    bundle = pending(binding_id)
    if not dry_run():
        with _store() as conn:
            previous = conn.execute("SELECT payload FROM results WHERE event_id = ?", (stable_id,)).fetchone()
        if previous:
            payload = json.loads(previous["payload"])
            if (payload["task_instance_id"], payload["observed_at"], payload["verification_level"]) != (task_id, canonical_time, verification_level):
                raise BridgeError("EVENT_CONFLICT")
            return _deliver_result(payload)
    task = next((task for task in bundle["tasks"] if task["task_instance_id"] == task_id), None)
    if not task:
        raise BridgeError("TASK_NOT_PENDING")
    if not task["window_start"] <= occurred.timestamp() < task["window_end"] or occurred.timestamp() > time.time():
        raise BridgeError("TASK_WINDOW")
    if verification_level not in task["verification_levels"]:
        raise BridgeError("VERIFICATION_NOT_ALLOWED")
    payload = {
        "event_id": stable_id, "task_instance_id": task_id,
        "cultivator_id": task["cultivator_id"], "binding_id": binding_id,
        "consent_version": route["consent_version"], "verification_level": verification_level,
        "source": verification_level, "channel": "wechat_ilink",
        "observed_at": canonical_time, "rule_version": task["rule_version"],
    }
    if dry_run():
        return {"dry_run": True, "payload": payload}
    with _store() as conn:
        conn.execute("INSERT OR IGNORE INTO results(event_id, payload) VALUES (?, ?)", (stable_id, _canonical(payload)))
        stored = conn.execute("SELECT payload FROM results WHERE event_id = ?", (stable_id,)).fetchone()
        if stored["payload"] != _canonical(payload):
            raise BridgeError("EVENT_CONFLICT")
    return _deliver_result(payload)

def _deliver_result(payload):
    bundle = pending(payload["binding_id"])
    if bundle["binding"]["consent_version"] != payload["consent_version"]:
        raise BridgeError("CONSENT_REVOKED")
    result = game_post("/internal/v1/task-results", payload)
    with _store() as conn:
        conn.execute("UPDATE results SET sent = 1 WHERE event_id = ?", (payload["event_id"],))
    return result

def retry_results():
    if dry_run():
        return
    with _store() as conn:
        queued = conn.execute("SELECT payload FROM results WHERE sent = 0 LIMIT 50").fetchall()
    for row in queued:
        try:
            _deliver_result(json.loads(row["payload"]))
        except (BridgeError, OSError):
            # 保留原请求，授权失效不能自动升级为新授权版本。
            continue

def complete_task_from_reply(binding_id, text, has_photo, message_id=""):
    """兼容旧调用但拒绝猜测：聊天关键词和图片存在不等于完成证据。"""
    return {"ok": False, "reason": "explicit_task_and_verified_evidence_required"}

def send_wechat(route, text):
    """直接走 iLink 网关发消息；不再依赖 openclaw CLI。"""
    if dry_run():
        return False
    try:
        import sys
        from pathlib import Path
        sidecar = str(Path(__file__).resolve().parent.parent / "wechat-sidecar")
        if sidecar not in sys.path:
            sys.path.insert(0, sidecar)
        import ilink_gateway
        result = ilink_gateway.send_to(str(route.get("channel_account_id", "")), str(route.get("target", "")), text)
        return bool(result.get("ok"))
    except (ImportError, OSError):
        return False

def claim_notifications():
    if dry_run():
        return 0
    # 一次只领一条，避免排队发送导致后续 30 秒租约过期。
    notes = game_post("/internal/v1/notifications/claim", {"limit": 1})["notifications"]
    for note in notes:
        path = "/internal/v1/notifications/" + quote(note["notification_id"], safe="")
        lease = {"lease_token": note["lease_token"]}
        try:
            route = route_for(note["binding_id"])
            bundle = pending(note["binding_id"])
            if bundle["binding"]["consent_version"] != note["consent_version"]:
                raise BridgeError("CONSENT_REVOKED")
            with _store() as conn:
                sent = conn.execute("SELECT id FROM delivered WHERE id = ?", (note["notification_id"],)).fetchone()
            if not sent:
                if time.time() + 10 >= note["lease_until"]:
                    raise BridgeError("LEASE_EXPIRING")
                if not send_wechat(route, "这次任务记录已同步给家人。"):
                    raise BridgeError("DELIVERY_FAILED")
                with _store() as conn:
                    conn.execute("INSERT OR IGNORE INTO delivered VALUES (?)", (note["notification_id"],))
            game_post(path + "/ack", lease)
            return 1
        except (BridgeError, OSError, subprocess.SubprocessError):
            try:
                game_post(path + "/nack", lease)
            except (BridgeError, OSError):
                pass
    return 0

def tick():
    current = datetime.now(UTC8)
    for route in routes():
        try:
            bundle = pending(route["binding_id"])
            for task in bundle["tasks"]:
                reminder = TASK_TEMPLATES.get(task["template_id"])
                if (not reminder or task["status"] in {"verified", "settled"}
                        or not task["window_start"] <= current.timestamp() < task["window_end"]
                        or reminder["time"] != current.strftime("%H:%M") or dry_run()):
                    continue
                marker = f"reminder:{task['task_instance_id']}:{current.date()}:{reminder['time']}"
                with _store() as conn:
                    sent = conn.execute("SELECT id FROM delivered WHERE id = ?", (marker,)).fetchone()
                if not sent and send_wechat(route, reminder["text"]):
                    with _store() as conn:
                        conn.execute("INSERT OR IGNORE INTO delivered VALUES (?)", (marker,))
        except (BridgeError, OSError, subprocess.SubprocessError):
            continue
    retry_results()
    claim_notifications()

def main():
    routes()
    while True:
        tick()
        if "--once" in sys.argv:
            return 0
        time.sleep(60)

if __name__ == "__main__":
    raise SystemExit(main())
