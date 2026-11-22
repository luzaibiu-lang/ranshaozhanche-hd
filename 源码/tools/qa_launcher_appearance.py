"""Render actual source-owned launcher controls silently, without game accounts."""
import http.server
import json
import os
import pathlib
import secrets
import subprocess
import threading

from private_desktop import run

ROOT = pathlib.Path(__file__).resolve().parents[2]
out = ROOT / ('.tools/qa/launcher-appearance-' + secrets.token_hex(4))
out.mkdir(parents=True)
requests_seen = []


class HealthOnly(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        requests_seen.append(self.command + ' ' + self.path)
        data = json.dumps({'edition': 'hd'}).encode()
        self.send_response(200 if self.path == '/health' else 404)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        requests_seen.append(self.command + ' ' + self.path)
        if self.path != '/api/register':
            self.send_error(500, 'Unexpected write request in visual QA')
            return
        self.rfile.read(int(self.headers.get('Content-Length', '0')))
        # A mocked token exercises the real retry controls without creating
        # an account, launching a game, or contacting the production service.
        data = json.dumps({'token': 'qa-visual-only-no-real-account'}).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


harness = out / 'VisualQA.cs'
harness.write_text(r'''
using System;
using System.IO;
using System.Windows.Forms;
internal static class LauncherVisualQA {
    [STAThread]private static int Main(string[] args) {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.ThrowException);
        try {using(var window=new LauncherWindow("",args[0])){Application.Run(window);return window.Result;}}
        catch(Exception error){File.WriteAllText(args[1],error.ToString());return 1;}
    }
}
''', encoding='utf8')
compiler = pathlib.Path('C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe')
exe = out / '燃烧战车.exe'
assets = ROOT / '源码/client/assets'
args = [compiler, '/nologo', '/optimize+', '/target:winexe', '/main:LauncherVisualQA', '/out:' + str(exe)]
args += ['/reference:' + ref for ref in ['System.Windows.Forms.dll', 'System.Drawing.dll', 'System.Web.Extensions.dll', 'System.Security.dll']]
args += ['/resource:' + str(path) + ',art.' + name for name, path in [
    ('title', assets / 'legacy/TitleBack.png'),
    ('back', assets / 'legacy/LobyBack.png'),
    ('button', assets / 'legacy/pop_ok.png'),
    ('start', assets / 'legacy/gl_start.png'),
]]
args += [ROOT / '源码/launcher/Launcher.cs', ROOT / '源码/launcher/LauncherWindow.cs', harness]
compiled = subprocess.run(list(map(str, args)), capture_output=True, text=True, creationflags=subprocess.CREATE_NO_WINDOW)
(out / 'compile.log').write_text(compiled.stdout + compiled.stderr, encoding='utf8')
assert compiled.returncode == 0, compiled.stdout + compiled.stderr
controls = out / 'controls.json'
controls.write_text(json.dumps({'stage': 'appearance', 'output': str(out)}), encoding='utf8')
profile = out / 'profile'
profile.mkdir()
environment = {'LOCALAPPDATA': str(profile), 'BCHD_VAULT_ROOT': str(profile / 'BurningChariotHD')}
previous = {key: os.environ.get(key) for key in environment}
try:
    os.environ.update(environment)
    with http.server.ThreadingHTTPServer(('127.0.0.1', 0), HealthOnly) as server:
        (out / 'connection.json').write_text(json.dumps({'endpoint': 'http://127.0.0.1:' + str(server.server_port), 'edition': 'hd'}), encoding='utf8')
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            result = run([exe, controls, out / 'exception.txt'], out / 'visual.log', 90)
        finally:
            server.shutdown()
    assert result['exit_code'] == 0, (out / 'exception.txt').read_text('utf8') if (out / 'exception.txt').exists() else result
    report = json.loads((out / 'appearance-report.json').read_text('utf-8-sig'))
    assert report['passed']
    assert requests_seen == ['GET /health', 'POST /api/register', 'GET /updates/manifest.json', 'GET /updates/manifest.json'], requests_seen
    assert not list(profile.rglob('session.dat'))
    assert len(list(profile.rglob('settings.json'))) == 1
    report.update(result, evidence=str(out), requests=requests_seen, no_accounts_created=True)
    (out / 'report.json').write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding='utf8')
    (ROOT / '.tools/qa/launcher-appearance-acceptance.json').write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding='utf8')
    print(json.dumps({'passed': True, 'checks': len(report['checks']), 'evidence': str(out)}, ensure_ascii=False))
finally:
    for key, value in previous.items():
        if value is None:
            os.environ.pop(key, None)
        else:
            os.environ[key] = value
