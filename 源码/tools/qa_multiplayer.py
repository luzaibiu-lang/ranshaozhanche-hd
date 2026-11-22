"""Two real native clients, silent desktops, actual authoritative matches.

The controller supplies shots through the same authenticated commands as the
game. Both windows poll and render that match, click their own result button,
and enter the next match. No production/legacy data or game is accessed unless
the independent HD endpoint is explicitly selected.
"""
import argparse,concurrent.futures,json,math,pathlib,secrets,ssl,sys,time,requests,numpy as np,struct
from private_desktop import run
ROOT=pathlib.Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--endpoint',default='http://127.0.0.1:18280');p.add_argument('--release',action='store_true');p.add_argument('--client',type=pathlib.Path);p.add_argument('--full',action='store_true');args=p.parse_args()
qa=ROOT/'.tools/qa';session=requests.Session();session.trust_env=False
session.verify=str(ROOT/'源码/client/hd-public.crt') if args.endpoint.startswith('https:') else True
def api(path,token='',data=None):
 r=session.request('POST' if data is not None else 'GET',args.endpoint+path,headers={'Authorization':'Bearer '+token},json=data,timeout=15)
 result=r.json()
 if not r.ok:raise RuntimeError('%s %s'%(path,result))
 return result
suffix=secrets.token_hex(3);names=['qa_p'+suffix+'a','qa_p'+suffix+'b'];tokens=[]
for name in names:tokens.append(api('/api/register',data={'name':name,'password':'qa-only-895432'})['token'])
command=lambda i,data:api('/api/command',tokens[i],data)
state=command(0,{'action':'create','name':'HD完整联机验收','map':4,'capacity':8});room=state['room']['id']
command(1,{'action':'join','room':room})
bots=[{'seat':i,'level':3 if i in [8,12] else 0,'vehicle':1 if i==8 else 6 if i==12 else 0} for i in range(16)]
if args.full:
 roster={1:(1,23),5:(2,25),8:(3,26),9:(1,20),12:(2,6),13:(3,9)}
 bots=[{'seat':i,'level':roster.get(i,(0,0))[0],'vehicle':roster.get(i,(0,0))[1]} for i in range(16)]
command(0,{'action':'bots','bots':bots})
exe=ROOT/'客户端/燃烧战车 高清重制版/Game.exe' if args.release else next(p for p in (ROOT/'.tools/godot').glob('*.exe') if not p.name.endswith('console.exe'))
if args.client:
 assert args.client.resolve().is_relative_to(ROOT)
 exe=args.client.resolve()/'Game.exe'
prefixes=[qa/('pair-'+suffix+'-'+str(i)) for i in range(2)]
def launch(i):
 options=[exe,'--audio-driver','Dummy']
 if not args.release and not args.client:options+=['--path',ROOT/'源码/client']
 options+=['--','--qa','--qa-endpoint='+args.endpoint,'--qa-user='+names[i],'--qa-size=1366x768','--qa-session-script='+str(prefixes[i])]
 options+=['--qa-session-seconds='+str(840 if args.full else 540)]
 # Two full-room matches may each use the 360-second match budget. Native
 # fatal explosions are part of match time; do not kill the rendering clients
 # before their independent controller budgets have elapsed.
 return run(options,str(prefixes[i])+'.log',900 if args.full else 600)
def aim(b,actor,target):
 # Solve from the native muzzle and 60 Hz f32 trajectory. Keep this separate
 # from the Go planner; a playable match must pass with independent shots.
 data=(ROOT/('源码/client/assets/maps/%d/collision.bin'%b['map'])).read_bytes();width,height=struct.unpack_from('<II',data)
 terrain=np.frombuffer(data,dtype=np.uint8,offset=8).reshape(height,width).copy()
 for hole in b.get('holes',[]):
  mask_id=int(hole.get('mask',0))
  if mask_id:
   mask=json.loads((ROOT/'源码/client/assets/terrain-masks.json').read_text('utf8'))['masks'][mask_id-1]
   left,top=int(hole['x'])-mask['width']//2,int(hole['y'])-mask['height']//2
   for row,(first,last) in enumerate(mask['rows']):
    y=top+row
    if 0<=y<height and first>=0:terrain[y,max(0,left+first):min(width,left+last+1)]=0
   continue
  x,y,r=hole['x'],hole['y'],hole['r'];lo=max(0,int(y-r));hi=min(height,int(y+r)+1);lx=max(0,int(x-r));hx=min(width,int(x+r)+1)
  yy,xx=np.ogrid[lo:hi,lx:hx];section=terrain[lo:hi,lx:hx];section[(xx-x)**2+(yy-y)**2<=r*r]=0
 best=(-1e12,45,.6)
 for angle in range(10,171,5):
  rad=math.radians(angle);cx=math.cos(rad);sy=math.sin(rad)
  for power in np.arange(.18,1.001,.06):
   native=bool(b.get('native_aim'))
   if native:
    rad=(int(angle+.5)%360)*0.017453288659453392;cx=math.cos(rad);sy=math.sin(rad)
    family=(actor['vehicle']-1)%10;offset=[(-1,-22),(-2,-20),(5,-18),(4,-23),(2,-23),(-6,-19),(0,-25),(0,-20),(16,-24),(0,-20)][family]
    mount=math.trunc(math.degrees(math.atan2(-offset[1],offset[0])))
    if angle>90:mount=180-mount
    mr=(mount+actor.get('slope',0))*0.017453288659453392;distance=math.trunc(math.hypot(*offset));length=[18,15,6,10,10,23,5,15,15,15][family]
    x=np.float32(actor['x']+math.trunc(math.cos(mr)*distance+.5)+math.trunc(cx*length+.5))
    y=np.float32(actor['y']-math.trunc(math.sin(mr)*distance+.5)-math.trunc(sy*length+.5))
    raw_charge=math.floor(float(power)*300+.5);speed=math.floor((raw_charge/15+.0005)*1000)/1000
    vx=np.float32(math.floor((speed*cx+.0005)*1000)/1000);up=np.float32(math.floor((speed*sy+.0005)*1000)/1000)
    wind=math.floor((b['wind']/9.5+.05)*10)/10;acc=np.float32(math.floor((wind/100+.0005)*1000)/1000);drift=np.float32(0)
   else:x=actor['x']+cx*22;y=actor['y']-22-sy*16;vx=cx*620*power;vy=-sy*620*power
   for tick in range(1100):
    if native:drift+=acc;x+=vx+drift;y-=up;up-=np.float32(.18)
    else:vx+=b['wind']*1.25/90;vy+=180/90;x+=vx/90;y+=vy/90
    if not 0<=x<width or y>=height:break
    if native:
     ix,iy=int(x+.5),int(y+.5);hit=iy>=-5 and iy<height+5 and bool(terrain[max(0,iy-5):min(height,iy+6),max(0,ix-5):min(width,ix+6)].any())
     hit=hit or any(u['hp']>0 and int(math.hypot(float(x)-u['x'],float(y)-u['y']))<15 for u in b['units'])
    else:
     hit=y>=0 and terrain[int(y),int(x)]!=0
     if tick>10:hit=hit or any(u['hp']>0 and u['seat']!=actor['seat'] and math.hypot(u['x']-x,u['y']-18-y)<17 for u in b['units'])
    if hit:
     score=1000-math.hypot(x-target['x'],y-target['y']+15)
     score-=sum(max(0,55-math.hypot(x-u['x'],y-u['y']+15))*30 for u in b['units'] if u['hp']>0 and u['team']==actor['team'])
     if score>best[0]:best=(score,angle,float(power))
     break
 return best[1:]
report={'endpoint':args.endpoint,'release':bool(args.release or args.client),'full_room':args.full,'names':names,'matches':[],'sync_samples':0,'max_poll_seconds':0}
pool=concurrent.futures.ThreadPoolExecutor(2);futures=[pool.submit(launch,i) for i in range(2)]
try:
 until=time.monotonic()+45
 while not all(pathlib.Path(str(x)+'.ready').exists() for x in prefixes):
  if time.monotonic()>until or any(f.done() for f in futures):raise RuntimeError('Native clients did not reach the room')
  time.sleep(.2)
 for match,map_id in enumerate([4,9]):
  command(0,{'action':'settings','map':map_id});command(0,{'action':'vehicle','vehicle':1 if match==0 else 30})
  command(1,{'action':'vehicle','vehicle':1 if match==0 else 26})
  command(0,{'action':'start'});started=time.monotonic();deadline=started+360 if args.full else started+240;turns=set();final=None;progress=-1
  while time.monotonic()<deadline:
   before=time.monotonic();a=api('/api/state',tokens[0]);b=api('/api/state',tokens[1]);report['max_poll_seconds']=max(report['max_poll_seconds'],time.monotonic()-before)
   if a['version']==b['version']:
    assert a['room']==b['room'],'Same-version clients received different room state';report['sync_samples']+=1
   if a.get('room') is None or b.get('room') is None:raise RuntimeError('A native test client left the room before the controller finished both matches')
   battle=a['room']['battle']
   elapsed=int(time.monotonic()-started)
   if elapsed//30>progress:
    progress=elapsed//30;print(json.dumps({'map':map_id,'seconds':elapsed,'round':battle['round'],'generation':battle['generation'],'alive':sum(u['hp']>0 for u in battle['units']),'human_actions':len(turns)},ensure_ascii=False),flush=True)
   if args.full:assert len(battle['units'])==8,'Full room lost participants'
   if battle.get('result'):
    final=battle;break
   active=next(u for u in battle['units'] if u['seat']==battle['active'])
   if battle['deadline']>0 and active['player']>0 and battle['generation'] not in turns:
    index=0 if active['player']==a['profile']['id'] else 1
    enemies=[u for u in battle['units'] if u['hp']>0 and u['team']!=active['team']]
    if not enemies:time.sleep(.1);continue
    target=min(enemies,key=lambda u:abs(u['x']-active['x']));angle,power=aim(battle,active,target)
    # Basic weapon remains free; original loadout/terrain decides the result.
    command(index,{'action':'fire','angle':angle,'power':power,'weapon':0,'generation':battle['generation']});turns.add(battle['generation'])
   time.sleep(.25)
  if final is None:raise RuntimeError('Multiplayer match failed to settle')
  report['matches'].append({'map':map_id,'rounds':final['round'],'human_actions':len(turns),'result':final['result']})
  wait_until=time.monotonic()+20
  while True:
   states=[api('/api/state',token) for token in tokens]
   if all(s['room'] and s['room']['battle'] is None for s in states):break
   if time.monotonic()>wait_until:raise RuntimeError('Native result buttons failed to return both clients')
   time.sleep(.25)
  if match==1:break
finally:
 for prefix in prefixes:pathlib.Path(str(prefix)+'.finish').write_text('done')
 for i,future in enumerate(futures):
  result=future.result(timeout=30);report['client_'+str(i)]=result
  log=pathlib.Path(str(prefixes[i])+'.log').read_text('utf8',errors='replace')
  if result['exit_code'] or 'SCRIPT ERROR' in log or 'ERROR:' in log:raise RuntimeError(log[-5000:])
 pool.shutdown()
(qa/'multiplayer-acceptance.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(report,ensure_ascii=False))
