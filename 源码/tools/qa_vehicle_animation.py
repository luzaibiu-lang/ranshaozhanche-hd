"""Silent GPU animation acceptance, isolated from the interactive desktop."""
import json, pathlib
from PIL import Image
from private_desktop import run
ROOT=pathlib.Path(__file__).resolve().parents[2]
out=ROOT/'.tools/qa/vehicle-animation';out.mkdir(parents=True,exist_ok=True)
exe=next(p for p in (ROOT/'.tools/godot').glob('*.exe') if not p.name.endswith('console.exe'))
result=run([exe,'--audio-driver','Dummy','--path',ROOT/'源码/client','--script',ROOT/'源码/tools/vehicle_animation_acceptance.gd','--',out],out/'acceptance.log',120)
text=(out/'acceptance.log').read_text('utf8',errors='replace')
if result['exit_code'] or 'ERROR:' in text or 'SCRIPT ERROR' in text:raise RuntimeError(text[-5000:])
assert 'NATIVE_VEHICLE_ACCEPTANCE ' in text
frames=[Image.open(out/('vehicles-%02d.png'%i)).convert('RGB').resize((1200,750)) for i in range(36)]
assert len({image.tobytes() for image in frames})>20,'Rendered frames are static'
frames[0].save(out/'30-vehicles.gif',save_all=True,append_images=frames[1:],duration=100,loop=0)
(out/'report.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'passed':True,'frames':36,'vehicles':30,'private_desktop':True,'silent':True,'animation':str(out/'30-vehicles.gif')},ensure_ascii=False))
