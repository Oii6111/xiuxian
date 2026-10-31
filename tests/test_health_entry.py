"""Contract checks; all model responses are fixtures, no network/model fees."""
import base64
import copy
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "health-entry"))
import server
import recognizer
from PIL import Image

DOCUMENT = {"title": "测试报告", "person": {"name": "不可保存的姓名"}, "groups": [
    {"title": "测试指标", "items": [{"label": "测试血压", "value": "100/70", "status": "unknown"}]}], "summary": "测试文本"}


class HealthEntryTest(unittest.TestCase):
    def setUp(self):
        self.client = server.app.test_client()
        self.tmp = tempfile.TemporaryDirectory()
        self.storage = patch.object(server, "BASELINE_DIR", self.tmp.name)
        self.storage.start()
        self.config = patch.object(recognizer, "load_config", return_value=("test-key", "http://127.0.0.1", "test-fixture"))
        self.config.start()
        server.RECORDS.clear()
        data = io.BytesIO()
        Image.new("RGB", (10, 10)).save(data, "PNG")
        self.image = "data:image/png;base64," + base64.b64encode(data.getvalue()).decode()

    def tearDown(self):
        self.config.stop()
        self.storage.stop()
        self.tmp.cleanup()

    def parse_request(self, payload):
        # Fill ordinary required form fields for existing protocol test cases.
        payload = copy.deepcopy(payload)
        if isinstance(payload.get("profile", {}), dict):
            profile = dict(name="健康测试", age=68, sex="男", relation="本人")
            profile.update(payload.get("profile", {}))
            payload["profile"] = profile
        return self.client.post("/api/v1/records/parse", json=payload)

    def parse(self):
        with patch.object(recognizer, "recognize_medical_report", return_value=copy.deepcopy(DOCUMENT)):
            response = self.parse_request({"data_urls": [self.image], "profile": {"name": "健康测试"}})
        self.assertEqual(response.status_code, 200)
        return response.get_json()

    def test_identity_and_secret_isolation(self):
        status = self.client.get("/api/v1/health").get_json()
        self.assertEqual(status["service"], "xiuxian-health-entry")
        self.assertNotIn("test-key", json.dumps(status))
        for path in ("/.env", "/.env.example", "/recognizer.py", "/baselines/test.json", "/.deps/dotenv/__init__.py"):
            self.assertEqual(self.client.get(path).status_code, 404)

    def test_bad_image_rejected_before_model(self):
        with patch.object(recognizer, "recognize_medical_report") as model:
            for value in ("data:image/png;base64,abcd", "data:application/pdf;base64,YQ==", self.image.replace("png", "jpeg")):
                self.assertEqual(self.parse_request({"data_url": value}).status_code, 400)
            model.assert_not_called()

    def test_missing_key_never_fabricates_result(self):
        with patch.object(recognizer, "load_config", return_value=("", "", "qwen3-vl-plus")):
            response = self.parse_request({"data_url": self.image})
        self.assertEqual(response.status_code, 503)
        self.assertNotIn("game_projection", response.get_json())

    def test_bad_model_document_not_projected(self):
        for data in ({}, {"groups": []}, {"groups": [None]}, {"groups": [{"items": ["bad"]}]}):
            with patch.object(recognizer, "recognize_medical_report", return_value=data):
                self.assertEqual(self.parse_request({"data_url": self.image}).status_code, 502)

    def test_rules_and_authoritative_lock(self):
        response = self.parse()
        expected = server.rules.build_projection(recognizer.validate_document(DOCUMENT))
        self.assertEqual(response["game_projection"], expected)
        self.assertEqual(response["document"]["person"]["name"], "健康测试")
        record = server.RECORDS[response["record_id"]]
        self.assertNotIn("document", record)
        self.assertFalse(list(Path(self.tmp.name).glob("*.json")))
        payload = dict(record_id=response["record_id"], recognition_mode="live", baseline_locked=True,
                       character_state={"attack": 99}, source_document=DOCUMENT)
        saved = self.client.post("/api/v1/game/baseline", json=payload)
        self.assertEqual(saved.status_code, 200)
        baseline = saved.get_json()["baseline"]
        self.assertEqual(baseline["character_state"], expected["character_state"])
        stored = next(Path(self.tmp.name).glob("*.json")).read_text(encoding="utf8")
        self.assertNotIn("不可保存", stored)
        self.assertNotIn("source_document", stored)
        self.assertNotIn("test-key", stored)
        self.assertEqual(self.client.post("/api/v1/game/baseline", json=payload).get_json()["baseline_id"], baseline["baseline_id"])
        self.assertEqual(len(list(Path(self.tmp.name).glob("*.json"))), 1)

    def test_lock_requires_existing_record(self):
        self.assertEqual(self.client.post("/api/v1/game/baseline", json={}).status_code, 400)
        self.assertEqual(self.client.post("/api/v1/game/baseline", json=dict(baseline_locked=True, recognition_mode="live", record_id="invented")).status_code, 409)

    def test_demo_is_always_labelled_sample(self):
        data = json.loads((Path(server.BASE_DIR) / "sample-baseline.json").read_text(encoding="utf8"))
        data["recognition_mode"] = "demo"
        response = self.client.post("/api/v1/game/baseline", json=data)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["baseline"]["recognition_mode"], "sample")
        data["character_state"]["attack"] = True
        self.assertEqual(self.client.post("/api/v1/game/baseline", json=data).status_code, 400)

    def test_multi_image_and_history_preserved(self):
        document = dict(DOCUMENT, history=[dict(condition="高血压", status="ongoing")],
                        medications=[dict(name="氨氯地平", purpose="降压", status="ongoing")])
        with patch.object(recognizer, "recognize_medical_report", return_value=document) as model:
            response = self.parse_request(dict(data_urls=[self.image, self.image], profile={"name": "合并测试"}))
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(model.call_args.args[0]), 2)
        data = response.get_json()
        self.assertEqual(data["game_projection"]["character_state"]["spirit"], 52)  # unknown test BP follows upstream rule +4, history -5, medication +3
        self.assertEqual(data["recognition_mode"], "live")
        self.assertIn("attribute_notes", data["game_projection"])
        self.assertNotIn("five_elements", data["game_projection"])

    def test_text_only_uses_current_rules_without_model(self):
        with patch.object(recognizer, "load_config", return_value=("", "", "qwen3-vl-plus")), patch.object(recognizer, "recognize_medical_report") as model:
            response = self.parse_request(dict(profile={"name": "文字测试"}, history_text="高血压10年", medications_text="氨氯地平"))
        self.assertEqual(response.status_code, 200)
        model.assert_not_called()
        result = response.get_json()
        self.assertEqual(result["recognition_mode"], "text")
        self.assertEqual(result["game_projection"]["character_state"]["spirit"], 48)
        saved = self.client.post("/api/v1/game/baseline", json=dict(record_id=result["record_id"], baseline_locked=True, recognition_mode="text")).get_json()["baseline"]
        self.assertEqual(saved["display_name"], "文字测试")
        self.assertEqual(saved["mapping_version"], "body_system_v2")
        self.assertNotIn("source_document", saved)
        self.assertNotIn("history", saved)

    def test_history_or_prescription_image_needs_no_exam_items(self):
        for document in ({"history": [{"condition": "高血压", "status": "ongoing"}]}, {"medications": [{"name": "氨氯地平", "status": "ongoing"}]}):
            with patch.object(recognizer, "recognize_medical_report", return_value=document):
                self.assertEqual(self.parse_request({"data_urls": [self.image]}).status_code, 200)

    def test_input_limits(self):
        for payload in ({"data_urls": [self.image] * 7}, {"profile": []}, {"history_text": "x" * 4001}, {"data_urls": [None]}):
            self.assertEqual(self.parse_request(payload).status_code, 400)

    def test_drug_generic_name_and_brand_survive_extraction(self):
        document = {"medications": [{"name": "阿托伐他汀钙片", "brand": "立普妥", "purpose": "降脂", "status": "ongoing"}]}
        with patch.object(recognizer, "recognize_medical_report", return_value=document):
            response = self.parse_request({"data_urls": [self.image]})
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertEqual(data["document"]["medications"][0]["brand"], "立普妥")
        self.assertEqual(data["game_projection"]["character_state"]["speed"], 53)
        self.assertEqual(data["game_projection"]["character_state"]["stamina"], 50)
        self.assertEqual(data["source_revision"], "1f356a0")

    def test_brand_does_not_drive_system_assignment(self):
        document = recognizer.validate_document({"medications": [{"name": "未识别通用名", "brand": "阿司匹林", "status": "unknown"}]})
        result = server.rules.build_projection(document)
        self.assertEqual(result["character_state"]["spirit"], 50)

    def test_history_notes_do_not_reassign_condition(self):
        document = {"history": [{"condition": "胃炎", "note": "高血压", "status": "ongoing"}]}
        result = server.rules.build_projection(document)
        self.assertEqual(result["character_state"]["hp_max"], 75)
        self.assertEqual(result["character_state"]["spirit"], 50)

    def test_three_fixture_images_are_readable_and_sent_together(self):
        data_urls = []
        for name in ("样本体检报告.png", "手写既往病史记录.png", "四款药品包装展示.png"):
            raw = (Path(server.BASE_DIR) / name).read_bytes()
            data_urls.append("data:image/png;base64," + base64.b64encode(raw).decode())
        with patch.object(recognizer, "recognize_medical_report", return_value=copy.deepcopy(DOCUMENT)) as model:
            response = self.parse_request({"data_urls": data_urls})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(model.call_args.args[0]), 3)

    def test_confirmed_record_retains_rules_revision(self):
        parsed = self.parse()
        response = self.client.post("/api/v1/game/baseline", json=dict(record_id=parsed["record_id"], recognition_mode="live", baseline_locked=True))
        self.assertEqual(response.get_json()["baseline"]["rules_revision"], "1f356a0")

    def test_required_profile_checked_before_model(self):
        valid = dict(name="必填测试", age=68, sex="男", relation="父亲")
        with patch.object(recognizer, "recognize_medical_report") as model:
            for key in ("name", "age", "sex", "relation"):
                missing = dict(valid)
                del missing[key]
                response = self.client.post("/api/v1/records/parse", json=dict(data_urls=[self.image], profile=missing))
                self.assertEqual(response.status_code, 400, key)
                self.assertNotIn("game_projection", response.get_json())
            model.assert_not_called()

    def test_invalid_age_and_blank_profile_rejected(self):
        for age in (None, "", "abc", 0, -1, 121, True, 20.5, "nan"):
            self.assertEqual(self.parse_request({"profile": {"age": age}}).status_code, 400)
        for field in ("name", "relation", "sex"):
            self.assertEqual(self.parse_request({"profile": {field: "   "}}).status_code, 400)

    def test_proxy_auto_routing_and_explicit_override(self):
        with patch.dict("os.environ", {}, clear=True), patch.object(recognizer, "dotenv_values", return_value={}):
            self.assertFalse(recognizer.use_system_proxy("https://dashscope.aliyuncs.com/compatible-mode/v1"))
            self.assertFalse(recognizer.use_system_proxy("https://ws-test.cn-beijing.maas.aliyuncs.com/compatible-mode/v1"))
            self.assertFalse(recognizer.use_system_proxy("http://127.0.0.1:9000/v1"))
            self.assertTrue(recognizer.use_system_proxy("https://api.example.com/v1"))
            self.assertTrue(recognizer.use_system_proxy("https://dashscope.aliyuncs.com.evil.example/v1"))
        for value, expected in (("true", True), ("false", False)):
            with patch.dict("os.environ", {}, clear=True), patch.object(recognizer, "dotenv_values", return_value={"LLM_USE_SYSTEM_PROXY": value}):
                self.assertEqual(recognizer.use_system_proxy("https://dashscope.aliyuncs.com/v1"), expected)

    def test_tls_failure_returns_specific_safe_error(self):
        with patch.object(recognizer.requests, "Session") as factory, patch.object(recognizer, "use_system_proxy", return_value=False):
            factory.return_value.post.side_effect = recognizer.requests.exceptions.SSLError("private-token-and-report-text")
            response = self.parse_request({"data_urls": [self.image]})
        self.assertEqual(response.status_code, 502)
        self.assertEqual(response.get_json()["error_code"], "network_tls")
        self.assertNotIn("private-token", json.dumps(response.get_json()))
        factory.return_value.close.assert_called_once()

    def test_auth_failure_never_echoes_upstream_body(self):
        with patch.object(recognizer.requests, "Session") as factory, patch.object(recognizer, "use_system_proxy", return_value=False):
            factory.return_value.post.return_value.status_code = 401
            factory.return_value.post.return_value.text = "private-key-and-report-body"
            response = self.parse_request({"data_urls": [self.image]})
        self.assertEqual(response.get_json()["error_code"], "upstream_http_401")
        self.assertNotIn("private-key", json.dumps(response.get_json()))

    def test_model_transport_uses_selected_route_with_tls_verification(self):
        with patch.object(recognizer.requests, "Session") as factory, patch.object(recognizer, "use_system_proxy", return_value=False):
            session = factory.return_value
            session.post.return_value.status_code = 200
            session.post.return_value.json.return_value = {"choices": [{"message": {"content": json.dumps(DOCUMENT)}}]}
            document = recognizer.recognize_medical_report(self.image)
        self.assertFalse(session.trust_env)
        self.assertNotIn("verify", session.post.call_args.kwargs)
        self.assertEqual(document["groups"], DOCUMENT["groups"])
        session.post.assert_called_once()

    def test_game_projection_endpoint_never_exposes_health_explanations(self):
        profile = dict(name="投影测试", age=68, sex="男", relation="父亲")
        response = self.client.post("/api/v1/game/projections/parse", json=dict(profile=profile, history_text="高血压", medications_text="氨氯地平"))
        self.assertEqual(response.status_code, 200)
        parsed = response.get_json()
        serialized = json.dumps(parsed, ensure_ascii=False)
        for forbidden in ("高血压", "氨氯地平", "attribute_notes", "evidence", "document", "provider"):
            self.assertNotIn(forbidden, serialized)
        self.assertEqual(parsed["game_projection"]["character_state"]["spirit"], 48)
        request = dict(record_id=parsed["record_id"], recognition_mode="text", baseline_locked=True)
        first = self.client.post("/api/v1/game/projections/confirm", json=request)
        repeated = self.client.post("/api/v1/game/projections/confirm", json=request)
        self.assertEqual(first.status_code, 200)
        self.assertEqual(first.get_json(), repeated.get_json())
        game_data = json.dumps(first.get_json(), ensure_ascii=False)
        for forbidden in ("高血压", "氨氯地平", "attribute_notes", "evidence", "document", "provider"):
            self.assertNotIn(forbidden, game_data)
        stored = next(Path(self.tmp.name).glob("*.json")).read_text(encoding="utf8")
        self.assertIn("attribute_notes", stored)  # This is the separate health-domain store.

    def test_config_refresh_and_default_model(self):
        # Never read or modify the user's real key in this test.
        self.config.stop()
        try:
            with patch.dict("os.environ", {}, clear=True), patch.object(recognizer, "dotenv_values", return_value={"LLM_API_KEY": "first"}):
                self.assertEqual(recognizer.load_config()[0], "first")
                self.assertEqual(recognizer.load_config()[2], "qwen3-vl-plus")
            with patch.dict("os.environ", {}, clear=True), patch.object(recognizer, "dotenv_values", return_value={"LLM_API_KEY": "second"}):
                self.assertEqual(recognizer.load_config()[0], "second")
        finally:
            self.config.start()


if __name__ == "__main__":
    unittest.main(verbosity=2)
