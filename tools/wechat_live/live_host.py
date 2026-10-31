"""Local live demo: existing game accounts, explicit Weixin binding and shared tasks."""
from contextlib import contextmanager, closing
from datetime import datetime, timezone
import hashlib
import hmac
import importlib
import json
import os
from pathlib import Path
import re
import secrets
import sqlite3
import sys
import threading
import time

from flask import Flask, jsonify, request
import requests

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'server/account'))
sys.path.insert(0, str(ROOT / 'tools/wechat_link_demo'))
from server import Accounts, AccountError
from sidecar_adapter import install
from projection import TaskProjection, UTC8


class Store:
    def __init__(self, path):
        self.path = Path(path)
        self.lock = threading.RLock()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.db() as db:
            db.executescript('''
                CREATE TABLE IF NOT EXISTS links(id TEXT PRIMARY KEY, account_id TEXT, member_id TEXT,
                    label TEXT, elder_id TEXT UNIQUE, status TEXT, bot_id TEXT, sender_id TEXT,
                    expires_at REAL, projection TEXT);
                CREATE UNIQUE INDEX IF NOT EXISTS member_active ON links(account_id,member_id) WHERE status='active';
                CREATE UNIQUE INDEX IF NOT EXISTS sender_active ON links(sender_id) WHERE status='active';
                CREATE TABLE IF NOT EXISTS versions(account_id TEXT PRIMARY KEY, revision INTEGER NOT NULL DEFAULT 0);
                CREATE TABLE IF NOT EXISTS messages(link_id TEXT, message_id TEXT, fingerprint TEXT, reply TEXT,
                    PRIMARY KEY(link_id,message_id));
            ''')

    @contextmanager
    def db(self):
        with self.lock, closing(sqlite3.connect(self.path, timeout=10)) as db, db:
            db.row_factory = sqlite3.Row
            yield db

    @staticmethod
    def bump(db, account):
        db.execute('INSERT INTO versions VALUES(?,1) ON CONFLICT(account_id) DO UPDATE SET revision=revision+1', (account,))

    @staticmethod
    def projection(row):
        p = TaskProjection(row['account_id'], row['member_id'], row['elder_id'])
        if row['projection']:
            value = json.loads(row['projection'])
            for key in ('plans', 'tasks', 'events', 'revision'):
                setattr(p, key, value[key])
        return p

    @staticmethod
    def save(db, row, p):
        value = json.dumps({key: getattr(p, key) for key in ('plans', 'tasks', 'events', 'revision')}, ensure_ascii=False)
        if row['projection'] != value:
            db.execute('UPDATE links SET projection=? WHERE id=?', (value, row['id']))
            Store.bump(db, row['account_id'])

    def invite(self, account, member, label):
        if not isinstance(member, str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,80}', member):
            raise AccountError(400, '请选择一个有效的游戏角色。')
        with self.db() as db:
            if db.execute("SELECT 1 FROM links WHERE account_id=? AND member_id=? AND status='active'", (account, member)).fetchone():
                raise AccountError(409, '当前角色已连接微信，请先断开原连接。')
            if db.execute("SELECT count(*) FROM links WHERE account_id=? AND status='active'", (account,)).fetchone()[0] >= 3:
                raise AccountError(409, '每个账号最多连接本人和两位家人。')
            db.execute("UPDATE links SET status='expired' WHERE account_id=? AND member_id=? AND status='pending'", (account, member))
            link_id = secrets.token_hex(24)
            db.execute('INSERT INTO links VALUES(?,?,?,?,?,?,?,?,?,?)', (link_id, account, member, str(label)[:24], 'wx_' + secrets.token_hex(16), 'pending', '', '', time.time() + 600, ''))
            return link_id

    def activate(self, link_id, bot_id, sender_id):
        with self.db() as db:
            row = db.execute('SELECT * FROM links WHERE id=?', (link_id,)).fetchone()
            if not row or row['expires_at'] < time.time() or row['status'] not in ('pending', 'active'):
                raise AccountError(409, '邀请已失效，请从游戏重新连接。')
            if row['status'] == 'active':
                if row['bot_id'] == bot_id and row['sender_id'] == sender_id:
                    return
                raise AccountError(409, '此邀请已连接其他微信。')
            try:
                db.execute("UPDATE links SET status='active',bot_id=?,sender_id=? WHERE id=?", (bot_id, sender_id, link_id))
            except sqlite3.IntegrityError:
                raise AccountError(409, '这个微信或游戏角色已有连接，请先解除原连接。')
            self.bump(db, row['account_id'])

    def active(self, link_id, bot_id, sender_id):
        with self.db() as db:
            row = db.execute("SELECT * FROM links WHERE id=? AND status='active' AND bot_id=? AND sender_id=?", (link_id, bot_id, sender_id)).fetchone()
            if not row:
                raise AccountError(403, '连接已断开或身份不匹配。')
            return dict(row)

    def apply(self, event):
        with self.db() as db:
            row = db.execute("SELECT * FROM links WHERE elder_id=? AND status='active'", (event.get('elder_id'),)).fetchone()
            if not row:
                raise AccountError(403, '没有对应的有效共享连接。')
            if event.get('event_type') == 'care_plan_confirmed' and event.get('plan', {}).get('kind') == 'medication':
                if event['plan'].get('frequency_label') not in ('1次/天', '一次/天'):
                    raise AccountError(422, '多次用药需要精确时段，目前不自动完成整日计划。')
            p = self.projection(row)
            result = p.apply(event)
            self.save(db, row, p)
            return result

    def snapshot(self, account):
        members = []
        with self.db() as db:
            for row in db.execute("SELECT * FROM links WHERE account_id=? AND status='active' ORDER BY member_id", (account,)).fetchall():
                p = self.projection(row)
                members.extend(p.snapshot()['members'])
                self.save(db, row, p)
            revision = db.execute('SELECT revision FROM versions WHERE account_id=?', (account,)).fetchone()
            return {'schema_version': 1, 'mode': 'live', 'account_id': account, 'revision': revision[0] if revision else 0,
                    'business_date': datetime.now(UTC8).date().isoformat(), 'members': members}


def create_app(data, service_token, gateway_url='http://127.0.0.1:8020', source=None):
    data = Path(data)
    accounts = Accounts(data / 'accounts.sqlite3')
    store = Store(data / 'links.sqlite3')
    source = source or ROOT / 'tools/wechat_link_demo/sidecar'
    os.environ['ELDER_DB_PATH'] = str(data / 'health.sqlite3')
    os.environ['HEALTH_EVENT_SINK_TOKEN'] = service_token
    sys.path.insert(0, str(source))
    elder = importlib.import_module('elder_assistant')
    class ClosingConnection(sqlite3.Connection):
        def __exit__(self, *args):
            try:
                return super().__exit__(*args)
            finally:
                self.close()
    def connect():
        conn = sqlite3.connect(elder.DB_PATH, timeout=10, factory=ClosingConnection)
        conn.row_factory = sqlite3.Row
        return conn
    elder._db = connect
    elder.init_db()
    flush = install(elder)
    app = Flask('wechat-live-demo', static_folder=None)
    app.config['MAX_CONTENT_LENGTH'] = 65536
    app.extensions.update(accounts=accounts, links=store, flush=flush)
    message_lock = threading.Lock()

    def token():
        value = request.headers.get('Authorization', '')
        return value[7:] if value.startswith('Bearer ') else request.headers.get('X-Companion-Read-Token', '')
    def account():
        return accounts.session(token())['id']
    def internal():
        if not hmac.compare_digest(request.headers.get('X-Wechat-Service-Token', '').encode(), service_token.encode()):
            raise AccountError(401, '需要内部服务凭证。')

    @app.errorhandler(AccountError)
    def problem(exc):
        return jsonify(ok=False, message=exc.message), exc.status
    @app.after_request
    def private(response):
        response.headers['Cache-Control'] = 'no-store'
        return response
    @app.get('/api/v1/health')
    def health():
        return {'ok': True, 'service': 'xiuxian-accounts', 'api_version': 1, 'wechat_link': True}
    @app.get('/api/v1/auth/session')
    def session():
        return {'ok': True, 'account': accounts.session(token())}
    @app.post('/api/v1/auth/<action>')
    def authentication(action):
        body = request.get_json(silent=True)
        if not isinstance(body, dict):
            raise AccountError(400, '需要JSON对象。')
        if action == 'register':
            return accounts.register(body)
        if action == 'login':
            return accounts.login(body, request.remote_addr or 'local')
        if action == 'logout':
            return accounts.logout(token())
        if action == 'claim-legacy':
            return accounts.claim_legacy(token(), body)
        raise AccountError(404, '接口不存在。')

    @app.post('/api/v1/wechat/invitations')
    def invite():
        owner = account()
        body = request.get_json(silent=True) or {}
        link_id = store.invite(owner, body.get('game_member_id'), body.get('label', '当前角色'))
        try:
            result = requests.post(gateway_url + '/internal/login', headers={'X-Wechat-Service-Token': service_token},
                                   json={'link_id': link_id, 'label': str(body.get('label', '当前角色'))[:24]}, timeout=20)
            result.raise_for_status()
            return {'ok': True, 'login_url': result.json()['login_url']}
        except (requests.RequestException, ValueError, KeyError):
            raise AccountError(503, '微信登录服务未连接，请启动现场联动服务后重试。')

    @app.get('/api/v1/wechat/bindings')
    def links():
        owner = account()
        with store.db() as db:
            rows = db.execute("SELECT id,member_id,label,status FROM links WHERE account_id=? AND status='active'", (owner,)).fetchall()
        channels = {}
        try:
            result = requests.post(gateway_url + '/internal/status', headers={'X-Wechat-Service-Token': service_token}, json={}, timeout=2)
            if result.status_code == 200:
                channels = {r['link_id']: r['status'] for r in result.json().get('channels', [])}
        except (requests.RequestException, ValueError, KeyError):
            pass
        return {'ok': True, 'bindings': [{**dict(row), 'channel_status': channels.get(row['id'], 'offline')} for row in rows]}

    @app.post('/api/v1/wechat/bindings/revoke')
    def revoke():
        owner = account()
        body = request.get_json(silent=True) or {}
        with store.db() as db:
            db.execute("UPDATE links SET status='revoked' WHERE account_id=? AND member_id=? AND status='active'", (owner, body.get('game_member_id')))
            store.bump(db, owner)
        return {'ok': True}

    @app.get('/api/v1/companion/state')
    def state():
        return store.snapshot(account())

    @app.post('/internal/wechat/confirmed')
    def confirmed():
        internal()
        body = request.get_json(silent=True) or {}
        if body.get('share_tasks') is not True or not all(isinstance(body.get(k), str) and body[k] for k in ('link_id', 'bot_id', 'sender_id')):
            raise AccountError(400, '扫码者需要确认角色及任务共享。')
        store.activate(body['link_id'], body['bot_id'], body['sender_id'])
        return {'ok': True}

    @app.post('/internal/wechat/events')
    def event():
        if not hmac.compare_digest(request.headers.get('X-Health-Internal-Token', '').encode(), service_token.encode()):
            raise AccountError(401, '需要内部服务凭证。')
        try:
            return store.apply(request.get_json(silent=True) or {})
        except (ValueError, KeyError, TypeError):
            raise AccountError(400, '任务事件格式不正确。')

    @app.post('/internal/wechat/inbound')
    def inbound():
        internal()
        body = request.get_json(silent=True) or {}
        row = store.active(body.get('link_id'), body.get('bot_id'), body.get('sender_id'))
        text, mid = body.get('text', ''), body.get('message_id')
        if not isinstance(mid, str) or not 1 <= len(mid) <= 160 or not isinstance(text, str) or len(text) > 4000:
            raise AccountError(400, '消息内容或稳定编号不正确。')
        fingerprint = hashlib.sha256(json.dumps(body, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
        with message_lock:
            with store.db() as db:
                old = db.execute('SELECT * FROM messages WHERE link_id=? AND message_id=?', (row['id'], mid)).fetchone()
                if old:
                    if old['fingerprint'] != fingerprint or not old['reply']:
                        raise AccountError(409, '消息存在冲突或未完成处理，需要检查后恢复。')
                    return {'ok': True, 'reply': old['reply']}
                db.execute('INSERT INTO messages VALUES(?,?,?,?)', (row['id'], mid, fingerprint, ''))
            now = datetime.now(timezone.utc).isoformat()
            event = {'event_id': 'wx_' + hashlib.sha256((row['id'] + ':' + mid).encode()).hexdigest(), 'elder_id': row['elder_id'], 'family_share': True, 'occurred_at': now}
            if re.search(r'连接.*(?:游戏|灵宠)|(?:游戏|灵宠).*(?:连接|联动)|连接.*成功', text):
                reply = '已经连接到对应的游戏角色了。您确认的日常安排和完成反馈会同步给灵宠。可以先问我“今日任务”，也可以告诉我原来就有的生活安排。'
            elif re.fullmatch(r'我(?:现在|目前|最近)?(?:每天|每日|天天)(?:晚饭后|饭后|吃完晚饭后)(?:都|会|都会|要|出去|去|坚持)*散步(?:[一二两三四五六七八九十\d]+分钟)?[。！! ]*', text):
                event.update(event_type='care_plan_confirmed', plan={'plan_id': 'walk_' + row['id'], 'kind': 'walk', 'start_date': datetime.now(UTC8).date().isoformat(), 'end_date': '9999-12-31'})
                store.apply(event)
                reply = '已记下您每天饭后散步的安排，游戏中的对应角色会同步看到。'
            elif re.fullmatch(r'我今天(?:已经|已)?(?:出去|去)?散步(?:完成了|完成|完了|完|了)[。！! ]*', text):
                event.update(event_type='walk_completed')
                result = store.apply(event)
                reply = '今天的散步完成记录已同步。' if result['status'] in ('applied', 'already_completed') else '还没有匹配到今天的散步安排，请先说清已有的安排。'
            elif text.strip() in ('今日任务', '今天的任务', '今日安排'):
                tasks = store.snapshot(row['account_id'])['members']
                items = next((p['tasks'] for p in tasks if p['game_member_id'] == row['member_id']), [])
                reply = '今天的安排：\n' + '\n'.join(t['title'] + ('：已反馈完成' if t['status'] == 'completed' else '：待反馈') for t in items) if items else '目前没有已确认的安排。您可以告诉我已有的日常安排，例如“我每天晚饭后散步”。'
            elif re.fullmatch(r'我(?:最近|现在|今天)?(?:生病了|身体不舒服|不舒服)[。！! ]*', text):
                reply = '听起来您不太舒服。方便说说哪里不舒服、从什么时候开始的吗？我先了解清楚。'
            else:
                payload = {'elder_id': row['elder_id'], 'sender_id': row['sender_id'], 'channel': 'openclaw-weixin', 'message_id': mid, 'text': text, 'attachments': [], 'consent': {'family_share': True}}
                with app.test_request_context(json=payload):
                    reply = str(elder.handle_message(payload).get('reply', '已收到您的消息。'))[:2000]
            with store.db() as db:
                db.execute('UPDATE messages SET reply=? WHERE link_id=? AND message_id=?', (reply, row['id'], mid))
            return {'ok': True, 'reply': reply}

    @app.post('/internal/wechat/check')
    def check_binding():
        internal()
        body = request.get_json(silent=True) or {}
        store.active(body.get('link_id'), body.get('bot_id'), body.get('sender_id'))
        return {'ok': True}

    return app
