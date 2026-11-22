"""GPU acceptance of energy alpha, continuous fire, UFO columns and fatal blasts."""
import argparse,json,pathlib,secrets
from private_desktop import run
ROOT=pathlib.Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--client',type=pathlib.Path);a=p.parse_args()
out=ROOT/('.tools/qa/skill-visuals-'+secrets.token_hex(4));out.mkdir(parents=True)
exe=a.client.resolve()/'Game.exe' if a.client else next(p for p in (ROOT/'.tools/godot').glob('*.exe')if not p.name.endswith('console.exe'))
command=[exe,'--audio-driver','Dummy']
if not a.client:command+=['--path',ROOT/'源码/client']
command+=['--script',ROOT/'源码/tools/skill_visual_acceptance.gd','--',out]
result=run(command,out/'acceptance.log',180)
log=(out/'acceptance.log').read_text('utf8',errors='replace')
assert result['exit_code']==0 and 'ERROR:'not in log and 'SCRIPT ERROR'not in log,log[-7000:]
report=json.loads(next(v.removeprefix('SKILL_VISUAL_ACCEPTANCE ')for v in log.splitlines()if v.startswith('SKILL_VISUAL_ACCEPTANCE ')))
report.update(result,evidence=str(out))
(out/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'passed':True,'checks':len(report['checks']),'evidence':str(out)},ensure_ascii=False))
