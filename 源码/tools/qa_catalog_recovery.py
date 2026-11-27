"""Local UI regression for a lost catalog response and a D1 host adding B1 AI."""
import argparse
from contextlib import contextmanager
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import secrets
import threading
from urllib.request import Request, urlopen
from urllib.error import HTTPError

import requests
from playwright.sync_api import sync_playwright
from private_desktop import run

ROOT = Path(__file__).resolve().parents[2]
UPSTREAM = "http://127.0.0.1:18280"
EDGE = Path("C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe")


@contextmanager
def test_site(directory, evidence):
    class Handler(SimpleHTTPRequestHandler):
        extensions_map = {**SimpleHTTPRequestHandler.extensions_map, ".wasm": "application/wasm"}
        def log_message(self, *args):
            pass

        def proxy(self):
            path = self.path.removeprefix("/hd-api")
            if path == "/api/catalog":
                evidence["catalog_requests"] += 1
                if evidence["catalog_requests"] == 1:
                    self.send_error(503)
                    return
            body = None
            if self.command == "POST":
                body = self.rfile.read(int(self.headers["Content-Length"]))
            headers = {k: v for k, v in self.headers.items() if k.lower() in ("content-type", "authorization", "if-none-match")}
            try:
                result = urlopen(Request(UPSTREAM + path, method=self.command, headers=headers, data=body), timeout=15)
            except HTTPError as error:
                result = error
            with result:
                data = result.read()
                if path == "/api/catalog" and evidence["catalog_requests"] == 2:
                    damaged = json.loads(data)
                    damaged["vehicles"][0]["name"] = None
                    data = json.dumps(damaged, ensure_ascii=False).encode("utf8")
                if path == "/api/command" and body:
                    action = json.loads(body)
                    if action["action"] in ("create", "seat", "bots", "start"):
                        evidence["actions"].append((action, result.status))
                self.send_response(result.status)
                self.send_header("Content-Type", result.headers.get("Content-Type", "application/json"))
                if result.headers.get("ETag"):
                    self.send_header("ETag", result.headers["ETag"])
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
        def do_GET(self):
            if self.path.startswith(("/hd-api/", "/api/")):
                self.proxy()
            else:
                super().do_GET()

        do_POST = proxy

    with ThreadingHTTPServer(("127.0.0.1", 0), partial(Handler, directory=str(directory))) as server:
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            yield "http://127.0.0.1:" + str(server.server_port)
        finally:
            server.shutdown()
            thread.join()


def browser_test(origin, name, folder):
    with sync_playwright() as p:
        browser = p.chromium.launch(executable_path=str(EDGE), headless=True, args=["--mute-audio", "--enable-unsafe-swiftshader"])
        page = browser.new_page(viewport={"width": 1440, "height": 900})
        page_errors = []
        page.on("pageerror", lambda error: page_errors.append(str(error)))
        catalog_loaded = {"ready": False}
        def catalog_response(response):
            if response.url.endswith("/api/catalog") and response.ok:
                catalog = response.json()
                catalog_loaded["ready"] = bool(catalog.get("vehicles")) and isinstance(catalog["vehicles"][0].get("name"), str)
        page.on("response", catalog_response)
        def click(x, y):
            page.mouse.click(x, y)
            page.wait_for_timeout(300)
        def capture(name):
            page.screenshot(path=str(folder / ("web-" + name + ".png")))
        def action(action_name, x, y):
            def matches(response):
                if not response.url.endswith("/api/command"):
                    return False
                return (response.request.post_data_json or {}).get("action") == action_name
            with page.expect_response(matches, timeout=10000) as result:
                click(x, y)
            assert result.value.ok, action_name
            return result.value.json()
        try:
            page.goto(origin + "/hd/play/", wait_until="domcontentloaded")
            page.wait_for_selector("#status[hidden]", state="attached", timeout=120000)
            for _ in range(150):
                page.wait_for_timeout(200)
                if catalog_loaded["ready"]:
                    break
            assert catalog_loaded["ready"], "catalog automatically recovers after HTTP error and null vehicle name"
            # Enter credentials through the same login used by players.
            for y, text_value in [(196, name), (271, "qa-only-895432")]:
                click((1440 - 760 * 900 / 510) / 2 + 545 * 900 / 510, y * 900 / 510)
                page.keyboard.type(text_value)
            with page.expect_response(lambda response: response.url.endswith("/api/login"), timeout=15000) as login:
                click(1012, 632)
            assert login.value.ok, "login succeeds after catalog recovery"
            page.wait_for_timeout(3500)
            click(210, 355)
            click(345, 837)
            page.wait_for_timeout(3000)
            click(575, 45)
            capture("create")
            state = action("create", 620, 645)
            assert state["room"]["name"] == name + "的战场"
            page.wait_for_timeout(1900)
            state = action("seat", 200, 490)
            assert state["room"]["members"][0]["seat"] == 12
            click(1170, 65)
            page.wait_for_timeout(500)
            capture("ai-initial")
            click(385, 358)
            click(330, 471)
            page.wait_for_timeout(500)
            capture("ai")
            state = action("bots", 525, 707)
            assert any(m["seat"] == 4 and m["ai"] == 3 and m["vehicle"] == 0 for m in state["room"]["members"])
            state = action("start", 500, 45)
            assert len(state["room"]["battle"]["units"]) == 2
            page.wait_for_timeout(1200)
            capture("battle")
            assert not page_errors, page_errors
        except Exception:
            capture("failure")
            raise
        finally:
            browser.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client", type=Path, required=True)
    parser.add_argument("--web", type=Path, required=True)
    parser.add_argument("--platform", choices=["windows", "web", "both"], default="both")
    args = parser.parse_args()
    suffix = secrets.token_hex(3)
    output = ROOT / ".tools/qa/catalog-021" / suffix
    output.mkdir(parents=True)
    print(output, flush=True)
    report = {}
    for platform in ["windows", "web"] if args.platform == "both" else [args.platform]:
        evidence = {"catalog_requests": 0, "actions": []}
        name = "qa_cr" + suffix + ("n" if platform == "windows" else "w")
        signed = requests.post(UPSTREAM + "/api/register", json={"name": name, "password": "qa-only-895432"}, timeout=10)
        signed.raise_for_status()
        with test_site(args.web.resolve(), evidence) as origin:
            if platform == "windows":
                result = run([args.client.resolve() / "Game.exe", "--audio-driver", "Dummy", "--max-fps", "40", "--script",
                              ROOT / "源码/tools/catalog_recovery_acceptance.gd", "--", "--qa-endpoint=" + origin,
                              "--name=" + name, "--output=" + str(output)], output / "windows.log", 120)
                log = (output / "windows.log").read_text("utf8")
                assert result["exit_code"] == 0 and "SCRIPT ERROR:" not in log and "ERROR:" not in log, log[-2000:]
            else:
                browser_test(origin, name, output)
        assert evidence["catalog_requests"] >= 3
        actions = dict((action["action"], (action, status)) for action, status in evidence["actions"])
        assert all(actions[k][1] == 200 for k in ("create", "seat", "bots", "start")), actions
        bots = actions["bots"][0]["bots"]
        by_seat = {bot["seat"]: bot for bot in bots}
        assert len(bots) == 16 and set(by_seat) == set(range(16))
        assert by_seat[4] == {"seat": 4, "level": 3, "vehicle": 0}
        assert by_seat[12]["level"] == 0 and all(0 <= b["vehicle"] <= 30 for b in bots)
        report[platform] = {"catalog_requests": evidence["catalog_requests"], "human_seat": 12, "bot_seat": 4,
                            "difficulty": 3, "random_vehicle": True, "battle_started": True}
        (output / "report.json").write_text(json.dumps(report, indent=2), encoding="utf8")
        print(platform, report[platform], flush=True)


if __name__ == "__main__":
    main()
