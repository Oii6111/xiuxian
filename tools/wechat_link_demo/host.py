"""Loopback-only integration harness. Synthetic identities; no C ledger or rewards."""
from datetime import datetime, timedelta, timezone
import hashlib
import hmac
import importlib
import json
import os
from pathlib import Path
import secrets
import sys
import threading

from flask import Flask, jsonify, request

from sidecar_adapter import install

UTC8 = timezone(timedelta(hours=8))
ACCOUNT = 'local-child'
MEMBER = 'wechat-demo-father'
ELDER = 'wechat-demo-elder'

class TaskProjection:
    def __init__(self):
        self.plans = {}
        self.tasks = {}
        self.events = {}
        self.revision = 0
        self.lock = threading.RLock()

    def day(self):
        return datetime.now(UTC8).date().isoformat()

    def ensure_tasks(self, day):
        for plan in self.plans.values():
            if plan['active'] and plan['start_date'] <= day <= plan['end_date']:
                task_id = 'task_' + hashlib.sha256((plan['plan_id'] + ':' + day).encode()).hexdigest()[:24]
                if task_id not in self.tasks:
                    self.tasks[task_id] = {'task_id': task_id, 'plan_id': plan['plan_id'], 'business_date': day, 'kind': 'medication', 'title': '记录今日既有用药安排', 'status': 'pending', 'completion_method': '', 'completed_at': ''}
                    self.revision += 1

    def apply(self, event):
        with self.lock:
            if event.get('elder_id') != ELDER or event.get('family_share') is not True:
                raise ValueError('Binding or sharing scope mismatch')
            event_id = str(event.get('event_id', ''))
            if not event_id or len(event_id) > 160:
                raise ValueError('Missing stable event ID')
            fingerprint = hashlib.sha256(json.dumps(event, sort_keys=True).encode()).hexdigest()
            if event_id in self.events:
                if self.events[event_id] != fingerprint:
                    raise ValueError('Event ID conflict')
                return {'ok': True, 'event_id': event_id, 'status': 'duplicate', 'revision': self.revision}
            kind = event.get('event_type')
            status = 'applied'
            if kind == 'care_plan_confirmed':
                incoming = event.get('plan') or {}
                start = datetime.fromisoformat(incoming['start_date']).date().isoformat()
                end = datetime.fromisoformat(incoming['end_date']).date().isoformat()
                if start > end or not incoming.get('plan_id') or incoming.get('kind') != 'medication':
                    raise ValueError('Incomplete plan')
                self.plans[incoming['plan_id']] = {'plan_id': incoming['plan_id'], 'start_date': start, 'end_date': end, 'active': True}
                self.revision += 1
                self.ensure_tasks(self.day())
            elif kind == 'care_plan_ended':
                plan_id = (event.get('plan') or {}).get('plan_id')
                if plan_id in self.plans:
                    self.plans[plan_id]['active'] = False
                    for task in self.tasks.values():
                        if task['plan_id'] == plan_id and task['status'] == 'pending':
                            task['status'] = 'cancelled'
                    self.revision += 1
            elif kind == 'medication_taken':
                observed = datetime.fromisoformat(event['occurred_at'])
                if observed.tzinfo is None:
                    raise ValueError('Timezone required')
                day = observed.astimezone(UTC8).date().isoformat()
                self.ensure_tasks(day)
                matches = [task for task in self.tasks.values() if task['business_date'] == day and task['status'] == 'pending' and self.plans[task['plan_id']]['active']]
                if len(matches) == 1:
                    matches[0].update(status='completed', completion_method='wechat_self_report', completed_at=event['occurred_at'])
                    self.revision += 1
                else:
                    status = 'unmatched' if not matches else 'needs_clarification'
            else:
                raise ValueError('Unsupported event')
            self.events[event_id] = fingerprint
            return {'ok': True, 'event_id': event_id, 'status': status, 'revision': self.revision}

    def snapshot(self):
        with self.lock:
            day = self.day()
            self.ensure_tasks(day)
            return {'schema_version': 1, 'mode': 'local_demo', 'account_id': ACCOUNT, 'revision': self.revision, 'server_time': datetime.now(UTC8).isoformat(), 'business_date': day, 'members': [{'game_member_id': MEMBER, 'tasks': [dict(task) for task in self.tasks.values() if task['business_date'] == day]}]}

def create_app(source_dir: Path, data_dir: Path):
    # Deliberately disable all external models and channel operations in this harness.
    for name in list(os.environ):
        if name.startswith(('HEALTH_CHAT_', 'MEDICAL_', 'VISION_', 'LLM_', 'OPENCLAW_', 'DEEPSEEK_', 'DASHSCOPE_', 'HEALTH_EVENT_SINK_')) or name == 'OPENAI_API_KEY':
            os.environ.pop(name, None)
    data_dir.mkdir(parents=True, exist_ok=True)
    os.environ['ELDER_DB_PATH'] = str(data_dir / 'elder-demo.sqlite3')
    os.environ['ELDER_SIDECAR_TOKEN'] = secrets.token_hex(32)
    os.environ['HEALTH_CHAT_ENABLED'] = 'false'
    os.environ['HEALTH_EVENT_SINK_TOKEN'] = secrets.token_hex(32)
    sys.path.insert(0, str(source_dir))
    elder = importlib.import_module('elder_assistant')
    app = Flask('wechat-task-local-demo', static_folder=None)
    app.config['MAX_CONTENT_LENGTH'] = 65536
    elder.register_elder_assistant_routes(app)
    flush = install(elder)
    projection = TaskProjection()
    read_token = secrets.token_hex(32)
    browser_token = secrets.token_hex(32)

    @app.post('/internal/demo/health-events')
    def accept_event():
        if not hmac.compare_digest(request.headers.get('X-Health-Internal-Token', ''), os.environ['HEALTH_EVENT_SINK_TOKEN']):
            return jsonify(ok=False), 401
        try:
            return jsonify(projection.apply(request.get_json(silent=True) or {}))
        except (ValueError, KeyError, TypeError):
            return jsonify(ok=False, message='Invalid task event'), 400

    @app.get('/api/v1/companion/state')
    def state():
        if not hmac.compare_digest(request.headers.get('X-Companion-Read-Token', ''), read_token):
            return jsonify(ok=False), 401
        return jsonify(projection.snapshot())

    @app.get('/')
    def page():
        # Synthetic local demo UI. This is a substitute transport, not a WeChat login.
        return '''<!doctype html><meta charset="utf-8"><title>老人文字入口 · 本地联调</title>
<style>body{font:20px system-ui;max-width:780px;margin:40px auto;background:#faf3df;color:#493b2c}input{font:inherit;width:75%;padding:12px}button{font:inherit;padding:12px}p{white-space:pre-wrap}label{display:block;margin:18px 0}#log{min-height:260px}</style>
<h1>老人文字入口 · 本地联调</h1><p>仅使用虚构记录。此页面模拟微信文字传入，不连接真实微信，不调用大模型，不发放奖励。</p>
<p>可依次试说：我最近在吃联调用药 → 吃七天，每天一次，饭后 → 我今天已经服药了 → 确认</p>
<label><input id="share" type="checkbox" style="width:auto">同意将本次虚构安排和完成记录共享到游戏</label>
<div id="log"></div><form id="form"><input id="text" placeholder="在这里输入文字" maxlength="600"><button>发送</button></form>
<script>const key=TOKEN;form.onsubmit=async e=>{e.preventDefault();const text=document.getElementById('text');const value=text.value.trim();if(!value)return;const p=document.createElement('p');p.textContent='我：'+value;log.appendChild(p);text.value='';const r=await fetch('/demo/message',{method:'POST',headers:{'Content-Type':'application/json','X-Demo-Token':key},body:JSON.stringify({text:value,share:share.checked,message_id:crypto.randomUUID()})});const data=await r.json();const a=document.createElement('p');a.textContent='助手：'+(data.reply||data.message||'请求失败');log.appendChild(a);};</script>'''.replace('TOKEN', json.dumps(browser_token))

    @app.post('/demo/message')
    def demo_message():
        if not hmac.compare_digest(request.headers.get('X-Demo-Token', ''), browser_token):
            return jsonify(message='Invalid demo session'), 401
        payload = request.get_json(silent=True) or {}
        with app.test_client() as internal:
            response = internal.post('/api/v1/elder/message', headers={'X-Elder-Sidecar-Token': os.environ['ELDER_SIDECAR_TOKEN']}, json={'elder_id': ELDER, 'sender_id': 'demo-sender', 'channel': 'openclaw-weixin', 'message_id': str(payload.get('message_id', '')), 'text': str(payload.get('text', ''))[:600], 'attachments': [], 'consent': {'family_share': payload.get('share') is True}})
            return jsonify(response.get_json()), response.status_code

    return app, projection, flush, {'read_token': read_token, 'browser_token': browser_token}
