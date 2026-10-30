"""健康资料视觉识别：调用 OpenAI 兼容的多模态接口，把图片转成结构化字段。

只负责“识别 + 结构化”，不做任何游戏数值计算（数值在 rules.py）。
支持一次传多张图片（体检报告 / 病历 / 用药单，可能分页），合并识别为一个 document。
默认走阿里云百炼 DashScope（国内可直连）；换 OpenAI / 本地 vLLM / Ollama 时，
只需改 .env 里的 LLM_BASE_URL 和 LLM_MODEL。
"""
import json
import os
import re

import requests

DEFAULT_BASE_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
DEFAULT_MODEL = "qwen3-vl-plus"

_SYSTEM = (
    "你是一名医疗健康资料结构化助手，负责把体检报告、病历、用药单等图片里的内容提取成 JSON。"
    "只提取图片中确实存在的内容；看不清、缺失或无法判断的字段用 null 或省略，绝不编造。"
)


def _prompt():
    return (
        "请阅读下面的健康资料图片（可能有 N 张，属于同一份资料、可能分页），"
        "严格按下面的 JSON 结构输出（不要输出任何解释文字、不要用 markdown 代码块，只输出一个合法 JSON 对象）：\n"
        "{\n"
        '  "title": "资料标题",\n'
        '  "person": {"name": null, "age": null, "sex": null},\n'
        '  "date": "检查/记录日期，如 2026-10-18，缺失为 null",\n'
        '  "groups": [\n'
        '    {"title": "分组名，例如 基本资料与生命体征 / 血常规 / 血糖与血脂 / 肝肾功能", "items": [\n'
        '      {"label": "指标中文名", "value": "结果值", "unit": "单位，无则空字符串", "status": "normal"}\n'
        "    ]}\n"
        "  ],\n"
        '  "history": [\n'
        '    {"condition": "疾病/病史名，如 高血压、糖尿病、胆囊切除术后", "onset": "起病时间或年份，未知为 null", "status": "ongoing=仍持续 / past=已痊愈或已手术 / unknown", "note": "补充说明，无则空字符串"}\n'
        "  ],\n"
        '  "medications": [\n'
        '    {"name": "药名", "dose": "用法用量，无则空字符串", "purpose": "用途，如 降压、降糖，未知为空字符串", "status": "ongoing=在服 / past=已停用 / unknown"}\n'
        "  ],\n"
        '  "clinical_notes": "病史、病历、出院小结、用药史等自由文本的忠实摘要，无则空字符串",\n'
        '  "summary": "一句话归纳当前最需要关注的点；若未发现异常，写 未发现明确异常结论"\n'
        "}\n"
        "status 取值规则：normal=在参考范围/正常/阴性；abnormal=异常/阳性/偏高/偏低/有明确病变；unknown=无参考范围或无法判断。\n"
        "重要：\n"
        "- 只提取「常规」体检项目（血常规、血糖血脂、肝肾功能、血压心率、BMI 体重等常见指标）；"
        "罕见、非常规的专科检查（基因检测、罕见肿瘤标志物、特殊免疫指标等）不要输出。\n"
        "- 病史、长期用药要单独整理进 history 和 medications，不要混进 groups。\n"
        "- 同一项指标的结果值尽量保留原文数字和单位（例如血压写成 122/76，单位 mmHg）。\n"
        "- 分组名用报告中实际出现的章节名。"
    )


def load_config():
    """返回 (api_key, base_url, model)。密钥优先级 LLM_API_KEY > OPENAI_API_KEY > DASHSCOPE_API_KEY。"""
    api_key = (
        os.environ.get("LLM_API_KEY")
        or os.environ.get("OPENAI_API_KEY")
        or os.environ.get("DASHSCOPE_API_KEY")
        or ""
    ).strip()
    base_url = (os.environ.get("LLM_BASE_URL") or DEFAULT_BASE_URL).strip().rstrip("/")
    model = (os.environ.get("LLM_MODEL") or DEFAULT_MODEL).strip()
    return api_key, base_url, model


def is_configured():
    key, _, _ = load_config()
    return bool(key)


def provider_label(base_url):
    b = (base_url or "").lower()
    if "dashscope" in b or "aliyun" in b:
        return "通义千问视觉"
    if "openai.com" in b:
        return "OpenAI 视觉"
    if "localhost" in b or "127.0.0.1" in b:
        return "本地视觉模型"
    return "OpenAI 兼容视觉"


def _extract_json(text):
    text = (text or "").strip()
    # 去掉 ```json ... ``` 包裹（部分模型会画蛇添足）
    fence = re.search(r"```(?:json)?\s*(.*?)```", text, re.S)
    if fence:
        text = fence.group(1).strip()
    start, end = text.find("{"), text.rfind("}")
    if start == -1 or end <= start:
        raise ValueError("模型未返回合法 JSON")
    return json.loads(text[start : end + 1])


def _downscale_data_url(data_url, max_side=1600, jpeg_quality=82):
    """把过大的图片降采样/压缩，加速视觉模型读取；失败或非图片时原样返回。"""
    if not data_url.startswith("data:image/"):
        return data_url
    try:
        import base64
        import io
        from PIL import Image
        header, _, b64 = data_url.partition(",")
        im = Image.open(io.BytesIO(base64.b64decode(b64))).convert("RGB")
        w, h = im.size
        long_side = max(w, h)
        if long_side > max_side:
            scale = max_side / long_side
            resample = getattr(Image, "LANCZOS", Image.BICUBIC)
            im = im.resize((max(1, round(w * scale)), max(1, round(h * scale))), resample)
        buf = io.BytesIO()
        im.save(buf, format="JPEG", quality=jpeg_quality)
        return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()
    except Exception:
        return data_url


def recognize_medical_report(data_urls, filename=""):
    """把多张健康资料图片（data URL 列表）识别为一个合并的 document。失败抛异常，不伪造结果。"""
    if isinstance(data_urls, str):
        data_urls = [data_urls]
    data_urls = [_downscale_data_url(u) for u in data_urls if isinstance(u, str) and u.strip()]
    if not data_urls:
        raise ValueError("没有可识别的图片")

    api_key, base_url, model = load_config()
    if not api_key:
        raise RuntimeError("未配置视觉模型密钥（请在 .env 设置 LLM_API_KEY 或 DASHSCOPE_API_KEY）")

    content_parts = [{"type": "text", "text": _prompt()}]
    for u in data_urls:
        content_parts.append({"type": "image_url", "image_url": {"url": u}})

    messages = [
        {"role": "system", "content": _SYSTEM},
        {"role": "user", "content": content_parts},
    ]
    body = {"model": model, "messages": messages, "temperature": 0.1}

    resp = requests.post(
        base_url + "/chat/completions",
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        json=body,
        timeout=120,
    )
    if resp.status_code != 200:
        raise RuntimeError(f"模型接口返回 {resp.status_code}: {resp.text[:300]}")

    try:
        content = resp.json()["choices"][0]["message"]["content"]
    except (KeyError, IndexError, ValueError) as exc:
        raise RuntimeError(f"模型返回格式异常: {exc}") from exc

    return _extract_json(content)
