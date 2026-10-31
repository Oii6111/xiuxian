"""Run the isolated, model-free WeChat-text -> Godot task demonstration."""
import argparse
import gc
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import webbrowser

from werkzeug.serving import make_server
from host import create_app

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--test', action='store_true')
    parser.add_argument('--screens', action='store_true')
    parser.add_argument('--open-browser', action='store_true')
    parser.add_argument('--godot')
    parser.add_argument('--work-dir')
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[2]
    base = Path(args.work_dir).resolve() if args.work_dir else (project / 'output/wechat-link-runs').resolve()
    base.mkdir(parents=True, exist_ok=True)
    run_dir = Path(tempfile.mkdtemp(prefix='session-', dir=base)).resolve()
    assert run_dir.is_relative_to(base)
    app, projection, flush, credentials = create_app(Path(__file__).parent / 'sidecar', run_dir)
    server = make_server('127.0.0.1', 0, app, threaded=True)
    address = f'http://127.0.0.1:{server.server_port}'
    os.environ['HEALTH_EVENT_SINK_URL'] = address + '/internal/demo/health-events'
    threading.Thread(target=server.serve_forever, daemon=True).start()
    stopping = threading.Event()
    def retries():
        while not stopping.wait(1):
            flush()
    threading.Thread(target=retries, daemon=True).start()
    godot = args.godot or os.environ.get('GODOT_BIN') or shutil.which('godot')
    if not godot and Path(r'F:\Godot_v4.7.2-stable_win64.exe').is_file():
        godot = r'F:\Godot_v4.7.2-stable_win64.exe'
    if not godot:
        raise SystemExit('Set GODOT_BIN or pass --godot with the Godot executable path.')
    env = os.environ.copy()
    for key in ['ELDER_SIDECAR_TOKEN', 'HEALTH_EVENT_SINK_TOKEN', 'HEALTH_EVENT_SINK_URL', 'XIUXIAN_COMPANION_API_URL', 'XIUXIAN_COMPANION_AUTH_ORIGIN']:
        env.pop(key, None)
    env['PYTHONDONTWRITEBYTECODE'] = '1'
    env['APPDATA'] = str(run_dir / 'appdata')
    env['XIUXIAN_COMPANION_TASK_URL'] = address + '/api/v1/companion/state'
    env['XIUXIAN_COMPANION_TASK_READ_TOKEN'] = credentials['read_token']
    env['XIUXIAN_ACCOUNT_URL'] = address
    command = [godot, '--path', str(project), '--log-file', str(run_dir / 'godot.log')]
    if args.test or args.screens:
        env['XIUXIAN_WECHAT_DEMO_INPUT_URL'] = address + '/demo/message'
        env['XIUXIAN_WECHAT_DEMO_INPUT_TOKEN'] = credentials['browser_token']
        command += ([] if args.screens else ['--headless']) + ['--script', 'res://tests/wechat_link_test.gd']
    command += ['--', '--preview', '--wechat-link-demo']
    if args.screens:
        command += ['--wechat-capture']
    print(json.dumps({'mode': 'local_text_integration', 'elder_text_page': address, 'logs': str(run_dir), 'model_calls': 'disabled', 'rewards': 'disabled'}, ensure_ascii=False), flush=True)
    if args.open_browser:
        webbrowser.open(address)
    result = None
    try:
        flags = getattr(subprocess, 'CREATE_NO_WINDOW', 0) if args.test or args.screens else 0
        result = subprocess.run(command, env=env, stdout=subprocess.PIPE if args.test or args.screens else None, stderr=subprocess.STDOUT if args.test or args.screens else None, encoding='utf-8', errors='replace', timeout=45 if args.test or args.screens else None, creationflags=flags)
        if result.stdout:
            (run_dir / 'stdout.log').write_text(result.stdout, encoding='utf-8')
        log_path = run_dir / 'godot.log'
        log = (log_path.read_text(encoding='utf-8', errors='replace') if log_path.exists() else '') + (result.stdout or '')
        lines = sorted(set(line for line in log.splitlines() if any(word in line for word in ['WECHAT LINK', 'SCRIPT ERROR:', 'ERROR:', 'CAPTURE '])))
        print(json.dumps({'exit': result.returncode, 'checks': lines, 'logs': str(run_dir)}, ensure_ascii=False), flush=True)
        return result.returncode or int('SCRIPT ERROR:' in log or '\nERROR:' in log)
    finally:
        stopping.set()
        server.shutdown()
        server.server_close()
        gc.collect()
        # Keep isolated logs and synthetic DB for inspectability; no player files used.

if __name__ == '__main__':
    raise SystemExit(main())
