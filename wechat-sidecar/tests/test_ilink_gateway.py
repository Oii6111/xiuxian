"""iLink 网关测试：用本地假 iLink 服务验证收消息、回消息、游标与去重。"""

from __future__ import annotations

import json
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import ilink_gateway  # noqa: E402


class FakeILink(BaseHTTPRequestHandler):
    state = {"updates": 0, "sent": [], "stale": False}

    def do_POST(self):
        size = int(self.headers.get("Content-Length", "0"))
        body = json.loads(self.rfile.read(size) or b"{}")
        if self.path.startswith("/ilink/bot/getupdates"):
            if self.state["stale"]:
                payload = {"ret": -14, "errmsg": "token expired"}
            elif self.state["updates"] == 0:
                payload = {
                    "ret": 0,
                    "get_updates_buf": "cursor-1",
                    "msgs": [{
                        "from_user_id": "user-1",
                        "context_token": "ctx-1",
                        "item_list": [{"type": 1, "text_item": {"text": "今天任务怎么样"}}],
                    }],
                }
                self.state["updates"] += 1
            else:
                payload = {"ret": 0, "get_updates_buf": "cursor-2", "msgs": []}
        elif self.path.startswith("/ilink/bot/sendmessage"):
            self.state["sent"].append(body.get("msg", {}))
            payload = {"ret": 0}
        else:
            payload = {"ret": 0}
        data = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


class GatewayTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), FakeILink)
        cls.port = cls.server.server_port
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.credentials = root / "ilink_accounts.json"
        self.credentials.write_text(json.dumps({
            "bot-1:user-1": {
                "ilink_bot_id": "bot-1",
                "ilink_user_id": "user-1",
                "bot_token": "token-1",
                "baseurl": f"http://127.0.0.1:{self.port}",
            }
        }), encoding="utf-8")
        self.state_path = root / "ilink_state.json"
        ilink_gateway.CREDENTIALS = self.credentials
        ilink_gateway.STATE = self.state_path
        FakeILink.state = {"updates": 0, "sent": [], "stale": False}

    def tearDown(self):
        self.tmp.cleanup()

    def test_receives_reply_and_persists_cursor(self):
        replies = []
        gateway = ilink_gateway.Gateway(reply=lambda payload: replies.append(payload) or {"reply": "收到：" + payload["text"]})
        gateway.start()
        deadline = time.time() + 6
        while time.time() < deadline and not FakeILink.state["sent"]:
            time.sleep(0.05)
        gateway.stop()
        self.assertEqual(len(replies), 1)
        self.assertEqual(replies[0]["elder_id"], ilink_gateway.elder_ref("bot-1", "user-1"))
        self.assertEqual(len(FakeILink.state["sent"]), 1)
        msg = FakeILink.state["sent"][0]
        self.assertEqual(msg["to_user_id"], "user-1")
        self.assertEqual(msg["context_token"], "ctx-1")
        self.assertEqual(msg["item_list"][0]["text_item"]["text"], "收到：今天任务怎么样")
        saved = json.loads(self.state_path.read_text(encoding="utf-8"))
        self.assertEqual(saved["bot-1"]["cursor"], "cursor-1")
        self.assertEqual(len(saved["bot-1"]["seen"]), 1)

    def test_duplicate_message_is_not_answered_twice(self):
        calls = []
        gateway = ilink_gateway.Gateway(reply=lambda payload: calls.append(payload) or {"reply": "ok"})
        gateway.start()
        time.sleep(1.0)
        gateway.stop()
        # 同样的 from+text 再出现一次（换一个 Gateway 实例模拟重启）
        FakeILink.state["updates"] = 0
        gateway2 = ilink_gateway.Gateway(reply=lambda payload: calls.append(payload) or {"reply": "ok"})
        gateway2.start()
        time.sleep(1.0)
        gateway2.stop()
        self.assertEqual(len(calls), 1)

    def test_stale_token_stops_polling(self):
        FakeILink.state["stale"] = True
        gateway = ilink_gateway.Gateway(reply=lambda payload: {"reply": "ok"})
        gateway.start()
        deadline = time.time() + 4
        while time.time() < deadline and gateway.last_error == "":
            time.sleep(0.05)
        time.sleep(0.3)
        gateway.stop()
        self.assertIn("ret=-14", gateway.last_error)
        self.assertFalse(any(t.is_alive() for t in gateway._threads))


if __name__ == "__main__":
    unittest.main()
