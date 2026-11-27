"""Test the real shipped bootstrap and legacy upgrade on a private Windows desktop."""
import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys
import threading
import time
from unittest.mock import patch

import psutil
from private_desktop import run

ROOT = Path(__file__).resolve().parents[2]
ENTRY = "燃烧战车.exe"


def owned_game(client):
    for process in psutil.process_iter(["name", "exe"]):
        if process.info["name"] == "Game.exe" and process.info["exe"] and Path(process.info["exe"]).resolve() == client / "Game.exe":
            return process
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--client", required=True, type=Path)
    parser.add_argument("--old-client", type=Path)
    args = parser.parse_args()
    source = args.client.resolve()
    out = ROOT / ".tools/qa" / ("launcher-" + secrets.token_hex(5))
    client = out / "client"
    shutil.copytree(source, client)
    manifest = json.loads((source / "manifest.json").read_text("utf8"))
    blobs = {}
    requests = Counter()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            requests[self.path] += 1
            if self.path == "/updates/manifest.json":
                data = json.dumps(manifest).encode()
            elif self.path in blobs:
                data = blobs[self.path].read_bytes()
            elif self.path in ["/health", "/api/catalog"]:
                data = b'{}'
            else:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_POST(self):
            self.rfile.read(int(self.headers.get("Content-Length", 0)))
            if self.path != "/api/register":
                self.send_error(404)
                return
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'{"token":"isolated-migration-session"}')

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    origin = "http://127.0.0.1:" + str(server.server_port)
    connection = client / "connection.json"
    connection.write_text(json.dumps({"edition":"hd","endpoint":origin}), encoding="utf8")
    for item in manifest["files"]:
        path = source / item["path"]
        if item["path"] == "connection.json":
            path = connection
            item["size"] = path.stat().st_size
            item["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
            item["url"] = "blobs/" + item["sha256"]
        blobs["/updates/" + item["url"]] = path
    threading.Thread(target=server.serve_forever, daemon=True).start()
    profile = out / "profile"
    env = {"LOCALAPPDATA":str(profile),"APPDATA":str(profile),
           "BCHD_VAULT_ROOT":str(profile / "BurningChariotHD"),"BCHD_QA_SILENT":"1"}
    checks = {}

    def launch(stage, arguments=(), *, require_ticket=False):
        requests.clear()
        finished = out / (stage + ".finish")
        status = out / (stage + ".status")
        worker = ThreadPoolExecutor(max_workers=1)
        job = worker.submit(run, [sys.executable, Path(__file__).resolve(), "--hold-desktop",
                                  status, finished, client / ENTRY, *arguments], out / (stage + ".log"), 90)
        try:
            deadline = time.monotonic() + 65
            while time.monotonic() < deadline:
                game = owned_game(client)
                if game and requests["/api/catalog"] and status.exists():
                    break
                if job.done():
                    raise AssertionError("Bootstrap worker exited early: " + str(job.result()))
                time.sleep(0.15)
            else:
                raise AssertionError(f"Game did not reach catalog after {stage}: {requests}, wrapper exit={status.read_text() if status.exists() else 'running'}")
            assert status.read_text() == "0"
            command = game.cmdline()
            assert "Dummy" in command, command[:4]
            assert any(arg.startswith("--launcher-ticket=") for arg in command) == require_ticket
            assert requests["/updates/manifest.json"] >= 1
            downloads = sorted(k.rsplit("/",1)[1] for k in requests if k.startswith("/updates/blobs/"))
            checks[stage] = {"blob_downloads": len(downloads), "game_requested_catalog": True}
            if stage == "clean":
                pid = game.pid
                before = requests["/updates/manifest.json"]
                repeat = run([client / ENTRY], out / "already-running.log", 10)
                assert repeat["exit_code"] == 0 and owned_game(client).pid == pid
                assert before == requests["/updates/manifest.json"]
            return downloads
        finally:
            game = owned_game(client)
            if game:
                game.terminate()
                game.wait(10)
            finished.touch()
            worker.shutdown(wait=True)

    try:
        with patch.dict(os.environ, env):
            assert not launch("clean")
            (client / "Game.pck").write_bytes(b"isolated broken file")
            assert launch("repair") == [next(f["sha256"] for f in manifest["files"] if f["path"] == "Game.pck")]
            # Appending a byte preserves this PE's loader behavior but forces a verified host swap.
            with (client / "LauncherHost.exe").open("ab") as host:
                host.write(b"qa")
            assert len(launch("host-self-update")) == 1
            assert not launch("repeat")
            if args.old_client:
                old = args.old_client.resolve()
                for name in (ENTRY, "LauncherHost.exe"):
                    shutil.copy2(old / name, client / name)
                controls = out / "legacy-controls.json"
                controls.write_text(json.dumps({"stage":"register","name":"legacy_qa","password":"qa-only-pass",
                                                "output":str(out)}), encoding="utf8")
                assert len(launch("legacy-first-update", ["--launcher-qa=" + str(controls)], require_ticket=True)) == 1
                def vault(operation, value=""):
                    return subprocess.run([str(client / "Vault.exe"),operation], input=value+"\n",
                                          capture_output=True, text=True, encoding="utf8", check=True,
                                          creationflags=subprocess.CREATE_NO_WINDOW).stdout.strip()
                saved = json.loads(vault("read-account"))
                assert saved == {"username":"legacy_qa","password":"qa-only-pass","origin":origin}
                saved["password"] = "加密测试-0123"
                assert vault("write-account", json.dumps(saved, ensure_ascii=False)) == "ok"
                assert json.loads(vault("read-account")) == saved
                assert saved["password"].encode() not in (profile / "BurningChariotHD/account.dat").read_bytes()
                assert vault("clear-account") == "" and vault("read-account") == ""
                checks["legacy-saved-password"] = {"read":True,"utf8_round_trip":True,"clear":True}
                assert not launch("legacy-next-start")
    finally:
        server.shutdown()
        server.server_close()
    result = {"evidence":str(out),"tests":checks}
    (out / "report.json").write_text(json.dumps(result, indent=2), encoding="utf8")
    print(json.dumps(result))


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--hold-desktop":
        status, finished = map(Path, sys.argv[2:4])
        executable = Path(sys.argv[4])
        process = subprocess.run([str(executable), *sys.argv[5:]], cwd=executable.parent, timeout=45)
        status.write_text(str(process.returncode))
        deadline = time.monotonic() + 70
        while not finished.exists() and time.monotonic() < deadline:
            time.sleep(0.1)
    else:
        main()
