"""No models or real WeChat. Contract, consent, missing data and retry tests."""
from pathlib import Path
import json
import os
import sqlite3
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/wechat_link_demo'))
from host import create_app, TaskProjection, ELDER

class ProjectionTests(unittest.TestCase):
    def plan(self, plan_id='plan-1'):
        return {'event_id': 'event-' + plan_id, 'elder_id': ELDER, 'family_share': True, 'event_type': 'care_plan_confirmed', 'occurred_at': '2026-11-01T12:00:00+08:00', 'plan': {'plan_id': plan_id, 'kind': 'medication', 'start_date': '2026-11-01', 'end_date': '2026-11-07'}}

    def projection(self):
        p = TaskProjection()
        p.day = lambda: '2026-11-01'
        return p

    def test_missing_plan_and_duplicate(self):
        p = self.projection()
        self.assertEqual(p.snapshot()['members'][0]['tasks'], [])
        p.apply(self.plan())
        task_id = p.snapshot()['members'][0]['tasks'][0]['task_id']
        self.assertEqual(p.apply(self.plan())['status'], 'duplicate')
        self.assertEqual(p.snapshot()['members'][0]['tasks'][0]['task_id'], task_id)

    def test_private_and_foreign_events(self):
        for field, value in [('family_share', False), ('elder_id', 'another-elder')]:
            event = self.plan()
            event[field] = value
            with self.assertRaises(ValueError):
                self.projection().apply(event)

    def test_ambiguous_completion_does_not_pick_a_task(self):
        p = self.projection()
        p.apply(self.plan())
        p.apply(self.plan('plan-2'))
        result = p.apply({'event_id': 'done', 'elder_id': ELDER, 'family_share': True, 'event_type': 'medication_taken', 'occurred_at': '2026-11-01T20:00:00+08:00'})
        self.assertEqual(result['status'], 'needs_clarification')
        self.assertTrue(all(t['status'] == 'pending' for t in p.tasks.values()))

    def test_ending_plan_cancels_pending(self):
        p = self.projection()
        p.apply(self.plan())
        p.apply({'event_id': 'end', 'elder_id': ELDER, 'family_share': True, 'event_type': 'care_plan_ended', 'occurred_at': '2026-11-01T20:00:00+08:00', 'plan': {'plan_id': 'plan-1'}})
        self.assertEqual(p.snapshot()['members'][0]['tasks'][0]['status'], 'cancelled')

class SidecarTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        base = ROOT / 'output/wechat-adapter-tests'
        base.mkdir(parents=True, exist_ok=True)
        cls.data = Path(tempfile.mkdtemp(dir=base)).resolve()
        assert cls.data.is_relative_to(base.resolve())
        cls.app, cls.projection, cls.flush, cls.keys = create_app(ROOT / 'tools/wechat_link_demo/sidecar', cls.data)
        cls.flush = staticmethod(cls.flush)
        cls.client = cls.app.test_client()
        cls.headers = {'X-Elder-Sidecar-Token': os.environ['ELDER_SIDECAR_TOKEN']}

    def setUp(self):
        os.environ.pop('HEALTH_EVENT_SINK_URL', None)

    def message(self, elder, text, share=True):
        response = self.client.post('/api/v1/elder/message', headers=self.headers, json={'elder_id': elder, 'sender_id': elder, 'text': text, 'message_id': 'message-' + text, 'consent': {'family_share': share}})
        self.assertEqual(response.status_code, 200)
        return response.get_json()

    def test_read_auth_and_no_models(self):
        self.assertEqual(self.client.get('/api/v1/companion/state').status_code, 401)
        self.assertEqual(self.client.get('/api/v1/companion/state', headers={'X-Companion-Read-Token': self.keys['read_token']}).status_code, 200)
        info = self.client.get('/api/v1/elder/health', headers=self.headers).get_json()
        self.assertFalse(info['vision_configured'])

    def test_incomplete_course_stays_pending_and_partial_answers_merge(self):
        self.message('partial', '我最近在吃联调用药')
        self.message('partial', '每天一次')
        with sqlite3.connect(self.data / 'elder-demo.sqlite3') as db:
            self.assertEqual(db.execute('SELECT status,duration_days FROM medication_courses WHERE elder_id=?', ('partial',)).fetchone(), ('pending_duration', None))
        self.message('partial', '吃七天')
        self.message('partial', '饭后')
        with sqlite3.connect(self.data / 'elder-demo.sqlite3') as db:
            self.assertEqual(db.execute('SELECT status,duration_days FROM medication_courses WHERE elder_id=?', ('partial',)).fetchone(), ('active', 7))
            payload = json.loads(db.execute("SELECT payload FROM game_link_outbox WHERE payload LIKE '%partial%' ORDER BY rowid DESC LIMIT 1").fetchone()[0])
            self.assertNotIn('联调用药', json.dumps(payload, ensure_ascii=False))

    def test_private_confirmed_record_is_not_forwarded(self):
        os.environ.pop('HEALTH_EVENT_SINK_URL', None)
        pending = self.message('private', '我今天已经服药了', False)
        result = self.client.post('/api/v1/elder/confirm', headers=self.headers, json={'event_id': pending['pending_event']['event_id'], 'decision': 'confirm'}).get_json()
        with sqlite3.connect(self.data / 'elder-demo.sqlite3') as db:
            self.assertIsNone(db.execute('SELECT event_id FROM game_link_outbox WHERE event_id=?', (result['event']['event_id'],)).fetchone())

    def test_failed_delivery_not_marked_synced_then_retries(self):
        os.environ['HEALTH_EVENT_SINK_URL'] = 'http://isolated.invalid/events'
        pending = self.message('retry', '我今天已经服药了')
        with patch('requests.post', return_value=SimpleNamespace(status_code=503)):
            result = self.client.post('/api/v1/elder/confirm', headers=self.headers, json={'event_id': pending['pending_event']['event_id'], 'decision': 'confirm'}).get_json()
        event_id = result['event']['event_id']
        with sqlite3.connect(self.data / 'elder-demo.sqlite3') as db:
            self.assertIsNone(db.execute('SELECT synced_at FROM health_events WHERE event_id=?', (event_id,)).fetchone()[0])
            self.assertEqual(db.execute('SELECT delivered FROM game_link_outbox WHERE event_id=?', (event_id,)).fetchone()[0], 0)
        def accepted(url, **kwargs):
            return SimpleNamespace(status_code=200, json=lambda: {'ok': True, 'event_id': kwargs['json']['event_id']})
        with patch('requests.post', side_effect=accepted):
            self.flush()
        with sqlite3.connect(self.data / 'elder-demo.sqlite3') as db:
            self.assertIsNotNone(db.execute('SELECT synced_at FROM health_events WHERE event_id=?', (event_id,)).fetchone()[0])

if __name__ == '__main__':
    unittest.main()
