"""Loopback bridge: report image -> model extraction -> existing rules -> confirmed baseline."""
import base64
import binascii
import copy
import io
import json
import math
import os
import sys
import threading
import time
import uuid

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(BASE_DIR, ".deps"))
from flask import Flask, jsonify, request, send_from_directory
from PIL import Image
import recognizer
import rules
from baseline import normalize_baseline

app = Flask(__name__, static_folder=None)
app.config["MAX_CONTENT_LENGTH"] = 45 * 1024 * 1024
BASELINE_DIR = os.path.join(BASE_DIR, "baselines")
RECORDS = {}
RECORD_LOCK = threading.Lock()


@app.get("/")
def index():
    return send_from_directory(BASE_DIR, "index.html")


@app.get("/api/v1/health")
def health():
    key, base_url, model = recognizer.load_config()
    return jsonify(service="xiuxian-health-entry", api_version=3, source_revision="1f356a0",
                   configured=bool(key), model=model,
                   provider=base_url if key else "",
                   provider_label=recognizer.provider_label(base_url))


@app.errorhandler(413)
def too_large(_error):
    return jsonify(message="资料过大，每张图片最多 10 MB，合计最多 30 MB。"), 413


def validate_image(data_url):
    if not isinstance(data_url, str) or "," not in data_url:
        raise ValueError("请选择 PNG、JPEG 或 WebP 报告图片。")
    header, encoded = data_url.split(",", 1)
    formats = {"data:image/png;base64": "PNG", "data:image/jpeg;base64": "JPEG",
               "data:image/webp;base64": "WEBP"}
    if header not in formats:
        raise ValueError("仅支持 PNG、JPEG、WebP 图片；PDF 请先导出为图片。")
    try:
        raw = base64.b64decode(encoded, validate=True)
        if len(raw) > 10 * 1024 * 1024:
            raise ValueError("报告图片不能超过 10 MB。")
        with Image.open(io.BytesIO(raw)) as image:
            if image.format != formats[header] or image.width * image.height > 25_000_000:
                raise ValueError("图片格式不匹配或分辨率过大。")
            image.verify()
        return len(raw)
    except (binascii.Error, OSError, Image.DecompressionBombError) as exc:
        raise ValueError("无法读取报告图片，请重新选择。") from exc


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


def validate_profile(profile):
    for key, label, limit in (("name", "姓名", 10), ("relation", "关系", 30)):
        value = profile.get(key)
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"请填写{label}。")
        if len(value.strip()) > limit:
            raise ValueError(f"{label}不能超过 {limit} 字。")
    if profile.get("sex") not in ("男", "女"):
        raise ValueError("请选择性别。")
    raw_age = profile.get("age")
    if isinstance(raw_age, bool) or not isinstance(raw_age, (str, int, float)):
        raise ValueError("请填写年龄。")
    try:
        age = float(raw_age)
    except (TypeError, ValueError):
        raise ValueError("年龄请填写 1—120 之间的整数。") from None
    if not math.isfinite(age) or not age.is_integer() or not 1 <= age <= 120:
        raise ValueError("年龄请填写 1—120 之间的整数。")
    return dict(name=profile["name"].strip(), relation=profile["relation"].strip(),
                age=int(age), sex=profile["sex"])


@app.post("/api/v1/records/parse")
def parse_record():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify(message="请求需要 JSON 对象。"), 400
    urls = data.get("data_urls", [data["data_url"]] if data.get("data_url") else [])
    if isinstance(urls, str):
        urls = [urls]
    profile = data.get("profile", {})
    if not isinstance(urls, list) or len(urls) > 6 or not isinstance(profile, dict):
        return jsonify(message="请提供最多 6 张图片，基础信息需要是对象。"), 400
    history_text = data.get("history_text", "")
    medications_text = data.get("medications_text", "")
    if not isinstance(history_text, str) or not isinstance(medications_text, str) or len(history_text) > 4000 or len(medications_text) > 4000:
        return jsonify(message="病史、用药各最多 4000 字。"), 400
    try:
        profile = validate_profile(profile)
    except ValueError as exc:
        return jsonify(message=str(exc)), 400
    try:
        if sum(validate_image(url) for url in urls) > 30 * 1024 * 1024:
            raise ValueError("图片合计不能超过 30 MB。")
    except ValueError as exc:
        return jsonify(message=str(exc)), 400
    if not urls and not any(str(value).strip() for value in profile.values()) and not history_text.strip() and not medications_text.strip():
        return jsonify(message="请至少上传一张图片，或填写基础信息、病史、用药。"), 400
    mode = "live" if urls else "text"
    if urls and not recognizer.is_configured():
        return jsonify(message="尚未配置模型密钥。请填写 health-entry/.env 的 LLM_API_KEY，再点击重新连接；也可只提交文字资料。"), 503
    try:
        if urls:
            document = recognizer.validate_document(recognizer.recognize_medical_report(urls, str(data.get("filename", "report"))[:160]))
        else:
            document = {"person": {}, "groups": [], "history": [], "medications": [], "clinical_notes": history_text, "summary": ""}
        document = _merge_profile(document, profile, history_text.strip(), medications_text.strip())
        projection = rules.build_projection(document)
    except recognizer.ModelServiceError as exc:
        app.logger.warning("Health model request failed [%s]", exc.code)
        return jsonify(message=exc.public_message, error_code=exc.code), 502
    except Exception as exc:
        app.logger.warning("Health analysis failed [%s]", type(exc).__name__)
        message = str(exc) if isinstance(exc, ValueError) else "模型调用失败，请检查密钥、模型地址或网络后重试。"
        if isinstance(exc, RuntimeError) and str(exc).startswith("模型接口返回 HTTP "):
            message = str(exc)
        return jsonify(message=message), 502
    _, base_url, model = recognizer.load_config()
    provider = recognizer.provider_label(base_url) if urls else "文字资料"
    model = model if urls else ""
    display_name = str((document.get("person") or {}).get("name") or "")[:10]
    record_id = "rec_" + uuid.uuid4().hex
    with RECORD_LOCK:
        for old_id in list(RECORDS):
            if RECORDS[old_id]["expires"] < time.time():
                del RECORDS[old_id]
        if len(RECORDS) >= 64:
            del RECORDS[next(iter(RECORDS))]
        # Keep only the game projection, never the report image or identifying document.
        RECORDS[record_id] = dict(expires=time.time() + 1800, projection=copy.deepcopy(projection),
                                 provider=provider, model=model, display_name=display_name, recognition_mode=mode, confirmed=None)
    return jsonify(source_revision="1f356a0", record_id=record_id, provider=provider, model=model,
                   confidence=rules.estimate_confidence(document), document=document, recognition_mode=mode, display_name=display_name,
                   game_projection=projection)


@app.post("/api/v1/game/baseline")
def game_baseline():
    data = request.get_json(silent=True)
    if not isinstance(data, dict) or data.get("baseline_locked") is not True:
        return jsonify(message="请先确认并锁定初始属性。"), 400
    mode = data.get("recognition_mode", "demo")
    with RECORD_LOCK:
        if mode in ("live", "text"):
            record = RECORDS.get(data.get("record_id", ""))
            if not record or record["expires"] < time.time():
                return jsonify(message="分析结果已过期或服务已重启，请重新分析报告。"), 409
            if record["recognition_mode"] != mode:
                return jsonify(message="资料模式不匹配，请重新分析。"), 409
            if record["confirmed"]:
                return jsonify(mode=mode, baseline=record["confirmed"], baseline_id=record["confirmed"]["baseline_id"])
            # Authoritative rules output; do not accept client-edited stats.
            payload = dict(record["projection"], recognition_mode=mode, display_name=record["display_name"], provider=record["provider"],
                           model=record["model"], baseline_locked=True)
        elif mode in ("demo", "sample"):
            payload = dict(data, recognition_mode="sample")
            record = None
        else:
            return jsonify(message="未知识别模式。"), 400
        try:
            payload = normalize_baseline(payload)
        except ValueError as exc:
            return jsonify(message=str(exc)), 400
        payload["baseline_id"] = "baseline_" + uuid.uuid4().hex
        payload["synced_at"] = time.strftime("%Y-%m-%dT%H:%M:%S")
        os.makedirs(BASELINE_DIR, exist_ok=True)
        out_path = os.path.join(BASELINE_DIR, payload["baseline_id"] + ".json")
        with open(out_path + ".tmp", "w", encoding="utf-8") as fh:
            json.dump(payload, fh, ensure_ascii=False, indent=2)
        os.replace(out_path + ".tmp", out_path)
        if record is not None:
            record["confirmed"] = payload
    return jsonify(mode=payload["recognition_mode"], baseline_id=payload["baseline_id"], baseline=payload)


if __name__ == "__main__":
    # The Godot client only connects to this loopback service.
    app.run(host="127.0.0.1", port=8000, debug=False)
