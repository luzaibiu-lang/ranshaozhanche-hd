import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import re
from threading import Thread
from playwright.sync_api import sync_playwright

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--web', default='.tools/web-023-final')
args = parser.parse_args()
web = (root / args.web).resolve()
out = root / '.tools/qa/release-0.2.3/mobile-shell'
out.mkdir(parents=True, exist_ok=True)
published = (web / 'hd/play/index.html').read_text(encoding='utf8')
shell = (root / '源码/web/play.html').read_text(encoding='utf8')
profile = (root / '源码/client/device_profile.js').read_text(encoding='utf8')
shell = shell.replace('<!-- DEVICE_PROFILE -->', '<script>\n' + profile + '\n</script>')
shell = shell.replace('<!-- BUILD_BASE -->', re.search(r'<base href="[^"]+">', published)[0])
shell = shell.replace('$GODOT_HEAD_INCLUDE', '').replace('$GODOT_THREADS_ENABLED', 'false')
shell = shell.replace('$GODOT_URL', 'game.js').replace('$GODOT_CONFIG', re.search(r'(?:new Engine\(|const config = )(\{[^\n]+\})', published)[1])

class Handler(SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass
    def copyfile(self, source, outputfile):
        try:
            super().copyfile(source, outputfile)
        except (ConnectionResetError, ConnectionAbortedError, BrokenPipeError):
            pass

server = ThreadingHTTPServer(('127.0.0.1', 0), partial(Handler, directory=str(web)))
Thread(target=server.serve_forever, daemon=True).start()
check = []
errors = []
edge = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'
try:
    with sync_playwright() as pw:
        browser = pw.chromium.launch(executable_path=edge, headless=True, args=['--mute-audio','--enable-unsafe-swiftshader'])
        for scenario in ('mobile','fallback','denied','desktop'):
            desktop = scenario == 'desktop'
            page = browser.new_page(viewport={'width':1280 if desktop else 390,'height':720 if desktop else 844}, is_mobile=not desktop, has_touch=not desktop,
                                    **({} if desktop else {'user_agent':pw.devices['Pixel 7']['user_agent']}))
            page.on('pageerror',lambda e: errors.append(str(e)))
            page.route('**/hd/play/',lambda route: route.fulfill(body=shell, content_type='text/html;charset=UTF-8'))
            if scenario == 'fallback':
                page.add_init_script("""Element.prototype.requestFullscreen = undefined;
                    Element.prototype.webkitRequestFullscreen = undefined;
                    Object.defineProperty(screen.orientation,'lock',{value:undefined});""")
            elif scenario == 'denied':
                page.add_init_script("""Element.prototype.requestFullscreen = () => Promise.reject(new Error('Denied'));
                    Element.prototype.webkitRequestFullscreen = undefined;
                    Object.defineProperty(screen.orientation,'lock',{value:undefined});""")
            page.goto(f'http://127.0.0.1:{server.server_port}/hd/play/',wait_until='domcontentloaded')
            button = page.locator('#landscape')
            if desktop:
                assert not button.is_visible()
                check.append('Desktop does not display the mobile overlay')
            elif scenario == 'mobile':
                assert button.is_visible() and page.locator('#status').is_visible()
                page.screenshot(path=out/'mobile-loading.png')
                button.tap()
                page.wait_for_function('!!document.fullscreenElement')
                check.append('Trusted loading-page touch enters native document fullscreen in Chromium mobile emulation')
                page.wait_for_selector('#status[hidden]',state='attached',timeout=120000)
                assert page.locator('canvas').bounding_box()['height'] > 100
                page.screenshot(path=out/'mobile-running.png')
                check.append('Real Godot WebAssembly starts and displays canvas after fullscreen entry')
                page.set_viewport_size({'width':844,'height':390})
                page.evaluate('document.exitFullscreen()')
                button.wait_for(state='visible')
                assert button.is_enabled()
                page.touchscreen.tap(420,195)
                assert button.is_visible(), 'Canvas touch must not remove the fullscreen entry'
                button.tap()
                page.wait_for_function('!!document.fullscreenElement')
                page.evaluate('document.exitFullscreen()')
                button.wait_for(state='visible')
                button.tap()
                page.wait_for_function('!!document.fullscreenElement')
                check.append('Exiting fullscreen restores the button; canvas touch preserves it and repeated trusted taps re-enter fullscreen')
            elif scenario == 'denied':
                button.tap()
                assert button.is_visible() and button.is_enabled()
                page.set_viewport_size({'width':844,'height':390})
                assert button.is_visible()
                button.tap()
                assert button.is_visible() and button.is_enabled()
                check.append('Denied fullscreen leaves an enabled retry button in portrait and landscape')
            else:
                button.tap()
                assert '请将手机横过来' in page.locator('#display-hint').inner_text()
                page.set_viewport_size({'width':844,'height':390})
                page.wait_for_selector('#mobile-display[hidden]',state='attached')
                check.append('Missing fullscreen/orientation APIs show physical-rotation fallback which clears on rotation')
            page.close()
        browser.close()
    assert not errors, errors
finally:
    server.shutdown()
    server.server_close()
    print(json.dumps({'checks':check,'page_errors':errors},ensure_ascii=False))
    (out/'report.json').write_text(json.dumps({'checks':check,'page_errors':errors,'web':web.name},ensure_ascii=False,indent=2),encoding='utf8')
