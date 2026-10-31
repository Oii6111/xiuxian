"""腾讯 iLink 长轮询网关（替代 openclaw-health-hook）。

协议参考腾讯 openclaw-weixin（iLink）HTTP 接口：
- POST /ilink/bot/get_bot_qrcode?bot_type=3   扫码登录（在 ilink_binding.py 中）
- GET  /ilink/bot/get_qrcode_status?qrcode=…  扫码状态
- POST /ilink/bot/getupdates                  长轮询收消息（游标 get_updates_buf）
- POST /ilink/bot/sendmessage                 发送文本（需要 context_token）

这里只做"收消息 → 交给 elder_assistant.handle_message → 发回复"，
绑定、授权与结算仍然走 ilink_binding.py 和 C 后端的既有接口。
"""

from __future__ import annotations

import base64
import hashlib
import json
import logging
import os
import secrets
import threading
import time
from pathlib import Path

import requests

log = logging.getLogger("ilink.gateway")

DEFAULT_BASE = os.environ.get("ILINK_API_BASE", "https://ilinkai.weixin.qq.com").rstrip("/")
CLIENT_VERSION = str((2 << 16) | (4 << 8) | 8)  # 2.4.8
BOT_AGENT = "xiuxian-sidecar/1.0 (python)"
CREDENTIALS = Path(os.environ.get(
    "ILINK_CREDENTIALS",
    str(Path(__file__).resolve().parent / "bot_data/ilink_accounts.json"),
))
STATE = Path(os.environ.get(
    "ILINK_STATE",
    str(Path(__file__).resolve().parent / "bot_data/ilink_state.json"),
))
SEEN_LIMIT = 500


def elder_ref(bot_id: str, user_id: str) -> str:
    """与 ilink_binding.elder_ref 保持一致，保证同一个人映射到同一份档案。"""
    return "wx_" + hashlib.sha256(json.dumps([bot_id, user_id], separators=(",", ":")).encode()).hexdigest()[:24]


def _uin() -> str:
    return base64.b64encode(str(secrets.randbelow(2 ** 32)).encode()).decode()


def _headers(token: str = "") -> dict:
    headers = {
        "Content-Type": "application/json",
        "iLink-App-Id": "bot",
        "iLink-App-ClientVersion": CLIENT_VERSION,
    }
    if token:
        headers.update({
            "AuthorizationType": "ilink_bot_token",
            "X-WECHAT-UIN": _uin(),
            "Authorization": f"Bearer {token}",
        })
    return headers


def base_info() -> dict:
    return {"channel_version": "2.4.8", "bot_agent": BOT_AGENT}


class ILinkError(RuntimeError):
    def __init__(self, message: str, stale: bool = False) -> None:
        super().__init__(message)
        self.stale = stale


class ILinkClient:
    def __init__(self, bot_token: str, base_url: str = "") -> None:
        self.token = bot_token
        self.base = (base_url or DEFAULT_BASE).rstrip("/")

    def _post(self, path: str, payload: dict, timeout: float = 20.0) -> dict:
        response = requests.post(self.base + path, json=payload, headers=_headers(self.token), timeout=timeout)
        if response.status_code >= 400:
            raise ILinkError(f"HTTP {response.status_code}")
        data = response.json()
        ret = data.get("ret", 0)
        errcode = data.get("errcode", 0)
        if ret not in (0, None) or errcode not in (0, None):
            stale = ret == -14 or errcode == -14
            raise ILinkError(f"ret={ret} errcode={errcode} errmsg={data.get('errmsg', '')}", stale=stale)
        return data

    def get_updates(self, cursor: str, timeout: float = 40.0) -> dict:
        return self._post("/ilink/bot/getupdates", {"get_updates_buf": cursor, "base_info": base_info()}, timeout=timeout)

    def send_text(self, to_user: str, text: str, context_token: str) -> dict:
        msg = {
            "from_user_id": "",
            "to_user_id": to_user,
            "client_id": f"xiuxian-{int(time.time() * 1000)}-{secrets.token_hex(3)}",
            "message_type": 2,
            "message_state": 2,
            "context_token": context_token,
            "item_list": [{"type": 1, "text_item": {"text": str(text)}}],
        }
        return self._post("/ilink/bot/sendmessage", {"msg": msg, "base_info": base_info()}, timeout=20.0)


def extract_text(raw: dict) -> str:
    parts: list[str] = []
    for item in raw.get("item_list") or []:
        if not isinstance(item, dict):
            continue
        if item.get("type") == 1 and isinstance(item.get("text_item"), dict):
            value = item["text_item"].get("text")
            if isinstance(value, str):
                parts.append(value)
        voice = item.get("voice_item")
        if isinstance(voice, dict) and isinstance(voice.get("text"), str):
            parts.append(voice["text"])
    return "\n".join(p.strip() for p in parts if p and p.strip())


class StateStore:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.lock = threading.Lock()
        self.data = self._load()

    def _load(self) -> dict:
        if not self.path.exists():
            return {}
        try:
            return json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return {}

    def for_bot(self, bot_id: str) -> dict:
        with self.lock:
            return dict(self.data.get(bot_id, {}))

    def update(self, bot_id: str, **changes) -> None:
        with self.lock:
            entry = self.data.setdefault(bot_id, {})
            entry.update(changes)
            seen = entry.get("seen") or []
            entry["seen"] = seen[-SEEN_LIMIT:]
            self.path.parent.mkdir(parents=True, exist_ok=True)
            temporary = self.path.with_suffix(".tmp")
            temporary.write_text(json.dumps(self.data, ensure_ascii=False), encoding="utf-8")
            os.replace(temporary, self.path)


def _load_credentials() -> list[dict]:
    if not CREDENTIALS.exists():
        return []
    try:
        data = json.loads(CREDENTIALS.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    records = []
    for record in data.values():
        if isinstance(record, dict) and record.get("bot_token") and record.get("ilink_bot_id"):
            records.append(record)
    return records


class Gateway:
    """每个已绑定 Bot 一个线程，游标与去重状态持久化到 bot_data/ilink_state.json。"""

    def __init__(self, reply=None) -> None:
        self.reply = reply
        self.state = StateStore(STATE)
        self._threads: list[threading.Thread] = []
        self._started: set[str] = set()
        self._stop = threading.Event()
        self.failures = 0
        self.last_error = ""
        self.connected_bots: list[str] = []

    def _handle(self, record: dict, client: ILinkClient, raw: dict) -> None:
        if raw.get("group_id"):
            return
        from_user = str(raw.get("from_user_id") or "")
        context = str(raw.get("context_token") or "")
        text = extract_text(raw)
        if not from_user or not text:
            return
        bot_id = str(record.get("ilink_bot_id"))
        message_id = str(raw.get("msg_id") or raw.get("client_id") or "")
        seen = self.state.for_bot(bot_id).get("seen") or []
        key = message_id or hashlib.sha256(f"{from_user}:{text}".encode()).hexdigest()[:16]
        if key in seen:
            return
        self.state.update(bot_id, seen=seen + [key])
        elder_id = elder_ref(bot_id, from_user)
        self.state.update(bot_id, contexts={**self.state.for_bot(bot_id).get("contexts", {}), from_user: context})
        try:
            result = self.reply({
                "elder_id": elder_id,
                "sender_id": from_user,
                "channel_account_id": bot_id,
                "channel": "weixin_ilink",
                "text": text,
                "attachments": [],
                "consent": {"family_share": True},
            })
            answer = str(result.get("reply") or "").strip()
        except Exception as error:  # noqa: BLE001 - 任何业务异常都要回一句可用的
            log.warning("elder reply failed: %s", error)
            answer = "我这边刚才没处理过来，你再说一遍好吗？"
        if answer and context:
            try:
                client.send_text(from_user, answer, context)
            except ILinkError as error:
                log.warning("sendmessage failed for %s: %s", from_user, error)

    def _loop(self, record: dict) -> None:
        bot_id = str(record.get("ilink_bot_id"))
        client = ILinkClient(str(record.get("bot_token")), str(record.get("baseurl") or DEFAULT_BASE))
        backoff = 2.0
        while not self._stop.is_set():
            cursor = str(self.state.for_bot(bot_id).get("cursor") or "")
            try:
                data = client.get_updates(cursor)
            except (ILinkError, requests.RequestException) as error:
                self.failures += 1
                self.last_error = str(error)
                stale = isinstance(error, ILinkError) and error.stale
                log.warning("getupdates failed (%s)%s", error, " - token stale" if stale else "")
                if stale:
                    return
                self._stop.wait(backoff if self.failures >= 3 else 2.0)
                backoff = min(backoff * 2, 30.0)
                continue
            backoff = 2.0
            self.failures = 0
            self.last_error = ""
            for raw in data.get("msgs") or []:
                if isinstance(raw, dict):
                    try:
                        self._handle(record, client, raw)
                    except Exception as error:  # noqa: BLE001 - 单条消息不能打断轮询
                        log.warning("message handling failed: %s", error)
            new_cursor = data.get("get_updates_buf")
            if new_cursor:
                self.state.update(bot_id, cursor=new_cursor)
            self._stop.wait(0.2)

    def start(self) -> None:
        records = _load_credentials()
        self.connected_bots = [str(r.get("ilink_bot_id")) for r in records]
        for record in records:
            bot_id = str(record.get("ilink_bot_id"))
            if bot_id in self._started:
                continue
            self._started.add(bot_id)
            thread = threading.Thread(target=self._loop, args=(record,), name=f"ilink-{bot_id}", daemon=True)
            thread.start()
            self._threads.append(thread)
            log.info("iLink gateway started for bot %s", bot_id)

    def supervise(self, interval: float = 10.0) -> None:
        """扫码绑定后凭证才落盘，这里定期发现新 Bot 并接管。"""
        while not self._stop.is_set():
            try:
                self.start()
            except Exception as error:  # noqa: BLE001 - 监督线程不能死
                log.warning("gateway supervise failed: %s", error)
            self._stop.wait(interval)

    def stop(self) -> None:
        self._stop.set()

    def status(self) -> dict:
        return {
            "configured": bool(self._threads),
            "bots": self.connected_bots,
            "failures": self.failures,
            "last_error": self.last_error,
            "polling": any(t.is_alive() for t in self._threads),
            "cursor_state": str(STATE),
        }


_gateway: Gateway | None = None


def start_background(reply=None, enabled: bool | None = None) -> Gateway | None:
    """在 sidecar 进程内启动网关；没有绑定凭证时静默跳过。"""
    global _gateway
    if _gateway is not None:
        return _gateway
    if enabled is None:
        enabled = os.environ.get("ILINK_GATEWAY_ENABLED", "1").lower() not in {"0", "false", "off", "no"}
    if not enabled:
        return None
    if reply is None:
        from elder_assistant import handle_message

        reply = handle_message
    _gateway = Gateway(reply=reply)
    _gateway.start()
    threading.Thread(target=_gateway.supervise, name="ilink-supervisor", daemon=True).start()
    return _gateway


def status() -> dict:
    return _gateway.status() if _gateway else {"configured": False, "polling": False, "bots": []}


def send_to(bot_id: str, user_id: str, text: str) -> dict:
    """给已经和 Bot 聊过天的老人主动发消息（复用入站时记下的 context_token）。"""
    record = next((r for r in _load_credentials() if str(r.get("ilink_bot_id")) == bot_id), None)
    if record is None:
        return {"ok": False, "error": "unknown_bot"}
    store = StateStore(STATE)
    entry = store.for_bot(bot_id)
    context = (entry.get("contexts") or {}).get(user_id)
    if not context:
        return {"ok": False, "error": "no_context_token"}
    client = ILinkClient(str(record.get("bot_token")), str(record.get("baseurl") or DEFAULT_BASE))
    try:
        client.send_text(user_id, text, context)
        return {"ok": True}
    except (ILinkError, requests.RequestException) as error:
        return {"ok": False, "error": str(error)}
