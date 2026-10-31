"""Real engine + real game UI with isolated trusted-channel fixture messages."""
import argparse
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import tempfile
import threading
from flask import request
from werkzeug.serving import make_server
from live_host import ROOT, create_app, AccountError


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--project', default=str(ROOT / 'work/playtest-project'))
    parser.add_argument('--godot', default=str(ROOT / 'work/runtime/Godot_v4.7.2-stable_win64.exe'))
    parser.add_argument('--screens', action='store_true')
    args = parser.parse_args()
    directory = ROOT / 'work/native-verification'
    directory.mkdir(parents=True, exist_ok=True)
    project = Path(args.project).resolve()
    (project / 'tests').mkdir(exist_ok=True)
    shutil.copy2(ROOT / 'tests/wechat_native_probe.gd', project / 'tests/wechat_native_probe.gd')
    secret, control = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
    for key in list(os.environ):
        if key.startswith(('HEALTH_CHAT_', 'OPENCLAW_', 'MEDICAL_', 'VISION_', 'LLM_')) or key == 'OPENAI_API_KEY':
            os.environ.pop(key, None)
    with tempfile.TemporaryDirectory(dir=directory) as temporary:
        app = create_app(Path(temporary), secret)
        server = make_server('127.0.0.1', 0, app, threaded=True)
        url = f'http://127.0.0.1:{server.server_port}'
        os.environ['HEALTH_EVENT_SINK_URL'] = url + '/internal/wechat/events'
        bindings = {}

        @app.post('/test/native/step')
        def step():
            import hmac
            if not hmac.compare_digest(request.headers.get('X-Test-Control', ''), control):
                raise AccountError(401, 'Test fixture authentication required')
            body = request.get_json()
            account, action = body['account_id'], body['step']
            store = app.extensions['links']
            if action == 'bind':
                link = store.invite(account, 'self', '联测本人')
                store.activate(link, 'test-bot-' + account, 'test-sender-' + account)
                bindings[account] = link
            elif action == 'revoke':
                with store.db() as db:
                    db.execute("UPDATE links SET status='revoked' WHERE id=?", (bindings[account],))
                    store.bump(db, account)
            else:
                text = '我每天晚饭后散步' if action == 'plan' else '我今天已经散步了'
                with app.test_client() as client:
                    result = client.post('/internal/wechat/inbound', headers={'X-Wechat-Service-Token': secret}, json={'link_id': bindings[account], 'bot_id': 'test-bot-' + account, 'sender_id': 'test-sender-' + account, 'message_id': action, 'text': text})
                    if result.status_code != 200:
                        raise AccountError(500, 'Fixture message failed')
            return {'ok': True}

        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        env = os.environ.copy()
        env.pop('HEALTH_EVENT_SINK_TOKEN', None)
        env.pop('HEALTH_EVENT_SINK_URL', None)
        env.update(APPDATA=str(Path(temporary) / 'appdata'), XIUXIAN_ACCOUNT_URL=url, XIUXIAN_WECHAT_LINK_ENABLED='1',
                   WECHAT_NATIVE_FIXTURE_URL=url + '/test/native/step', WECHAT_NATIVE_FIXTURE_TOKEN=control)
        if args.screens:
            env['WECHAT_NATIVE_SCREENSHOT'] = str(directory / 'completed-task.png')
        command = [args.godot, '--path', str(project), '--log-file', str(directory / 'godot.log'), '--script', 'res://tests/wechat_native_probe.gd']
        if not args.screens:
            command.insert(1, '--headless')
        try:
            result = subprocess.run(command, env=env, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=60,
                                    creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
            (directory / 'stdout.log').write_text(result.stdout + result.stderr, encoding='utf-8')
            print(result.stdout)
            print(result.stderr)
            return result.returncode
        finally:
            server.shutdown(); server.server_close(); worker.join()


if __name__ == '__main__':
    raise SystemExit(main())
