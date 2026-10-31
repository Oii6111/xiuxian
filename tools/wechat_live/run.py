"""Start local live account/health service, Tencent transport and optionally Godot."""
import argparse
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import threading
import time

from werkzeug.serving import make_server
from live_host import ROOT, create_app


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data', default=str(ROOT / 'work/wechat-live'))
    parser.add_argument('--port', type=int, default=8010)
    parser.add_argument('--gateway-port', type=int, default=8020)
    parser.add_argument('--godot')
    parser.add_argument('--project', default=str(ROOT), help='Optional isolated complete game project')
    parser.add_argument('--experience', action='store_true', help='Use a separate generated test account and open the actual QR flow')
    parser.add_argument('--allow-models', action='store_true')
    args = parser.parse_args()
    if args.experience and not args.godot:
        parser.error('--experience requires --godot')
    data = Path(args.data).resolve()
    data.mkdir(parents=True, exist_ok=True)
    if not args.allow_models:
        for key in list(os.environ):
            if key.startswith(('HEALTH_CHAT_', 'OPENCLAW_', 'MEDICAL_', 'VISION_', 'LLM_', 'DEEPSEEK_', 'DASHSCOPE_')) or key == 'OPENAI_API_KEY':
                os.environ.pop(key, None)
        os.environ['HEALTH_CHAT_ENABLED'] = 'false'
    secret_path = data / 'service-token.txt'
    if not secret_path.exists():
        with secret_path.open('x', encoding='utf-8') as output:
            output.write(secrets.token_urlsafe(32))
    token = secret_path.read_text(encoding='utf-8').strip()
    account_url, gateway_url = f'http://127.0.0.1:{args.port}', f'http://127.0.0.1:{args.gateway_port}'
    app = create_app(data, token, gateway_url)
    os.environ['HEALTH_EVENT_SINK_URL'] = account_url + '/internal/wechat/events'
    server = make_server('127.0.0.1', args.port, app, threaded=True)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    env = os.environ.copy()
    env.update(WECHAT_LIVE_DATA=str(data), WECHAT_LIVE_SERVICE_TOKEN=token,
               WECHAT_LIVE_ACCOUNT_URL=account_url, WECHAT_LIVE_GATEWAY_PORT=str(args.gateway_port))
    node = shutil.which('node')
    if not node:
        raise SystemExit('Node.js 24 is required for Weixin transport.')
    with (data / 'gateway.log').open('a', encoding='utf-8') as log:
        gateway = subprocess.Popen([node, str(Path(__file__).with_name('gateway.mjs'))], env=env, stdout=log, stderr=log,
                                   creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        stopped = threading.Event()
        def retry():
            while not stopped.wait(3):
                try:
                    app.extensions['flush']()
                except Exception:
                    print('Event delivery retained for retry.', flush=True)
        threading.Thread(target=retry, daemon=True).start()
        game = None
        try:
            if args.godot:
                env.pop('WECHAT_LIVE_SERVICE_TOKEN', None)
                env.pop('HEALTH_EVENT_SINK_TOKEN', None)
                env.pop('HEALTH_EVENT_SINK_URL', None)
                env.update(XIUXIAN_ACCOUNT_URL=account_url, XIUXIAN_WECHAT_LINK_ENABLED='1', APPDATA=str(data / 'player-cache'))
                project = Path(args.project).resolve()
                command = [args.godot, '--path', str(project), '--log-file', str(data / 'live-game.log')]
                if args.experience:
                    credentials_path = data / 'experience-account.json'
                    if not credentials_path.exists():
                        credentials = {'username': 'showcase_' + secrets.token_hex(4), 'password': secrets.token_urlsafe(24), 'display_name': '微信联测', 'avatar': 'male'}
                        registered = app.extensions['accounts'].register(credentials)
                        app.extensions['accounts'].logout(registered['token'])
                        credentials_path.write_text(json.dumps(credentials, ensure_ascii=False), encoding='utf-8')
                    env['WECHAT_EXPERIENCE_CREDENTIALS'] = credentials_path.read_text(encoding='utf-8')
                    env['WECHAT_LIVE_CAPTURE_DIR'] = str(data)
                    (project / 'tests').mkdir(exist_ok=True)
                    shutil.copy2(ROOT / 'tests/wechat_live_experience.gd', project / 'tests/wechat_live_experience.gd')
                    command += ['--script', 'res://tests/wechat_live_experience.gd']
                game = subprocess.Popen(command, env=env)
            print(json.dumps({'account_service': account_url, 'wechat_gateway': gateway_url, 'player_mode': 'normal_login', 'data': str(data)}, ensure_ascii=False), flush=True)
            while game is None or game.poll() is None:
                if gateway.poll() is not None:
                    raise SystemExit('Weixin gateway stopped; inspect work/wechat-live/gateway.log')
                time.sleep(.5)
        except KeyboardInterrupt:
            pass
        finally:
            stopped.set()
            if game is not None and game.poll() is None:
                game.terminate()
                game.wait(timeout=10)
            gateway.terminate()
            gateway.wait(timeout=10)
            server.shutdown()
            server.server_close()


if __name__ == '__main__':
    main()
