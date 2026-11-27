"""Exercise the exported loading page on desktop and handheld browser profiles."""
import argparse
import json
from dataclasses import dataclass
from pathlib import Path

from playwright.sync_api import expect, sync_playwright


ROOT = Path(__file__).resolve().parents[2]
URL = "http://localhost/hd/play/"
ENGINE_STUB = """
window.Engine = class {
    static getMissingFeatures() { return []; }
    startGame() { return new Promise(resolve => { window.finishLoading = resolve; }); }
};
"""


@dataclass(frozen=True)
class Profile:
    name: str
    platform: str
    ua_platform: str
    hints_platform: str | None
    touches: int
    handheld: bool
    size: tuple[int, int] = (1920, 953)
    hints_mobile: bool = False
    mouse_primary: bool = False


PROFILES = (
    Profile("Windows mouse", "Win32", "Windows NT 10.0; Win64; x64", "Windows", 0, False),
    Profile("Windows touch and mouse", "Win32", "Windows NT 10.0; Win64; x64", "Windows", 10, False, mouse_primary=True),
    Profile("Windows tablet touch", "Win32", "Windows NT 10.0; Win64; x64", None, 10, False, (768, 1024)),
    Profile("Windows narrow", "Win32", "Windows NT 10.0; Win64; x64", "Windows", 10, False, (390, 844)),
    Profile("Linux touch", "Linux x86_64", "X11; Linux x86_64", "Linux", 5, False),
    Profile("ChromeOS convertible", "Linux x86_64", "X11; CrOS x86_64", "Chrome OS", 10, False),
    Profile("macOS", "MacIntel", "Macintosh; Intel Mac OS X 10_15", None, 0, False),
    Profile("Android phone", "Linux armv8l", "Linux; Android 14; Pixel", "Android", 5, True, (390, 844), True),
    Profile("Android tablet", "Linux armv8l", "Linux; Android 14; Tablet", "Android", 5, True, (1366, 1024)),
    Profile("Android desktop site", "Linux armv8l", "X11; Linux x86_64", "Android", 5, True, (1366, 1024)),
    Profile("iPhone", "iPhone", "iPhone; CPU iPhone OS 18_0 like Mac OS X", None, 5, True, (390, 844)),
    Profile("iPad desktop user agent", "MacIntel", "Macintosh; Intel Mac OS X 10_15", None, 5, True, (1366, 1024)),
    Profile("HarmonyOS phone", "Linux armv8l", "Linux; HarmonyOS 4.0", None, 5, True, (390, 844)),
)


def check_profile(browser, entry, profile):
    width, height = profile.size
    context = browser.new_context(
        user_agent=f"Mozilla/5.0 ({profile.ua_platform}) AppleWebKit/537.36 Safari/537.36",
        viewport={"width": width, "height": height}, is_mobile=profile.handheld, has_touch=profile.touches > 0,
    )
    hints = None if profile.hints_platform is None else {"platform": profile.hints_platform, "mobile": profile.hints_mobile}
    setup = """
    const [platform, points, hints, mousePrimary] = PROFILE;
    for (const [name, value] of Object.entries({platform, maxTouchPoints: points, userAgentData: hints})) {
        Object.defineProperty(navigator, name, {get: () => value});
    }
    if (mousePrimary) {
        const match = window.matchMedia.bind(window);
        window.matchMedia = query => {
            const media = match(query);
            const options = {'(pointer:coarse)':false, '(pointer:fine)':true,
                '(hover:none)':false, '(hover:hover)':true, '(any-pointer:coarse)':true};
            const key = query.replace(/\\s/g, '');
            if (key in options) Object.defineProperty(media, 'matches', {get: () => options[key]});
            return media;
        };
    }
    """
    context.add_init_script(setup.replace("PROFILE", json.dumps([profile.platform, profile.touches, hints, profile.mouse_primary])))
    page = context.new_page()
    errors = []
    page.on("pageerror", lambda exc: errors.append(str(exc)))
    # Keep the game paused at the moment reproduced in the user report, then release loading.
    def resource(route):
        if route.request.url == URL:
            route.fulfill(body=entry, content_type="text/html; charset=utf-8")
        elif route.request.url.endswith("/game.js"):
            route.fulfill(body=ENGINE_STUB, content_type="application/javascript")
        else:
            route.fulfill(status=204)
    context.route("**/*", resource)
    try:
        page.goto(URL)
        button = page.locator("#landscape")
        page.wait_for_function("typeof window.finishLoading === 'function'")
        def verify():
            assert page.evaluate("window.BurningChariotDevice.mobile") is profile.handheld, profile.name
            (expect(button).to_be_visible if profile.handheld else expect(button).to_be_hidden)()
        verify()
        page.set_viewport_size({"width": height, "height": width})
        verify()
        page.evaluate("window.finishLoading()")
        expect(page.locator("#status")).to_be_hidden()
        verify()
        if profile.name == "Android phone":
            for _ in range(2):
                button.tap()
                page.wait_for_function("Boolean(document.fullscreenElement)")
                expect(button).to_be_hidden()
                page.evaluate("document.exitFullscreen()")
                expect(button).to_be_enabled()
                verify()
        assert not errors, errors
        return {"profile": profile.name, "mobile": profile.handheld, "passed": True}
    finally:
        context.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--web", type=Path, required=True, help="Directory generated by build_web.py")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    entry = (args.web / "hd/play/index.html").read_text(encoding="utf8")
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(channel="msedge", headless=True, args=["--mute-audio"])
        try:
            results = [check_profile(browser, entry, profile) for profile in PROFILES]
        finally:
            browser.close()
    report = {"environment": "Edge touch emulation; exported HTML with simulated loading",
              "profiles": results, "fullscreen_reentry_cycles": 2}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2), encoding="utf8")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
