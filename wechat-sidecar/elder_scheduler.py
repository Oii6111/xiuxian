"""老人端主动关怀调度器：定时主动问“吃药了吗 / 今天吃了什么 / 准备吃什么”。

这个脚本独立于 Flask 侧车运行，每分钟检查一次：
1. reminders 表里到点的用药提醒；
2. 内置的用餐问候时间表（准备吃什么 / 已经吃了什么）。

对每条应触达的消息做幂等去重，再通过 OpenClaw 出站发送给老人。

运行前先确认两件事：
* OpenClaw 已登录微信（`openclaw channels status` 显示 openclaw-weixin 正常）。
* 出站通道标识与目标地址（OPENCLAW_SEND_CHANNEL / OPENCLAW_SEND_TARGET）。

发送命令等价于：
    openclaw message send --channel <CHANNEL> --target <TARGET> --message "<文字>"

不同 OpenClaw 版本的 Weixin 通道标识可能不叫 openclaw-weixin。先用
OPENCLAW_DRY_RUN=1 试跑，看打出来的命令在你的环境里对不对，再关掉 dry-run。

环境变量：
    ELDER_ID              老人 ID（默认 elder_demo_001）
    OPENCLAW_SEND_CHANNEL 出站通道标识（默认 openclaw-weixin）
    OPENCLAW_SEND_TARGET  老人的微信接收地址（登录成功后从 channels status 拿到）
    OPENCLAW_SEND_ACCOUNT 可选，指定 OpenClaw 账户 ID
    OPENCLAW_BIN          openclaw 可执行文件路径（默认优先用同目录 openclaw.bat）
    OPENCLAW_DRY_RUN      设为 1 时只打印、不发送
    ELDER_MEAL_SCHEDULE   可选，JSON 覆盖用餐时间表
    ELDER_MOVE_SCHEDULE   可选，JSON 覆盖运动/久坐提醒时间表（[{time, kind, text}]）
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List

import elder_assistant as elder

BASE_DIR = Path(__file__).resolve().parent
STATE_PATH = Path(os.environ.get("ELDER_PROACTIVE_STATE", str(BASE_DIR / "bot_data" / "elder_proactive_state.json")))

# 默认用餐问候时间表：餐前问“准备吃什么”，餐后问“吃了什么”。
DEFAULT_MEAL_SCHEDULE: List[Dict[str, str]] = [
    {"time": "07:30", "kind": "plan", "meal": "早饭"},
    {"time": "08:30", "kind": "check", "meal": "早饭"},
    {"time": "11:30", "kind": "plan", "meal": "午饭"},
    {"time": "12:30", "kind": "check", "meal": "午饭"},
    {"time": "17:30", "kind": "plan", "meal": "晚饭"},
    {"time": "18:30", "kind": "check", "meal": "晚饭"},
]

# 默认运动/久坐提醒时间表：每天固定时间推，文案轮换避免每次都一样。
DEFAULT_MOVE_SCHEDULE: List[Dict[str, str]] = [
    {"time": "09:00", "kind": "exercise", "text": "早上好呀，起来活动活动，出门走一走晒晒太阳，腿脚更利索。"},
    {"time": "10:30", "kind": "stretch", "text": "坐了好一会儿啦，起来伸个懒腰、走两步，喝口水。"},
    {"time": "15:00", "kind": "stretch", "text": "下午啦，别一直坐着，起来活动活动腿脚、扭扭腰。"},
    {"time": "16:30", "kind": "stretch", "text": "坐久了对腰腿不好，起来走两圈、伸伸胳膊。"},
]


def _meal_schedule() -> List[Dict[str, str]]:
    raw = os.environ.get("ELDER_MEAL_SCHEDULE", "").strip()
    if raw:
        try:
            parsed = json.loads(raw)
            if isinstance(parsed, list):
                return parsed
        except ValueError:
            print(f"[warn] ELDER_MEAL_SCHEDULE 解析失败，使用默认时间表：{raw}")
    return DEFAULT_MEAL_SCHEDULE


def _move_schedule() -> List[Dict[str, str]]:
    raw = os.environ.get("ELDER_MOVE_SCHEDULE", "").strip()
    if raw:
        try:
            parsed = json.loads(raw)
            if isinstance(parsed, list):
                return parsed
        except ValueError:
            print(f"[warn] ELDER_MOVE_SCHEDULE 解析失败，使用默认时间表：{raw}")
    return DEFAULT_MOVE_SCHEDULE


def _openclaw_bin() -> str:
    configured = os.environ.get("OPENCLAW_BIN", "").strip()
    if configured:
        return configured
    local_bat = BASE_DIR / "openclaw.bat"
    if local_bat.exists():
        return str(local_bat)
    return "openclaw"


def _now_hhmm() -> str:
    return datetime.now().astimezone().strftime("%H:%M")


def _today() -> str:
    return datetime.now().astimezone().strftime("%Y-%m-%d")


def _run(args: List[str]) -> subprocess.CompletedProcess:
    bin_ = _openclaw_bin()
    if os.name == "nt":
        # Windows 下 .bat/.cmd 需要交给 cmd.exe，list2cmdline 负责引号转义。
        cmdline = subprocess.list2cmdline([bin_, *args])
        return subprocess.run(cmdline, shell=True, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=60)
    return subprocess.run([bin_, *args], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=60)


def send(target: str, text: str) -> Dict[str, Any]:
    """通过 openclaw message send 出站发送一条消息。"""
    channel = os.environ.get("OPENCLAW_SEND_CHANNEL", "openclaw-weixin").strip() or "openclaw-weixin"
    account = os.environ.get("OPENCLAW_SEND_ACCOUNT", "").strip()
    args = ["message", "send", "--channel", channel, "--target", target, "--message", text]
    if account:
        args = ["message", "send", "--account", account, "--channel", channel, "--target", target, "--message", text]
    if os.environ.get("OPENCLAW_DRY_RUN", "").strip().lower() in {"1", "true", "yes", "on"}:
        print(f"[dry-run] {_openclaw_bin()} " + subprocess.list2cmdline(args))
        return {"ok": True, "dry_run": True}
    try:
        proc = _run(args)
        ok = proc.returncode == 0
        return {"ok": ok, "returncode": proc.returncode, "stdout": proc.stdout, "stderr": proc.stderr}
    except Exception as exc:  # noqa: BLE001 — 调度器不能因单条发送失败而退出
        return {"ok": False, "error": str(exc)}


def _load_state() -> Dict[str, Any]:
    if STATE_PATH.exists():
        try:
            return json.loads(STATE_PATH.read_text(encoding="utf-8"))
        except (ValueError, OSError):
            return {}
    return {}


def _save_state(state: Dict[str, Any]) -> None:
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")


def _due_items(elder_id: str) -> List[Dict[str, str]]:
    """把“到点的用药提醒 + 用药疗程提醒 + 用餐问候”统一成待发送条目。"""
    stamp = _now_hhmm()
    items: List[Dict[str, str]] = []
    # 通用提醒（家庭端设置，如量血压）：只说提醒本身，不硬塞“吃药”话术。
    for reminder in elder.due_reminders(elder_id, at=stamp):
        label = str(reminder.get("label") or "健康提醒")
        items.append({
            "key": f"rem:{reminder['reminder_id']}:{_today()}:{stamp}",
            "text": f"到点啦，提醒你一下：{label}。",
        })
    # 用药疗程：接下来几天饭点自动提醒，直到疗程结束。
    for course in elder.due_courses(elder_id, at=stamp):
        drug = str(course.get("drug_name") or "药")
        when = str(course.get("when_take") or "")
        items.append({
            "key": f"course:{course['course_id']}:{_today()}:{stamp}",
            "text": f"该吃药啦：{drug}（{when}）。吃完回我“吃过了”，我帮你记着。",
        })
    care = elder.active_care_tip(elder_id)
    for slot in _meal_schedule():
        if str(slot.get("time") or "").strip()[:5] == stamp:
            kind = str(slot.get("kind") or "check")
            meal = str(slot.get("meal") or "这顿饭")
            if kind == "plan":
                text = f"今天{meal}准备吃什么呀？我帮你看看吃得舒不舒服。"
            else:
                text = f"今天{meal}吃了什么呀？说一声或拍张照，我帮你记下来。"
            if care:
                text += f" {care}"
            items.append({"key": f"meal:{kind}:{meal}:{_today()}:{stamp}", "text": text})
    # 运动 / 久坐提醒：每天固定时间推，提醒起来活动一下。
    for slot in _move_schedule():
        if str(slot.get("time") or "").strip()[:5] == stamp:
            text = str(slot.get("text") or "起来活动活动。").strip()
            items.append({"key": f"move:{slot.get('time')}:{_today()}", "text": text})
    return items


def tick(elder_id: str, target: str, state: Dict[str, Any]) -> bool:
    """执行一次检查；返回是否发送了至少一条消息。"""
    sent_any = False
    for item in _due_items(elder_id):
        if state.get("sent", {}).get(item["key"]):
            continue
        if not target:
            print(f"[skip] 未配置 OPENCLAW_SEND_TARGET，跳过：{item['text']}")
            state.setdefault("sent", {})[item["key"]] = True
            continue
        print(f"[send] {item['text']}")
        result = send(target, item["text"])
        if result.get("ok") or result.get("dry_run"):
            state.setdefault("sent", {})[item["key"]] = True
            sent_any = True
        else:
            print(f"[error] 发送失败：{result}")
    return sent_any


def main() -> int:
    elder_id = os.environ.get("ELDER_ID", "elder_demo_001").strip() or "elder_demo_001"
    target = os.environ.get("OPENCLAW_SEND_TARGET", "").strip()
    once = "--once" in sys.argv

    elder.init_db()
    state = _load_state()
    print(f"[scheduler] elder_id={elder_id} target={'<已配置>' if target else '<未配置>'} once={once}")
    if not target:
        print("[warn] 尚未配置 OPENCLAW_SEND_TARGET；请先登录微信并从 `openclaw channels status` 拿到老人接收地址。")

    while True:
        try:
            tick(elder_id, target, state)
        except Exception as exc:  # noqa: BLE001
            print(f"[error] tick 异常：{exc}")
        _save_state(state)
        if once:
            break
        time.sleep(60)


if __name__ == "__main__":
    raise SystemExit(main())
