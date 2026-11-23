"""Render original inventory/radar geometry and combat fixes without user input or audio."""
import argparse,json,pathlib,secrets,urllib.request
from PIL import Image
from private_desktop import run
ROOT=pathlib.Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--client',type=pathlib.Path);p.add_argument('--endpoint',default='http://127.0.0.1:18280');a=p.parse_args()
out=ROOT/('.tools/qa/feedback-alignment-'+secrets.token_hex(4));out.mkdir(parents=True)
with urllib.request.urlopen(a.endpoint+'/api/catalog',timeout=10) as response:catalog=json.load(response)
(out/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False),encoding='utf8')
exe=a.client.resolve()/'Game.exe' if a.client else next(p for p in (ROOT/'.tools/godot').glob('*.exe') if not p.name.endswith('console.exe'))
args=[exe,'--audio-driver','Dummy']
if not a.client:args+=['--path',ROOT/'源码/client']
args+=['--script',ROOT/'源码/tools/feedback_alignment_acceptance.gd','--','--catalog='+str(out/'catalog.json'),'--output='+str(out)]
r=run(args,out/'acceptance.log',100);log=(out/'acceptance.log').read_text('utf8',errors='replace')
assert r['exit_code']==0 and 'ERROR:' not in log and 'SCRIPT ERROR' not in log,str(out)+'\n'+log[-6000:]
report=json.loads((out/'report.json').read_text('utf8'));report.update(r,evidence=str(out))
# The opaque grey ring backing must match the source panel exactly.
source=Image.open(ROOT/'源码/client/assets/icons/Shop/04.png').convert('RGB')
ability=Image.open(ROOT/'源码/client/assets/icons/AbilityInfo/00.png').convert('RGB')
for vehicle in [0,1,13,23,30]:
 image=Image.open(out/f'radar-{vehicle}.png').convert('RGB')
 count=0
 for y in range(93):
  for x in range(93):
   color=ability.getpixel((x,y))
   if max(color)-min(color)<9 and sum(color)>135:
    expected=source.getpixel((34+x,17+y));actual=image.getpixel((34+x,17+y))
    assert max(abs(u-v) for u,v in zip(expected,actual))<3,(vehicle,x,y,expected,actual)
    count+=1
 assert count>400
report['radar_backing_pixel_checks']=count*5
for target in [out/'report.json',ROOT/'.tools/qa/feedback-alignment-acceptance.json']:target.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'passed':True,'checks':len(report['checks']),'pixel_checks':count*5,'evidence':str(out)},ensure_ascii=False))
