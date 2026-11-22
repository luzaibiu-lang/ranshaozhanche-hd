import argparse,json,pathlib,subprocess,sys,time,urllib.request,ssl
from private_desktop import run

ROOT=pathlib.Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--scene',default='battle');p.add_argument('--size',default='1600x1000');p.add_argument('--map',default='1');p.add_argument('--check-layout',action='store_true');p.add_argument('--release',action='store_true');p.add_argument('--release-dir',type=pathlib.Path);p.add_argument('--endpoint');p.add_argument('--shot',action='store_true');p.add_argument('--wait',default='2');args=p.parse_args()
qa=ROOT/'.tools/qa';qa.mkdir(parents=True,exist_ok=True)
endpoint=args.endpoint or 'http://127.0.0.1:18280'
context=ssl.create_default_context(cafile=str(ROOT/'源码/client/hd-public.crt')) if endpoint.startswith('https:') else None
handlers=[urllib.request.ProxyHandler({})]
if context:handlers.append(urllib.request.HTTPSHandler(context=context))
opener=urllib.request.build_opener(*handlers)
try:
    with opener.open(endpoint+'/health',timeout=8) as response:assert json.load(response)['edition']=='hd'
except Exception:
    if args.endpoint:raise
    log=(qa/'server.log').open('ab')
    binary=ROOT/'.tools/hdserver-current.exe'
    if not binary.exists():binary=ROOT/'.tools/hdserver.exe'
    process=subprocess.Popen([str(binary),'--listen','127.0.0.1:18280','--data',str(qa/'server'),'--assets',str(ROOT/'源码/client/assets')],stdout=log,stderr=log,creationflags=subprocess.CREATE_NO_WINDOW)
    (qa/'server.pid').write_text(str(process.pid))
    for _ in range(40):
        try:
            with opener.open(endpoint+'/health',timeout=1) as response:assert json.load(response)['edition']=='hd'
            break
        except Exception:time.sleep(.15)
    else:raise RuntimeError('Isolated HD QA server failed to start')
exe=next(p for p in (ROOT/'.tools/godot').glob('*.exe') if not p.name.endswith('console.exe'))
if args.release:exe=ROOT/'客户端/燃烧战车 高清重制版/Game.exe'
if args.release_dir:exe=args.release_dir.resolve()/'Game.exe'
image=qa/(args.scene+'-'+args.size+'.png');log=qa/(args.scene+'-'+args.size+'.log')
arguments=[exe,'--audio-driver','Dummy']
if not args.release and not args.release_dir:arguments+=['--path',ROOT/'源码/client']
arguments+=['--','--qa','--qa-endpoint='+endpoint,'--qa-scene='+args.scene,'--qa-size='+args.size,'--qa-map='+args.map,'--qa-screenshot='+str(image)]
arguments.append('--qa-wait='+args.wait)
if args.shot:arguments.append('--qa-shot=true')
if args.check_layout:arguments.append('--qa-check-layout=true')
result=run(arguments,log,120)
content=log.read_text('utf8',errors='replace');errors=[line for line in content.splitlines() if 'ERROR' in line or '   at:' in line or line.startswith('{')]
result.update(screenshot=str(image),messages=errors)
print(json.dumps(result,ensure_ascii=False));sys.exit(1 if result['exit_code'] or any('ERROR' in e for e in errors) else 0)
