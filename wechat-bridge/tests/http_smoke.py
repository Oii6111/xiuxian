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
        character = command(token, "growth.create", {"name": "测试", "element": "water"}, f"create-{index}")
        invite = request("/api/v2/bindings/invitations", {"cultivator_id": character["cultivator_id"]}, token)
        binding = bridge.game_post("/internal/v1/bindings/confirm", {"invite_token": invite["invite_token"],
            "channel": "wechat_ilink", "channel_account_id": "test-bot", "sender_id": f"sender-{index}",
            "elder_ref": f"elder-{index}", "consent_proof_id": "local-simulated-consent", "consent_scope": "family_game",
            "health_processing": True, "ai_processing": True})
        routes.append({"binding_id": binding["binding_id"], "elder_id": f"elder-{index}", "sender_id": f"sender-{index}",
                       "channel_account_id": "test-bot", "target": f"target-{index}", "consent_version": binding["consent_version"]})
        accounts.append(token)
        characters.append(character)
        tasks.append(command(token, "quests.assign", {"cultivator_id": character["cultivator_id"],
            "template_id": "daily_step_record", "date": today, "request_id": f"assign-{index}"}))
    os.environ["ELDER_BINDINGS"] = json.dumps(routes)
    with tempfile.TemporaryDirectory() as temp:
        bridge.STATE_PATH = Path(temp) / "bridge.sqlite3"
        def submit(index, task, event):
            route = routes[index]
            return bridge.submit_confirmed(route["binding_id"], task["task_instance_id"], event,
                now.isoformat(), "photo", route["sender_id"], route["channel_account_id"])
        for index in range(2):
            result = submit(index, tasks[index], f"health-{index}")
            bridge.game_post(f"/internal/v1/task-results/{result['event_id']}/settle", {})
            assert submit(index, tasks[index], f"health-{index}")["status"] == "settled"
        targets = []
        with patch.object(bridge, "send_wechat", side_effect=lambda route, text: targets.append(route["target"]) or True):
            assert bridge.claim_notifications() == 1
            assert bridge.claim_notifications() == 1
        assert set(targets) == {"target-0", "target-1"}, targets
        extra = command(accounts[0], "quests.assign", {"cultivator_id": characters[0]["cultivator_id"],
            "template_id": "daily_measurement_record", "date": today, "request_id": "measure"})
        result = submit(0, extra, "health-measure")
        bridge.game_post(f"/internal/v1/task-results/{result['event_id']}/settle", {})
        draw = command(accounts[0], "growth.draw", {"cultivator_id": characters[0]["cultivator_id"], "count": 1, "request_id": "draw"})
        assert draw["character"]["resources"]["spirit_stones"] == 5, draw
        other = command(accounts[1], "growth.snapshot", {"cultivator_id": characters[1]["cultivator_id"]})
        assert other["resources"]["spirit_stones"] == 6, other
        request(f"/api/v2/bindings/{routes[0]['binding_id']}/revoke", {}, accounts[0])
        try:
            submit(0, extra, "health-measure")
            raise AssertionError("revoked binding accepted")
        except bridge.BridgeError:
            pass
    print("D_HTTP_SMOKE: two accounts, settlement, retry, routing, gacha, revocation passed")


if __name__ == "__main__":
    main()
