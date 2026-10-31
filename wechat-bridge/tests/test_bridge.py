import importlib.util
import json
import os
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("bridge", Path(__file__).resolve().parents[1] / "game_task_bridge.py")
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.route = {"binding_id": "binding-a", "elder_id": "elder-a", "sender_id": "sender-a",
                      "channel_account_id": "bot-a", "target": "recipient-a", "consent_version": 1}
        patch.dict(os.environ, {"ELDER_BINDINGS": json.dumps([self.route]), "OPENCLAW_DRY_RUN": "0"}).start()
        patch.object(bridge, "STATE_PATH", Path(self.temp.name) / "state.sqlite3").start()
        self.addCleanup(patch.stopall)
        self.stamp = time.time() - 10
        self.observed = bridge.datetime.fromtimestamp(self.stamp, bridge.timezone.utc).isoformat(timespec="seconds")
        self.bundle = {"binding": {"binding_id": "binding-a", "consent_version": 1, "status": "active",
                                   "consent_status": "active", "connected": True},
                       "tasks": [{"task_instance_id": "task-a", "cultivator_id": "character-a", "status": "pending",
                                  "template_id": "daily_step_record", "verification_levels": ["photo", "self_report"],
                                  "window_start": self.stamp - 60, "window_end": self.stamp + 3600, "rule_version": "integration-v1"}]}
        patch.object(bridge, "game_get", return_value=self.bundle).start()

    def submit(self, **changes):
        values = dict(binding_id="binding-a", task_id="task-a", event_id="health-a", observed_at=self.observed,
                      verification_level="photo", sender_id="sender-a", channel_account_id="bot-a")
        values.update(changes)
        return bridge.submit_confirmed(**values)

    def note(self, **changes):
        value = {"notification_id": "note-a", "binding_id": "binding-a", "consent_version": 1,
                 "lease_until": time.time() + 30, "lease_token": "lease-a", "payload": {}}
        value.update(changes)
        return value

    def test_dry_run_never_mutates(self):
        with patch.dict(os.environ, {"OPENCLAW_DRY_RUN": "1"}), patch.object(bridge, "game_post") as post:
            self.assertTrue(self.submit()["dry_run"])
            bridge.claim_notifications()
            bridge.retry_results()
            post.assert_not_called()
            self.assertFalse(bridge.STATE_PATH.exists())

    def test_same_event_survives_settlement_and_restart(self):
        with patch.object(bridge, "game_post", return_value={}) as post:
            self.submit()
            first = post.call_args.args[1]
            self.bundle["tasks"] = []
            self.submit()
            self.assertEqual(first, post.call_args.args[1])
            self.assertEqual(set(first), {"event_id", "task_instance_id", "cultivator_id", "binding_id",
                "consent_version", "verification_level", "source", "channel", "observed_at", "rule_version"})
            with self.assertRaisesRegex(bridge.BridgeError, "EVENT_CONFLICT"):
                self.submit(verification_level="self_report")

    def test_failure_keeps_original_payload(self):
        with patch.object(bridge, "game_post", side_effect=OSError):
            with self.assertRaises(OSError):
                self.submit()
        self.bundle["tasks"] = []
        with patch.object(bridge, "game_post", return_value={}) as post:
            bridge.retry_results()
            self.assertEqual(post.call_count, 1)
            self.assertEqual(post.call_args.args[1]["observed_at"], self.observed)

    def test_revoked_or_disconnected_cannot_retry(self):
        with patch.object(bridge, "game_post", side_effect=OSError):
            with self.assertRaises(OSError):
                self.submit()
        self.bundle["binding"]["consent_status"] = "revoked"
        with patch.object(bridge, "game_post") as post:
            bridge.retry_results()
            post.assert_not_called()
        self.bundle["binding"]["consent_status"] = "active"
        self.bundle["binding"]["connected"] = False
        with self.assertRaises(bridge.BridgeError):
            self.submit()

    def test_identity_window_and_verification_checks(self):
        for changes in [{"sender_id": "other"}, {"channel_account_id": "other"}, {"event_id": ""},
                        {"task_id": "other"}, {"verification_level": "device"},
                        {"observed_at": "2020-01-01T00:00:00+00:00"}]:
            with self.subTest(changes=changes), self.assertRaises(bridge.BridgeError):
                self.submit(**changes)

    def test_chat_and_random_photo_do_not_complete_task(self):
        for text in ["还没有吃药", "你好", "我在医院"]:
            self.assertFalse(bridge.complete_task_from_reply("binding-a", text, True, "message")["ok"])

    def test_notification_routes_and_ack_retry_deduplicate(self):
        delivered = []
        def post(path, body):
            if path.endswith("claim"):
                return {"notifications": [self.note()]}
            if path.endswith("ack") and not delivered:
                raise OSError()
            return {}
        with patch.object(bridge, "game_post", side_effect=post), patch.object(bridge, "send_wechat", return_value=True) as send:
            self.assertEqual(bridge.claim_notifications(), 0)
            delivered.append(True)
            self.assertEqual(bridge.claim_notifications(), 1)
            send.assert_called_once()
            self.assertEqual(send.call_args.args[0]["target"], "recipient-a")

    def test_unknown_route_and_failed_send_nack(self):
        for note in [self.note(binding_id="unknown"), self.note()]:
            with patch.object(bridge, "game_post", return_value={"notifications": [note]}) as post, patch.object(bridge, "send_wechat", return_value=False):
                self.assertEqual(bridge.claim_notifications(), 0)
                self.assertTrue(post.call_args.args[0].endswith("/nack"))

    def test_mapping_rejects_ambiguous_old_format(self):
        for value in [{"elder-a": "binding-a"}, [self.route, self.route]]:
            with patch.dict(os.environ, {"ELDER_BINDINGS": json.dumps(value)}), self.assertRaises(bridge.BridgeError):
                bridge.routes()

    def test_templates_match_c(self):
        source = (Path(__file__).resolve().parents[2] / "server/src/game/rules.ts").read_text(encoding="utf-8")
        for template in bridge.TASK_TEMPLATES:
            self.assertIn("id: '" + template + "'", source)


if __name__ == "__main__":
    unittest.main()
