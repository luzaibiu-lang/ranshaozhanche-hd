import argparse,json,pathlib,secrets
from PIL import Image
from private_desktop import run
ROOT=pathlib.Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--endpoint',default='http://127.0.0.1:18327');p.add_argument('--client',type=pathlib.Path);a=p.parse_args()
out=ROOT/('.tools/qa/controls-'+secrets.token_hex(4));out.mkdir(parents=True)
exe=a.client.resolve()/'Game.exe'if a.client else next(p for p in(ROOT/'.tools/godot').glob('*.exe')if not p.name.endswith('console.exe'))
args=[exe,'--audio-driver','Dummy']
if not a.client:args+=['--path',ROOT/'源码/client']
args+=['--script',ROOT/'源码/tools/control_acceptance.gd','--','--qa-endpoint='+a.endpoint,'--name=qa_ctrl'+secrets.token_hex(3),'--output='+str(out)]
r=run(args,out/'acceptance.log',120);log=(out/'acceptance.log').read_text('utf8',errors='replace')
assert not r['exit_code']and'ERROR:'not in log and'SCRIPT ERROR'not in log,str(out)+'\n'+log[-6000:]
report=json.loads((out/'report.json').read_text('utf8'));report.update(r,evidence=str(out));(out/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
image=Image.open(out/'power-half.png').convert('RGB');width,height=image.size;scale=min(width/800,height/600)
x=width/2-138*scale;y=height-28*scale
crop=image.crop((int(x),int(y),int(x+300*scale),int(y+15*scale)))
columns=sum(any(crop.getpixel((cx,cy))[0]>120 and crop.getpixel((cx,cy))[0]>crop.getpixel((cx,cy))[1]*1.6 for cy in range(crop.height))for cx in range(crop.width))
fraction=columns/crop.width;assert .43<fraction<.58,('native red power bar does not match half charge',fraction)
report['power_render_pixels']={'red_fill_fraction':fraction,'matches_native_half_charge':True};(out/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
(ROOT/'.tools/qa/controls-acceptance.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'passed':True,'checks':len(report['checks']),'evidence':str(out)},ensure_ascii=False))
