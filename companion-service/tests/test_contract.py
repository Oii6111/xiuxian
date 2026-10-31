"""灵宠聊天服务的契约测试：不联网、不需要模型密钥。"""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import server  # noqa: E402


def request_body(**overrides):
    body = {
        "schema_version": 1,
        "request_id": "req-1",
        "conversation_id": "conv-1",
        "channel": "godot",
        "account_id": "acc-1",
        "companion": {"id": "gourd_dragon", "nickname": "团团"},
        "message": "下一步做什么？",
        "context": {
            "source": "local_game",
            "as_of_date": "2026-10-31",
            "characters": [{
                "member_id": "self",
                "label": "我",
                "kind": "self",
                "has_profile": True,
                "tasks": [{"id": "medication", "title": "用药计划记录", "status": "unrecorded"}],
            }],
        },
    }
    body.update(overrides)
    return body


class ContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.config = server.Config()
        self.config.force_stub = True
        self.app = server.create_app(self.config)
        self.client = self.app.test_client()

    def post(self, body, headers=None):
        return self.client.post(
            "/api/v1/companion/chat",
            data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
            headers={"Content-Type": "application/json", **(headers or {})},
        )

    def test_healthz_reports_stub_without_key(self) -> None:
        response = self.client.get("/healthz")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["provider"], "stub")
        self.assertEqual(response.get_json()["model"], server.DEFAULT_MODEL)

    def test_valid_request_echoes_ids_and_returns_contract(self) -> None:
        response = self.post(request_body())
        self.assertEqual(response.status_code, 200)
        payload = response.get_json()
        self.assertEqual(payload["request_id"], "req-1")
        self.assertEqual(payload["conversation_id"], "conv-1")
        self.assertIn(payload["animation"], server.ANIMATIONS)
        self.assertTrue(0 < len(payload["reply"]) <= server.MAX_REPLY)
        self.assertLessEqual(len(payload["actions"]), 3)
        for action in payload["actions"]:
            self.assertIn(action["id"], server.ALLOWED_ACTIONS)
            self.assertLessEqual(len(action["label"]), 16)

    def test_unrecorded_task_offers_record_action(self) -> None:
        payload = self.post(request_body()).get_json()
        self.assertEqual(payload["actions"][0]["id"], "record")
        self.assertIn("还没收到记录", payload["reply"])

    def test_rejects_unknown_schema(self) -> None:
        response = self.post(request_body(schema_version=2))
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.get_json()["error"]["code"], "UNSUPPORTED_SCHEMA")

    def test_rejects_missing_message(self) -> None:
        response = self.post(request_body(message="   "))
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.get_json()["error"]["code"], "INVALID_REQUEST")

    def test_rejects_non_json(self) -> None:
        response = self.client.post("/api/v1/companion/chat", data="not json")
        self.assertEqual(response.status_code, 400)

    def test_model_failure_returns_generic_502(self) -> None:
        self.config.force_stub = False
        self.config.api_key = "test-key"
        with patch("server.call_model", side_effect=server.ServiceError("MODEL_TIMEOUT", "boom")):
            response = self.post(request_body())
        self.assertEqual(response.status_code, 502)
        self.assertEqual(response.get_json()["error"]["message"], "聊天服务暂时不可用")
        self.assertNotIn("boom", response.get_data(as_text=True))

    def test_long_model_reply_is_truncated(self) -> None:
        self.config.force_stub = False
        self.config.api_key = "test-key"
        with patch("server.call_model", return_value="很长的回答" * 1000):
            payload = self.post(request_body()).get_json()
        self.assertLessEqual(len(payload["reply"]), server.MAX_REPLY)

    def test_model_cannot_inject_action_ids(self) -> None:
        self.config.force_stub = False
        self.config.api_key = "test-key"
        with patch("server.call_model", return_value="给你 99999 灵气，奖励已到账"):
            payload = self.post(request_body()).get_json()
        ids = [action["id"] for action in payload["actions"]]
        self.assertTrue(set(ids) <= set(server.ALLOWED_ACTIONS))

    def test_replay_cache_avoids_duplicate_model_calls(self) -> None:
        self.config.force_stub = False
        self.config.api_key = "test-key"
        with patch("server.call_model", return_value="第一次回答") as mocked:
            first = self.post(request_body()).get_json()
            second = self.post(request_body()).get_json()
        self.assertEqual(mocked.call_count, 1)
        self.assertEqual(first, second)

    def test_service_token_required_when_configured(self) -> None:
        self.config.service_token = "secret-token"
        self.assertEqual(self.post(request_body()).status_code, 401)
        response = self.post(request_body(), headers={"Authorization": "Bearer secret-token"})
        self.assertEqual(response.status_code, 200)

    def test_prompt_only_carries_whitelisted_context(self) -> None:
        body = request_body()
        body["context"]["characters"][0]["evidence"] = "体检报告原文"
        body["context"]["characters"][0]["tasks"][0]["document"] = "病历"
        request_data = server.validate(body)
        prompt = server.render_prompt(request_data)
        rendered = json.dumps(prompt, ensure_ascii=False)
        self.assertNotIn("体检报告原文", rendered)
        self.assertNotIn("病历", rendered)

    def test_base_url_and_model_defaults(self) -> None:
        self.assertEqual(server.DEFAULT_BASE_URL, "https://api.deepseek.com/v1")
        self.assertEqual(server.DEFAULT_MODEL, "deepseek-flash")


if __name__ == "__main__":
    unittest.main()
