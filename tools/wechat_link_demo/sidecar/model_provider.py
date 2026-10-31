"""统一模型供应接口：文本与视觉共用一个 OpenAI 兼容调用，多供应商可插拔。

用法：
    from model_provider import chat, vision, text_config, vision_config

    base, key, model, temp = text_config("chat")          # 或 "medical"
    reply = chat(base, key, model, [{"role": "system", ...}, {"role": "user", ...}], temp)

    base, key, model = vision_config()
    text = vision([data_url, ...], prompt, system, base, key, model)

设计：
- 一个 `chat()` 跑文本、一个 `vision()` 跑图片，都走 OpenAI 兼容的 /chat/completions。
- 供应商用 PROVIDERS 注册表 + 环境变量声明；加新供应商只加一行，不改调用代码。
- 视觉默认 deepseek-flash（DeepSeek 原生多模态）；文本默认 deepseek-chat。
- 保留旧配置兼容：视觉会回退到 LLM_*（原 Qwen/DashScope 配置），文本回退到 DEEPSEEK_*。
"""

import os

import requests


def _env(*names):
    for name in names:
        value = (os.environ.get(name) or "").strip()
        if value:
            return value
    return ""


# 供应商注册表：默认 base_url + 各用途的密钥/模型环境变量名。
# 加新供应商（如 OpenAI / 本地 vLLM / Ollama）在这里加一行即可。
PROVIDERS = {
    "deepseek": {
        "label": "DeepSeek",
        "base_url": "https://api.deepseek.com",
        "key_env": "DEEPSEEK_API_KEY",
        "chat_model_env": "DEEPSEEK_CHAT_MODEL",
        "chat_model_default": "deepseek-chat",
        "vision_model_env": "DEEPSEEK_VISION_MODEL",
        "vision_model_default": "deepseek-flash",
    },
    "dashscope": {
        "label": "通义千问",
        "base_url": "https://dashscope.aliyuncs.com/compatible-mode/v1",
        "key_env": "DASHSCOPE_API_KEY",
        "chat_model_env": "DASHSCOPE_CHAT_MODEL",
        "chat_model_default": "qwen-plus",
        "vision_model_env": "DASHSCOPE_VISION_MODEL",
        "vision_model_default": "qwen3-vl-plus",
    },
}

_DEFAULT_PROVIDER = "deepseek"


def _provider(name):
    return PROVIDERS.get(name) or PROVIDERS[_DEFAULT_PROVIDER]


def text_config(route="chat"):
    """返回 (base_url, api_key, model, temperature)。医疗路由温度更低、更保守。"""
    deepseek = _provider("deepseek")
    route = "medical" if route == "medical" else "chat"
    if route == "medical":
        base = _env("MEDICAL_BASE_URL", "HEALTH_CHAT_BASE_URL") or deepseek["base_url"]
        key = _env("MEDICAL_API_KEY", "HEALTH_CHAT_API_KEY", deepseek["key_env"])
        model = _env("MEDICAL_MODEL", "HEALTH_CHAT_MODEL", deepseek["chat_model_env"]) or deepseek["chat_model_default"]
        temperature = 0.2
    else:
        base = _env("HEALTH_CHAT_BASE_URL") or deepseek["base_url"]
        key = _env("HEALTH_CHAT_API_KEY", deepseek["key_env"])
        model = _env("HEALTH_CHAT_MODEL", deepseek["chat_model_env"]) or deepseek["chat_model_default"]
        temperature = 0.7
    return (base.rstrip("/") or None, key or None, model.strip() or deepseek["chat_model_default"], temperature)


def vision_config():
    """返回 (base_url, api_key, model)。默认 deepseek-flash，兼容旧 LLM_*（Qwen）配置。"""
    deepseek = _provider("deepseek")
    base = _env("VISION_BASE_URL", "LLM_BASE_URL") or deepseek["base_url"]
    key = _env("VISION_API_KEY", "LLM_API_KEY", "OPENAI_API_KEY", "DASHSCOPE_API_KEY", deepseek["key_env"])
    model = _env("VISION_MODEL", "LLM_MODEL", deepseek["vision_model_env"]) or deepseek["vision_model_default"]
    return (base.rstrip("/") or None, key or None, model.strip() or deepseek["vision_model_default"])


def _post(base_url, api_key, body, timeout):
    resp = requests.post(
        (base_url or "").rstrip("/") + "/chat/completions",
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        json=body,
        timeout=timeout,
    )
    if resp.status_code != 200:
        raise RuntimeError(f"模型接口返回 {resp.status_code}: {resp.text[:300]}")
    try:
        content = resp.json()["choices"][0]["message"]["content"]
    except (KeyError, IndexError, ValueError) as exc:
        raise RuntimeError(f"模型返回格式异常: {exc}") from exc
    if isinstance(content, list):
        content = "".join(str(part.get("text", "")) for part in content if isinstance(part, dict))
    return content


def chat(base_url, api_key, model, messages, temperature=0.7):
    """文本对话：messages 为 OpenAI 格式，返回 content 字符串或 None（未配置时返回 None）。"""
    if not api_key or not base_url or not model:
        return None
    body = {"model": model, "messages": messages, "temperature": temperature}
    try:
        return _post(base_url, api_key, body, timeout=45)
    except (OSError, requests.RequestException, ValueError, KeyError, IndexError):
        return None


def vision(data_urls, prompt, system, base_url, api_key, model, temperature=0.1):
    """视觉识别：把多张图片 + 提示词发给多模态模型，返回模型文本输出；失败抛异常。"""
    if isinstance(data_urls, str):
        data_urls = [data_urls]
    data_urls = [u for u in data_urls if isinstance(u, str) and u.strip()]
    if not data_urls:
        raise ValueError("没有可识别的图片")
    if not api_key:
        raise RuntimeError("未配置视觉模型密钥（请在 .env 设置 VISION_API_KEY / LLM_API_KEY / DASHSCOPE_API_KEY）")

    content_parts = [{"type": "text", "text": prompt}]
    for u in data_urls:
        content_parts.append({"type": "image_url", "image_url": {"url": u}})
    messages = [
        {"role": "system", "content": system},
        {"role": "user", "content": content_parts},
    ]
    body = {"model": model, "messages": messages, "temperature": temperature}
    return _post(base_url, api_key, body, timeout=120)
