"""Real touch input from manual login through start, chat dismissal and map gestures."""
import argparse,json,secrets,time,math
from pathlib import Path
import requests
from playwright.sync_api import sync_playwright
from qa_web_streaming import ROOT,EDGE,backend,local_site
from qa_manual_auth import login

parser=argparse.ArgumentParser();parser.add_argument('--web',type=Path,required=True);parser.add_argument('--report',type=Path,required=True);args=parser.parse_args()
errors=[];traffic=[];actions=[];checks=[]
with backend(ROOT/'.tools/hdserver-current.exe') as upstream,local_site(args.web.resolve(),upstream,traffic) as origin,sync_playwright() as pw:
    name='qa_touch'+secrets.token_hex(3);password=secrets.token_hex(10)
    auth=requests.post(upstream+'/api/register',json={'name':name,'password':password},timeout=10).json()
    headers={'Authorization':'Bearer '+auth['token']}
    def command(action,**kw):
        r=requests.post(upstream+'/api/command',headers=headers,json={'action':action,**kw},timeout=10);r.raise_for_status();return r.json()
    browser=pw.chromium.launch(executable_path=str(EDGE),headless=True,args=['--mute-audio','--enable-unsafe-swiftshader'])
    page=browser.new_page(viewport={'width':844,'height':390},is_mobile=True,has_touch=True,device_scale_factor=1,user_agent=pw.devices['Pixel 7']['user_agent'])
    page.on('pageerror',lambda e:errors.append(str(e)))
    page.on('console',lambda m:errors.append(m.text) if m.type=='error' and 'ERROR:' in m.text else None)
    def response(res):
        if res.url.endswith('/api/command'):actions.append((res.request.post_data_json,res.status))
    page.on('response',response);cdp=page.context.new_cdp_session(page)
    def touch(kind,points):cdp.send('Input.dispatchTouchEvent',{'type':kind,'touchPoints':[{'id':i,'x':x,'y':y} for i,x,y in points]})
    try:
        page.goto(origin+'/hd/play/',wait_until='domcontentloaded');page.wait_for_selector('#status[hidden]',state='attached',timeout=120000)
        page.wait_for_timeout(1800)
        page.locator('#landscape').tap()
        page.wait_for_function('Boolean(document.fullscreenElement)')
        login(page,name,password,True);page.wait_for_timeout(1600)
        page.touchscreen.tap(150,154);page.wait_for_timeout(180)
        with page.expect_response(lambda r:r.url.endswith('/api/state') and r.ok,timeout=20000):page.touchscreen.tap(235,363)
        page.wait_for_timeout(1500);checks.append('touch selects a channel and enters it')
        command('create',name=name,map=4)
        for slot,item in enumerate([2,3,4,5]):command('buy',item=item,slot=slot)
        command('bots',bots=[{'seat':i,'level':int(i==4),'vehicle':int(i==4)} for i in range(16)])
        page.wait_for_function("BurningChariotResourceState.loaded.includes('map_4') && BurningChariotResourceState.loaded.includes('battle_fx')",timeout=120000)
        page.wait_for_timeout(1400)
        with page.expect_response(lambda r:r.url.endswith('/api/command') and r.request.post_data_json.get('action')=='start',timeout=20000) as started:
            page.touchscreen.tap(215,20)
        assert started.value.ok,'Touch start was rejected'
        page.wait_for_timeout(2000);checks.append('room Start button starts a game through a real touch')
        page.touchscreen.tap(238,297)
        page.wait_for_function("document.activeElement.matches('input:enabled')",timeout=5000)
        page.keyboard.insert_text('保留聊天草稿')
        page.set_viewport_size({'width':844,'height':270});page.wait_for_timeout(300)
        page.set_viewport_size({'width':844,'height':390});page.wait_for_timeout(300)
        page.touchscreen.tap(500,180)
        page.wait_for_function("!document.activeElement.matches('input:enabled,textarea:enabled')",timeout=5000)
        checks.append('touching outside chat closes keyboard and returns control')
        touch('touchStart',[(1,360,180),(2,500,180)])
        page.wait_for_function("typeof BurningChariotCamera!=='undefined' && BurningChariotCamera.touches===2",timeout=5000)
        before=page.evaluate('BurningChariotCamera')
        touch('touchMove',[(1,300,170),(2,580,205)]);page.wait_for_timeout(120)
        after=page.evaluate('BurningChariotCamera')
        assert after['zoom']>before['zoom']*1.3,(before,after)
        touch('touchEnd',[]);checks.append('two real touch fingers change the game zoom')
        touch('touchStart',[(1,430,180)]);page.wait_for_timeout(50);before=page.evaluate('BurningChariotCamera')
        touch('touchMove',[(1,500,205)]);page.wait_for_timeout(100);after=page.evaluate('BurningChariotCamera')
        assert math.dist(before['camera'],after['camera'])>5,(before,after)
        touch('touchEnd',[]);checks.append('one real touch finger moves the game camera')
        for _ in range(250):
            page.wait_for_timeout(150)
            state=requests.get(upstream+'/api/state',headers=headers,timeout=5).json();battle=state['room']['battle']
            own=next(u for u in battle['units'] if u['player']>0)
            if battle['active']==own['seat'] and battle['deadline']>time.time()+5:break
        else:raise AssertionError('Could not acquire a QA turn')
        touch('touchStart',[(1,125,292)]);page.wait_for_timeout(550);touch('touchEnd',[]);page.wait_for_timeout(400)
        assert any(a['action']=='move' and status==200 for a,status in actions),actions
        checks.append('movement buttons work after chat and gestures')
        args.report.parent.mkdir(parents=True,exist_ok=True);page.screenshot(path=str(args.report.with_suffix('.png')))
        assert not errors,errors
        report={'passed':True,'checks':checks,'engine_errors':errors,'touch_actions':actions,'device':'Chromium actual touch events; no physical device'}
        args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8');print(json.dumps(report,ensure_ascii=False))
    except Exception:
        args.report.parent.mkdir(parents=True,exist_ok=True);page.screenshot(path=str(args.report.parent/'mobile-flow-failure.png'));print(json.dumps({'errors':errors,'checks':checks,'actions':actions},ensure_ascii=False));raise
    finally:browser.close()
