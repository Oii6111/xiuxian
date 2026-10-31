import hashlib
from contextlib import closing
import importlib.util
import json
from pathlib import Path
import sqlite3
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

spec = importlib.util.spec_from_file_location("account_server", Path(__file__).resolve().parents[1] / "server/account/server.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class AccountsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "accounts.sqlite3"
        self.server = module.make_server(self.path, 0)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.temp.cleanup()

    def call(self, route, data=None, token=""):
        headers = {"Content-Type": "application/json"}
        if token:
            headers["Authorization"] = "Bearer " + token
        request = Request(self.base + route, json.dumps(data).encode() if data is not None else None, headers)
        try:
            with urlopen(request, timeout=5) as response:
                return response.status, json.load(response)
        except HTTPError as error:
            return error.code, json.load(error)

    def register(self, name="child_one"):
        return self.call("/api/v1/auth/register", {"username": name, "password": "fixture-password", "display_name": "测试子女"})

    def test_registration_hashing_and_duplicate(self):
        code, result = self.register()
        self.assertEqual(code, 200)
        self.assertEqual(len(result["account"]["id"]), 32)
        with closing(sqlite3.connect(self.path)) as db:
            salt, hashed = db.execute("SELECT salt,password_hash FROM users").fetchone()
        self.assertEqual(hashed, hashlib.pbkdf2_hmac("sha256", b"fixture-password", salt, module.ITERATIONS))
        self.assertNotIn("fixture-password", self.path.read_bytes().decode("latin-1"))
        self.assertEqual(self.register()[0], 409)

    def test_login_logout_and_expiry(self):
        self.register()
        self.assertEqual(self.call("/api/v1/auth/login", {"username": "child_one", "password": "wrong-password"})[0], 401)
        code, logged = self.call("/api/v1/auth/login", {"username": "CHILD_ONE", "password": "fixture-password"})
        self.assertEqual(code, 200)
        token = logged["token"]
        self.assertEqual(self.call("/api/v1/auth/session", token=token)[0], 200)
        self.assertEqual(self.call("/api/v1/auth/logout", {}, token)[0], 200)
        self.assertEqual(self.call("/api/v1/auth/session", token=token)[0], 401)
        _, expired = self.call("/api/v1/auth/login", {"username": "child_one", "password": "fixture-password"})
        with closing(sqlite3.connect(self.path)) as db:
            db.execute("UPDATE sessions SET expires_at=0")
            db.commit()
        self.assertEqual(self.call("/api/v1/auth/session", token=expired["token"])[0], 401)

    def test_legacy_progress_has_one_account_owner(self):
        _, a = self.register("child_a")
        _, b = self.register("child_b")
        data = {"fingerprint": "a" * 64}
        self.assertEqual(self.call("/api/v1/auth/claim-legacy", data, a["token"])[0], 200)
        self.assertEqual(self.call("/api/v1/auth/claim-legacy", data, a["token"])[0], 200)
        self.assertEqual(self.call("/api/v1/auth/claim-legacy", data, b["token"])[0], 409)
        self.assertEqual(self.call("/api/v1/auth/claim-legacy", data)[0], 401)

    def test_validation_and_rate_limit(self):
        self.assertEqual(self.call("/api/v1/auth/register", {"username": "../unsafe", "password": "12345678", "display_name": "昵称"})[0], 400)
        self.assertEqual(self.call("/api/v1/auth/register", {"username": "valid_name", "password": "short", "display_name": "昵称"})[0], 400)
        self.register()
        for _ in range(5):
            self.assertEqual(self.call("/api/v1/auth/login", {"username": "child_one", "password": "wrong-password"})[0], 401)
        self.assertEqual(self.call("/api/v1/auth/login", {"username": "child_one", "password": "fixture-password"})[0], 429)


if __name__ == "__main__":
    unittest.main()
