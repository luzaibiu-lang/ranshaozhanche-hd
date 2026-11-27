"""Real registration, remembering and channel transition on an inactive desktop."""
from pathlib import Path
import argparse,secrets,json,os,subprocess
import requests
from private_desktop import run
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--client',type=Path,required=True);args=p.parse_args()
out=ROOT/'.tools/qa/login-022/flow';out.mkdir(parents=True,exist_ok=True)
profile=out/('profile-'+secrets.token_hex(3));name='qa_l'+secrets.token_hex(3)
reports=[]
for stage in ['register','remembered','forgotten','handoff']:
 ticket=''
 if stage=='handoff':
  response=requests.post('http://127.0.0.1:18280/api/login',json={'name':name,'password':'qa-联机-895432'},timeout=10);response.raise_for_status();token=response.json()['token']
  vault=profile/'vault';vault.mkdir(parents=True,exist_ok=True)
  subprocess.run([str(args.client.resolve()/'Vault.exe'),'write'],input=token+'\n',text=True,encoding='utf8',capture_output=True,check=True,creationflags=subprocess.CREATE_NO_WINDOW,env={**os.environ,'BCHD_VAULT_ROOT':str(vault)})
  ticket=secrets.token_hex(16);(vault/'handoff').mkdir(exist_ok=True);(vault/'session.dat').replace(vault/'handoff'/(ticket+'.dat'))
 command=[args.client.resolve()/'Game.exe','--audio-driver','Dummy','--script',ROOT/'源码/tools/login_page_acceptance.gd','--','--qa-endpoint=http://127.0.0.1:18280','--name='+name,'--profile='+str(profile),'--output='+str(out),'--stage='+stage]
 if ticket:command+=['--launcher-ticket='+ticket,'--ticket='+ticket]
 result=run(command,out/(stage+'.log'),100)
 log=(out/(stage+'.log')).read_text('utf8')
 assert result['exit_code']==0 and 'ERROR:' not in log,log
 reports.append(json.loads((out/(stage+'-flow.json')).read_text('utf8')))
 print(json.dumps({'stage':stage,'passed':True},ensure_ascii=False),flush=True)
(out/'report.json').write_text(json.dumps({'passed':True,'stages':reports,'private_desktop':True,'audio':'Dummy'},ensure_ascii=False,indent=2),encoding='utf8')
