"""Loopback-only Web build server and same-origin HD API proxy for browser QA."""
import argparse,http.server,pathlib,urllib.request,urllib.error

parser=argparse.ArgumentParser()
parser.add_argument('--root',type=pathlib.Path,required=True)
parser.add_argument('--listen',type=int,default=18380)
parser.add_argument('--endpoint',default='http://127.0.0.1:18280')
args=parser.parse_args()
assert args.endpoint.startswith('http://127.0.0.1:')
class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map=dict(http.server.SimpleHTTPRequestHandler.extensions_map,**{'.wasm':'application/wasm','.pck':'application/octet-stream','.js':'application/javascript'})
    def __init__(self,*a,**kw):super().__init__(*a,directory=str(args.root.resolve()),**kw)
    def log_message(self,*a):pass
    def end_headers(self):
        self.send_header('Cache-Control','no-store')
        super().end_headers()
    def proxy(self):
        body=self.rfile.read(int(self.headers.get('Content-Length','0'))) if self.command=='POST' else None
        headers={k:v for k,v in self.headers.items() if k.lower() in ['authorization','content-type','if-none-match','accept']}
        request=urllib.request.Request(args.endpoint+self.path[len('/hd-api'):],data=body,headers=headers,method=self.command)
        try:response=urllib.request.urlopen(request,timeout=25)
        except urllib.error.HTTPError as error:response=error
        with response:
            data=response.read();self.send_response(response.status)
            for name in ['Content-Type','ETag']:
                if response.headers.get(name):self.send_header(name,response.headers[name])
            self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
    def do_GET(self):
        if self.path.startswith('/hd-api/'):return self.proxy()
        return super().do_GET()
    def do_POST(self):
        if self.path.startswith('/hd-api/'):return self.proxy()
        self.send_error(404)
http.server.ThreadingHTTPServer(('127.0.0.1',args.listen),Handler).serve_forever()
