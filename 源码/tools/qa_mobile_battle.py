"""Exercise the exported game with Chromium touch events and an isolated HD Go server."""
import argparse
import json
import secrets
import socket
import subprocess
import tempfile
import time
from pathlib import Path

import requests
from playwright.sync_api import sync_playwright

import qa_catalog_recovery as site
from qa_manual_auth import login

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--web", type=Path, required=True)
parser.add_argument("--server", type=Path, default=ROOT / ".tools/hdserver-current.exe")
args = parser.parse_args()
out = ROOT / ".tools/qa/release-0.2.3/mobile"
out.mkdir(parents=True, exist_ok=True)
with socket.socket() as probe:
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
site.UPSTREAM = f"http://127.0.0.1:{port}"
with tempfile.TemporaryDirectory() as data:
    server = subprocess.Popen([str(args.server), "--listen", f"127.0.0.1:{port}", "--data", data,
                               "--assets", str(ROOT / "源码/client/assets")],
                              creationflags=subprocess.CREATE_NO_WINDOW, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for attempt in range(80):
            try:
                if requests.get(site.UPSTREAM + "/health", timeout=.5).ok:break
            except requests.ConnectionError:
                time.sleep(.1)
        name = "qa_m" + secrets.token_hex(3)
        password = secrets.token_hex(9)
        token = requests.post(site.UPSTREAM+"/api/register", json={"name":name,"password":password}, timeout=5).json()["token"]
        headers = {"Authorization":"Bearer "+token}
        def command(action, **fields):
            response = requests.post(site.UPSTREAM+"/api/command", json={"action":action,**fields},headers=headers,timeout=5)
            assert response.ok, (action,response.text[:300])
            return response.json()
        with site.test_site(args.web.resolve(), {"catalog_requests":3,"actions":[]}) as origin, sync_playwright() as pw:
            browser = pw.chromium.launch(executable_path=str(site.EDGE), headless=True, args=["--mute-audio","--enable-unsafe-swiftshader"])
            page = browser.new_page(viewport={"width":1440,"height":900},is_mobile=True,has_touch=True,device_scale_factor=1,
                                    user_agent=pw.devices['Pixel 7']['user_agent'])
            page.add_init_script("sessionStorage.setItem('burningchariot.hd.session',"+json.dumps(token)+")")
            errors, actions = [], []
            page.on("pageerror", lambda e:errors.append(str(e)))
            def response(res):
                if res.url.endswith("/api/command"):
                    req=res.request.post_data_json
                    actions.append((req,res.status))
            page.on("response",response)
            cdp=page.context.new_cdp_session(page)
            def touches(kind, pts):
                cdp.send("Input.dispatchTouchEvent",{"type":kind,"touchPoints":[{"x":x,"y":y,"id":i,"radiusX":4,"radiusY":4} for i,x,y in pts]})
            def tap(x,y):
                page.touchscreen.tap(x,y)
                page.wait_for_timeout(230)
            def hold(x,y,ms):
                touches("touchStart",[(1,x,y)])
                page.wait_for_timeout(ms)
                touches("touchEnd",[])
                page.wait_for_timeout(200)
            def shot(name):
                page.screenshot(path=str(out/(name+".png")))
            def state():
                return requests.get(site.UPSTREAM+"/api/state", headers=headers, timeout=5).json()
            try:
                page.goto(origin+"/hd/play/",wait_until="domcontentloaded")
                page.wait_for_selector("#status[hidden]",state="attached",timeout=180000)
                login(page,name,password,True)
                page.wait_for_timeout(2200)
                tap(210,355)
                tap(345,837)
                page.wait_for_timeout(1600)
                command("create",name=name,map=4)
                command("buy",item=2,slot=0)
                bots=[{"seat":i,"level":1 if i==4 else 0,"vehicle":1 if i==4 else 0} for i in range(16)]
                command("bots",bots=bots)
                page.set_viewport_size({"width":844,"height":390})
                page.wait_for_timeout(600)
                initial=command("start")["room"]["battle"]
                if page.evaluate("typeof BurningChariotResourceState !== 'undefined'"):
                    page.wait_for_function("BurningChariotResourceState.loaded.includes('map_4') && BurningChariotResourceState.loaded.includes('battle_fx')",timeout=120000)
                    page.wait_for_timeout(1000)
                for _ in range(90):
                    page.wait_for_timeout(200)
                    battle=state()["room"]["battle"]
                    own=next(u for u in battle["units"] if u["player"]>0)
                    if battle["active"]==own["seat"] and battle["deadline"]>time.time()+7:break
                page.wait_for_timeout(700)
                shot("touch-battle")
                # Viewport 844x390, Godot renders at 1:1 CSS pixel ratio.
                hold(125,292,340)
                hold(32,292,430)
                hold(78,247,520)
                tap(78,198)   # F2
                tap(672,247)  # First item
                page.wait_for_timeout(700)
                touches("touchStart",[(1,804,294)])
                page.wait_for_timeout(600)
                touches("touchCancel",[])
                page.wait_for_timeout(250)
                assert not any(c["action"]=="fire" for c,_ in actions),"touchcancel fired a shot"
                hold(804,294,820)
                page.wait_for_timeout(900)
                fired=[c for c,status in actions if c["action"]=="fire" and status==200]
                assert any(c["action"]=="move" and status==200 for c,status in actions), actions
                assert any(c["action"]=="item" and c["slot"]==0 and status==200 for c,status in actions), actions
                assert len(fired)==1 and fired[0]["weapon"]==1 and fired[0]["power"]>0 and fired[0]["angle"]!=own["elevation"], actions
                touches("touchStart",[(1,360,200),(2,495,200)])
                touches("touchMove",[(1,300,180),(2,570,220)])
                touches("touchEnd",[])
                page.wait_for_timeout(350)
                shot("touch-after-fire")
                assert not errors,errors
                result={"passed":True,"viewport":[844,390],"device":"headless Chromium touch emulation","actions":actions}
                (out/"browser.json").write_text(json.dumps(result,indent=2),encoding="utf8")
                print(json.dumps(result),flush=True)
            except Exception:
                shot("failure")
                raise
            finally:
                browser.close()
    finally:
        server.terminate()
        server.wait(timeout=15)
