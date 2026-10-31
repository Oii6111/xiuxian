"""轻量 RAG：本地医学小词典（药用途 + 疾病科普），给老人端做准确兜底。

不依赖向量库/嵌入，就是一张确定性的「药名/病名 → 说明」表。
老人问「这药干什么用」「XX 是什么 / 要注意什么」时先查这里；查得到就按词典答，
查不到再让模型答（模型答时仍受「不诊断、不替代医生」的人设约束）。
"""
from __future__ import annotations

import json
import re
from pathlib import Path

KB_PATH = Path(__file__).resolve().parent / "medical_kb.json"
_KB = json.loads(KB_PATH.read_text(encoding="utf-8"))

# 匹配时去掉空格和常见标点，只比核心字
_NORM = re.compile(r"[\s，。、（）()：:！？!?·-]")


def _norm(s):
    return _NORM.sub("", str(s)).lower()


def _find(kind: str, text: str):
    """在 text 里找第一个命中的词条，返回 (命中的名/别名, 词条) 或 (None, None)。"""
    t = _norm(text)
    if not t:
        return None, None
    for name, entry in _KB[kind].items():
        for n in [name] + list(entry.get("aliases") or []):
            nn = _norm(n)
            if nn and nn in t:
                return n, entry
    return None, None


def lookup_drug(text: str):
    return _find("drugs", text)


def lookup_disease(text: str):
    return _find("diseases", text)


def purpose_of(label: str):
    """按药名/牌子名查用途短语，查不到返回 None。"""
    _, entry = lookup_drug(label)
    return entry["purpose"] if entry else None


def drug_purpose_reply(name: str, entry: dict) -> str:
    """「XX 是干什么用的」的词典答案。"""
    return f"{name}是{entry['purpose']}。"


def disease_reply(name: str, entry: dict) -> str:
    """疾病基本信息科普，老人能听懂的短句。"""
    text = f"{name}啊，简单说：{entry['summary']}。"
    if entry.get("signs"):
        text += f"常见表现是{entry['signs']}。"
    if entry.get("tips"):
        text += f"平时多注意：{entry['tips']}。"
    return text


def rag_context(text: str) -> str:
    """把 text 里命中的词条拼成一段权威说明，可注入模型提示词做接地。"""
    parts = []
    name, entry = lookup_drug(text)
    if name:
        parts.append(f"【{name}】{entry['purpose']}。")
    name, entry = lookup_disease(text)
    if name:
        parts.append(f"【{name}】{entry['summary']}。{entry.get('tips', '')}")
    return "\n".join(parts)
