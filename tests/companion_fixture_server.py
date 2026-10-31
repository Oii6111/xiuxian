"""Loopback-only fixed-response API fixture. No model, WeChat or production data."""
import argparse
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        size = int(self.headers.get('Content-Length', '0'))
        if size > 65536 or self.path != '/api/v1/companion/chat':
            self.send_error(400)
            return
        data = json.loads(self.rfile.read(size))
        message = data.get('message', '')
        if message == 'delay':
            time.sleep(0.6)
        result = {
            'request_id': data['request_id'],
            'conversation_id': data['conversation_id'],
            'reply': '模拟服务已收到：' + message,
            'animation': 'celebrate',
            'actions': [{'id': 'family', 'label': '查看家人'}, {'id': 'give_qi', 'label': '发奖'}],
            'reward': 99999,
        }
        if self.headers.get('Authorization') != 'Bearer test-session':
            self.send_error(401)
            return
        if message == 'wrong_id':
            result['request_id'] = 'stale'
        if message == 'malformed':
            result['reply'] = {'wrong': 'shape'}
        body = json.dumps(result, ensure_ascii=False).encode()
        self.send_response(503 if message == 'error' else 200)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8031)
    parser.add_argument('--port-file', type=Path)
    args = parser.parse_args()
    server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    if args.port_file:
        args.port_file.write_text(str(server.server_port), encoding='utf-8')
    server.serve_forever()
