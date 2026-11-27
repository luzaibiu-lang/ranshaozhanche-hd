"""Fault injection against real streamed packs, with an isolated Go room."""
import argparse,json,re,secrets,time
from pathlib import Path
import requests
from playwright.sync_api import sync_playwright
from qa_web_streaming import ROOT,EDGE,backend,local_site

p=argparse.ArgumentParser();p.add_argument('--web',type=Path,required=True);p.add_argument('--report',type=Path,required=True);args=p.parse_args()
entry=(args.web/'hd/play/index.html').read_text('utf8')
manifest_url=re.search(r'name="game-stream-manifest" content="([^"]+)"',entry)[1]
manifest=json.loads((args.web/manifest_url.lstrip('/')).read_text('utf8'))
traffic=[];errors=[];faults={'map_4':0,'map_5':0}
with backend(ROOT/'.tools/hdserver-current.exe') as upstream,local_site(args.web.resolve(),upstream,traffic) as origin,sync_playwright() as pw:
    auth=requests.post(upstream+'/api/register',json={'name':'qa_rec'+secrets.token_hex(3),'password':secrets.token_hex(10)},timeout=10).json()
    headers={'Authorization':'Bearer '+auth['token']}
    def command(action,**kw):
        r=requests.post(upstream+'/api/command',json={'action':action,**kw},headers=headers,timeout=10);r.raise_for_status();return r.json()
    browser=pw.chromium.launch(executable_path=str(EDGE),headless=True,args=['--mute-audio','--enable-unsafe-swiftshader'])
    context=browser.new_context(viewport={'width':1440,'height':900})
    context.add_init_script("sessionStorage.setItem('burningchariot.hd.session',"+json.dumps(auth['token'])+")")
    page=context.new_page();page.on('pageerror',lambda e:errors.append(str(e)))
    page.on('console',lambda m:errors.append(m.text) if m.type=='error' and 'ERROR:' in m.text else None)
    def intercept(key):
        def handle(route):
            faults[key]+=1
            if key=='map_4' and faults[key]==2:route.fulfill(status=200,body=b'incomplete pack')
            elif faults[key] <= (2 if key=='map_4' else 3):route.fulfill(status=503,body=b'temporary unavailable')
            else:route.continue_()
        return handle
    for key in faults:page.route('**'+manifest['groups'][key]['url'],intercept(key))
    try:
        page.goto(origin+'/hd/play/',wait_until='domcontentloaded')
        page.wait_for_selector('#status[hidden]',state='attached',timeout=120000)
        page.wait_for_timeout(2400);page.mouse.click(210,355);page.mouse.click(345,837);page.wait_for_timeout(1500)
        command('create',name='qa_recovery',map=4)
        page.wait_for_function("BurningChariotResourceState.loaded.includes('map_4') && BurningChariotResourceState.loaded.includes('battle_fx')",timeout=120000)
        assert faults['map_4']==3,faults
        command('settings',map=5)
        page.wait_for_function("BurningChariotResourceState.loaded.includes('map_5')",timeout=120000)
        assert faults['map_5']==4,faults
        command('bots',bots=[{'seat':i,'level':int(i==4),'vehicle':int(i==4)} for i in range(16)])
        command('start')
        page.wait_for_timeout(1800)
        assert not errors,errors
        used={r['path'] for r in traffic}
        assert manifest['groups']['map_12']['url'] not in used
        args.report.parent.mkdir(parents=True,exist_ok=True)
        page.screenshot(path=str(args.report.with_suffix('.png')))
        result={'passed':True,'fault_attempts':faults,'server_503_recovered':True,'corrupt_200_rejected':True,'all_attempts_failed_then_automatic_recovery':True,'unused_map_12_not_requested':True,'engine_errors':errors,'device':'headless Chromium actual WebAssembly and isolated Go'}
        args.report.write_text(json.dumps(result,indent=2),encoding='utf8');print(json.dumps(result))
    finally:browser.close()
