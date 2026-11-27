"""Run packed native transport through a slow isolated HTTP fallback."""
import argparse,json,threading,time
from pathlib import Path
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from private_desktop import run
from qa_web_streaming import ROOT
p=argparse.ArgumentParser();p.add_argument('--client',type=Path,required=True);p.add_argument('--report',type=Path,required=True);args=p.parse_args()
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*_):pass
 def do_GET(self):
  if self.path.startswith('/slow/'):time.sleep(6)
  self.send_response(304);self.end_headers()
with ThreadingHTTPServer(('127.0.0.1',0),Handler) as server:
 thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
 args.report.parent.mkdir(parents=True,exist_ok=True)
 result=run([args.client.resolve()/'Game.exe','--audio-driver','Dummy','--script',ROOT/'源码/tools/native_transport_acceptance.gd','--',f'http://127.0.0.1:{server.server_port}'],args.report.with_suffix('.log'),60)
 server.shutdown();thread.join()
 log=args.report.with_suffix('.log').read_text('utf8');assert result['exit_code']==0 and 'ERROR' not in log,log
 report=json.loads(next(line.split('TRANSPORT029 ',1)[1] for line in log.splitlines() if line.startswith('TRANSPORT029 ')))
 args.report.write_text(json.dumps(report,indent=2),encoding='utf8');print(json.dumps(report))
