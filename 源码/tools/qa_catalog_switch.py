import pathlib,sys,threading,time,json,argparse
from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
import requests
root=pathlib.Path(__file__).resolve().parents[2];sys.path.insert(0,str(root/'源码/tools'))
from private_desktop import run
parser=argparse.ArgumentParser();parser.add_argument('--client',type=pathlib.Path,required=True);args=parser.parse_args()
output=root/'.tools/qa/release-0.2.1/catalog-switch';output.mkdir(parents=True,exist_ok=True)
catalog=requests.get('http://127.0.0.1:18280/api/catalog',timeout=10).json()
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_GET(self):
  data=json.loads(json.dumps(catalog))
  if self.server.old:
   time.sleep(3);data['vehicles'][0]['name']='旧服务烈火'
  body=json.dumps(data,ensure_ascii=False).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
servers=[]
try:
 for old in (True,False):
  s=ThreadingHTTPServer(('127.0.0.1',0),Handler);s.old=old;threading.Thread(target=s.serve_forever,daemon=True).start();servers.append(s)
 origins=['http://127.0.0.1:'+str(s.server_port) for s in servers]
 result=run([args.client.resolve()/'Game.exe','--audio-driver','Dummy','--max-fps','40','--script',root/'源码/tools/catalog_switch_acceptance.gd','--','--qa-endpoint='+origins[0],'--next='+origins[1],'--output='+str(output)],output/'game.log',40)
 log=(output/'game.log').read_text('utf8');assert result['exit_code']==0 and 'ERROR:' not in log,log
 print((output/'switch.json').read_text('utf8'))
finally:
 for s in servers:s.shutdown();s.server_close()
