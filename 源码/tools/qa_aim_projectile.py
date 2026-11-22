"""Pixel-check native shell direction and render actual reticles without focus/audio."""
import json,pathlib,secrets
from PIL import Image,ImageDraw,ImageChops,ImageStat
from private_desktop import run

ROOT=pathlib.Path(__file__).resolve().parents[2]
out=ROOT/('.tools/qa/aim-projectile-'+secrets.token_hex(4));out.mkdir(parents=True)
exe=next(p for p in (ROOT/'.tools/godot').glob('*.exe')if not p.name.endswith('console.exe'))
result=run([exe,'--audio-driver','Dummy','--path',ROOT/'源码/client','--script',ROOT/'源码/tools/aim_projectile_acceptance.gd','--',out],out/'acceptance.log',180)
log=(out/'acceptance.log').read_text('utf8',errors='replace')
assert not result['exit_code'] and 'ERROR:'not in log and 'SCRIPT ERROR'not in log,log[-6000:]
report=json.loads(next(line.removeprefix('AIM_PROJECTILE_ACCEPTANCE ')for line in log.splitlines()if line.startswith('AIM_PROJECTILE_ACCEPTANCE ')))
directions=[(1,0),(0,-1),(-1,0),(0,1)]
pixels=[]
for layer in ['core','halo']:
 im=Image.open(out/f'projectiles-{layer}.png').convert('RGB')
 background=im.getpixel((0,0))
 for row,id in [(0,1),(1,2),(3,18),(5,101)]:
  for column,(dx,dy)in enumerate(directions):
   cx,cy=200+400*column,140+170*row
   weight=projection=0
   for y in range(cy-80,cy+81):
    for x in range(cx-105,cx+106):
     color=im.getpixel((x,y));contrast=sum(abs(a-b)for a,b in zip(color,background))
     if contrast<35:continue
     weight+=contrast;projection+=((x-cx)*dx+(y-cy)*dy)*contrast
   assert weight>0,(layer,id,column)
   center=projection/weight
   assert center>8 if layer=='core'else center<-2,(layer,id,column,center)
   pixels.append({'layer':layer,'projectile':id,'direction':column,'projected_centroid':round(center,3)})
report.update(result);report['pixel_checks']=pixels
spin_checks=[]
for page,ids in enumerate([[5,16,17,20,21,28],[29,59,60,82]]):
 im=Image.open(out/f'projectiles-spin-{page}.png').convert('RGB')
 for row,id in enumerate(ids):
  cy=140+row*170
  reference=im.crop((200-105,cy-80,200+106,cy+81))
  assert ImageStat.Stat(reference).stddev[0]>1,('empty spin render',id)
  for col in range(1,4):
   cx=200+col*400
   actual=im.crop((cx-105,cy-80,cx+106,cy+81))
   error=max(ImageStat.Stat(ImageChops.difference(reference,actual)).mean)
   assert error<.1,('spin must be independent of flight direction',id,col,error)
   spin_checks.append({'projectile':id,'direction':col,'mean_pixel_difference':error})
report['native_spin_pixel_checks']=spin_checks
sheet=Image.new('RGB',(1200,700),'#18283c');draw=ImageDraw.Draw(sheet)
for index,shot in enumerate(report['reticle_snapshots']):
 id=shot['vehicle'];face='right'if shot['face']>0 else 'left'
 im=Image.open(out/f'aim-{id:02d}-{face}.png').crop((510,315,1090,665)).resize((240,140))
 x=index%5*240;y=index//5*175
 center=[round(v,3)for v in shot['center']]
 sheet.paste(im,(x,y));draw.text((x+6,y+143),f'vehicle {id}, {face}, mount {center}',fill='white')
sheet.save(out/'reticle-mount-contact-sheet.png')
(out/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'passed':True,'checks':len(report['checks']),'pixel_checks':len(pixels)+len(spin_checks),'evidence':str(out)},ensure_ascii=False))
