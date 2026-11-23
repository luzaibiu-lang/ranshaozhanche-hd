"""Compare Godot walking with original x86 fixtures on an inactive desktop."""
import argparse,json,pathlib,secrets
from private_desktop import run
ROOT=pathlib.Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--client',type=pathlib.Path);args=p.parse_args()
out=ROOT/('.tools/qa/walking-'+secrets.token_hex(4));out.mkdir(parents=True)
exe=args.client.resolve()/'Game.exe' if args.client else next(p for p in (ROOT/'.tools/godot').glob('*.exe') if not p.name.endswith('console.exe'))
command=[exe,'--audio-driver','Dummy']
if not args.client:command+=['--path',ROOT/'源码/client']
command+=['--script',ROOT/'源码/tools/walking_acceptance.gd','--','--fixture='+str(ROOT/'源码/server/testdata/native-walking-oracle.json'),'--output='+str(out)]
result=run(command,out/'acceptance.log',120)
log=(out/'acceptance.log').read_text('utf8',errors='replace')
assert result['exit_code']==0 and 'ERROR:' not in log and 'SCRIPT ERROR' not in log,log[-6000:]
report=json.loads((out/'report.json').read_text('utf8'));report.update(result)
(ROOT/'.tools/qa/walking-acceptance.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'passed':True,'checks':report['checks'],'original_cases':report['original_cases'],'evidence':str(out)},ensure_ascii=False))
