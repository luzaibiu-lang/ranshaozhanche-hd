"""Verify native battle chat in an exported browser build against isolated Go rooms."""
import argparse
import json
import secrets
import threading
import time
import re
from pathlib import Path

import requests
from playwright.sync_api import expect, sync_playwright

from qa_manual_auth import login
from qa_web_streaming import EDGE, ROOT, backend, local_site


def run(web, server, report):
    checks = []
    errors = []
    with backend(server) as upstream:
        # Open the exported release from its normal play route.
        with local_site(web.resolve(), upstream, []) as origin, sync_playwright() as pw:
            browser = pw.chromium.launch(executable_path=str(EDGE), headless=True,
                                         args=["--mute-audio", "--enable-unsafe-swiftshader", "--disable-background-timer-throttling", "--disable-renderer-backgrounding"])
            browsers = [browser]
            context_options = dict(
                viewport={"width": 844, "height": 390}, is_mobile=True, has_touch=True,
                device_scale_factor=1, user_agent=pw.devices["Pixel 7"]["user_agent"])

            def player(prefix):
                name = prefix + secrets.token_hex(3)
                password = secrets.token_hex(10)
                registration = requests.post(upstream + "/api/register",
                                             json={"name": name, "password": password}, timeout=10)
                registration.raise_for_status()
                headers = {"Authorization": "Bearer " + registration.json()["token"]}
                if len(browsers) == 1 and not hasattr(player, "used"):
                    peer_browser = browser
                    player.used = True
                else:
                    peer_browser = pw.chromium.launch(executable_path=str(EDGE), headless=True,
                        args=["--mute-audio", "--enable-unsafe-swiftshader", "--disable-background-timer-throttling", "--disable-renderer-backgrounding"])
                    browsers.append(peer_browser)
                page = peer_browser.new_page(**context_options)
                page.on("pageerror", lambda error: errors.append(str(error)))
                page.on("console", lambda m: errors.append(m.text) if m.type == "error" and "ERROR:" in m.text else None)
                page.goto(origin + "/hd/play/", wait_until="domcontentloaded")
                page.wait_for_selector("#status[hidden]", state="attached", timeout=120000)
                with page.expect_response(lambda r: r.url.endswith("/api/state") and r.ok):
                    login(page, name, password, mobile=True)
                page.wait_for_timeout(2200)
                page.touchscreen.tap(150, 154)
                page.wait_for_timeout(180)
                with page.expect_response(lambda result: result.url.endswith("/api/state") and result.ok):
                    page.touchscreen.tap(235, 363)
                page.wait_for_timeout(1300)
                return page, name, headers

            def command(headers, action, **fields):
                response = requests.post(upstream + "/api/command", headers=headers,
                                         json={"action": action, "loading_barrier": True, **fields}, timeout=10)
                response.raise_for_status()
                return response.json()

            try:
                sender, name, sender_headers = player("qa_chat_a")
                recipient, _, recipient_headers = player("qa_chat_b")
                html = (web / "hd/play/index.html").read_text("utf8")
                resource_url = re.search(r'game-stream-manifest" content="([^"]+)"', html)[1]
                manifest = requests.get(origin + resource_url, timeout=10).json()
                map_urls = {origin + spec["url"] for key, spec in manifest["groups"].items() if key.startswith("map_")}
                delayed = []
                def delay_map(route):
                    if route.request.url in map_urls and not delayed:
                        delayed.append(time.time())
                        time.sleep(5)
                    route.continue_()
                recipient.route("**/*.pck", delay_map)
                samples = []
                sample_stop = threading.Event()
                def sample():
                    while not sample_stop.wait(.12):
                        state = requests.get(upstream + "/api/state", headers=sender_headers, timeout=5).json()
                        b = (state.get("room") or {}).get("battle")
                        if b:
                            samples.append({"time": time.time(), "loading": b.get("loading", False), "deadline": b["deadline"], "generation": b["generation"], "shot": b["shot"] is not None})
                sampler = threading.Thread(target=sample, daemon=True)
                sampler.start()
                room = command(sender_headers, "create", name=name, map=0)["room"]
                command(recipient_headers, "join", room=room["id"], seat=4)
                lost_acks = []
                def lose_first_ack(route):
                    if route.request.post_data_json.get("action") == "battle_loaded" and not lost_acks:
                        lost_acks.append(time.time())
                        route.abort()
                    else:
                        route.continue_()
                sender.route("**/api/command", lose_first_ack)
                command(sender_headers, "start")
                # Headless tabs can suspend animation frames when another tab
                # owns focus. Keep both independent game loops active in QA.
                for _ in range(400):
                    statuses = []
                    for game in (sender, recipient):
                        game.bring_to_front()
                        game.wait_for_timeout(150)
                        statuses.append(game.evaluate("globalThis.BurningChariotBattleReady || {}"))
                    if all(row.get("prepared") and not row.get("loading", True) for row in statuses):
                        break
                else:
                    raise AssertionError(("Both clients did not finish loading", statuses))
                sample_stop.set()
                sampler.join(timeout=6)
                waiting = [row for row in samples if row["loading"]]
                playing = [row for row in samples if not row["loading"]]
                assert delayed and lost_acks and waiting and playing, (delayed, lost_acks, samples[-6:])
                assert all(row["deadline"] == 0 and row["generation"] == 1 and not row["shot"] for row in waiting), waiting
                first = playing[0]
                assert 33.8 <= first["deadline"] - first["time"] <= 35.2, first
                assert waiting[-1]["time"] - waiting[0]["time"] >= 4, waiting
                sender.unroute("**/api/command", lose_first_ack)
                checks.append("Random-map battle waits for both rendered clients; delayed map and dropped ready ACK preserve full first turn")
                trigger = sender.locator("#mobile-chat-trigger")
                expect(trigger).to_be_visible(timeout=120000)
                expect(recipient.locator("#mobile-chat-trigger")).to_be_visible(timeout=120000)
                sender.bring_to_front()
                trigger.tap()

                field = sender.locator("#mobile-chat-input")
                send = sender.locator("#mobile-chat-send")
                expect(field).to_be_focused()
                expect(send).to_be_disabled()
                sender.set_viewport_size({"width": 844, "height": 224})
                sender.wait_for_function("""() => Math.abs(
                    document.querySelector('#mobile-chat').getBoundingClientRect().bottom
                    - (visualViewport.offsetTop + visualViewport.height)) < 2""")
                checks.append("Trusted touch focuses native field and bar follows reduced visual viewport")

                message = "中文聊天，发送测试"
                field.dispatch_event("compositionstart", {"data": ""})
                sender.keyboard.insert_text(message)
                field.dispatch_event("keydown", {"key": "Enter", "isComposing": True, "bubbles": True})
                sender.wait_for_timeout(350)
                expect(field).to_have_value(message)
                field.dispatch_event("compositionend", {"data": message})
                checks.append("Enter during composition finishes without sending")

                def chat_response(response):
                    return response.url.endswith("/api/command") and response.request.post_data_json.get("action") == "chat"

                def reject_chat(route):
                    if route.request.post_data_json.get("action") == "chat":
                        route.fulfill(status=503, json={"error": "测试：发送暂时失败"})
                    else:
                        route.continue_()

                sender.route("**/api/command", reject_chat)
                with sender.expect_response(chat_response) as failed:
                    send.tap()
                assert failed.value.status == 503
                expect(sender.locator("#mobile-chat-status")).to_contain_text("失败")
                expect(field).to_have_value(message)
                expect(send).to_be_enabled()
                sender.unroute("**/api/command", reject_chat)
                checks.append("Rejected send displays error and preserves draft for retry")

                sender.set_viewport_size({"width": 390, "height": 844})
                expect(field).to_have_value(message)
                sender.locator("#mobile-chat-close").tap()
                expect(field).to_be_hidden()
                sender.set_viewport_size({"width": 844, "height": 390})
                trigger.tap()
                expect(field).to_have_value(message)
                checks.append("Draft survives orientation changes and closing/reopening chat")

                with sender.expect_response(chat_response) as sent:
                    send.tap()
                assert sent.value.ok
                expect(field).to_be_hidden()
                recipient.bring_to_front()
                with recipient.expect_response(lambda reply: reply.url.endswith("/api/state") and reply.ok) as state:
                    pass
                chat = state.value.json()["room"]["chat"]
                assert sum(row["name"] == name and row["text"] == message for row in chat) == 1, chat
                checks.append("Tap Send puts one confirmed Chinese message in the other player's live snapshot")

                sender.bring_to_front()
                trigger.tap()
                expect(field).to_have_value("")
                sender.touchscreen.tap(500, 150)
                expect(field).to_be_hidden()
                assert sender.evaluate("BurningChariotBattleReady.prepared")
                assert recipient.evaluate("BurningChariotBattleReady.prepared")
                recipient.screenshot(path=str(report.with_name("mobile-chat-recipient.png")))
                assert not errors, errors
                checks.append("Confirmed send clears draft and outside tap releases the editor")
                report.parent.mkdir(parents=True, exist_ok=True)
                sender.screenshot(path=str(report.with_suffix(".png")))
                result = {"passed": True, "device": "Chromium touch emulation", "checks": checks, "loading_samples": samples, "engine_errors": errors}
                report.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
                print(json.dumps({key: value for key, value in result.items() if key != "loading_samples"}, ensure_ascii=True))
            except Exception:
                report.parent.mkdir(parents=True, exist_ok=True)
                for index, game in enumerate([sender, recipient] if "recipient" in locals() else [sender]):
                    game.screenshot(path=str(report.with_name(f"chat-failure-{index}.png")))
                    print("PAGE", index, game.evaluate("({resources:globalThis.BurningChariotResourceState,ready:globalThis.BurningChariotBattleReady,camera:globalThis.BurningChariotCamera})"), flush=True)
                print("ENGINE_ERRORS", errors, flush=True)
                print("SAMPLES", samples[-10:] if "samples" in locals() else [], flush=True)
                raise
            finally:
                if "sample_stop" in locals():sample_stop.set()
                for peer_browser in browsers:peer_browser.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--web", type=Path, required=True)
    parser.add_argument("--server", type=Path, default=ROOT / ".tools/hdserver-current.exe")
    parser.add_argument("--report", type=Path, required=True)
    options = parser.parse_args()
    run(options.web, options.server, options.report)
