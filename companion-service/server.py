"""灵宠聊天 HTTP 服务：把 docs/COMPANION_API.md 的 v1 契约接到大模型。

默认走 DeepSeek（模型 deepseek-flash）；任何 OpenAI 兼容服务都可以用
LLM_BASE_URL / LLM_MODEL 覆盖。模型密钥只留在本服务，不发往 Godot 或浏览器。

运行：
    cd companion-service
    python server.py

没有配置密钥时自动进入 stub 模式，只返回本地固定话术，便于离线联调游戏链路。
"""

from __future__ import annotations

import json
import os
import threading
import time
from collections import OrderedDict
from pathlib import Path

import requests
from flask import Flask, jsonify, request

DEFAULT_BASE_URL = "https://api.deepseek.com/v1"
DEFAULT_MODEL = "deepseek-flash"

# 与 scripts/companion_client.gd 的 Context.ACTIONS 保持一致。
ALLOWED_ACTIONS = ("record", "family", "health", "treasure", "equipment", "boss")
ANIMATIONS = ("idle", "talk", "celebrate")
MAX_MESSAGE = 500
MAX_REPLY = 2000

SYSTEM_PROMPT = """你是《家族修真录》里陪伴年轻人的灵宠，用温和、简短的中文回答。

硬性规则：
1. 只根据我给你的“游戏记录投影”说话，不要编造任务状态、奖励、账本数字或家人情况。
2. 你没有任何执行能力：不能完成任务、不能发灵气、不能改装备、不能加经验。需要操作时只建议玩家去对应页面。
3. 不输出 Markdown、代码块、列表符号和表情符号堆叠；不超过 120 个汉字。
4. 不询问也不复述真实姓名、年龄、病史、用药、体检数值、图片或聊天记录。
5. 记录状态分三种：confirmed（已确认）、unrecorded（未收到）、not_applicable（不适用）。未收到不等于没做，要说“还没收到记录”。
6. 拿不准就建议去“今日记录”页面核对，不要猜。"""


class ServiceError(RuntimeError):
    """对外只暴露稳定的错误码，细节留在服务日志。"""

    def __init__(self, code: str, message: str, status: int = 502) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.status = status


def load_env_file(path: Path) -> None:
    """只补齐缺失的变量，不覆盖调用方显式设置的环境变量。"""
    if not path.exists():
        return
    try:
        from dotenv import load_dotenv
    except ImportError:
        for raw in path.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            name, value = line.split("=", 1)
            os.environ.setdefault(name.strip(), value.strip().strip("'\""))
        return
    load_dotenv(path, override=False)


def setting(name: str, default: str = "") -> str:
    return (os.environ.get(name) or default).strip()


class Config:
    def __init__(self) -> None:
        self.base_url = setting("LLM_BASE_URL", DEFAULT_BASE_URL).rstrip("/")
        self.model = setting("LLM_MODEL", DEFAULT_MODEL)
        self.api_key = setting("LLM_API_KEY") or setting("OPENAI_API_KEY") or setting("DEEPSEEK_API_KEY")
        if self.api_key.lower() in ("your-api-key", "your_api_key", "sk-xxx", "请填写密钥"):
            self.api_key = ""
        self.timeout = float(setting("LLM_TIMEOUT", "20") or 20)
        self.force_stub = setting("COMPANION_PROVIDER").lower() == "stub"
        self.service_token = setting("COMPANION_SERVICE_TOKEN")
        self.host = setting("HOST", "127.0.0.1")
        self.port = int(setting("PORT", "8031") or 8031)

    @property
    def provider(self) -> str:
        if self.force_stub or not self.api_key:
            return "stub"
        return "openai-compatible"

    def session(self) -> requests.Session:
        """LLM_USE_SYSTEM_PROXY=false 时完全忽略环境代理，避免模型请求被本地代理劫持。"""
        session = requests.Session()
        mode = setting("LLM_USE_SYSTEM_PROXY", "auto").lower()
        if mode in ("false", "0", "off", "none"):
            session.trust_env = False
        return session


def _clean_message(value: object) -> str:
    if not isinstance(value, str):
        raise ServiceError("INVALID_REQUEST", "message 必须是字符串", 400)
    text = value.strip()
    if not text:
        raise ServiceError("INVALID_REQUEST", "message 不能为空", 400)
    return text[:MAX_MESSAGE]


def _clean_context(value: object) -> dict:
    """只保留渲染话术需要的字段，避免把整包未知数据带进提示词。"""
    if not isinstance(value, dict):
        return {}
    characters = []
    for item in value.get("characters") or []:
        if not isinstance(item, dict):
            continue
        tasks = []
        for task in item.get("tasks") or []:
            if not isinstance(task, dict):
                continue
            tasks.append({
                "title": str(task.get("title", ""))[:40],
                "status": str(task.get("status", "unrecorded")),
            })
        characters.append({
            "label": str(item.get("label", ""))[:16],
            "kind": str(item.get("kind", "")),
            "has_profile": bool(item.get("has_profile")),
            "tasks": tasks[:8],
        })
    return {
        "as_of_date": str(value.get("as_of_date", ""))[:20],
        "characters": characters[:4],
    }


def validate(payload: object) -> dict:
    if not isinstance(payload, dict):
        raise ServiceError("INVALID_REQUEST", "请求体必须是 JSON 对象", 400)
    if payload.get("schema_version") != 1:
        raise ServiceError("UNSUPPORTED_SCHEMA", "只支持 schema_version 1", 400)
    request_id = payload.get("request_id")
    conversation_id = payload.get("conversation_id")
    if not isinstance(request_id, str) or not request_id.strip():
        raise ServiceError("INVALID_REQUEST", "request_id 缺失", 400)
    if not isinstance(conversation_id, str) or not conversation_id.strip():
        raise ServiceError("INVALID_REQUEST", "conversation_id 缺失", 400)
    companion = payload.get("companion") if isinstance(payload.get("companion"), dict) else {}
    return {
        "request_id": request_id.strip(),
        "conversation_id": conversation_id.strip(),
        "message": _clean_message(payload.get("message")),
        "companion_id": str(companion.get("id", ""))[:32],
        "companion_nickname": str(companion.get("nickname", ""))[:16],
        "context": _clean_context(payload.get("context")),
    }


def render_prompt(request_data: dict) -> list[dict]:
    nickname = request_data["companion_nickname"] or "灵宠"
    context_text = json.dumps(request_data["context"], ensure_ascii=False)
    user = (
        f"玩家对我说：{request_data['message']}\n\n"
        f"游戏记录投影（只作提示，不是权威数据）：{context_text}\n\n"
        f"你现在的名字是“{nickname}”，请直接开口回答。"
    )
    return [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": user},
    ]


def call_model(config: Config, messages: list[dict]) -> str:
    url = f"{config.base_url}/chat/completions"
    body = {
        "model": config.model,
        "messages": messages,
        "temperature": 0.6,
        "max_tokens": 320,
        "stream": False,
    }
    headers = {"Content-Type": "application/json"}
    if config.api_key:
        headers["Authorization"] = f"Bearer {config.api_key}"
    try:
        response = config.session().post(
            url,
            headers=headers,
            data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
            timeout=config.timeout,
        )
    except requests.Timeout as error:
        raise ServiceError("MODEL_TIMEOUT", "模型请求超时") from error
    except requests.RequestException as error:
        raise ServiceError("MODEL_UNREACHABLE", f"模型网络不可用: {error}") from error
    if response.status_code == 401 or response.status_code == 403:
        raise ServiceError("MODEL_UNAUTHORIZED", "模型密钥无效或无权访问")
    if response.status_code >= 400:
        raise ServiceError("MODEL_ERROR", f"模型返回 {response.status_code}")
    try:
        data = response.json()
        content = data["choices"][0]["message"]["content"]
    except (ValueError, KeyError, IndexError, TypeError) as error:
        raise ServiceError("MODEL_BAD_RESPONSE", "模型返回格式无法解析") from error
    if not isinstance(content, str):
        raise ServiceError("MODEL_BAD_RESPONSE", "模型没有返回文本")
    return content


def choose_animation(reply: str) -> str:
    if any(word in reply for word in ("完成", "恭喜", "太棒", "已记录")):
        return "celebrate"
    return "talk"


def choose_actions(request_data: dict, reply: str) -> list[dict]:
    """动作只由本地规则挑选，绝不采用模型给的 id。"""
    text = request_data["message"] + reply
    picks: list[str] = []
    if any(word in text for word in ("家", "老人", "爸", "妈")):
        picks.append("family")
    if any(word in text for word in ("健康", "体检", "属性")):
        picks.append("health")
    if any(word in text for word in ("抽", "祈愿", "聚宝")):
        picks.append("treasure")
    if any(word in text for word in ("装备", "行囊", "武器")):
        picks.append("equipment")
    if any(word in text for word in ("试炼", "Boss", "首领", "闯关")):
        picks.append("boss")
    if any(task.get("status") == "unrecorded"
           for character in request_data["context"].get("characters", [])
           for task in character.get("tasks", [])):
        picks.append("record")
    if not picks:
        picks.append("record")
    labels = {
        "record": "查看今日记录",
        "family": "查看家人",
        "health": "查看档案",
        "treasure": "去祈愿",
        "equipment": "打开行囊",
        "boss": "去试炼",
    }
    unique: list[str] = []
    for action in picks:
        if action in ALLOWED_ACTIONS and action not in unique:
            unique.append(action)
    return [{"id": action, "label": labels[action]} for action in unique[:3]]


def stub_reply(request_data: dict) -> str:
    pending = [
        task["title"]
        for character in request_data["context"].get("characters", [])
        for task in character.get("tasks", [])
        if task.get("status") == "unrecorded"
    ]
    if pending:
        return f"今天的「{pending[0]}」还没收到记录。完成后可以去今日记录页面核对，我陪你一起去。"
    return "今天的记录我都看到了。想推进的话，可以去试炼或者聚宝阁看看，别太累。"


def finalize(request_data: dict, reply: str) -> dict:
    text = " ".join(str(reply).split())
    text = text[:MAX_REPLY]
    if not text:
        raise ServiceError("MODEL_EMPTY_REPLY", "模型返回空文本")
    return {
        "request_id": request_data["request_id"],
        "conversation_id": request_data["conversation_id"],
        "reply": text,
        "animation": choose_animation(text),
        "actions": choose_actions(request_data, text),
    }


class ReplayCache:
    """同一 request_id 的重试直接回放，避免模型重复计费。"""

    def __init__(self, size: int = 256) -> None:
        self._data: OrderedDict[str, dict] = OrderedDict()
        self._size = size
        self._lock = threading.Lock()

    def get(self, key: str) -> dict | None:
        with self._lock:
            value = self._data.get(key)
            if value is not None:
                self._data.move_to_end(key)
            return value

    def put(self, key: str, value: dict) -> None:
        with self._lock:
            self._data[key] = value
            self._data.move_to_end(key)
            while len(self._data) > self._size:
                self._data.popitem(last=False)


def create_app(config: Config | None = None) -> Flask:
    config = config or Config()
    app = Flask(__name__)
    cache = ReplayCache()

    def authorized() -> bool:
        if not config.service_token:
            return request.remote_addr in ("127.0.0.1", "::1")
        header = request.headers.get("Authorization", "")
        return header == f"Bearer {config.service_token}"

    @app.get("/healthz")
    def healthz():
        return jsonify({
            "ok": True,
            "provider": config.provider,
            "model": config.model,
            "base_url": config.base_url,
        })

    @app.post("/api/v1/companion/chat")
    def chat():
        if not authorized():
            return jsonify({"error": {"code": "UNAUTHORIZED", "message": "需要服务凭证"}}), 401
        try:
            request_data = validate(request.get_json(silent=True))
        except ServiceError as error:
            return jsonify({"error": {"code": error.code, "message": error.message}}), error.status

        cached = cache.get(request_data["request_id"])
        if cached is not None:
            return jsonify(cached)

        try:
            if config.provider == "stub":
                reply = stub_reply(request_data)
            else:
                reply = call_model(config, render_prompt(request_data))
            payload = finalize(request_data, reply)
        except ServiceError as error:
            app.logger.warning("companion chat failed: %s (%s)", error.code, error.message)
            return jsonify({"error": {"code": error.code, "message": "聊天服务暂时不可用"}}), error.status

        cache.put(request_data["request_id"], payload)
        return jsonify(payload)

    return app


def main() -> None:
    load_env_file(Path(__file__).with_name(".env"))
    config = Config()
    app = create_app(config)
    print(f"灵宠聊天服务：http://{config.host}:{config.port}/api/v1/companion/chat")
    print(f"provider={config.provider} model={config.model} base_url={config.base_url}")
    if config.provider == "stub":
        print("未配置 LLM_API_KEY，当前为离线演练模式；填入 DeepSeek 密钥后自动切换真实模型。")
    app.run(host=config.host, port=config.port, debug=False, threaded=True)


if __name__ == "__main__":
    main()
