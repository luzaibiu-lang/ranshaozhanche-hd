"""Drive only the launcher windows on their own inactive Windows desktop."""
import argparse, json, os, pathlib, secrets, shutil, time
import psutil, requests
from private_desktop import run

ROOT=pathlib.Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--client',type=pathlib.Path,required=True);p.add_argument('--endpoint',required=True);p.add_argument('--old-host',type=pathlib.Path);p.add_argument('--publication',type=pathlib.Path,default=ROOT/'.tools/qa/updates-013');a=p.parse_args()
source=a.client.resolve();assert source.is_relative_to(ROOT)
out=ROOT/('.tools/qa/launcher-'+secrets.token_hex(4));out.mkdir(parents=True)
client=out/'client';shutil.copytree(source,client)
(client/'connection.json').write_text(json.dumps({'endpoint':a.endpoint,'edition':'hd'}),encoding='utf8')
profile=out/'profile';profile.mkdir();proof=out/'game-proof.json'
os.environ.update(LOCALAPPDATA=str(profile),BCHD_VAULT_ROOT=str(profile/'BurningChariotHD'),BCHD_QA_SILENT='1',BCHD_QA_PROOF=str(proof))
session=requests.Session();session.trust_env=False
manifest=json.loads((client/'manifest.json').read_text('utf8'))
# The isolated development service serves this exact verified candidate.
name='qa_launch'+secrets.token_hex(3);password='qa-only-895432';checks=[];failures=[]
def wait(predicate,seconds=30):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  value=predicate()
  if value:return value
  time.sleep(.08)
 raise TimeoutError('Launcher UI did not reach expected state')

def stop_owned_game():
 for process in psutil.process_iter(['exe']):
  try:
   if process.info['exe']and pathlib.Path(process.info['exe']).resolve()==(client/'Game.exe').resolve():process.terminate();process.wait(10)
  except psutil.NoSuchProcess:pass

fixture=a.publication.resolve()
assert fixture.is_relative_to(ROOT/'.tools/qa')
assert fixture.exists(),'Prepare the explicit loopback publication fixture first'
original=(fixture/'manifest.json').read_bytes()
connection=client/'connection.json'
import hashlib
entry=next(f for f in manifest['files']if f['path']=='connection.json')
entry.update(size=connection.stat().st_size,sha256=hashlib.sha256(connection.read_bytes()).hexdigest())
entry['url']='blobs/'+entry['sha256']
shutil.copy2(connection,fixture/'blobs'/entry['sha256'])
(fixture/'manifest.json').write_text(json.dumps(manifest),encoding='utf8')
config=out/'controls.json'
try:
 for stage in ['register','resume','bad-password']+(['upgrade']if a.old_host else[]):
  if proof.exists():proof.unlink()
  target_name=name+'u'if stage=='upgrade'else name
  if stage=='upgrade':
   assert a.old_host.resolve().is_relative_to(ROOT)
   shutil.copy2(a.old_host,client/'LauncherHost.exe')
  controls={'stage':'register'if stage=='upgrade'else stage,'name':target_name,'password':'intentionally-wrong'if stage=='bad-password'else password,'output':str(out)}
  config.write_text(json.dumps(controls),encoding='utf8')
  result=run([client/'燃烧战车.exe','--launcher-qa='+str(config)],out/('launcher-'+stage+'.log'),90)
  assert result['exit_code']==0,(result,(out/'launcher-error.txt').read_text('utf8')if(out/'launcher-error.txt').exists()else'')
  shutil.copy2(out/'launcher-login.png',out/('launcher-'+stage+'.png'))
  if stage=='bad-password':
   error=json.loads((out/'expected-error.json').read_text('utf-8-sig'))
   assert error['enabled']and '错误'in error['message'],error
   assert not proof.exists()
   checks.append('incorrect password stays in launcher and enables retry')
  else:
   wait(lambda:proof.exists(),40)
   value=json.loads(proof.read_text('utf8'));assert value['scene']=='channel'and value['username']==target_name,value
   shutil.copy2(proof,out/('proof-'+stage+'.json'));shutil.copy2(str(proof)+'.png',out/('game-'+stage+'.png'))
   checks.append('real launcher '+stage+' enters the channel chooser without second login')
   assert not list((profile/'BurningChariotHD/handoff').glob('*.dat'))
   assert (profile/'BurningChariotHD/session.dat').exists()
   stop_owned_game()
   if stage=='upgrade':
    assert hashlib.sha256((client/'LauncherHost.exe').read_bytes()).hexdigest()==next(f['sha256']for f in manifest['files']if f['path']=='LauncherHost.exe')
    checks.append('running launcher exits before bootstrap replaces it, then authenticated game starts')
 checks.extend(['encrypted one-use token handoff','source-themed launcher rendered','remembered token saved with Windows DPAPI'])
finally:
 (fixture/'manifest.json').write_bytes(original)
 stop_owned_game()
report={'passed':True,'private_desktop':True,'silent':True,'checks':checks,'evidence':str(out)}
(out/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8');print(json.dumps(report,ensure_ascii=False))
