"""Measure cold and warm browser startup against precompressed local release files."""
import argparse
from contextlib import contextmanager
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import secrets
import socket
import subprocess
import tempfile
import threading
import time
from urllib.parse import urlsplit

import requests
from playwright.sync_api import sync_playwright

from qa_catalog_recovery import EDGE, ROOT
from qa_manual_auth import login


@contextmanager
def backend(executable):
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        address = f"127.0.0.1:{probe.getsockname()[1]}"
    origin = f"http://{address}"
    with tempfile.TemporaryDirectory() as data:
        process = subprocess.Popen(
            [str(executable), "--listen", address, "--data", data, "--assets", str(ROOT / "源码/client/assets")],
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            for _ in range(100):
                if process.poll() is not None:
                    raise RuntimeError(f"Local server exited with {process.returncode}")
                try:
                    if requests.get(origin + "/health", timeout=.5).ok:
                        break
                except requests.ConnectionError:
                    time.sleep(.1)
            else:
                raise RuntimeError("Local server did not become healthy")
            yield origin
        finally:
            process.terminate()
            process.wait(timeout=10)


@contextmanager
def local_site(directory, upstream, traffic):
    class Handler(SimpleHTTPRequestHandler):
        extensions_map = {**SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm"}

        def log_message(self, *args):
            pass

        def proxy(self):
            path = self.path.removeprefix("/hd-api")
            headers = {k: v for k, v in self.headers.items() if k.lower() in ("authorization", "content-type", "if-none-match")}
            reply = requests.request(self.command, upstream + path, headers=headers, timeout=25,
                                     data=self.rfile.read(int(self.headers.get("Content-Length", 0))))
            with reply:
                self.send_response(reply.status_code)
                for key in ("Content-Type", "ETag"):
                    if key in reply.headers:
                        self.send_header(key, reply.headers[key])
                self.send_header("Content-Length", str(len(reply.content)))
                self.end_headers()
                self.wfile.write(reply.content)

        do_POST = proxy

        def do_GET(self):
            path = urlsplit(self.path).path
            if path.startswith(("/api/", "/hd-api/")):
                self.proxy()
                return
            file = Path(self.translate_path(path))
            if file.is_dir():
                file /= "index.html"
            compressed = file.with_suffix(file.suffix + ".gz")
            gzip = "gzip" in self.headers.get("Accept-Encoding", "") and compressed.is_file()
            source = compressed if gzip else file
            if not source.is_file():
                self.send_error(404)
                return
            size = source.stat().st_size
            self.send_response(200)
            self.send_header("Content-Type", self.guess_type(str(file)))
            self.send_header("Content-Length", str(size))
            immutable = path.startswith("/hd/play/") and file.suffix != ".html"
            self.send_header("Cache-Control", "public, max-age=31536000, immutable" if immutable else "no-cache")
            if gzip:
                self.send_header("Content-Encoding", "gzip")
                self.send_header("Vary", "Accept-Encoding")
            self.end_headers()
            with source.open("rb") as stream:
                self.copyfile(stream, self.wfile)
            traffic.append({"path": path, "bytes": size, "gzip": gzip})

    with ThreadingHTTPServer(("127.0.0.1", 0), partial(Handler, directory=str(directory))) as server:
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            yield f"http://127.0.0.1:{server.server_port}"
        finally:
            server.shutdown()
            thread.join()


def startup(context, origin, traffic):
    page = context.new_page()
    index = len(traffic)
    errors = []
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.on("console", lambda message: errors.append(message.text) if message.type == "error" and "ERROR:" in message.text else None)
    started = time.monotonic()
    page.goto(origin + "/hd/play/", wait_until="domcontentloaded")
    page.wait_for_selector("#status[hidden]", state="attached", timeout=180000)
    ready = time.monotonic() - started
    page.wait_for_timeout(1200)
    assert not errors, errors
    records = traffic[index:]
    timings = page.evaluate("""() => performance.getEntriesByType('resource').map(r => ({
        path: new URL(r.name).pathname, body: r.encodedBodySize, transfer: r.transferSize
    })).filter(r => r.path.startsWith('/hd/play/'))""")
    return page, {"server_bytes": sum(r["bytes"] for r in records), "requests": records,
                  "ready_seconds_local": round(ready, 2), "browser_resources": timings}


def battle_test(page, upstream, origin, traffic, folder):
    name = "qa_stream" + secrets.token_hex(3)
    password = secrets.token_hex(9)
    registration = requests.post(upstream + "/api/register", timeout=10,
                                 json={"name": name, "password": password})
    registration.raise_for_status()
    token = registration.json()["token"]
    headers = {"Authorization": "Bearer " + token}
    def command(action, **fields):
        reply = requests.post(upstream + "/api/command", headers=headers, timeout=10,
                              json={"action": action, **fields})
        reply.raise_for_status()
        return reply.json()
    errors = []
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.on("console", lambda message: errors.append(message.text) if message.type == "error" and "ERROR:" in message.text else None)
    page.evaluate("t => sessionStorage.setItem('burningchariot.hd.session', t)", token)
    page.goto(origin + "/hd/play/", wait_until="domcontentloaded")
    page.wait_for_selector("#status[hidden]", state="attached", timeout=180000)
    login(page,name,password)
    page.wait_for_timeout(3200)
    page.mouse.click(210, 355)
    page.wait_for_timeout(400)
    page.mouse.click(345, 837)
    page.wait_for_timeout(1800)
    start = len(traffic)
    command("create", name=name, map=4)
    bots = [{"seat": i, "level": int(i == 4), "vehicle": int(i == 4)} for i in range(16)]
    command("bots", bots=bots)
    with page.expect_response(lambda response: response.request.method == "GET"
                             and urlsplit(response.url).path.endswith("/api/state")
                             and response.ok and bool((response.json().get("room") or {}).get("battle")), timeout=45000):
        battle = command("start")["room"]["battle"]
    assert len(battle["units"]) == 2, battle
    if page.evaluate("typeof BurningChariotResourceState !== 'undefined'"):
        page.wait_for_function("BurningChariotResourceState.loaded.includes('map_4') && BurningChariotResourceState.loaded.includes('battle_fx')",timeout=120000)
    page.wait_for_timeout(1800)
    page.screenshot(path=str(folder / "streaming-battle.png"))
    assert not errors, errors
    if page.evaluate("typeof BurningChariotResourceState !== 'undefined'"):
        assert page.evaluate("BurningChariotResourceState.loaded.includes('map_4') && BurningChariotResourceState.loaded.includes('battle_fx')")
    return {"selected_map": 4, "battle_units": len(battle["units"]), "requests": traffic[start:]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--web", type=Path, required=True, help="Website export containing hd/play/index.html")
    parser.add_argument("--server", type=Path, default=ROOT / ".tools/hdserver-current.exe")
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--battle", action="store_true", help="Also enter an isolated two-player AI match")
    parser.add_argument("--cold-budget-mib", type=float, help="Maximum compressed startup payload in MiB")
    parser.add_argument("--warm-budget-mib", type=float, help="Maximum repeat-open payload in MiB")
    args = parser.parse_args()
    traffic = []
    with backend(args.server.resolve()) as upstream, local_site(args.web.resolve(), upstream, traffic) as origin, sync_playwright() as pw, tempfile.TemporaryDirectory() as profile:
        context = pw.chromium.launch_persistent_context(profile, executable_path=str(EDGE), headless=True,
            args=["--mute-audio", "--enable-unsafe-swiftshader"], viewport={"width": 1440, "height": 900})
        try:
            page, cold = startup(context, origin, traffic)
            page.close()
            page, warm = startup(context, origin, traffic)
            report = {"cold": cold, "warm": warm}
            args.report.parent.mkdir(parents=True, exist_ok=True)
            if args.battle:
                report["battle"] = battle_test(page, upstream, origin, traffic, args.report.parent)
            page.close()
            args.report.write_text(json.dumps(report, indent=2), "utf8")
            print(json.dumps({k: report[k]["server_bytes"] for k in ("cold", "warm")}), flush=True)
            for stage, budget in (("cold", args.cold_budget_mib), ("warm", args.warm_budget_mib)):
                if budget is not None:
                    assert report[stage]["server_bytes"] <= budget * 2**20, f"{stage} exceeded {budget} MiB"
        finally:
            context.close()


if __name__ == "__main__":
    main()
