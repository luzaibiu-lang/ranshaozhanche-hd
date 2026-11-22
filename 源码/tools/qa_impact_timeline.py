"""Replay a real native Go shot through production Godot visuals without focus/audio."""
import argparse,json,pathlib,secrets,statistics
from private_desktop import run

ROOT=pathlib.Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--endpoint',default='http://127.0.0.1:18324');p.add_argument('--client',type=pathlib.Path);a=p.parse_args()
out=ROOT/('.tools/qa/impact-timeline-'+secrets.token_hex(4));out.mkdir(parents=True)
exe=a.client.resolve()/'Game.exe' if a.client else next(p for p in(ROOT/'.tools/godot').glob('*.exe')if not p.name.endswith('console.exe'))
arguments=[exe,'--audio-driver','Dummy']
if not a.client:arguments+=['--path',ROOT/'源码/client']
arguments+=['--script',ROOT/'源码/tools/impact_timeline_acceptance.gd','--','--output='+str(out),'--fixture='+str(ROOT/'.tools/qa/native-impact-fixture.json'),'--endpoint='+a.endpoint]
result=run(arguments,out/'acceptance.log',240)
log=(out/'acceptance.log').read_text('utf8',errors='replace')
handoff=ROOT/'.tools/qa/impact-handoff.md'
if result['exit_code']or'ERROR:'in log or'SCRIPT ERROR'in log:
 handoff.write_text('爆炸时间线 QA 未通过。\n\n证据目录：'+str(out)+'\n\n```text\n'+log[-6000:]+'\n```\n',encoding='utf8')
 raise RuntimeError(log[-6000:])
r=json.loads((out/'report.json').read_text('utf8'))
summary={}
for key in ['process_us','frame_wait_us','poll_us']:
 values=sorted(x[key]for x in r['timings'])
 summary[key]={'median':statistics.median(values),'p95':values[int(len(values)*.95)],'max':max(values),'max_tick':max(r['timings'],key=lambda x:x[key])['tick']}
summary['impact']=r['timings'][53]
summary['additional_texture_loads']=[x for x in r['timings']if x['new_textures']]
r['performance_summary']=summary;r['process']=result
(out/'report.json').write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf8')
handoff.write_text('爆炸时间线 QA 已通过。\n\n证据目录：'+str(out)+'\n\n检查数：'+str(len(r['checks']))+'；原版 mask：'+str(r['masks'])+'。\n\n'+json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
print(json.dumps({'passed':True,'checks':len(r['checks']),'native_masks':r['masks'],'evidence':str(out),'performance':summary},ensure_ascii=False))
