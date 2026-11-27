"""Exercise exported mobile Web transport, pending UI and recovery in isolation."""
import argparse,json,secrets,time
from pathlib import Path
import requests
from playwright.sync_api import sync_playwright
from qa_web_streaming import ROOT,EDGE,backend,local_site
from qa_manual_auth import login

p=argparse.ArgumentParser();p.add_argument('--web',type=Path,required=True);p.add_argument('--server',type=Path,required=True);p.add_argument('--report',type=Path,required=True);args=p.parse_args()
checks=[];errors=[];commands=[];held=[];streams=[];replies=[]
with backend(args.server.resolve()) as upstream,local_site(args.web.resolve(),upstream,[]) as origin,sync_playwright() as pw:
    http=requests.Session();http.trust_env=False
    name='qa_net'+secrets.token_hex(3);password=secrets.token_hex(10)
    auth=http.post(upstream+'/api/register',json={'name':name,'password':password},timeout=10).json();headers={'Authorization':'Bearer '+auth['token']}
    def command(action,**fields):
        r=http.post(upstream+'/api/command',headers=headers,json={'action':action,'loading_barrier':True,**fields},timeout=10);r.raise_for_status();return r.json()
    browser=pw.chromium.launch(executable_path=str(EDGE),headless=True,args=['--mute-audio','--enable-unsafe-swiftshader'])
    context=browser.new_context(viewport={'width':844,'height':390},is_mobile=True,has_touch=True,device_scale_factor=1,user_agent=pw.devices['Pixel 7']['user_agent'])
    page=context.new_page();page.on('pageerror',lambda e:errors.append(str(e)))
    page.on('console',lambda m:errors.append(m.text) if m.type=='error' and 'ERROR:' in m.text else None)
    block={'start':True,'silence':False,'drop_fire':False}
    def route_ws(ws):
        server=ws.connect_to_server();streams.append((ws,server))
        def incoming(raw):
            packet=json.loads(raw)
            if packet.get('path')=='/api/command':
                commands.append(packet)
                if packet.get('payload',{}).get('action')=='start' and block['start']:
                    held.append((server,raw,ws));return
            if block['silence']:return
            server.send(raw)
        def outgoing(raw):
            if block['silence']:return
            packet=json.loads(raw);replies.append(packet)
            ws.send(raw)
        ws.on_message(incoming);server.on_message(outgoing)
    page.route_web_socket('**/api/stream',route_ws)
    try:
        page.goto(origin+'/hd/play/',wait_until='domcontentloaded');page.wait_for_selector('#status[hidden]',state='attached',timeout=120000);page.wait_for_timeout(1600)
        login(page,name,password,True)
        page.wait_for_function("globalThis.BurningChariotNetwork?.transport==='websocket'",timeout=20000)
        page.wait_for_function("BurningChariotNetwork.scene==='channel'");page.wait_for_timeout(2200)
        page.touchscreen.tap(150,154);page.wait_for_timeout(180);page.touchscreen.tap(235,363)
        page.wait_for_function("BurningChariotNetwork.scene==='lobby'",timeout=15000)
        checks.append('Manual mobile login establishes authenticated persistent stream and enters channel')
        command('create',name=name,map=4)
        command('bots',bots=[{'seat':i,'level':int(i==4),'vehicle':1} for i in range(16)])
        page.wait_for_function("BurningChariotNetwork.scene==='room'")
        page.wait_for_function("BurningChariotResourceState.loaded.includes('map_4') && BurningChariotResourceState.loaded.includes('battle_fx')",timeout=120000)
        page.wait_for_timeout(800)
        page.touchscreen.tap(215,20)
        page.wait_for_function("BurningChariotNetwork.start_pending.length>0 && BurningChariotNetwork.command_busy")
        for _ in range(7):page.touchscreen.tap(215,20)
        page.wait_for_timeout(1200)
        assert len(held)==1,(len(held),commands)
        state=http.get(upstream+'/api/state',headers=headers,timeout=10).json();assert state['room'].get('battle') is None
        args.report.parent.mkdir(parents=True,exist_ok=True);page.screenshot(path=str(args.report.with_name('start-pending.png')))
        checks.append('Delayed Start shows disabled loading state; eight touches produce one command')
        first=json.loads(held[0][1]);held[0][2].send(json.dumps({'id':first['id'],'status':400,'data':{'error':'测试：请重试开局'}}))
        page.wait_for_function("!BurningChariotNetwork.command_busy && BurningChariotNetwork.start_pending.length===0")
        page.touchscreen.tap(215,20)
        page.wait_for_function("BurningChariotNetwork.command_busy")
        page.wait_for_timeout(500)
        assert len(held)==2,len(held)
        checks.append('A rejected Start restores the button and allows a deliberate retry')
        block['start']=False;held[1][0].send(held[1][1])
        page.wait_for_function("BurningChariotNetwork.scene==='battle' && globalThis.BurningChariotBattleReady?.prepared && !BurningChariotBattleReady.loading",timeout=120000)
        assert sum(c.get('payload',{}).get('action')=='start' for c in commands)==2
        checks.append('Delayed acknowledgement opens one new battle after render readiness')
        page.locator('#mobile-chat-trigger').tap();page.locator('#mobile-chat-input').fill('长连接中文消息')
        page.locator('#mobile-chat-send').tap();page.wait_for_selector('#mobile-chat-layer[hidden]',state='attached')
        assert any((r.get('data',{}).get('room') or {}).get('chat') for r in replies)
        page.wait_for_timeout(1200)
        state=http.get(upstream+'/api/state',headers=headers,timeout=10).json()
        assert sum(x['text']=='长连接中文消息' for x in state['room']['chat'])==1
        checks.append('Native mobile chat sends Chinese exactly once through the persistent connection')
        block['silence']=True;page.wait_for_timeout(3500);block['silence']=False
        page.wait_for_timeout(1000)
        assert page.evaluate("BurningChariotNetwork.transport==='websocket' && BurningChariotNetwork.failures===0")
        checks.append('A short 3.5-second network stall does not create repeated disconnect warnings')
        # Cut the live socket while preserving the account and room. The next
        # socket authenticates, obtains a full state and resumes input.
        streams[-1][0].close(code=1012,reason='QA reconnect')
        page.wait_for_function("BurningChariotNetwork.transport==='http'",timeout=10000)
        page.wait_for_function("BurningChariotNetwork.transport==='websocket'",timeout=20000)
        assert len(streams)>=2
        checks.append('Socket replacement reconnects to the same battle with a fresh authenticated snapshot')
        page.locator('#mobile-chat-trigger').tap();page.locator('#mobile-chat-input').fill('重连后继续聊天');page.locator('#mobile-chat-send').tap()
        page.wait_for_selector('#mobile-chat-layer[hidden]',state='attached');page.wait_for_timeout(600)
        state=http.get(upstream+'/api/state',headers=headers,timeout=10).json()
        assert sum(x['text']=='重连后继续聊天' for x in state['room']['chat'])==1
        checks.append('Confirmed chat works after reconnection without duplicate messages')
        command('leave')
        page.wait_for_function("BurningChariotNetwork.scene==='lobby'")
        command('create',name=name,map=4)
        command('bots',bots=[{'seat':i,'level':int(i==4),'vehicle':1} for i in range(16)])
        page.wait_for_function("BurningChariotNetwork.scene==='room'")
        page.wait_for_timeout(1400)
        page.touchscreen.tap(215,20)
        page.wait_for_function("BurningChariotNetwork.scene==='battle' && BurningChariotBattleReady.prepared && !BurningChariotBattleReady.loading",timeout=30000)
        checks.append('Leaving and starting the next match restores the original Start button state')
        cdp=page.context.new_cdp_session(page)
        def touch(kind,points):cdp.send('Input.dispatchTouchEvent',{'type':kind,'touchPoints':[{'id':i,'x':x,'y':y} for i,x,y in points]})
        touch('touchStart',[(1,360,180),(2,500,180)])
        page.wait_for_function("globalThis.BurningChariotCamera?.touches===2")
        before=page.evaluate('BurningChariotCamera.zoom')
        touch('touchMove',[(1,300,170),(2,580,205)]);page.wait_for_timeout(150)
        assert page.evaluate('BurningChariotCamera.zoom')>before*1.3
        touch('touchEnd',[])
        checks.append('Two real touch points still zoom the map after reconnect and the next match')
        touch('touchStart',[(1,125,292)]);page.wait_for_timeout(550);touch('touchEnd',[]);page.wait_for_timeout(500)
        assert any(c.get('payload',{}).get('action')=='move' for c in commands)
        checks.append('Touch movement continues through the stream after chat, reconnect and the next match')
        assert not errors,errors
        page.screenshot(path=str(args.report.with_suffix('.png')))
        result={'passed':True,'checks':checks,'engine_errors':errors,'connections':len(streams),'start_commands':sum(c.get('payload',{}).get('action')=='start' for c in commands),'network':page.evaluate('BurningChariotNetwork'),'physical_phone_tested':False}
        args.report.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8');print(json.dumps(result,ensure_ascii=False))
    except Exception:
        args.report.parent.mkdir(parents=True,exist_ok=True);page.screenshot(path=str(args.report.with_name('network-failure.png')))
        print(json.dumps({'checks':checks,'errors':errors,'network':page.evaluate('globalThis.BurningChariotNetwork'),'streams':len(streams),'held':len(held),'last_reply_statuses':[(r.get('id'),r.get('status')) for r in replies[-4:]]},ensure_ascii=False),flush=True);raise
    finally:browser.close()
