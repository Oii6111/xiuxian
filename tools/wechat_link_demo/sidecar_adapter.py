"""Opt-in task-event adapter for the pinned elder sidecar; no model keys required.

The upstream module stays unchanged. This extension is installed explicitly by the
isolated demo host; a real sidecar deployment must review/install it separately.
"""
from contextlib import closing
from datetime import datetime, timezone
import hashlib
import json
import os
import re
import threading

from flask import has_request_context, request
import requests


def install(elder):
    if getattr(elder, '_game_link_installed', False):
        return elder._game_link_flush
    lock = threading.RLock()

    def connect():
        return elder._db()

    with closing(connect()) as db, db:
        db.executescript('''
        CREATE TABLE IF NOT EXISTS game_link_sources (
          course_id TEXT PRIMARY KEY, elder_id TEXT NOT NULL,
          source_message_id TEXT NOT NULL, share_allowed INTEGER NOT NULL,
          current_use_confirmed INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS game_link_outbox (
          event_id TEXT PRIMARY KEY, payload TEXT NOT NULL,
          delivered INTEGER NOT NULL DEFAULT 0, attempts INTEGER NOT NULL DEFAULT 0);
        ''')

    def incoming():
        return (request.get_json(silent=True) or {}) if has_request_context() else {}

    def flush():
        url = os.environ.get('HEALTH_EVENT_SINK_URL', '').strip()
        token = os.environ.get('HEALTH_EVENT_SINK_TOKEN', '').strip()
        if not url or not token:
            return 0
        delivered = 0
        with lock:
            with closing(connect()) as db:
                rows = db.execute('SELECT event_id,payload FROM game_link_outbox WHERE delivered=0 ORDER BY rowid LIMIT 20').fetchall()
            for row in rows:
                success = False
                try:
                    response = requests.post(url, json=json.loads(row['payload']), headers={'X-Health-Internal-Token': token}, timeout=3)
                    result = response.json() if response.status_code == 200 else {}
                    success = result.get('ok') is True and result.get('event_id') == row['event_id']
                except (requests.RequestException, ValueError):
                    pass
                with closing(connect()) as db, db:
                    db.execute('UPDATE game_link_outbox SET attempts=attempts+1,delivered=? WHERE event_id=?', (int(success), row['event_id']))
                    if success:
                        db.execute('UPDATE health_events SET synced_at=? WHERE event_id=?', (elder._now(), row['event_id']))
                        delivered += 1
        return delivered

    def enqueue(event):
        if event.get('family_share') is not True:
            return None
        # Only minimum game facts cross this boundary; no medication names,
        # measurements, raw conversation, pictures or model responses.
        kind = event.get('event_type')
        if kind not in {'care_plan_confirmed', 'care_plan_ended', 'medication_taken'}:
            return None
        clean = {key: event[key] for key in ['event_id', 'elder_id', 'event_type', 'family_share', 'occurred_at']}
        if kind.startswith('care_plan_'):
            clean['plan'] = event['plan']
        with closing(connect()) as db, db:
            db.execute('INSERT OR IGNORE INTO game_link_outbox(event_id,payload) VALUES(?,?)', (clean['event_id'], json.dumps(clean, ensure_ascii=False)))
        flush()
        with closing(connect()) as db:
            row = db.execute('SELECT delivered FROM game_link_outbox WHERE event_id=?', (clean['event_id'],)).fetchone()
        return 'synced' if row and row['delivered'] else None

    original_create = elder._create_course
    original_complete = elder._complete_course
    original_stop = elder._stop_active_course
    original_intent = elder._intent
    original_handle = elder.handle_message

    def create_course(elder_id, drug):
        course_id = original_create(elder_id, drug)
        payload = incoming()
        text = str(payload.get('text', '')).strip()
        current = bool(re.search(r'^我(?:最近|现在|目前|正在|一直|还)?(?:正在)?在吃', text))
        share = (payload.get('consent') or {}).get('family_share') is True
        message_id = str(payload.get('message_id', '')).strip()
        with closing(connect()) as db, db:
            db.execute('INSERT INTO game_link_sources VALUES(?,?,?,?,?)', (course_id, elder_id, message_id, int(share), int(current)))
        return course_id

    def complete_course(elder_id, course, answer):
        merged = {'days': answer.get('days') or course.get('duration_days'), 'freq': answer.get('freq') or course.get('times_per_day'), 'when': answer.get('when') or course.get('when_take')}
        missing = [name for key, name in [('days', '原来安排的天数'), ('freq', '每天的次数'), ('when', '原来安排的时间')] if not merged[key]]
        if missing:
            with closing(connect()) as db, db:
                db.execute('UPDATE medication_courses SET duration_days=?,times_per_day=?,when_take=?,updated_at=? WHERE course_id=?', (merged['days'], merged['freq'], merged['when'], elder._now(), course['course_id']))
            return '我先记住已经说清的部分。还需要您补充' + '、'.join(missing) + '，按您已有的安排告诉我就好。'
        reply = original_complete(elder_id, course, merged)
        with closing(connect()) as db:
            source = db.execute('SELECT * FROM game_link_sources WHERE course_id=?', (course['course_id'],)).fetchone()
            active = db.execute('SELECT start_date,end_date FROM medication_courses WHERE course_id=?', (course['course_id'],)).fetchone()
        payload = incoming()
        share_now = (payload.get('consent') or {}).get('family_share') is True
        if source and source['share_allowed'] and source['current_use_confirmed'] and source['source_message_id'] and payload.get('message_id') and share_now:
            # Opaque plan ID; the game never receives the drug name or dose.
            plan_id = 'plan_' + hashlib.sha256(course['course_id'].encode()).hexdigest()[:24]
            enqueue({'event_id': 'plan_confirmed_' + plan_id, 'elder_id': elder_id, 'event_type': 'care_plan_confirmed', 'family_share': True, 'occurred_at': elder._now(), 'plan': {'plan_id': plan_id, 'kind': 'medication', 'start_date': active['start_date'], 'end_date': active['end_date'], 'schedule_label': str(merged['when']), 'frequency_label': str(merged['freq'])}})
        return reply

    def stop_course(elder_id):
        with closing(connect()) as db:
            courses = db.execute("SELECT course_id FROM medication_courses WHERE elder_id=? AND status='active'", (elder_id,)).fetchall()
        result = original_stop(elder_id)
        payload = incoming()
        if (payload.get('consent') or {}).get('family_share') is True and payload.get('message_id'):
            for course in courses:
                plan_id = 'plan_' + hashlib.sha256(course['course_id'].encode()).hexdigest()[:24]
                enqueue({'event_id': 'plan_ended_' + plan_id, 'elder_id': elder_id, 'event_type': 'care_plan_ended', 'family_share': True, 'occurred_at': elder._now(), 'plan': {'plan_id': plan_id}})
        return result

    def intent(text, attachments):
        result = original_intent(text, attachments)
        if result == 'medication_taken' and re.search(r'没|未|没有|还没|是否|有没有|吗|[?？]', text):
            return 'chat'
        return result

    def handle(payload):
        # Finishing today's dose and ending a course are different statements.
        if str(payload.get('text', '')).strip() in {'药吃完了', '我药吃完了', '吃完药了'}:
            return {'mode': 'elder_only', 'intent': 'clarification', 'needs_confirmation': False, 'reply': '您是说今天这次已经吃过，还是原来的整个用药安排已经结束了？'}
        course = elder._pending_course(str(payload.get('elder_id', '')))
        answer = elder._parse_course_answer(str(payload.get('text', '')))
        if course and answer.get('when') and not answer.get('days') and not answer.get('freq'):
            reply = complete_course(str(payload['elder_id']), course, answer)
            elder._save_turn(str(payload['elder_id']), 'user', str(payload.get('text', '')))
            elder._save_turn(str(payload['elder_id']), 'assistant', reply)
            return {'mode': 'elder_only', 'intent': 'medication_course', 'needs_confirmation': False, 'reply': reply}
        return original_handle(payload)

    elder._create_course = create_course
    elder._complete_course = complete_course
    elder._stop_active_course = stop_course
    elder._intent = intent
    elder.handle_message = handle
    elder._send_event_sink = enqueue
    elder._game_link_installed = True
    elder._game_link_flush = flush
    return flush
