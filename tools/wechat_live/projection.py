"""Account-scoped projection, derived from the existing tested local adapter.
Persistence and authentication are supplied by live_host.Store.
"""
from datetime import datetime, timedelta, timezone
import hashlib
import json
import threading
UTC8 = timezone(timedelta(hours=8))

class TaskProjection:
    def __init__(self, account, member, elder):
        self.account, self.member, self.elder = account, member, elder
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
                    self.tasks[task_id] = {'task_id': task_id, 'plan_id': plan['plan_id'], 'business_date': day, 'kind': plan.get('kind', 'medication'), 'title': '记录今日散步安排' if plan.get('kind') == 'walk' else '记录今日既有用药安排', 'status': 'pending', 'completion_method': '', 'completed_at': ''}
                    self.revision += 1

    def apply(self, event):
        with self.lock:
            if event.get('elder_id') != self.elder or event.get('family_share') is not True:
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
                if start > end or not incoming.get('plan_id') or incoming.get('kind') not in {'medication', 'walk'}:
                    raise ValueError('Incomplete plan')
                self.plans[incoming['plan_id']] = {'plan_id': incoming['plan_id'], 'start_date': start, 'end_date': end, 'active': True, 'kind': incoming['kind']}
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
            elif kind in {'medication_taken', 'walk_completed'}:
                observed = datetime.fromisoformat(event['occurred_at'])
                if observed.tzinfo is None:
                    raise ValueError('Timezone required')
                day = observed.astimezone(UTC8).date().isoformat()
                self.ensure_tasks(day)
                matches = [task for task in self.tasks.values() if task['business_date'] == day and task['kind'] == ('walk' if kind == 'walk_completed' else 'medication') and task['status'] == 'pending' and self.plans[task['plan_id']]['active']]
                if len(matches) == 1:
                    matches[0].update(status='completed', completion_method='wechat_self_report', completed_at=event['occurred_at'])
                    self.revision += 1
                else:
                    prior = [task for task in self.tasks.values() if task['business_date'] == day and task['kind'] == ('walk' if kind == 'walk_completed' else 'medication') and task['status'] == 'completed']
                    status = 'already_completed' if not matches and len(prior) == 1 else ('unmatched' if not matches else 'needs_clarification')
            else:
                raise ValueError('Unsupported event')
            self.events[event_id] = fingerprint
            return {'ok': True, 'event_id': event_id, 'status': status, 'revision': self.revision}

    def snapshot(self):
        with self.lock:
            day = self.day()
            self.ensure_tasks(day)
            return {'schema_version': 1, 'mode': 'live', 'account_id': self.account, 'revision': self.revision, 'server_time': datetime.now(UTC8).isoformat(), 'business_date': day, 'members': [{'game_member_id': self.member, 'tasks': [dict(task) for task in self.tasks.values() if task['business_date'] == day]}]}
