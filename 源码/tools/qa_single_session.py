"""Real manual logins on desktop/mobile Web; no shared bearer fixture."""
import argparse,json,secrets,time
from pathlib import Path
import requests
from playwright.sync_api import sync_playwright
from qa_web_streaming import ROOT,EDGE,backend,local_site
from qa_manual_auth import login
p=argparse.ArgumentParser();p.add_argument('--web',type=Path,required=True);p.add_argument('--server',type=Path,required=True);p.add_argument('--report',type=Path,required=True);args=p.parse_args()
checks=[];errors=[];logout_requests=[]
with backend(args.server.resolve()) as upstream,local_site(args.web.resolve(),upstream,[]) as origin,sync_playwright() as pw:
    http=requests.Session();http.trust_env=False
    name='qa_single'+secrets.token_hex(3);password=secrets.token_hex(10)
    r=http.post(upstream+'/api/register',json={'name':name,'password':password},timeout=10);r.raise_for_status()
    browser=pw.chromium.launch(executable_path=str(EDGE),headless=True,args=['--mute-audio','--enable-unsafe-swiftshader','--disable-background-timer-throttling','--disable-renderer-backgrounding'])
    def page(mobile):
        options={'viewport':{'width':844,'height':390},'is_mobile':mobile,'has_touch':mobile}
        if mobile:options['user_agent']=pw.devices['Pixel 7']['user_agent']
        game=browser.new_page(**options)
        game.on('pageerror',lambda e:errors.append(str(e)))
        game.on('console',lambda m:errors.append(m.text) if m.type=='error' and 'ERROR:' in m.text else None)
        game.on('request',lambda r:logout_requests.append(r.url) if r.url.endswith('/api/logout') else None)
        game.goto(origin+'/hd/play/',wait_until='domcontentloaded');game.wait_for_selector('#status[hidden]',state='attached',timeout=120000);game.wait_for_timeout(1500)
        return game
    def enter_channel(game,mobile):
        game.wait_for_function("globalThis.BurningChariotNetwork?.scene==='channel'",timeout=20000);game.wait_for_timeout(2000)
        tap=game.touchscreen.tap if mobile else game.mouse.click
        tap(150,154);game.wait_for_timeout(180);tap(235,363)
    def state(raw):
        r=http.get(upstream+'/api/state',headers={'Authorization':'Bearer '+raw},timeout=10)
        return r.status_code,r.json()
    def command(raw,action,**fields):
        r=http.post(upstream+'/api/command',headers={'Authorization':'Bearer '+raw},json={'action':action,'loading_barrier':True,**fields},timeout=10)
        r.raise_for_status();return r.json()
    try:
        desktop=page(False);desktop.bring_to_front()
        first=login(desktop,name,password).json()['token'];enter_channel(desktop,False)
        desktop.wait_for_function("BurningChariotNetwork.scene==='lobby'",timeout=15000)
        room=command(first,'create',name=name,map=4)['room'];room_id=room['id']
        desktop.wait_for_function("BurningChariotNetwork.scene==='room'",timeout=20000)
        mobile=page(True);mobile.bring_to_front()
        login(mobile,name,'incorrect-password',True,False)
        assert state(first)[0]==200
        checks.append('Incorrect password does not evict the existing desktop login')
        second=login(mobile,name,password,True).json()['token']
        desktop.bring_to_front();desktop.wait_for_function("globalThis.BurningChariotSession?.reason==='session_replaced'",timeout=10000)
        assert desktop.evaluate("!sessionStorage.getItem('burningchariot.hd.session') && !localStorage.getItem('burningchariot.hd.session')")
        assert not logout_requests,logout_requests
        args.report.parent.mkdir(parents=True,exist_ok=True);desktop.screenshot(path=str(args.report.with_name('desktop-replaced.png')))
        checks.append('A new mobile login returns desktop to login, shows replacement reason and clears the old local session without logging out the new player')
        code,data=state(first);assert code==401 and data['code']=='session_replaced'
        mobile.bring_to_front();enter_channel(mobile,True)
        mobile.wait_for_function("BurningChariotNetwork.scene==='room'",timeout=20000)
        code,data=state(second);assert code==200 and data['room']['id']==room_id and len(data['room']['members'])==1
        checks.append('The new mobile session resumes the same room with one player entry')
        old_logout=http.post(upstream+'/api/logout',headers={'Authorization':'Bearer '+first},json={},timeout=10);old_logout.raise_for_status()
        assert state(second)[1]['room']['id']==room_id
        checks.append('A stale desktop logout cannot remove the mobile player from the room')
        desktop.bring_to_front();third=login(desktop,name,password).json()['token']
        mobile.bring_to_front();mobile.wait_for_function("globalThis.BurningChariotSession?.reason==='session_replaced'",timeout=10000)
        mobile.screenshot(path=str(args.report.with_name('mobile-replaced.png')))
        checks.append('Logging in on desktop again evicts the mobile login in the reverse direction')
        desktop.bring_to_front();enter_channel(desktop,False)
        desktop.wait_for_function("BurningChariotNetwork.scene==='room'",timeout=20000)
        assert state(second)[0]==401 and state(third)[1]['room']['id']==room_id
        command(third,'chat',text='互斥登录后继续聊天')
        assert any(x['text']=='互斥登录后继续聊天' for x in state(third)[1]['room']['chat'])
        checks.append('The latest login retains room state and can continue sending commands')
        assert not errors,errors
        command(third,'leave')
        result={'passed':True,'checks':checks,'engine_errors':errors,'forced_logout_sent_http_logout':bool(logout_requests),'mode':'Headless Chromium desktop and mobile UI, manual login','physical_phone_tested':False}
        args.report.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8');print(json.dumps(result,ensure_ascii=False))
    except Exception:
        args.report.parent.mkdir(parents=True,exist_ok=True)
        for i,game in enumerate(browser.contexts):
            for j,item in enumerate(game.pages):item.screenshot(path=str(args.report.with_name(f'failure-{i}-{j}.png')))
        print(json.dumps({'checks':checks,'errors':errors,'logout_requests':len(logout_requests)},ensure_ascii=False),flush=True);raise
    finally:browser.close()
