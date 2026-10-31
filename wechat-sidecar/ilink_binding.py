"""iLink 扫码绑定与游戏事件路由（D 健康域）。

年轻人在网页游戏里点“绑定老人微信”→ C 生成一次性业务凭据（不展示给任何人）→ 本模块向 iLink 申请二维码 →
老人用自己的微信扫码确认 → 以 iLink 返回的 bot/用户标识向 C 确认绑定。老人侧不需要任何客户端或邀请码。
之后老人在微信里确认的用药计划启用当日任务，明确的本人完成反馈按 self_report 提交给 C 结算。
"""
from __future__ import annotations
import base64
import hashlib
import hmac
import importlib.util
import json
import os
import secrets
import threading
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

import requests
from flask import jsonify, request

_spec = importlib.util.spec_from_file_location("game_task_bridge", Path(__file__).resolve().parent.parent / "wechat-bridge/game_task_bridge.py")
bridge = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(bridge)

UTC8 = timezone(timedelta(hours=8))
ILINK_BASE = os.environ.get("ILINK_API_BASE", "https://ilinkai.weixin.qq.com").rstrip("/")
CLIENT_VERSION = str((2 << 16) | (4 << 8) | 8)
CREDENTIALS = Path(os.environ.get("ILINK_CREDENTIALS", str(Path(__file__).resolve().parent / "bot_data/ilink_accounts.json")))
_sessions: dict[str, dict] = {}
_lock = threading.Lock()


def elder_ref(bot_id: str, user_id: str) -> str:
    """与 openclaw-health-hook 的默认推导一致：同一微信用户在同一 Bot 下始终对应同一老人档案。"""
    return "wx_" + hashlib.sha256(json.dumps([bot_id, user_id], separators=(",", ":")).encode()).hexdigest()[:24]


def _headers(post: bool) -> dict:
    headers = {"iLink-App-Id": "bot", "iLink-App-ClientVersion": CLIENT_VERSION}
    if post:
        uin = str(secrets.randbelow(2 ** 32)).encode()
        headers.update({"Content-Type": "application/json", "AuthorizationType": "ilink_bot_token", "X-WECHAT-UIN": base64.b64encode(uin).decode()})
    return headers


def _qr_svg(content: str) -> str:
    try:
        import qrcode
        import qrcode.image.svg
    except ImportError:
        return ""
    image = qrcode.make(content, image_factory=qrcode.image.svg.SvgPathImage, box_size=12)
    return image.to_string(encoding="unicode")


def _save_credentials(record: dict) -> None:
    # Bot 凭证只留在 D 服务端，不进入 C、游戏客户端或模型上下文。
    CREDENTIALS.parent.mkdir(parents=True, exist_ok=True)
    existing = json.loads(CREDENTIALS.read_text(encoding="utf-8")) if CREDENTIALS.exists() else {}
    existing[record["ilink_bot_id"] + ":" + record["ilink_user_id"]] = record
    temporary = CREDENTIALS.with_suffix(".tmp")
    temporary.write_text(json.dumps(existing, ensure_ascii=False), encoding="utf-8")
    os.replace(temporary, CREDENTIALS)


def start(invite_token: str) -> dict:
    response = requests.post(ILINK_BASE + "/ilink/bot/get_bot_qrcode?bot_type=3", json={"local_token_list": []}, headers=_headers(True), timeout=10)
    data = response.json()
    if not data.get("qrcode") or not data.get("qrcode_img_content"):
        raise ValueError("ILINK_QRCODE_UNAVAILABLE")
    bind_id = secrets.token_urlsafe(16)
    with _lock:
        _sessions[bind_id] = {"invite_token": invite_token, "qrcode": data["qrcode"], "content": data["qrcode_img_content"], "base": ILINK_BASE, "status": "wait", "created": time.time()}
    return {"bind_id": bind_id, "qr_content": data["qrcode_img_content"], "qr_svg": _qr_svg(data["qrcode_img_content"]), "status": "wait"}


def poll(bind_id: str) -> dict:
    with _lock:
        session = _sessions.get(bind_id)
    if not session or time.time() - session["created"] > 600:
        return {"status": "expired"}
    if session["status"] in {"bound", "failed"}:
        return {"status": session["status"], "binding_id": session.get("binding_id", ""), "code": session.get("code", "")}
    try:
        data = requests.get(session["base"] + "/ilink/bot/get_qrcode_status", params={"qrcode": session["qrcode"]}, headers=_headers(False), timeout=40).json()
    except (requests.RequestException, ValueError):
        return {"status": "wait"}
    status = str(data.get("status", "wait"))
    if status == "scaned_but_redirect" and data.get("redirect_host"):
        session["base"] = "https://" + str(data["redirect_host"]).strip("/")
    if status != "confirmed":
        return {"status": status}
    bot_id, user_id = str(data["ilink_bot_id"]), str(data["ilink_user_id"])
    _save_credentials({"ilink_bot_id": bot_id, "ilink_user_id": user_id, "bot_token": data["bot_token"], "baseurl": data.get("baseurl", session["base"])})
    try:
        binding = bridge.game_post("/internal/v1/bindings/confirm", {
            "invite_token": session["invite_token"], "channel": "wechat_ilink", "channel_account_id": bot_id, "sender_id": user_id,
            "elder_ref": elder_ref(bot_id, user_id), "consent_proof_id": "ilink_qr:" + bind_id, "consent_scope": "family_game",
            "health_processing": True, "ai_processing": True})
        bridge.save_route({"binding_id": binding["binding_id"], "elder_id": elder_ref(bot_id, user_id), "sender_id": user_id,
                           "channel_account_id": bot_id, "target": user_id, "consent_version": binding["consent_version"]})
        session.update(status="bound", binding_id=binding["binding_id"])
    except (bridge.BridgeError, OSError) as error:
        session.update(status="failed", code=str(error))
    session.pop("invite_token", None)
    return {"status": session["status"], "binding_id": session.get("binding_id", ""), "code": session.get("code", "")}


def _active_course(database, elder_id: str) -> bool:
    today = datetime.now(UTC8).date().isoformat()
    with database() as conn:
        return conn.execute("SELECT 1 FROM medication_courses WHERE elder_id = ? AND status = 'active' AND end_date >= ?", (elder_id, today)).fetchone() is not None


def route_event(database, event: dict) -> dict:
    """老人已确认的计划 → 启用当日用药记录；明确的本人完成反馈 → self_report 提交。其他健康事实不进入游戏。"""
    if event.get("family_share") is not True or event.get("event_type") != "medication_taken":
        return {"status": "ignored"}
    route = bridge.route_for_elder(str(event.get("elder_id", "")))
    if not _active_course(database, route["elder_id"]):
        return {"status": "no_confirmed_plan"}
    with database() as conn:
        identity = conn.execute("SELECT * FROM game_event_identity WHERE event_id = ?", (event["event_id"],)).fetchone()
    if not identity:
        return {"status": "identity_unknown"}
    observed = datetime.fromisoformat(str(event["occurred_at"]).replace("Z", "+00:00"))
    if observed.tzinfo is None:
        observed = observed.replace(tzinfo=UTC8)
    task = bridge.enable_task(route["binding_id"], "daily_medication_record", observed.astimezone(UTC8).date().isoformat())
    result = bridge.submit_confirmed(route["binding_id"], task["task_instance_id"], event["event_id"], observed.isoformat(),
                                     "self_report", identity["sender_id"], identity["channel_account_id"])
    return {"status": "submitted", "result": result}


def register_binding_routes(app, database) -> None:
    @app.post("/api/v1/wechat/bind")
    def wechat_bind():
        # 业务凭据由 C 为已登录年轻人的指定角色签发；这里只把它换成 iLink 二维码，不展示给老人。
        payload = request.get_json(silent=True) or {}
        token = payload.get("invite_token")
        if not isinstance(token, str) or not 16 <= len(token) <= 128:
            return jsonify({"ok": False, "code": "INVALID_PAYLOAD"}), 400
        try:
            return jsonify({"ok": True, "data": start(token)})
        except (requests.RequestException, ValueError):
            return jsonify({"ok": False, "code": "ILINK_UNAVAILABLE"}), 503

    @app.get("/api/v1/wechat/bind/<bind_id>")
    def wechat_bind_status(bind_id):
        return jsonify({"ok": True, "data": poll(bind_id)})

    @app.get("/wechat/bind/<bind_id>")
    def wechat_bind_page(bind_id):
        with _lock:
            session = _sessions.get(bind_id)
        if not session:
            return "二维码已失效，请回到游戏重新生成。", 404
        svg = _qr_svg(session["content"]) or f'<p>请在手机微信中打开：<br><code>{session["content"]}</code></p>'
        return f'''<!doctype html><meta charset="utf-8"><title>绑定老人微信</title>
<style>body{{font:20px system-ui;text-align:center;margin:40px;background:#faf3df;color:#493b2c}}svg{{width:320px;height:320px}}</style>
<h1>请老人用自己的微信扫一扫</h1>{svg}
<p>扫码确认后，老人在微信里和健康助手聊天、报告每天的完成情况即可，不需要安装其他应用。</p>
<p>扫码即表示老人同意：健康资料由助手处理，完成记录同步给家人的游戏。</p><p id="s">等待扫码…</p>
<script>const s=document.getElementById('s');const t={{wait:'等待扫码…',scaned:'已扫码，请在手机上确认',bound:'绑定成功，可以关闭此页',expired:'二维码已过期，请回游戏重新生成',failed:'绑定失败，请回游戏重试'}};
async function p(){{const r=await fetch('/api/v1/wechat/bind/{bind_id}');const d=(await r.json()).data;s.textContent=t[d.status]||d.status;if(!['bound','expired','failed'].includes(d.status))setTimeout(p,1500)}}p()</script>'''

    @app.post("/internal/v1/game/health-events")
    def game_health_event():
        expected = os.environ.get("HEALTH_EVENT_SINK_TOKEN", "")
        if not expected or not hmac.compare_digest(request.headers.get("X-Health-Internal-Token", ""), expected):
            return jsonify({"ok": False, "code": "UNAUTHORIZED"}), 401
        try:
            return jsonify({"ok": True, "data": route_event(database, request.get_json(silent=True) or {})})
        except (bridge.BridgeError, ValueError, KeyError) as error:
            return jsonify({"ok": False, "code": str(error)}), 409
        except OSError:
            return jsonify({"ok": False, "code": "GAME_UNAVAILABLE_RETRY"}), 503

    @app.get("/api/v1/elder/bound")
    def elder_bound():
        # 受侧车令牌保护：hook 用它确认发送者已扫码绑定，未绑定不处理健康资料。
        try:
            bridge.route_for_elder(str(request.args.get("elder_id", "")))
            return jsonify({"ok": True, "bound": True})
        except bridge.BridgeError:
            return jsonify({"ok": True, "bound": False})
