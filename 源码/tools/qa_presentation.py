import argparse,json,pathlib,secrets
from PIL import Image
from private_desktop import run
ROOT=pathlib.Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--client',type=pathlib.Path,required=True);p.add_argument('--endpoint',required=True);a=p.parse_args()
out=ROOT/('.tools/qa/presentation-'+secrets.token_hex(4));out.mkdir(parents=True)
result=run([a.client.resolve()/'Game.exe','--audio-driver','Dummy','--script',ROOT/'源码/tools/presentation_acceptance.gd','--','--endpoint='+a.endpoint,'--output='+str(out)],out/'acceptance.log',90)
content=(out/'acceptance.log').read_text('utf8',errors='replace')
assert result['exit_code']==0 and 'ERROR:'not in content and 'SCRIPT ERROR'not in content,content[-5000:]
lines=[x.removeprefix('PRESENTATION_ACCEPTANCE ')for x in content.splitlines()if x.startswith('PRESENTATION_ACCEPTANCE ')]
assert len(lines)==1,content[-2000:]
report=json.loads(lines[0]);report.update(result);(out/'report.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf8')
def blue_halves(path):
    image=Image.open(path).convert('RGB');scale=768/600
    left=1366/2-138*scale;top=768-51*scale
    counts=[]
    for low,high in [(2,49),(52,99)]:
        crop=image.crop((int(left+low*scale),int(top+2*scale),int(left+high*scale),int(top+8*scale)))
        counts.append(sum(b>r*1.5 and b>g*1.1 and b>70 for r,g,b in crop.getdata()))
    return counts
positive=blue_halves(out/'aim-wind-35.png');negative=blue_halves(out/'aim-wind--35.png');zero=blue_halves(out/'aim-wind-0.png')
assert positive[1]>positive[0]+100,positive
assert negative[0]>negative[1]+100,negative
assert sum(zero)<50,zero
report['wind_rendered_pixel_checks']={'positive_left_right':positive,'negative_left_right':negative,'zero_left_right':zero}
(out/'report.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf8')
(ROOT/'.tools/qa/presentation-acceptance.json').write_text(json.dumps({'checks':len(report['checks']),'evidence':str(out),'passed':True}),encoding='utf8')
print(json.dumps({'checks':len(report['checks']),'passed':True,'evidence':str(out)},ensure_ascii=False))
