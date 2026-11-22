"""Verify bounded native shutdown after Go accepts a delayed leave request."""
import argparse
import json
import os
import pathlib
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

import requests
from private_desktop import run

ROOT = pathlib.Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--endpoint', default='http://127.0.0.1:18280')
parser.add_argument('--client', type=pathlib.Path)
args = parser.parse_args()
endpoint = urlsplit(args.endpoint)
assert endpoint.scheme == 'http' and endpoint.hostname == '127.0.0.1' and endpoint.port and endpoint.path in ['', '/']
upstream = args.endpoint.rstrip('/')
health = requests.get(upstream + '/health', timeout=3)
health.raise_for_status()
assert health.json()['edition'] == 'hd'
out = ROOT / '.tools/qa' / ('close-recovery-' + secrets.token_hex(4))
out.mkdir(parents=True)
os.environ['LOCALAPPDATA'] = str(out / 'profile')
os.environ['BCHD_VAULT_ROOT'] = str(out / 'vault')
leave = {}


class Relay(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        self.proxy()

    def do_POST(self):
        self.proxy()

    def proxy(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', 0))) or None
        headers = {key: self.headers[key] for key in ['Authorization', 'Content-Type', 'If-None-Match'] if key in self.headers}
        response = requests.request(self.command, upstream + self.path, data=body, headers=headers, timeout=8)
        if self.path == '/api/command' and body and json.loads(body).get('action') == 'leave':
            response.raise_for_status()
            leave.update(at=time.monotonic(), room_released=response.json().get('room') is None)
            time.sleep(5)
        try:
            self.send_response(response.status_code)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(response.content)))
            if response.headers.get('ETag'):
                self.send_header('ETag', response.headers['ETag'])
            self.end_headers()
            self.wfile.write(response.content)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass


if args.client:
    client = args.client.resolve()
    assert client.is_relative_to(ROOT)
    executable = client / 'Game.exe'
else:
    executable = next(p for p in (ROOT / '.tools/godot').glob('*.exe') if not p.name.endswith('console.exe'))
command = [executable, '--audio-driver', 'Dummy']
if not args.client:
    command += ['--path', ROOT / '源码/client']
with ThreadingHTTPServer(('127.0.0.1', 0), Relay) as server:
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    command += ['--', '--qa', '--qa-endpoint=http://127.0.0.1:' + str(server.server_port),
                '--qa-scene=room', '--qa-wait=0.1', '--qa-user=qa_close' + secrets.token_hex(4)]
    try:
        result = run(command, out / 'client.log', 35)
        finished = time.monotonic()
    finally:
        server.shutdown()
        thread.join()
log = (out / 'client.log').read_text('utf8', errors='replace')
assert result['exit_code'] == 0 and 'ERROR:' not in log, log[-4000:]
assert leave.get('room_released'), 'Go did not release the room'
elapsed = finished - leave['at']
assert 0 <= elapsed < 2.5, ('Shutdown waited for the blocked original reply', elapsed)
report = dict(result, passed=True, shutdown_seconds_after_leave_request=round(elapsed, 3),
              delay_seconds=5, server_released_room=True, evidence=str(out), release=bool(args.client))
(out / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
(ROOT / '.tools/qa/close-recovery-acceptance.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
print(json.dumps(report, ensure_ascii=False))
