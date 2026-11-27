"""Saved valid sessions must not authenticate until the login button is used."""
import argparse,json,secrets
from pathlib import Path
import requests
from playwright.sync_api import sync_playwright
from qa_web_streaming import ROOT,EDGE,backend,local_site
from qa_manual_auth import login

parser=argparse.ArgumentParser();parser.add_argument('--web',type=Path,required=True);parser.add_argument('--report',type=Path,required=True);args=parser.parse_args()
checks=[];errors=[];traffic=[]
with backend(ROOT/'.tools/hdserver-current.exe') as upstream,local_site(args.web.resolve(),upstream,traffic) as origin,sync_playwright() as pw:
    name='qa_manual'+secrets.token_hex(2);password=secrets.token_hex(10)
    auth=requests.post(upstream+'/api/register',json={'name':name,'password':password},timeout=10).json()
    browser=pw.chromium.launch(executable_path=str(EDGE),headless=True,args=['--mute-audio','--enable-unsafe-swiftshader'])
    try:
        for mobile in [False,True]:
            options={'viewport':{'width':844 if mobile else 1440,'height':390 if mobile else 900},'has_touch':mobile,'is_mobile':mobile}
            if mobile:options['user_agent']=pw.devices['Pixel 7']['user_agent']
            context=browser.new_context(**options)
            context.add_init_script("for(const storage of [localStorage,sessionStorage])storage.setItem('burningchariot.hd.session',"+json.dumps(auth['token'])+")")
            page=context.new_page();requests_seen=[]
            page.on('request',lambda request:requests_seen.append(request.url) if request.url.endswith(('/api/state','/api/login')) else None)
            page.on('pageerror',lambda error:errors.append(str(error)))
            page.on('console',lambda message:errors.append(message.text) if message.type=='error' and 'ERROR:' in message.text else None)
            def stopped(label):
                page.wait_for_selector('#status[hidden]',state='attached',timeout=120000)
                page.wait_for_timeout(2200)
                assert not requests_seen,(label,requests_seen)
                assert page.evaluate("!localStorage.getItem('burningchariot.hd.session') && !sessionStorage.getItem('burningchariot.hd.session')")
                checks.append({'mobile':mobile,'check':label,'passed':True})
            page.goto(origin+'/hd/play/',wait_until='domcontentloaded')
            stopped('valid legacy tokens in both stores cannot authenticate startup')
            login(page,name,'incorrect-password',mobile,False)
            assert not any(url.endswith('/api/state') for url in requests_seen)
            checks.append({'mobile':mobile,'check':'wrong manual password remains at login','passed':True})
            login(page,name,password,mobile)
            page.wait_for_function("Boolean(sessionStorage.getItem('burningchariot.hd.session') || localStorage.getItem('burningchariot.hd.session'))")
            page.wait_for_timeout(1500)
            checks.append({'mobile':mobile,'check':'manual button accepts correct credentials','passed':True})
            requests_seen.clear();page.reload(wait_until='domcontentloaded')
            stopped('refresh after successful login still requires manual login')
            args.report.parent.mkdir(parents=True,exist_ok=True)
            page.screenshot(path=str(args.report.parent/('manual-mobile.png' if mobile else 'manual-desktop.png')))
            login(page,name,password,mobile)
            checks.append({'mobile':mobile,'check':'manual login after refresh works','passed':True})
            context.close()
        assert not errors,errors
        result={'passed':True,'checks':checks,'engine_errors':errors,'real_mobile_hardware_tested':False}
        args.report.write_text(json.dumps(result,indent=2),encoding='utf8');print(json.dumps(result))
    finally:browser.close()
