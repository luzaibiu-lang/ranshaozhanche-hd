"""Verify the exported game's login form with trusted Chromium touches on loopback."""
import argparse
from contextlib import contextmanager
import json
from pathlib import Path
import secrets
import socket
import subprocess
import tempfile
import time

from playwright.sync_api import sync_playwright
import requests

import qa_catalog_recovery as site


@contextmanager
def local_api(binary):
    with tempfile.TemporaryDirectory() as data:
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        listen = f"127.0.0.1:{port}"
        with subprocess.Popen([str(binary.resolve()), "--listen", listen, "--data", data,
                               "--assets", str(site.ROOT / "源码/client/assets")],
                              creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) as server:
            site.UPSTREAM = "http://" + listen
            try:
                for _ in range(60):
                    try:
                        if requests.get(site.UPSTREAM + "/health", timeout=1).ok:
                            break
                    except requests.ConnectionError:
                        pass
                    time.sleep(0.1)
                else:
                    raise RuntimeError("Local test API failed to start")
                yield
            finally:
                server.terminate()


def verify(browser, origin, mobile, name, password, output):
    options = {"viewport": {"width": 915, "height": 412}, "has_touch": True}
    if mobile:
        options.update(is_mobile=True, user_agent="Mozilla/5.0 (Linux; Android 13) "
                       "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36")
    context = browser.new_context(**options)
    try:
        page = context.new_page()
        errors = []
        page.on("pageerror", lambda exc: errors.append(str(exc)))
        session = context.new_cdp_session(page)
        page.goto(origin + "/hd/play/", wait_until="domcontentloaded")
        page.wait_for_selector("#status[hidden]", state="attached", timeout=120000)
        page.wait_for_timeout(2500)
        assert page.evaluate("BurningChariotDevice.mobile") is mobile
        if mobile:
            page.locator("#landscape").tap()
            page.wait_for_function("!!document.fullscreenElement", timeout=3000)
        size = page.evaluate("({w:canvas.clientWidth,h:canvas.clientHeight})")
        w, h = size["w"], size["h"]
        unit = min(max(min(w/1280, h/720), 0.65), 1.6, (w-24)/480, (h-80)/337)
        x, y = (w-480*unit)/2, max(72*unit, h*0.215)
        def select(fx, fy):
            point = (x+fx*unit, y+fy*unit)
            if mobile:
                page.touchscreen.tap(*point)
            else:
                page.mouse.click(*point)
            page.wait_for_timeout(180)
        select(245, 43)
        if mobile:
            page.wait_for_function("document.activeElement.matches('input[type=text]:enabled')", timeout=4000)
            session.send("Input.imeSetComposition", {"text": name[:2], "selectionStart": 2, "selectionEnd": 2})
            session.send("Input.insertText", {"text": name[:2]})
            page.keyboard.insert_text(name[2:])
        else:
            assert not page.locator("main > input").count()
            page.keyboard.type(name)
        select(245, 115)
        if mobile:
            page.wait_for_function("document.activeElement.matches('input[type=password]:enabled')", timeout=4000)
            # The headless browser has its own clipboard. Exercise the native paste event.
            context.grant_permissions(["clipboard-read", "clipboard-write"], origin=origin)
            page.evaluate("value => navigator.clipboard.writeText(value)", password)
            page.keyboard.press("Control+v")
            page.wait_for_function("n => document.activeElement.value.length === n", arg=len(password))
        else:
            page.keyboard.type(password)
        if output:
            page.screenshot(path=str(output / ("mobile-login.png" if mobile else "desktop-login.png")))
        with page.expect_response(lambda res: res.url.endswith("/api/login"), timeout=20000) as result:
            select(406, 80)
        actual = result.value.request.post_data_json
        assert result.value.ok, (f"Game login HTTP {result.value.status}: {result.value.text()}; "
            f"name={actual.get('name')!r}, expected={name!r}, "
            f"password_length={len(actual.get('password',''))}, expected_length={len(password)}, "
            f"password_matches={actual.get('password') == password}")
        assert result.value.request.post_data_json == {"name": name, "password": password}
        page.wait_for_function("!!sessionStorage.getItem('burningchariot.hd.session') || "
                               "!!localStorage.getItem('burningchariot.hd.session')", timeout=12000)
        assert not errors, errors
    finally:
        context.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--web", required=True, type=Path)
    parser.add_argument("--server", required=True, type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.output:
        args.output.mkdir(parents=True, exist_ok=True)
    with local_api(args.server), site.test_site(args.web.resolve(), {"catalog_requests": 2, "actions": []}) as origin:
        with sync_playwright() as pw:
            browser = pw.chromium.launch(executable_path=str(site.EDGE), headless=True,
                                         args=["--mute-audio", "--enable-unsafe-swiftshader"])
            try:
                for mobile in (True, False):
                    name = ("战车" if mobile else "qatouch") + secrets.token_hex(3)
                    password = secrets.token_urlsafe(14)
                    requests.post(site.UPSTREAM + "/api/register", json={"name": name, "password": password},
                                  timeout=10).raise_for_status()
                    verify(browser, origin, mobile, name, password, args.output)
            finally:
                browser.close()
    print(json.dumps({"mobile_touch_login": True, "mobile_password_masked": True,
                      "ime_composition": True, "password_paste": True,
                      "fullscreen_mobile": True, "touch_desktop_login": True, "physical_devices": False}))


if __name__ == "__main__":
    main()
