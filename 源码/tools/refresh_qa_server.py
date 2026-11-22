"""Build and refresh only the explicitly tracked local HD test process."""
import json
import pathlib
import subprocess
import time
import urllib.request
import psutil

ROOT = pathlib.Path(__file__).resolve().parents[2]
qa = ROOT/'.tools/qa'
qa.mkdir(parents=True,exist_ok=True)
binary = ROOT/'.tools/hdserver-current.exe'
pending = ROOT/'.tools/hdserver-next.exe'
subprocess.run(['go','build','-trimpath','-o',str(pending),'.'],cwd=ROOT/'源码/server',check=True,
               creationflags=subprocess.CREATE_NO_WINDOW)
pidfile = qa/'server.pid'
for process in psutil.process_iter(['exe','cmdline']):
    try:
        path=pathlib.Path(process.info['exe'] or '').resolve()
        command=process.info['cmdline'] or []
        if path.parent==ROOT/'.tools' and path.name in ('hdserver.exe','hdserver-current.exe') and '127.0.0.1:18280' in command:
            process.terminate();process.wait(10)
    except (psutil.NoSuchProcess,psutil.AccessDenied):pass
pending.replace(binary)
with (qa/'server.log').open('ab') as log:
    process=subprocess.Popen([str(binary),'--listen','127.0.0.1:18280','--data',str(qa/'server'),
                              '--assets',str(ROOT/'源码/client/assets')],stdout=log,stderr=log,
                              creationflags=subprocess.CREATE_NO_WINDOW)
pidfile.write_text(str(process.pid))
for _ in range(40):
    try:
        with urllib.request.urlopen('http://127.0.0.1:18280/health',timeout=1) as response:
            state=json.load(response)
            assert state['edition']=='hd'
            print(json.dumps(dict(qa_only=True,listen='127.0.0.1:18280',version=state['version'])))
            break
    except Exception:
        time.sleep(.15)
else:
    raise RuntimeError('Refreshed local QA server did not start')
