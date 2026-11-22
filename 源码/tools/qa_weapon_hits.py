"""Render all 90 damaging weapon timelines in the actual silent HD client."""
import argparse,json,pathlib,secrets
from PIL import Image,ImageDraw
from private_desktop import run
ROOT=pathlib.Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser();parser.add_argument('--client',type=pathlib.Path);args=parser.parse_args()
out=ROOT/('.tools/qa/weapon-hits-'+secrets.token_hex(4));out.mkdir(parents=True)
exe=args.client.resolve()/'Game.exe' if args.client else next(p for p in(ROOT/'.tools/godot').glob('*.exe')if not p.name.endswith('console.exe'))
arguments=[exe,'--audio-driver','Dummy']
if not args.client:arguments+=['--path',ROOT/'源码/client']
arguments+=['--script',ROOT/'源码/tools/weapon_hit_acceptance.gd','--','--output='+str(out),'--fixture='+str(ROOT/'.tools/qa/weapon-hit-matrix/native-hit-matrix.json')]
result=run(arguments,out/'acceptance.log',240)
log=(out/'acceptance.log').read_text('utf8',errors='replace')
assert not result['exit_code']and'ERROR:'not in log and'SCRIPT ERROR'not in log,log[-6000:]
r=json.loads((out/'report.json').read_text());assert len(r['weapons'])==90
for page in range(5):
 sheet=Image.new('RGB',(1536,1116),'#18283c');draw=ImageDraw.Draw(sheet)
 for index,row in enumerate(r['weapons'][page*18:page*18+18]):
  im=Image.open(out/row['image']).convert('RGB').resize((256,160))
  x=index%6*256;y=index//6*372
  # Full frame plus close impact crop allows both placement and crater review.
  sheet.paste(im,(x,y))
  close=Image.open(out/row['image']).convert('RGB').crop((420,420,900,700)).resize((256,149))
  sheet.paste(close,(x,y+160))
  draw.text((x+4,y+314),f'V{int(row["vehicle"]):02d} slot{int(row["slot"])} id{int(row["logical"])} damage{int(row["damage"])}',fill='white')
  draw.text((x+4,y+332),f'hits {row["impacts"]}, cuts {row["holes"]}, fall {row["fall_frames"]}',fill='white')
 sheet.save(out/f'contact-sheet-{page}.png')
r.update(result);(out/'report.json').write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'passed':True,'weapons':90,'checks':r['checks'],'evidence':str(out)},ensure_ascii=False))
