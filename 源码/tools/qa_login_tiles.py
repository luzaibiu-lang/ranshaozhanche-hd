"""Render the real tile login on an inactive desktop, including mouse input."""
from pathlib import Path
import argparse,json
from private_desktop import run
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--client',type=Path);args=p.parse_args()
out=ROOT/'.tools/qa/login-023';out.mkdir(parents=True,exist_ok=True)
if args.client:
 command=[args.client.resolve()/'Game.exe','--audio-driver','Dummy']
else:
 engine=next(x for x in (ROOT/'.tools/godot').glob('*.exe') if not x.name.endswith('console.exe'))
 command=[engine,'--audio-driver','Dummy','--path',ROOT/'源码/client']
command+=['--script',ROOT/'源码/tools/login_tiles_acceptance.gd','--','--output='+str(out)]
result=run(command,out/'tiles.log',80)
log=(out/'tiles.log').read_text('utf8')
assert result['exit_code']==0 and 'ERROR:' not in log,log
print(json.dumps(json.loads((out/'tiles-report.json').read_text('utf8')),ensure_ascii=False))
