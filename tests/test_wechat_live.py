"""Live-host tests use isolated accounts and trusted channel callbacks, never real Weixin."""
from contextlib import closing
from pathlib import Path
import importlib
import json
import os
import sqlite3
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

import requests
from werkzeug.serving import make_server

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/wechat_live'))
from live_host import create_app, Store, AccountError


class LiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.data = Path(cls.temp.name)
        cls.secret = 'isolated-channel-service-token-0000000000'
        for key in list(os.environ):
            if key.startswith(('HEALTH_CHAT_', 'OPENCLAW_', 'LLM_', 'VISION_', 'MEDICAL_')) or key == 'OPENAI_API_KEY':
                os.environ.pop(key, None)
        cls.app = create_app(cls.data, cls.secret)
        cls.server = make_server('127.0.0.1', 0, cls.app, threaded=True)
        cls.url = f'http://127.0.0.1:{cls.server.server_port}'
        os.environ['HEALTH_EVENT_SINK_URL'] = cls.url + '/internal/wechat/events'
        cls.worker = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.worker.start()
        cls.client = cls.app.test_client()
        cls.store = cls.app.extensions['links']

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown(); cls.server.server_close(); cls.worker.join()
        cls.temp.cleanup()

    def setUp(self):
        import secrets
        self.username = 'guest_' + secrets.token_hex(3)
        response = self.client.post('/api/v1/auth/register', json={'username': self.username, 'display_name': '体验者', 'password': 'isolated-test-password'})
        self.assertEqual(response.status_code, 200)
        self.account, self.token = response.json['account']['id'], response.json['token']
        self.headers = {'Authorization': 'Bearer ' + self.token}
        self.internal = {'X-Wechat-Service-Token': self.secret}
        self.link = self.store.invite(self.account, 'self', '本人体验者')
        self.bot, self.sender = 'bot-' + self.username, 'sender-' + self.username

    def activate(self):
        return self.client.post('/internal/wechat/confirmed', headers=self.internal, json={'link_id': self.link, 'bot_id': self.bot, 'sender_id': self.sender, 'share_tasks': True})

    def inbound(self, text, mid):
        return self.client.post('/internal/wechat/inbound', headers=self.internal, json={'link_id': self.link, 'bot_id': self.bot, 'sender_id': self.sender, 'message_id': mid, 'text': text})

    def snapshot(self):
        return self.client.get('/api/v1/companion/state', headers=self.headers).json

    def test_walk_to_game_projection_without_simulated_web_input(self):
        self.assertEqual(self.snapshot()['members'], [])
        self.assertEqual(self.activate().status_code, 200)
        self.assertIn('没有已确认', self.inbound('今日任务', 'm0').json['reply'])
        self.assertEqual(self.inbound('我每天晚饭后散步', 'm1').status_code, 200)
        task = self.snapshot()['members'][0]['tasks'][0]
        self.assertEqual(task['status'], 'pending')
        self.inbound('我今天已经散步了', 'm2')
        completed = self.snapshot()['members'][0]['tasks'][0]
        self.assertEqual(completed['task_id'], task['task_id'])
        self.assertEqual(completed['status'], 'completed')
        self.assertEqual(completed['completion_method'], 'wechat_self_report')
        self.assertIn('已同步', self.inbound('我今天已经散步了', 'm3').json['reply'])
        self.assertEqual(len(self.snapshot()['members'][0]['tasks']), 1)
        restarted = Store(self.data / 'links.sqlite3')
        self.assertEqual(restarted.snapshot(self.account), self.snapshot())

    def test_scope_consent_replay_and_revocation(self):
        body = {'link_id': self.link, 'bot_id': self.bot, 'sender_id': self.sender}
        self.assertEqual(self.client.post('/internal/wechat/confirmed', headers=self.internal, json=body).status_code, 400)
        self.assertEqual(self.inbound('我每天晚饭后散步', 'unbound').status_code, 403)
        self.activate()
        first = self.inbound('我每天晚饭后散步', 'm1')
        before = self.snapshot()
        self.assertEqual(self.inbound('我每天晚饭后散步', 'm1').json, first.json)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.inbound('另一条消息', 'm1').status_code, 409)
        self.assertEqual(self.client.get('/api/v1/companion/state').status_code, 401)
        self.client.post('/api/v1/wechat/bindings/revoke', headers=self.headers, json={'game_member_id': 'self'})
        self.assertEqual(self.snapshot()['members'], [])
        self.assertEqual(self.inbound('我今天已经散步了', 'm2').status_code, 403)

    def test_two_accounts_cannot_share_sender_or_task_state(self):
        self.activate()
        other_link = self.store.invite('another-account', 'self', '另一位体验者')
        with self.assertRaises(AccountError):
            self.store.activate(other_link, 'another-bot', self.sender)
        self.store.activate(other_link, 'another-bot', 'another-sender-' + self.username)
        self.inbound('我每天晚饭后散步', 'm1')
        self.assertEqual(self.store.snapshot('another-account')['members'][0]['tasks'], [])

    def test_medication_existing_module_outbox_reaches_game(self):
        self.activate()
        self.inbound('我最近在吃联调用药', 'med1')
        self.inbound('每天一次', 'med2')
        self.assertEqual(self.snapshot()['members'][0]['tasks'], [])
        self.inbound('吃七天，饭后', 'med3')
        self.app.extensions['flush']()
        self.assertEqual(self.snapshot()['members'][0]['tasks'][0]['status'], 'pending')
        self.inbound('我还没吃过药', 'med4')
        self.assertEqual(self.snapshot()['members'][0]['tasks'][0]['status'], 'pending')
        self.inbound('我今天已经服药了', 'med5')
        self.inbound('确认', 'med6')
        self.app.extensions['flush']()
        result = self.snapshot()
        self.assertEqual(result['members'][0]['tasks'][0]['status'], 'completed')
        self.assertNotIn('联调用药', json.dumps(result, ensure_ascii=False))

    def test_logout_revokes_read_and_forged_gateway_fails(self):
        self.assertEqual(self.client.post('/internal/wechat/confirmed', json={}).status_code, 401)
        self.client.post('/api/v1/auth/logout', headers=self.headers, json={})
        self.assertEqual(self.client.get('/api/v1/companion/state', headers=self.headers).status_code, 401)

    def test_connection_question_and_vague_illness_do_not_fabricate_tasks(self):
        self.activate()
        self.assertIn('已经连接', self.inbound('你连接到游戏了吗', 'connection').json['reply'])
        self.assertIn('哪里不舒服', self.inbound('我生病了', 'illness').json['reply'])
        self.assertEqual(self.snapshot()['members'][0]['tasks'], [])
        self.inbound('我每天晚饭后都会散步三十分钟。', 'habit')
        self.assertEqual(self.snapshot()['members'][0]['tasks'][0]['status'], 'pending')
        self.inbound('我今天已经散步完了。', 'done')
        self.assertEqual(self.snapshot()['members'][0]['tasks'][0]['status'], 'completed')


if __name__ == '__main__':
    unittest.main(verbosity=2)
