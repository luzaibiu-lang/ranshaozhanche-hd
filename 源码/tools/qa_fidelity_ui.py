import argparse, json, pathlib, secrets
from private_desktop import run
ROOT=pathlib.Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--endpoint',required=True);p.add_argument('--client',type=pathlib.Path);p.add_argument('--scenario',choices=['interface','social','items','supplies','return'],default='interface');p.add_argument('--nonbattle',action='store_true');a=p.parse_args()
out=ROOT/('.tools/qa/fidelity-ui-'+secrets.token_hex(4));out.mkdir(parents=True)
exe=a.client/'Game.exe' if a.client else next(p for p in (ROOT/'.tools/godot').glob('*.exe') if not p.name.endswith('console.exe'))
args=[exe,'--audio-driver','Dummy']
if not a.client:args+=['--path',ROOT/'源码/client']
script={'interface':'fidelity_ui_acceptance.gd','social':'room_social_acceptance.gd','return':'room_social_acceptance.gd','items':'item_ui_acceptance.gd','supplies':'item_ui_acceptance.gd'}[a.scenario]
args+=['--script',ROOT/'源码/tools'/script,'--','--qa-endpoint='+a.endpoint,'--profile='+str(out/'profile'),'--name=qa_fid'+secrets.token_hex(3),'--output='+str(out)]
if a.nonbattle:args+=['--nonbattle=true']
if a.scenario=='supplies':args+=['--supplies=true']
if a.scenario=='return':args+=['--return-test=true']
result=run(args,out/'acceptance.log',150)
text=(out/'acceptance.log').read_text('utf8',errors='replace')
if result['exit_code'] or 'ERROR:' in text or 'SCRIPT ERROR' in text:raise RuntimeError(str(out)+'\n'+text[-5000:])
markers=[s.removeprefix('FIDELITY_UI_ACCEPTANCE ') for s in text.splitlines() if s.startswith('FIDELITY_UI_ACCEPTANCE ')]
assert len(markers)==1,text[-4000:]
report=json.loads(markers[0]);report.update(result)
(ROOT/('.tools/qa/'+('client-flow' if a.nonbattle else {'interface':'fidelity-ui','social':'social-ui','return':'return-ui','items':'item-ui','supplies':'supply-ui'}[a.scenario])+'-acceptance.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'passed':True,'checks':len(report['checks']),'evidence':str(out)},ensure_ascii=False))
