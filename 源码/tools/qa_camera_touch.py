"""Exercise map gestures and wider mouse borders on an inactive desktop."""
from pathlib import Path
import argparse,json
from private_desktop import run
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--client',type=Path);args=p.parse_args()
out=ROOT/'.tools/qa/release-0.2.3/camera';out.mkdir(parents=True,exist_ok=True)
exe=args.client.resolve()/'Game.exe' if args.client else next(x for x in (ROOT/'.tools/godot').glob('*.exe') if not x.name.endswith('console.exe'))
command=[exe,'--audio-driver','Dummy']
if not args.client:command+=['--path',ROOT/'源码/client']
command+=['--script',ROOT/'源码/tools/camera_touch_acceptance.gd','--',out]
result=run(command,out/'runtime.log',60);log=(out/'runtime.log').read_text('utf8')
assert result['exit_code']==0 and 'ERROR:' not in log,log
print((out/'report.json').read_text('utf8'))
