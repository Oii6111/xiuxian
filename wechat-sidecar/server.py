"""疯狂修仙，中 · 健康资料注册入口 —— 本地联调服务。

作用：
- 托管前端原型 index.html
- GET  /api/v1/health         识别引擎配置状态（前端顶部药丸读取）
- POST /api/v1/records/parse  接收多张图片 + 文字基础信息，调用视觉模型识别 + 规则引擎投影
- POST /api/v1/game/baseline  接收确认后的 baseline（Demo 阶段落盘，联调时替换为游戏服务）
- POST /api/v1/elder/message  老人端微信助手的统一消息入口（不返回游戏字段）
- POST /api/v1/elder/confirm  候选健康记录确认入口

records/parse 请求体：
    {
      "data_urls": ["data:image/...", "data:image/..."],   // 可空
      "profile": {"relation": "爸爸", "name": null, "age": 68, "sex": "男"},
      "history_text": "高血压10年…",       // 可空
      "medications_text": "氨氯地平 5mg…"   // 可空
    }
至少提供图片或文字信息之一。

运行：
    pip install -r requirements.txt
    copy .env.example .env   （填入 LLM_API_KEY）
    python server.py
然后浏览器打开 http://127.0.0.1:8000
"""
import json
import os
import time
import uuid

from dotenv import load_dotenv
from flask import Flask, jsonify, request, send_from_directory

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(BASE_DIR, ".env"))

import recognizer
import rules
from elder_assistant import register_elder_assistant_routes

app = Flask(__name__, static_folder=None)

BASELINE_DIR = os.path.join(BASE_DIR, "baselines")
os.makedirs(BASELINE_DIR, exist_ok=True)


@app.get("/")
def index():
    return send_from_directory(os.path.join(BASE_DIR, "..", "health-entry"), "index.html")


@app.get("/api/v1/health")
def health():
    key, base_url, model = recognizer.load_config()
    configured = bool(key)
    return jsonify({
        "configured": configured,
        "provider": base_url if configured else "",
        "provider_label": recognizer.provider_label(base_url) if configured else "",
        "model": model,
    })


def _merge_profile(document, profile, history_text, medications_text):
    """把用户手填的基础信息合并进 document：手填优先，病史/用药以追加方式并入。"""
    person = document.get("person") or {}
    for k in ("relation", "name", "age", "sex"):
        v = profile.get(k)
        if v not in (None, ""):
            person[k] = v
    document["person"] = person

    history = list(document.get("history") or [])
    if history_text:
        history.append({"condition": history_text, "status": "unknown", "source": "text"})
    document["history"] = history

    medications = list(document.get("medications") or [])
    if medications_text:
        medications.append({"name": medications_text, "status": "unknown", "source": "text"})
    document["medications"] = medications
    return document


@app.post("/api/v1/records/parse")
def parse_record():
    data = request.get_json(silent=True) or {}
    data_urls = data.get("data_urls") or []
    if isinstance(data_urls, str):
        data_urls = [data_urls]
    data_urls = [u for u in data_urls if isinstance(u, str) and u.strip()]

    profile = data.get("profile") or {}
    history_text = str(data.get("history_text") or "").strip()
    medications_text = str(data.get("medications_text") or "").strip()

    has_text = bool(
        profile.get("relation") or profile.get("name") or profile.get("age") or profile.get("sex")
        or history_text or medications_text
    )
    if not data_urls and not has_text:
        return jsonify({"message": "请至少上传一张图片，或填写基础信息"}), 400
    for u in data_urls:
        if not u.startswith("data:"):
            return jsonify({"message": "图片必须是 data:image/...;base64,... 格式"}), 400

    # 有图片 → 视觉模型识别；没有图片 → 直接由文字信息构造 document（不调模型，秒回）
    if data_urls:
        if not recognizer.is_configured():
            return jsonify({
                "message": "未配置视觉模型，无法识别照片。请在 .env 设置 LLM_API_KEY，或只填写文字基础信息。",
            }), 503
        try:
            document = recognizer.recognize_medical_report(data_urls, data.get("filename") or "report")
        except Exception as exc:  # noqa: BLE001 —— 识别失败要把原因返回给前端，不伪造结果
            return jsonify({"message": f"识别失败：{exc}"}), 502
    else:
        document = {
            "person": {}, "groups": [], "history": [], "medications": [],
            "clinical_notes": history_text, "summary": "",
        }

    document = _merge_profile(document, profile, history_text, medications_text)

    _, base_url, model = recognizer.load_config()
    projection = rules.build_projection(document)
    return jsonify({
        "record_id": f"rec_{time.strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:6]}",
        "provider": recognizer.provider_label(base_url) if data_urls else "文字资料",
        "model": model if data_urls else None,
        "confidence": document.get("confidence") or rules.estimate_confidence(document),
        "document": document,
        "game_projection": projection,
    })


@app.post("/api/v1/game/baseline")
def game_baseline():
    payload = request.get_json(silent=True) or {}
    baseline_id = f"baseline_{time.strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:6]}"
    payload["baseline_id"] = baseline_id
    payload["synced_at"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    out_path = os.path.join(BASELINE_DIR, f"{baseline_id}.json")
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=2)

    # 完整 baseline 只在 D 域归档，不能送入 C 或 Godot，也不宣称已同步游戏。
    return jsonify({"mode": "health_archive_only", "baseline_id": baseline_id})


# 老人端健康助手单独挂载：老人只看到聊天、提醒、拍照和语音，
# 不会看到游戏字段；确认后的结构化事件可通过 HEALTH_EVENT_SINK_URL 转发。
register_elder_assistant_routes(app)

# 直接用 iLink 长轮询收微信消息，不再依赖 openclaw-health-hook。
try:
    import ilink_gateway

    ilink_gateway.start_background()
except Exception as error:  # noqa: BLE001 - 网关故障不能拖垮健康入口
    print(f"[ilink] gateway disabled: {error}")


@app.get("/api/v1/wechat/gateway")
def wechat_gateway_status():
    try:
        import ilink_gateway

        return jsonify({"ok": True, "data": ilink_gateway.status()})
    except Exception as error:  # noqa: BLE001
        return jsonify({"ok": False, "message": str(error)})


if __name__ == "__main__":
    host = os.environ.get("HOST", "127.0.0.1")
    port = int(os.environ.get("PORT", "8000"))
    app.run(host=host, port=port, debug=False)
