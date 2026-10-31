"""只连测试启动器提供的 loopback C 服务；不访问微信、不调用 AI。"""
import importlib.util
import json
import os
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch
import urllib.request

spec = importlib.util.spec_from_file_location("bridge", Path(__file__).resolve().parents[1] / "game_task_bridge.py")
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


def request(path, body=None, token=None, key=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    if key:
        headers["Idempotency-Key"] = key
    req = urllib.request.Request(os.environ["GAME_API_BASE"] + path,
        data=None if body is None else json.dumps(body).encode(), headers=headers)
    with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(req, timeout=10) as response:
        result = json.load(response)
    assert result["ok"], result
    return result["data"]


def command(token, name, payload, key=None):
    return request("/api/v2/commands", {"version": 1, "command": name, "payload": payload}, token, key)


def main():
    routes, accounts, characters, tasks = [], [], [], []
    now = datetime.now(timezone.utc).replace(microsecond=0) - timedelta(seconds=2)
    today = now.astimezone(timezone(timedelta(hours=8))).date().isoformat()
    for index in range(2):
        credentials = {"username": f"d_smoke_{index}", "password": "local-test-password-123"}
        request("/api/v2/auth/register", credentials)
        token = request("/api/v2/auth/login", credentials)["token"]
        character = command(token, "growth.create_member", {"role": "elder", "name": "测试", "request_id": f"create-{index}",
            "profile": {"title": "测试化身", "avatar": "male", "relation": "父亲", "age": 70, "sex": "男", "mode": "family", "consent": True}})
        ticket = request("/api/v2/baselines/tickets", {"cultivator_id": character["cultivator_id"]}, token)
        stats = {key: 50 for key in ("hp_max", "hp_current", "attack", "defense", "spirit", "stamina", "insight", "mind", "speed", "luck")}
        bridge.game_post("/internal/v1/baselines", {"baseline_ticket": ticket["baseline_ticket"], "baseline_id": f"baseline-{index}",
            "projection": {"projection_version": "legacy-pixel-v1", "mapping_version": "body_system_v2", "recognition_mode": "sample", "character_state": stats, "readiness": 60}})
        invite = request("/api/v2/bindings/invitations", {"cultivator_id": character["cultivator_id"]}, token)
        binding = bridge.game_post("/internal/v1/bindings/confirm", {"invite_token": invite["invite_token"],
            "channel": "wechat_ilink", "channel_account_id": "test-bot", "sender_id": f"sender-{index}",
            "elder_ref": f"elder-{index}", "consent_proof_id": "local-simulated-consent", "consent_scope": "family_game",
            "health_processing": True, "ai_processing": True})
        routes.append({"binding_id": binding["binding_id"], "elder_id": f"elder-{index}", "sender_id": f"sender-{index}",
                       "channel_account_id": "test-bot", "target": f"target-{index}", "consent_version": binding["consent_version"]})
        accounts.append(token)
        characters.append(character)
    os.environ["ELDER_BINDINGS"] = json.dumps(routes)
    for route in routes:
        tasks.append(bridge.enable_task(route["binding_id"], "daily_medication_record", today))
        assert bridge.enable_task(route["binding_id"], "daily_medication_record", today) == tasks[-1]
    with tempfile.TemporaryDirectory() as temp:
        bridge.STATE_PATH = Path(temp) / "bridge.sqlite3"
        def submit(index, task, event):
            route = routes[index]
            return bridge.submit_confirmed(route["binding_id"], task["task_instance_id"], event,
                now.isoformat(), "self_report", route["sender_id"], route["channel_account_id"])
        for index in range(2):
            result = submit(index, tasks[index], f"health-{index}")
            bridge.game_post(f"/internal/v1/task-results/{result['event_id']}/settle", {})
            assert submit(index, tasks[index], f"health-{index}")["status"] == "settled"
        targets = []
        with patch.object(bridge, "send_wechat", side_effect=lambda route, text: targets.append(route["target"]) or True):
            assert bridge.claim_notifications() == 1
            assert bridge.claim_notifications() == 1
        assert set(targets) == {"target-0", "target-1"}, targets
        # 同日第二项记录只更新完成状态，日奖励组不重复发放。
        extra = bridge.enable_task(routes[0]["binding_id"], "daily_planned_record", today)
        result = submit(0, extra, "health-measure")
        second = bridge.game_post(f"/internal/v1/task-results/{result['event_id']}/settle", {})
        assert (second["spirit_stones"], second["reason"]) == (0, "daily_group_claimed"), second
        draw = command(accounts[0], "growth.draw", {"cultivator_id": characters[0]["cultivator_id"], "count": 1, "request_id": "draw"})
        assert draw["character"]["resources"]["spirit_stones"] == 30, draw
        other = command(accounts[1], "growth.snapshot", {"cultivator_id": characters[1]["cultivator_id"]})
        assert other["resources"]["spirit_stones"] == 100 and other["resources"]["seals"] == 1, other
        request(f"/api/v2/bindings/{routes[0]['binding_id']}/revoke", {}, accounts[0])
        try:
            submit(0, extra, "health-measure")
            raise AssertionError("revoked binding accepted")
        except bridge.BridgeError:
            pass
    print("D_HTTP_SMOKE: two accounts, settlement, retry, routing, gacha, revocation passed")


if __name__ == "__main__":
    main()
