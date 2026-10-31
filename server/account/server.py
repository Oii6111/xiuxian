"""Loopback account service: real password verification and revocable sessions.

Game progress remains per-account local files. No passwords are written by Godot.
"""
from __future__ import annotations
import argparse
from contextlib import contextmanager
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import secrets
import sqlite3
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ITERATIONS = 600_000
SESSION_SECONDS = 12 * 60 * 60
USERNAME = re.compile(r"^[A-Za-z0-9_]{3,24}$")


class AccountError(Exception):
    def __init__(self, status: int, message: str):
        self.status, self.message = status, message


class Accounts:
    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.lock = threading.Lock()
        self.failures: dict[str, list[float]] = {}
        with self.connect() as db:
            db.executescript("""
            CREATE TABLE IF NOT EXISTS users (
                id TEXT PRIMARY KEY, username TEXT UNIQUE NOT NULL,
                display_name TEXT NOT NULL, avatar TEXT NOT NULL,
                salt BLOB NOT NULL, password_hash BLOB NOT NULL,
                iterations INTEGER NOT NULL, created_at REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS sessions (
                token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id),
                expires_at REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS legacy_claims (
                fingerprint TEXT PRIMARY KEY, user_id TEXT NOT NULL,
                created_at REAL NOT NULL);
            """)

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=5)
        db.row_factory = sqlite3.Row
        try:
            with db:
                yield db
        finally:
            db.close()

    @staticmethod
    def public(user):
        return {key: user[key] for key in ("id", "username", "display_name", "avatar")}

    @staticmethod
    def digest(password: str, salt: bytes, iterations=ITERATIONS):
        return hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations)

    def issue(self, db, user):
        token = secrets.token_urlsafe(32)
        expires = time.time() + SESSION_SECONDS
        db.execute("DELETE FROM sessions WHERE expires_at <= ?", (time.time(),))
        db.execute("INSERT INTO sessions VALUES(?,?,?)", (hashlib.sha256(token.encode()).hexdigest(), user["id"], expires))
        return {"ok": True, "account": self.public(user), "token": token, "expires_at": expires}

    def register(self, data):
        username = str(data.get("username", "")).strip().lower()
        password = data.get("password", "")
        name = str(data.get("display_name", "")).strip()
        if not USERNAME.fullmatch(username):
            raise AccountError(400, "用户名请使用 3—24 位字母、数字或下划线。")
        if not isinstance(password, str) or not 8 <= len(password) <= 128:
            raise AccountError(400, "密码长度应为 8—128 位。")
        if not 1 <= len(name) <= 10:
            raise AccountError(400, "请填写昵称，最多 10 个字。")
        avatar = "female" if data.get("avatar") == "female" else "male"
        salt = secrets.token_bytes(16)
        hashed = self.digest(password, salt)
        with self.connect() as db:
            try:
                db.execute("INSERT INTO users VALUES(?,?,?,?,?,?,?,?)", (secrets.token_hex(16), username, name, avatar, salt, hashed, ITERATIONS, time.time()))
            except sqlite3.IntegrityError:
                raise AccountError(409, "该用户名已注册，请登录或换一个用户名。")
            return self.issue(db, db.execute("SELECT * FROM users WHERE username=?", (username,)).fetchone())

    def login(self, data, peer="local"):
        username = str(data.get("username", "")).strip().lower()
        password = data.get("password", "")
        if not isinstance(password, str) or len(password) > 128 or not USERNAME.fullmatch(username):
            raise AccountError(401, "用户名或密码不正确。")
        key = peer + ":" + username
        with self.lock:
            attempts = [t for t in self.failures.get(key, []) if time.time() - t < 60]
            self.failures[key] = attempts
            if len(attempts) >= 5:
                raise AccountError(429, "尝试次数较多，请一分钟后重试。")
        with self.connect() as db:
            user = db.execute("SELECT * FROM users WHERE username=?", (username,)).fetchone()
            expected = user["password_hash"] if user else bytes(32)
            actual = self.digest(password, user["salt"] if user else bytes(16), user["iterations"] if user else ITERATIONS)
            if not user or not hmac.compare_digest(actual, expected):
                with self.lock:
                    self.failures.setdefault(key, []).append(time.time())
                raise AccountError(401, "用户名或密码不正确。")
            with self.lock:
                self.failures.pop(key, None)
            return self.issue(db, user)

    def session(self, token):
        if not token or len(token) > 256:
            raise AccountError(401, "登录已失效，请重新登录。")
        hashed = hashlib.sha256(token.encode()).hexdigest()
        with self.connect() as db:
            user = db.execute("SELECT users.* FROM sessions JOIN users ON users.id=sessions.user_id WHERE token_hash=? AND expires_at>?", (hashed, time.time())).fetchone()
            if not user:
                raise AccountError(401, "登录已失效，请重新登录。")
            return self.public(user)

    def logout(self, token):
        with self.connect() as db:
            db.execute("DELETE FROM sessions WHERE token_hash=?", (hashlib.sha256(token.encode()).hexdigest(),))
        return {"ok": True}

    def claim_legacy(self, token, data):
        account = self.session(token)
        fingerprint = data.get("fingerprint", "")
        if not isinstance(fingerprint, str) or not re.fullmatch(r"[a-f0-9]{64}", fingerprint):
            raise AccountError(400, "旧存档校验失败，请重新打开游戏。")
        with self.connect() as db:
            db.execute("INSERT OR IGNORE INTO legacy_claims VALUES(?,?,?)", (fingerprint, account["id"], time.time()))
            owner = db.execute("SELECT user_id FROM legacy_claims WHERE fingerprint=?", (fingerprint,)).fetchone()[0]
            if owner != account["id"]:
                raise AccountError(409, "这份旧进度已归属其他账号。你可以为当前账号创建新的角色。")
        return {"ok": True}


def make_server(path, port=8010):
    accounts = Accounts(path)

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass  # Do not log credentials, tokens or user-controlled bodies.

        def reply(self, status, value):
            body = json.dumps(value, ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def token(self):
            header = self.headers.get("Authorization", "")
            return header[7:] if header.startswith("Bearer ") else ""

        def do_GET(self):
            try:
                if self.path == "/api/v1/health":
                    self.reply(200, {"ok": True, "service": "xiuxian-accounts", "api_version": 1})
                elif self.path == "/api/v1/auth/session":
                    self.reply(200, {"ok": True, "account": accounts.session(self.token())})
                else:
                    self.reply(404, {"ok": False, "message": "接口不存在。"})
            except AccountError as exc:
                self.reply(exc.status, {"ok": False, "message": exc.message})

        def do_POST(self):
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if length < 1 or length > 16384:
                    raise AccountError(400, "请求格式错误。")
                data = json.loads(self.rfile.read(length))
                if not isinstance(data, dict):
                    raise AccountError(400, "请求格式错误。")
                if self.path == "/api/v1/auth/register":
                    result = accounts.register(data)
                elif self.path == "/api/v1/auth/login":
                    result = accounts.login(data, self.client_address[0])
                elif self.path == "/api/v1/auth/logout":
                    result = accounts.logout(self.token())
                elif self.path == "/api/v1/auth/claim-legacy":
                    result = accounts.claim_legacy(self.token(), data)
                else:
                    raise AccountError(404, "接口不存在。")
                self.reply(200, result)
            except AccountError as exc:
                self.reply(exc.status, {"ok": False, "message": exc.message})
            except (ValueError, UnicodeDecodeError):
                self.reply(400, {"ok": False, "message": "请求格式错误。"})
            except sqlite3.Error:
                self.reply(503, {"ok": False, "message": "账号数据暂时无法保存，请稍后重试。"})

    return ThreadingHTTPServer(("127.0.0.1", port), Handler)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=int(os.environ.get("XIUXIAN_ACCOUNT_PORT", "8010")))
    parser.add_argument("--db", default=os.environ.get("XIUXIAN_ACCOUNT_DB", str(Path(__file__).parent / "data" / "accounts.sqlite3")))
    args = parser.parse_args()
    make_server(args.db, args.port).serve_forever()
