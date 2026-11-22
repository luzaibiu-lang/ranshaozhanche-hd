"""Run the actual battle client on a silent desktop with delayed battle replies."""
import argparse
import json
import pathlib
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

import requests

from private_desktop import run

ROOT = pathlib.Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--endpoint', default='http://127.0.0.1:18280')
    parser.add_argument('--client', type=pathlib.Path)
    args = parser.parse_args()
    endpoint = urlsplit(args.endpoint)
    if (endpoint.scheme != 'http' or endpoint.hostname != '127.0.0.1' or
            endpoint.path not in ['', '/'] or endpoint.port is None):
        parser.error('Input recovery QA requires a local Go test service')
    upstream = args.endpoint.rstrip('/')
    health = requests.get(upstream + '/health', timeout=3).json()
    assert health.get('edition') == 'hd', health

    lock = threading.Lock()
    records = []
    armed = False
    fault_mode = 'retry'
    lost_sequence = None
    player_token = None
    discovery_time = time.monotonic()
    fault_routes = {
        '/qa/drop-move-ack': 'retry',
        '/qa/late-move-error': 'late_error',
        '/qa/late-fire-reply': 'fire_reply',
        '/qa/late-item-reply': 'item_reply',
    }

    class Relay(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def send_payload(self, status, body, etag=None):
            try:
                self.send_response(status)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(body)))
                if etag:
                    self.send_header('ETag', etag)
                self.end_headers()
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
                pass

        def do_GET(self):
            if self.path in fault_routes:
                nonlocal armed, player_token, fault_mode
                with lock:
                    armed = True
                    fault_mode = fault_routes[self.path]
                    player_token = self.headers.get('Authorization')
                self.send_payload(200, b'{"ok":true}')
                return
            self.proxy()

        def do_POST(self):
            self.proxy()

        def proxy(self):
            nonlocal armed, lost_sequence
            body = self.rfile.read(int(self.headers.get('Content-Length', 0))) or None
            action = json.loads(body) if self.path == '/api/command' and body else {}
            headers = {key: self.headers[key] for key in
                       ['Authorization', 'Content-Type', 'If-None-Match'] if key in self.headers}
            with lock:
                is_player = headers.get('Authorization') == player_token and player_token is not None
                suppress_poll_ack = is_player and lost_sequence is not None and self.path == '/api/state'
            if suppress_poll_ack:
                # Keep the previous snapshot until the retry or the next action.
                # This tests recovery when polling cannot supply the missing acknowledgement.
                with lock:
                    records.append({'action': 'poll_without_ack', 'elapsed': time.monotonic() - discovery_time})
                self.send_payload(304, b'')
                return
            response = requests.request(self.command, upstream + self.path, data=body, headers=headers, timeout=5)
            drop = False
            late_error = False
            late_fire = False
            late_item = False
            if self.path in ['/api/register', '/api/login']:
                with lock:
                    records.append({'action': self.path, 'status': response.status_code})
            if is_player and action.get('action') in ['move', 'fire', 'pass', 'item']:
                with lock:
                    record = {key: action.get(key) for key in ['action', 'generation', 'move_sequence', 'distance', 'weapon']}
                    record['status'] = response.status_code
                    record['elapsed'] = time.monotonic() - discovery_time
                    if action['action'] == 'move' and response.ok:
                        state = response.json()
                        actor = next(u for u in state['room']['battle']['units'] if u['player'] == state['profile']['id'])
                        record.update({key: actor.get(key) for key in ['x', 'sp', 'move_spent']})
                        if armed and fault_mode in ['retry', 'late_error']:
                            armed = False
                            drop = True
                            if fault_mode == 'retry':
                                lost_sequence = action['move_sequence']
                                record['dropped'] = True
                            else:
                                late_error = True
                                record['late_error'] = True
                        elif lost_sequence == action.get('move_sequence'):
                            lost_sequence = None
                    elif action['action'] in ['fire', 'pass']:
                        lost_sequence = None
                        if action['action'] == 'fire' and armed and fault_mode == 'fire_reply':
                            armed = False
                            late_fire = True
                            record['late_fire_reply'] = True
                    elif action['action'] == 'item':
                        record['slot'] = action.get('slot')
                        if response.ok:
                            record['inventory'] = response.json()['profile']['inventory']
                        if response.ok and armed and fault_mode == 'item_reply':
                            armed = False
                            late_item = True
                    records.append(record)
            if late_item:
                time.sleep(1.1)
                self.send_payload(500, b'{"error":"QA late item reply after consumption"}')
                with lock:
                    records.append({'action': 'late_item_reply', 'status': 500})
                return
            if late_fire:
                time.sleep(6.0)
                self.send_payload(500, b'{"error":"QA late fire reply after accepted shot"}')
                return
            if drop:
                # Exceed the client movement timeout after the move has reached Go.
                # The old response is sent late, so the client must ignore it.
                time.sleep(1.1 if late_error else 4.0)
            if late_error:
                self.send_payload(500, b'{"error":"QA late response after authoritative acknowledgement"}')
                return
            self.send_payload(response.status_code, response.content, response.headers.get('ETag'))

    out = ROOT / '.tools' / 'qa' / ('input-recovery-' + secrets.token_hex(4))
    out.mkdir(parents=True)
    game = args.client.resolve() / 'Game.exe' if args.client else next(
        p for p in (ROOT / '.tools/godot').glob('*.exe') if not p.name.endswith('console.exe'))
    command = [game, '--audio-driver', 'Dummy']
    if not args.client:
        command += ['--path', ROOT / '源码/client']
    with ThreadingHTTPServer(('127.0.0.1', 0), Relay) as server:
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        relay = 'http://127.0.0.1:' + str(server.server_port)
        command += ['--script', ROOT / '源码/tools/input_recovery_acceptance.gd', '--',
                    '--qa-endpoint=' + relay, '--upstream=' + upstream,
                    '--name=qa_ir' + secrets.token_hex(4), '--output=' + str(out)]
        try:
            result = run(command, out / 'acceptance.log', 125)
        finally:
            server.shutdown()
            thread.join()
            with lock:
                (out / 'network.json').write_text(json.dumps(records, indent=2), encoding='utf8')
    log = (out / 'acceptance.log').read_text('utf8', errors='replace')
    assert not result['exit_code'] and 'ERROR:' not in log, str(out) + '\n' + log[-6000:]
    report_path = out / 'report.json'
    report = json.loads(report_path.read_text('utf8'))
    lost = next(r for r in records if r.get('dropped'))
    retries = [r for r in records if r['action'] == 'move' and not r.get('dropped') and
               r['generation'] == lost['generation'] and r['move_sequence'] == lost['move_sequence']]
    assert retries, str(out) + '\n' + json.dumps(records)
    for retry in retries:
        assert retry['status'] == 200, retry
        assert all(retry[key] == lost[key] for key in ['x', 'sp', 'move_spent', 'distance']), (lost, retry)
    assert any(r['action'] == 'poll_without_ack' for r in records), records
    assert any(r.get('late_error') for r in records), records
    assert any(r.get('late_fire_reply') for r in records), records
    assert sum(r['action'] == 'fire' and r['status'] == 200 for r in records) == 1, records
    items = [r for r in records if r['action'] == 'item']
    assert len(items) == 1 and items[0]['status'] == 200 and items[0]['slot'] == 0, records
    assert items[0]['inventory'][0] == 0, records
    assert any(r['action'] == 'late_item_reply' and r['status'] == 500 for r in records), records
    report.update(result, evidence=str(out), retries=len(retries), move_applied_once=True, item_applied_once=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
    print(json.dumps({'passed': True, 'checks': len(report['checks']), 'evidence': str(out)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
