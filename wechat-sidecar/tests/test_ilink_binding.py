"""扫码绑定与事件路由：不访问真实 iLink 或 C，只验证 D 侧的身份推导与提交门槛。"""
import json
import os
import sqlite3
import sys
import tempfile
import unittest
from contextlib import contextmanager
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ilink_binding  # noqa: E402


class FakeResponse:
    def __init__(self, data):
        self.data = data

    def json(self):
        return self.data


class BindingTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        ilink_binding.bridge.STATE_PATH = Path(self.temp.name) / "bridge.sqlite3"
        ilink_binding.CREDENTIALS = Path(self.temp.name) / "ilink.json"
        os.environ["ELDER_BINDINGS"] = "[]"
        self.db_path = Path(self.temp.name) / "elder.sqlite3"
        with self.database() as conn:
            conn.execute("CREATE TABLE medication_courses (course_id TEXT, elder_id TEXT, status TEXT, end_date TEXT)")
            conn.execute("CREATE TABLE game_event_identity (event_id TEXT PRIMARY KEY, sender_id TEXT, channel_account_id TEXT)")

    def tearDown(self):
        self.temp.cleanup()

    @contextmanager
    def database(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        try:
            with conn:
                yield conn
        finally:
            conn.close()

    def bind(self):
        with patch.object(ilink_binding.requests, "post", return_value=FakeResponse({"qrcode": "q", "qrcode_img_content": "https://liteapp/q"})):
            started = ilink_binding.start("invite-token-1234567890")
        confirmed = {"status": "confirmed", "ilink_bot_id": "bot@im.bot", "ilink_user_id": "elder@im.wechat", "bot_token": "secret"}
        calls = []
        with patch.object(ilink_binding.requests, "get", return_value=FakeResponse(confirmed)), \
                patch.object(ilink_binding.bridge, "game_post", side_effect=lambda path, body: calls.append((path, body)) or {"binding_id": "binding_1", "consent_version": 1}):
            result = ilink_binding.poll(started["bind_id"])
        return result, calls

    def test_scan_confirms_binding_without_elder_code(self):
        result, calls = self.bind()
        self.assertEqual(result["status"], "bound")
        path, body = calls[0]
        self.assertEqual(path, "/internal/v1/bindings/confirm")
        self.assertEqual((body["channel_account_id"], body["sender_id"]), ("bot@im.bot", "elder@im.wechat"))
        self.assertEqual(body["elder_ref"], ilink_binding.elder_ref("bot@im.bot", "elder@im.wechat"))
        self.assertNotIn("secret", json.dumps(body))
        self.assertEqual(ilink_binding.bridge.route_for_elder(body["elder_ref"])["binding_id"], "binding_1")

    def test_self_report_needs_confirmed_plan(self):
        _, calls = self.bind()
        elder = calls[0][1]["elder_ref"]
        event = {"event_id": "health_1", "elder_id": elder, "event_type": "medication_taken", "family_share": True, "occurred_at": "2026-10-31T19:00:00+08:00"}
        self.assertEqual(ilink_binding.route_event(self.database, event)["status"], "no_confirmed_plan")
        with self.database() as conn:
            conn.execute("INSERT INTO medication_courses VALUES ('c', ?, 'active', '2099-01-01')", (elder,))
            conn.execute("INSERT INTO game_event_identity VALUES ('health_1', 'elder@im.wechat', 'bot@im.bot')")
        with patch.object(ilink_binding.bridge, "enable_task", return_value={"task_instance_id": "task_1"}) as enable, \
                patch.object(ilink_binding.bridge, "submit_confirmed", return_value={"status": "pending"}) as submit:
            self.assertEqual(ilink_binding.route_event(self.database, event)["status"], "submitted")
        self.assertEqual(enable.call_args.args[1:], ("daily_medication_record", "2026-10-31"))
        self.assertEqual(submit.call_args.args[4], "self_report")
        self.assertEqual(ilink_binding.route_event(self.database, {**event, "family_share": False})["status"], "ignored")


if __name__ == "__main__":
    unittest.main()
