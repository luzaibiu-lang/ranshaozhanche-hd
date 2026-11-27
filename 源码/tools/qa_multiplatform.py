"""Play a local match with the real Web export and the packaged Windows game."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from contextlib import ExitStack
import json
from pathlib import Path
import secrets
import time
from urllib.parse import urlparse

import requests
from playwright.sync_api import sync_playwright
from private_desktop import run


ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--client", required=True, type=Path)
parser.add_argument("--web", default="http://127.0.0.1:18380")
parser.add_argument("--endpoint", default="http://127.0.0.1:18280")
parser.add_argument("--browser", type=Path)
args = parser.parse_args()
for origin in (args.endpoint, args.web):
    if urlparse(origin).hostname != "127.0.0.1":
        parser.error("This test creates fixture accounts only on a loopback server")
run_id = secrets.token_hex(3)
base = ROOT / ".tools/qa/multiplatform020"
out = base / ("match-" + run_id)
out.mkdir(parents=True)
session = requests.Session()
session.trust_env = False
names = ["qa_m" + run_id + role for role in "wnf"]
password = "qa-only-895432"


def post(path, data, token=""):
    response = session.post(args.endpoint + path, json=data, headers={"Authorization": "Bearer " + token}, timeout=8)
    if not response.ok:
        raise ValueError((path, response.status_code, response.json().get("error")))
    return response.json()


tokens = [post("/api/register", {"name": name, "password": password})["token"] for name in names]


def command(index, action, **data):
    return post("/api/command", dict(action=action, **data), tokens[index])


room_id = command(0, "create", name="跨端对战验收", map=4)["room"]["id"]
command(1, "join", room=room_id)
command(1, "seat", seat=1)
command(1, "vehicle", vehicle=3)
command(1, "ready", ready=True)
command(2, "join", room=room_id)
exe = args.client.resolve() / "Game.exe"
native_args = [exe, "--audio-driver", "Dummy", "--max-fps", "40", "--script",
               ROOT / "源码/tools/multiplatform_acceptance.gd", "--", "--name=" + names[1],
               "--output=" + str(out), "--qa-endpoint=" + args.endpoint]
pool = ThreadPoolExecutor(1)
native = pool.submit(run, native_args, out / "native.log", 420)
report = {"passed": False, "directory": str(out), "checks": [], "sampled_generations": [], "evidence": []}
web_state = {}
errors = []
serial = 0


def state():
    try:
        return json.loads((out / "state.json").read_text("utf8"))
    except (FileNotFoundError, PermissionError, ValueError):
        return {}


def battle(room):
    return (room or {}).get("battle") or {}


def compact(room):
    b = battle(room)
    units = [(u["seat"], u["vehicle"], u["hp"], u["sp"], u["x"], u["y"]) for u in b.get("units", [])]
    return (room["id"], room["map"], b.get("id"), b.get("round"), b.get("generation"), b.get("wind"),
            b.get("active"), b.get("holes"), units, (b.get("shot") or {}).get("id"))


try:
    with ExitStack() as cleanup:
        playwright = cleanup.enter_context(sync_playwright())
        # The Windows test process can inherit Playwright pipe handles. Close
        # the private desktop before Playwright waits for those handles.
        cleanup.callback((out / "finish").touch)
        browser = playwright.chromium.launch(executable_path=str(args.browser) if args.browser else None,
            headless=True, args=["--mute-audio", "--enable-unsafe-swiftshader"])
        page = browser.new_page(viewport={"width": 1440, "height": 900})
        page.on("pageerror", lambda error: errors.append(str(error)))

        def finished(request):
            if "/hd-api/api/" in request.url and request.url.rsplit("/", 1)[-1] in ("state", "command"):
                response = request.response()
                if response and response.status == 200:
                    data = response.json()
                    if "profile" in data and data["version"] >= web_state.get("version", 0):
                        web_state.update(data)

        page.on("requestfinished", finished)

        def wait(label, predicate, seconds=25):
            until = time.monotonic() + seconds
            while time.monotonic() < until:
                if predicate():
                    print(label, flush=True)
                    report["checks"].append(label)
                    return
                if native.done():
                    raise RuntimeError(("native exited", native.result(), (out / "native.log").read_text("utf8")[-1200:]))
                page.wait_for_timeout(180)
            page.screenshot(path=str(out / "failure.png"))
            raise RuntimeError(("timed out", label, state().get("scene"), web_state.get("version"), state().get("version")))

        def native_action(action, **data):
            global serial
            serial += 1
            temp = out / "cmd.next"
            temp.write_text(json.dumps(dict(action=action, **data), ensure_ascii=False), encoding="utf8")
            temp.replace(out / ("cmd-%d.json" % serial))
            wait("native " + action, lambda: state().get("serial") == serial)

        def snap(name):
            page.screenshot(path=str(out / (name + "-web.png")))
            native_action("screenshot", name=name + "-native")
            report["evidence"].append(name)

        def aligned():
            rooms = [web_state.get("room"), state().get("room")]
            return all(rooms) and compact(rooms[0]) == compact(rooms[1])

        page.goto(args.web + "/hd/play/", wait_until="domcontentloaded")
        page.wait_for_timeout(12500)
        scale = 900 / 510
        def login_click(x, y):
            page.mouse.click((1440 - 760 * scale) / 2 + x * scale, y * scale)
        login_click(545, 196)
        page.keyboard.type(names[0], delay=25)
        login_click(545, 271)
        page.keyboard.type(password, delay=25)
        login_click(545, 358)
        wait("browser login and room state", lambda: bool(web_state.get("room")))
        page.wait_for_timeout(2300)
        page.mouse.click(210, 355)
        page.mouse.click(345, 837)
        wait("Windows room entry", lambda: state().get("scene") == "room")
        command(0, "settings", map=9)
        wait("map and room synchronized", lambda: aligned() and web_state["room"]["map"] == 9)
        page.wait_for_timeout(1800)
        snap("room")
        command(0, "start")
        wait("battle, wind, vehicles, HP and SP synchronized", lambda: state().get("scene") == "battle" and aligned()
             and bool(battle(web_state.get("room"))))
        page.wait_for_timeout(1200)
        page.keyboard.press("Enter")
        page.keyboard.type("web for windows", delay=70)
        page.keyboard.press("Enter")
        wait("Windows displays browser chat", lambda: "web for windows" in state().get("visible_chat", ""))
        native_action("chat", text="windows for web")
        wait("browser receives Windows chat", lambda: any(m["text"] == "windows for web" for m in web_state["room"]["chat"]))
        snap("battle-chat")
        fired = set()
        generation_done = set()
        started = time.monotonic()
        while time.monotonic() - started < 150:
            b = battle(web_state.get("room"))
            if b.get("result") or (b.get("round", 0) >= 3 and fired == {0, 1}):
                break
            if not b or b.get("deadline", 0) == 0 or b["generation"] in generation_done:
                page.wait_for_timeout(180)
                continue
            generation = b["generation"]
            wait("state agrees at turn " + str(generation), aligned)
            b = battle(web_state["room"])
            seat = b["active"]
            if seat == 0:
                page.keyboard.down("Space")
                page.wait_for_timeout(530)
                page.keyboard.up("Space")
            elif seat == 1:
                native_action("fire")
            else:
                command(2, "pass", generation=generation)
            if seat in (0, 1):
                wait("shot accepted from seat " + str(seat), lambda: (battle(web_state["room"]).get("generation") != generation
                     or battle(web_state["room"]).get("deadline") == 0))
                fired.add(seat)
            report["sampled_generations"].append({"generation": generation, "seat": seat, "round": b["round"]})
            generation_done.add(generation)
            page.wait_for_timeout(160)
        assert fired == {0, 1} and max(v["round"] for v in report["sampled_generations"]) >= 2, report["sampled_generations"]
        # Two real clients face a third fixture. Surrender by leaving ends the
        # match through the same death/settlement path as a player disconnect.
        command(2, "leave")
        wait("both clients receive settlement", lambda: all(battle(r).get("result") for r in (state().get("room"), web_state.get("room"))))
        page.wait_for_timeout(1300)
        snap("result")
        native_action("return")
        page.mouse.click(720, 678)
        wait("both clients back in the room", lambda: state().get("scene") == "room" and aligned() and not battle(web_state.get("room")))
        command(1, "seat", seat=4)
        command(1, "ready", ready=True)
        command(0, "settings", map=4)
        command(0, "start")
        wait("second match starts with fresh map, round and generation", lambda: state().get("scene") == "battle"
             and aligned() and battle(web_state.get("room")).get("map") == 4
             and battle(web_state.get("room")).get("round") == 1)
        snap("second")
        assert not errors, errors
        report["passed"] = True
finally:
    (out / "finish").touch()
    result = native.result(timeout=25)
    pool.shutdown()
    report["native_exit_code"] = result["exit_code"]
    report["browser_exceptions"] = errors
    report["passed"] = report["passed"] and result["exit_code"] == 0
    (out / "report.json").write_text(json.dumps(report, indent=2), encoding="utf8")
    if report["passed"]:
        (base / "mixed-report.json").write_text(json.dumps(report, indent=2), encoding="utf8")
    for index in (0, 1, 2):
        try:
            command(index, "leave")
        except (requests.RequestException, ValueError):
            pass
assert report["passed"], out
print(out, flush=True)
