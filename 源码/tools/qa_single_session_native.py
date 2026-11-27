"""Actual Windows release is replaced by a real browser login, silently."""
import argparse,concurrent.futures,json,secrets,time,tempfile
from pathlib import Path
import requests
from playwright.sync_api import sync_playwright
from qa_web_streaming import ROOT,EDGE,backend,local_site
from qa_manual_auth import login
from private_desktop import run
p=argparse.ArgumentParser();p.add_argument('--client',type=Path,required=True);p.add_argument('--web',type=Path,required=True);p.add_argument('--server',type=Path,required=True);p.add_argument('--report',type=Path,required=True);args=p.parse_args()
args.report.parent.mkdir(parents=True,exist_ok=True)
with backend(args.server.resolve()) as upstream,local_site(args.web.resolve(),upstream,[]) as origin,tempfile.TemporaryDirectory() as temp,concurrent.futures.ThreadPoolExecutor(1) as pool:
    scratch=Path(temp);fixture={'name':'qa_win'+secrets.token_hex(3),'password':secrets.token_hex(10)}
    http=requests.Session();http.trust_env=False
    http.post(upstream+'/api/register',json=fixture,timeout=10).raise_for_status()
    (scratch/'fixture.json').write_text(json.dumps(fixture),encoding='utf8')
    ready=scratch/'ready.json'
    future=pool.submit(run,[args.client.resolve()/'Game.exe','--audio-driver','Dummy','--script',ROOT/'源码/tools/single_session_native_acceptance.gd','--','--qa-endpoint='+upstream,'--fixture='+str(scratch/'fixture.json'),'--profile='+str(scratch/'profile'),'--ready='+str(ready),'--output='+str(args.report.parent.resolve())],args.report.with_suffix('.log'),140)
    deadline=time.monotonic()+40
    while not ready.exists():
        if future.done():raise AssertionError(args.report.with_suffix('.log').read_text('utf8'))
        assert time.monotonic()<deadline,'Windows UI did not reach QA room'
        time.sleep(.15)
    room=json.loads(ready.read_text('utf8'))['room']
    with sync_playwright() as pw:
        browser=pw.chromium.launch(executable_path=str(EDGE),headless=True,args=['--mute-audio','--enable-unsafe-swiftshader'])
        page=browser.new_page(viewport={'width':844,'height':390})
        try:
            page.goto(origin+'/hd/play/',wait_until='domcontentloaded');page.wait_for_selector('#status[hidden]',state='attached',timeout=120000);page.wait_for_timeout(1600)
            current=login(page,fixture['name'],fixture['password']).json()['token']
            result=future.result(timeout=25)
            log=args.report.with_suffix('.log').read_text('utf8');assert result['exit_code']==0 and 'ERROR' not in log,log
            state=http.get(upstream+'/api/state',headers={'Authorization':'Bearer '+current},timeout=10).json()
            assert state['room']['id']==room,'Closing replaced Windows game removed the browser player'
            report=json.loads((args.report.parent/'native-result.json').read_text('utf8'));report['new_browser_session_kept_room_after_old_windows_exit']=True
            args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8');print(json.dumps(report))
        finally:browser.close()
