"""Exercise remembered credentials in the shipped WinForms assembly on a private desktop."""
import argparse
import http.server
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import threading
from unittest.mock import patch

from private_desktop import run


ROOT = Path(__file__).resolve().parents[2]
DRIVER = r'''
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Threading.Tasks;
using System.Windows.Forms;

class RememberDriver {
    static readonly BindingFlags Private = BindingFlags.NonPublic | BindingFlags.Instance;

    static void Require(bool ok, string message) {
        if (!ok) throw new Exception(message);
    }

    static T Find<T>(Form form, string name) where T : Control {
        return (T)form.Controls.Find(name, true)[0];
    }

    [STAThread] static int Main(string[] args) {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        var type = Assembly.LoadFrom(Path.GetFullPath("LauncherHost.exe")).GetType("LauncherWindow", true);
        var form = (Form)Activator.CreateInstance(type, Private, null, new object[]{"", ""}, null);
        int result = 1;
        form.Shown += async (s,e) => {
            try {
                var elapsed = Stopwatch.StartNew();
                while ((bool)type.GetField("loading", Private).GetValue(form)) {
                    Require(elapsed.ElapsedMilliseconds < 20000, "startup timeout");
                    await Task.Delay(20);
                }
                string stage = args[0];
                string name = Environment.GetEnvironmentVariable("QA_REMEMBER_NAME");
                string secret = Environment.GetEnvironmentVariable("QA_REMEMBER_PASSWORD");
                var user = Find<TextBox>(form, "Username");
                var password = Find<TextBox>(form, "Password");
                var remember = Find<CheckBox>(form, "Remember");
                Require(password.UseSystemPasswordChar || password.PasswordChar != '\0', "password masking missing");
                bool restored = stage != "save" && stage != "corrupt" && stage != "forgotten" && stage != "other-origin";
                if (restored) {
                    Require(remember.Checked && user.Text == name && password.Text == secret,
                        "account, checkbox or actual masked password not restored");
                }
                if (stage == "restore") {
                    type.GetMethod("CaptureClient", Private).Invoke(form, new object[]{args[1]});
                } else if (stage == "account-switch") {
                    user.Text = name + "_another";
                    Require(password.Text.Length == 0, "other account received previous password");
                    Require((string)type.GetField("session", Private).GetValue(form) == "", "other account received previous session");
                } else if (stage == "register-view") {
                    Find<Button>(form, "ToggleRegistration").PerformClick();
                    Require(Find<TextBox>(form, "Confirmation").Visible && password.Text.Length == 0, "registration kept password");
                } else if (stage == "forget") {
                    remember.Checked = false;
                } else if (stage == "forgotten" || stage == "other-origin") {
                    Require(password.Text.Length == 0, "password unexpectedly restored");
                    if (stage == "forgotten") Require(!remember.Checked, "forgotten preference not persisted");
                } else {
                    if (stage == "save" || stage == "corrupt") {
                        Require(password.Text.Length == 0, "unexpected initial password");
                        user.Text = name; password.Text = secret; remember.Checked = true;
                    } else if (stage == "wrong") {
                        password.Text = secret + "-wrong";
                    } else Require(stage == "transient" || stage == "expired", "unknown fixture stage");
                    await (Task)type.GetMethod("Start", Private).Invoke(form, null);
                }
                result = 0;
            } catch (Exception error) {
                Console.Error.WriteLine(error.GetBaseException().Message);
            } finally { form.Close(); }
        };
        Application.Run(form);
        form.Dispose();
        return result;
    }
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client', type=Path, required=True, help='Candidate directory containing LauncherHost.exe')
    args = parser.parse_args()
    candidate = args.client.resolve()
    out = ROOT / '.tools' / 'qa' / ('remember-' + secrets.token_hex(4))
    out.mkdir(parents=True)
    for filename in ('LauncherHost.exe', '燃烧战车.exe'):
        shutil.copyfile(candidate / filename, out / filename)
    driver = out / 'RememberDriver.cs'
    driver.write_text(DRIVER, encoding='utf-8')
    exe = out / 'RememberDriver.exe'
    compiler = Path(os.environ['WINDIR']) / 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
    subprocess.run([compiler, '/nologo', '/target:exe', '/out:' + str(exe),
                    '/reference:System.Windows.Forms.dll', driver], check=True,
                   creationflags=subprocess.CREATE_NO_WINDOW)
    profile = out / 'profile'
    vault = profile / 'BurningChariotHD'
    vault.mkdir(parents=True)
    name = 'qa_' + secrets.token_hex(5)
    password = secrets.token_urlsafe(25)
    token = secrets.token_hex(32)
    events = []
    state_codes = []
    checks = []

    class Service(http.server.BaseHTTPRequestHandler):
        def reply(self, code, body):
            data = json.dumps(body).encode()
            self.send_response(code)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            if self.path == '/api/state':
                valid = self.headers.get('Authorization') == 'Bearer ' + token
                code = state_codes.pop(0) if state_codes else 200
                code = code if valid else 401
                body = {'profile': {'name': name}} if code == 200 else {'error': 'fixture state error'}
            elif self.path == '/health':
                code, body = 200, {'edition': 'hd'}
            else:
                code, body = 404, {'error': 'fixture update unavailable'}
            events.append((self.path, code))
            self.reply(code, body)

        def do_POST(self):
            data = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
            correct = self.path == '/api/login' and data.get('name') == name and data.get('password') == password
            code = 200 if correct else 401
            events.append((self.path, code))
            self.reply(code, {'token': token} if correct else {'error': 'fixture password incorrect'})

        def log_message(self, *args):
            pass

    def stage(label):
        events.clear()
        result = run([exe, label, out / 'remembered.png'], out / (label + '.log'), timeout=35)
        if result['exit_code']:
            detail = (out / (label + '.log')).read_text('utf-8', errors='replace')
            raise AssertionError(label + ': ' + detail)

    def check(value, description):
        if not value:
            raise AssertionError(description + '; requests=' + repr(events))
        checks.append(description)

    def origin(service):
        (out / 'connection.json').write_text(json.dumps({'endpoint': 'http://127.0.0.1:' + str(service.server_port),
                                                        'edition': 'hd'}), encoding='utf-8')

    profile_env = {'LOCALAPPDATA': str(profile), 'BCHD_VAULT_ROOT': str(vault),
                   'QA_REMEMBER_NAME': name, 'QA_REMEMBER_PASSWORD': password}
    account_file = vault / 'account.dat'
    session_file = vault / 'session.dat'
    with patch.dict(os.environ, profile_env), http.server.ThreadingHTTPServer(('127.0.0.1', 0), Service) as server:
        threading.Thread(target=server.serve_forever, daemon=True).start()
        origin(server)
        try:
            stage('save')
            check(events.count(('/api/login', 200)) == 1, 'first manual login submits exactly once')
            # CryptProtectData serializes the DPAPI provider GUID immediately after the version.
            dpapi = bytes.fromhex('01000000d08c9ddf0115d1118c7a00c04fc297eb')
            check(all(p.read_bytes().startswith(dpapi) for p in (account_file, session_file)),
                  'both saved files contain Windows DPAPI blobs')
            encodings = ('utf-8', 'utf-16-le')
            check(all(secret.encode(encoding) not in path.read_bytes() for path in vault.rglob('*') if path.is_file()
                      for secret in (password, token) for encoding in encodings), 'profile contains no plaintext password or token')
            stage('restore')
            check(('/api/state', 200) in events and not any(p == '/api/login' for p, _ in events),
                  'new process restores masked password and session')
            stage('account-switch')
            checks.append('changing account clears recalled password and session')
            stage('register-view')
            checks.append('registration does not prefill the remembered password')
            with http.server.ThreadingHTTPServer(('127.0.0.1', 0), Service) as other:
                threading.Thread(target=other.serve_forever, daemon=True).start()
                origin(other)
                try:
                    stage('other-origin')
                    check(not any(p in ('/api/login', '/api/state') for p, _ in events),
                          'saved password and session are scoped to their service origin')
                finally:
                    other.shutdown()
                    origin(server)
            state_codes[:] = [503, 200]
            stage('transient')
            check(events[:2] == [('/api/state', 503), ('/api/state', 200)]
                  and not any(p == '/api/login' for p, _ in events) and ('/updates/manifest.json', 404) in events,
                  'retry after temporary outage restores the same session')
            state_codes[:] = [401]
            stage('expired')
            check(('/api/state', 401) in events and events.count(('/api/login', 200)) == 1
                  and ('/updates/manifest.json', 404) in events, 'expired session uses saved password on Start')
            stage('wrong')
            check(('/api/login', 401) in events and ('/updates/manifest.json', 404) not in events,
                  'wrong edited password is rejected before update')
            stage('restore')
            checks.append('unsuccessful login did not overwrite the saved password')
            account_file.write_bytes(b'corrupt isolated QA blob')
            session_file.write_bytes(b'corrupt isolated QA blob')
            stage('corrupt')
            check(('/api/login', 200) in events and account_file.read_bytes().startswith(dpapi),
                  'damaged credentials recover through manual login')
            stage('forget')
            check(not account_file.exists() and not session_file.exists(), 'unchecking forgets both credentials immediately')
            stage('forgotten')
            checks.append('next process keeps remember disabled and password empty')
        finally:
            server.shutdown()
    report = {'passed': True, 'private_desktop': True, 'checks': checks,
              'launcher_sha256': __import__('hashlib').sha256((out / 'LauncherHost.exe').read_bytes()).hexdigest()}
    (out / 'report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps({'passed': True, 'checks': len(checks), 'evidence': str(out)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
