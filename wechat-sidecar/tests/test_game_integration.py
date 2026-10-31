import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from flask import Flask

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import elder_assistant as elder
import game_integration as integration


class SidecarTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        patch.object(elder, "DB_PATH", Path(temp.name) / "health.sqlite3").start()
        self.route = {"binding_id": "binding-a", "elder_id": "elder-a", "sender_id": "sender-a",
                      "channel_account_id": "bot-a", "target": "recipient-a", "consent_version": 1}
        patch.dict(os.environ, {"ELDER_BINDINGS": json.dumps([self.route]), "ELDER_SIDECAR_TOKEN": "sidecar-test",
                               "GAME_REVIEW_TOKEN": "review-test", "HEALTH_EVENT_SINK_URL": ""}).start()
        self.addCleanup(patch.stopall)
        app = Flask(__name__)
        elder.register_elder_assistant_routes(app)
        self.client = app.test_client()

    def confirmed(self, family_share=True, sender="sender-a"):
        session = elder._save_session("elder-a", "openclaw-weixin", sender, "bot-a")
        pending = elder._save_pending("elder-a", session, {"event_type": "photo_observation",
            "facts": {"medical_notes": "private diagnosis", "raw_photo": "private-image"}}, "routine", family_share)
        return elder.confirm_pending(pending, "confirm")["event"]

    def review(self, event, **changes):
        payload = {"binding_id": "binding-a", "task_instance_id": "task-a", "event_id": event["event_id"],
                   "verification_level": "photo", "evidence_confirmed": True}
        payload.update(changes)
        return self.client.post("/internal/v1/game/verified-events", json=payload,
                                headers={"Authorization": "Bearer review-test"})

    def test_verified_projection_never_passes_health_objects(self):
        event = self.confirmed()
        with patch.object(integration.bridge, "submit_confirmed", return_value={"status": "pending"}) as submit:
            self.assertEqual(self.review(event).status_code, 200)
            args = submit.call_args.args
            self.assertEqual(args[2], event["event_id"])
            self.assertNotIn("private", str(args))
            self.assertEqual(args[-2:], ("sender-a", "bot-a"))

    def test_unshared_and_foreign_identity_rejected(self):
        for event in [self.confirmed(False), self.confirmed(sender="foreign")]:
            with patch.object(integration.bridge, "submit_confirmed") as submit:
                self.assertEqual(self.review(event).status_code, 409)
                submit.assert_not_called()

    def test_extra_fields_and_unverified_or_upgraded_evidence_rejected(self):
        event = self.confirmed()
        for changes in [{"raw_photo": "image"}, {"evidence_confirmed": False}, {"verification_level": "device"}]:
            with patch.object(integration.bridge, "submit_confirmed") as submit:
                self.assertIn(self.review(event, **changes).status_code, [400, 409])
                submit.assert_not_called()

    def test_chat_token_cannot_call_reviewer(self):
        for auth in ["", "Bearer sidecar-test"]:
            response = self.client.post("/internal/v1/game/verified-events", json={}, headers={"Authorization": auth})
            self.assertEqual(response.status_code, 401)

    def test_unconfigured_sidecar_is_closed(self):
        with patch.dict(os.environ, {"ELDER_SIDECAR_TOKEN": ""}):
            self.assertEqual(self.client.post("/api/v1/elder/message", json={}).status_code, 503)

    def test_unshared_events_never_go_to_sink(self):
        with patch.object(elder.requests, "post") as post:
            elder._send_event_sink({"family_share": False})
            post.assert_not_called()

    def test_expired_confirmation_is_blocked(self):
        session = elder._save_session("elder-a", "openclaw-weixin", "sender-a", "bot-a")
        pending = elder._save_pending("elder-a", session, {"event_type": "photo_observation"}, "routine", True)
        with elder._db() as conn:
            conn.execute("UPDATE pending_events SET expires_at = '2000-01-01' WHERE event_id = ?", (pending,))
        self.assertEqual(elder.confirm_pending(pending, "confirm")["status"], "expired")


if __name__ == "__main__":
    unittest.main()
