"""家族修真录 · 健康资料注册入口 —— 本地联调服务。

作用：
- 托管前端原型 index.html
- GET  /api/v1/health         识别引擎配置状态（前端顶部药丸读取）
- POST /api/v1/records/parse  接收图片 data_url，调用视觉模型识别 + 规则引擎投影
- POST /api/v1/game/baseline  接收确认后的 baseline（Demo 阶段落盘，联调时替换为游戏服务）

运行：
    cd prototype
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

import recognizer
import rules

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
load_dotenv(os.path.join(BASE_DIR, ".env"))

app = Flask(__name__, static_folder=BASE_DIR, static_url_path="")

BASELINE_DIR = os.path.join(BASE_DIR, "baselines")
os.makedirs(BASELINE_DIR, exist_ok=True)


@app.get("/")
def index():
    return send_from_directory(BASE_DIR, "index.html")


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


@app.post("/api/v1/records/parse")
def parse_record():
    data = request.get_json(silent=True) or {}
    data_url = (data.get("data_url") or "").strip()
    filename = data.get("filename") or "report.jpg"

    if not data_url:
        return jsonify({"message": "缺少图片数据 data_url"}), 400
    if not data_url.startswith("data:"):
        return jsonify({"message": "data_url 必须是 data:image/...;base64,... 格式"}), 400
    if not recognizer.is_configured():
        return jsonify({
            "message": "未配置视觉模型，无法识别真实照片。请在 .env 设置 LLM_API_KEY（或 DASHSCOPE_API_KEY），或先用“示例报告”演示。",
        }), 503

    try:
        document = recognizer.recognize_medical_report(data_url, filename)
    except Exception as exc:  # noqa: BLE001 —— 识别失败要把原因返回给前端，不伪造结果
        return jsonify({"message": f"识别失败：{exc}"}), 502

    _, base_url, model = recognizer.load_config()
    projection = rules.build_projection(document)
    return jsonify({
        "record_id": f"rec_{time.strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:6]}",
        "provider": recognizer.provider_label(base_url),
        "model": model,
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

    # Demo 阶段：baseline 落盘即为“已同步”。正式联调时，在这里调用现有游戏服务
    # （例如 window.XIUXIAN_GAME_API 指向的 /api/v1/game/baseline 或 Godot 侧适配器）。
    return jsonify({"mode": "live", "baseline_id": baseline_id, "saved_to": out_path})


if __name__ == "__main__":
    host = os.environ.get("HOST", "127.0.0.1")
    port = int(os.environ.get("PORT", "8000"))
    app.run(host=host, port=port, debug=False)
