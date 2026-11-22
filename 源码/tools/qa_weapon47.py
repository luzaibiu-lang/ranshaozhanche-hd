"""Check the actual native47 canvas variant silently on an inactive desktop."""
import pathlib,json
from PIL import Image
from private_desktop import run
ROOT=pathlib.Path(__file__).resolve().parents[2]
out=ROOT/'.tools/qa/weapon47';out.mkdir(parents=True,exist_ok=True)
exe=next(p for p in(ROOT/'.tools/godot').glob('*.exe')if not p.name.endswith('console.exe'))
result=run([exe,'--audio-driver','Dummy','--path',ROOT/'源码/client','--script',ROOT/'源码/tools/weapon47_render_acceptance.gd','--',out/'projectiles.png'],out/'render.log',90)
text=(out/'render.log').read_text('utf8',errors='replace')
assert result['exit_code']==0 and 'ERROR:'not in text and 'SCRIPT ERROR'not in text and 'NATIVE47_RENDERED'in text,text[-5000:]
image=Image.open(out/'projectiles.png').convert('RGB')
counts=[]
for cx in [240,720]:
 crop=image.crop((cx-95,390-65,cx+95,390+65))
 green=sum(g>100 and g>r*1.4 and g>b*1.4 for r,g,b in crop.getdata())
 assert green>300,green
 counts.append(green)
report=dict(result,native_projectile=47,sprite='New/Weapon44.spr',additive_frame=1,opaque_frame=1,green_pixels_left_right=counts,passed=True)
(out/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(report,ensure_ascii=False))
