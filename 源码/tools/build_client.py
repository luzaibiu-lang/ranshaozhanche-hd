"""Windows export with independently updatable code, map and audio packs."""
import hashlib,json,pathlib,shutil,subprocess,re,argparse
import psutil
from PIL import Image
ROOT=pathlib.Path(__file__).resolve().parents[2];client=ROOT/'源码/client';tools=ROOT/'.tools'
godot=next(p for p in (tools/'godot').glob('*.exe') if not p.name.endswith('console.exe'))
parser=argparse.ArgumentParser();parser.add_argument('--output',type=pathlib.Path);parser.add_argument('--endpoint',default='http://127.0.0.1:18180');args=parser.parse_args()
from urllib.parse import urlsplit
address=urlsplit(args.endpoint)
if not (address.scheme=='https' or (address.scheme=='http' and address.hostname in ('127.0.0.1','localhost','::1'))):
    parser.error('--endpoint must use HTTPS or loopback HTTP')
if address.username or address.password or address.path not in ('','/') or address.query or address.fragment:
    parser.error('--endpoint must be an origin without credentials, path, query or fragment')
output=(args.output or ROOT/'客户端/燃烧战车 高清重制版').resolve();assert output.is_relative_to(ROOT)
for process in psutil.process_iter(['exe']):
    try:
        executable=pathlib.Path(process.info['exe']).resolve() if process.info['exe'] else None
        if executable and executable.parent==output and executable.name in ['Game.exe','LauncherHost.exe','燃烧战车.exe']:
            raise RuntimeError('Build target is running; export to a separate candidate directory')
    except (psutil.NoSuchProcess,psutil.AccessDenied):pass
output.mkdir(parents=True,exist_ok=True)
version=re.search(r'config/version="([^"]+)"',(client/'project.godot').read_text('utf8')).group(1)
art=Image.open(client/'assets/tanks/1/00.png').convert('RGBA').resize((216,216),Image.Resampling.NEAREST)
canvas=Image.new('RGBA',(256,256));canvas.paste(art,(20,20),art)
canvas.save(client/'assets/icon.ico',sizes=[(16,16),(32,32),(48,48),(64,64),(128,128),(256,256)])
canvas.save(client/'assets/app_icon.png')
def run(arguments,log,cwd=None):
    r=subprocess.run(list(map(str,arguments)),cwd=cwd,capture_output=True,text=True,encoding='utf8',errors='replace',creationflags=subprocess.CREATE_NO_WINDOW,timeout=300)
    text=r.stdout+r.stderr;(tools/log).write_text(text,encoding='utf8')
    if r.returncode or 'SCRIPT ERROR' in text or 'ERROR:' in text:raise RuntimeError(text[-6000:])
    return text
full=tools/'export-full.pck'
print('Exporting full imported resources',flush=True)
run([godot,'--headless','--audio-driver','Dummy','--path',client,'--export-pack','Windows Desktop',full],'export.log')
packer=tools/'packer';packer.mkdir(exist_ok=True)
(packer/'project.godot').write_text('config_version=5\n[application]\nconfig/name="HD Pack Builder"\n',encoding='utf8')
shutil.copy2(ROOT/'源码/tools/qa_license.gd',packer/'license.gd')
run([godot,'--headless','--path',packer,'--script',packer/'license.gd','--',output/'LICENSES.txt'],'licenses.log')
shutil.copy2(ROOT/'源码/tools/split_pack.gd',packer/'split_pack.gd')
print(run([godot,'--headless','--path',packer,'--script',packer/'split_pack.gd','--',full,output,client/'assets/app_icon.png'],'split-pack.log'),flush=True)
shutil.copy2(tools/'templates/windows_release_x86_64.exe',output/'Game.exe')
framework=pathlib.Path('C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe')
for source,name,refs,target in [('Vault.cs','Vault.exe',['System.Security.dll'],'exe'),('Launcher.cs','燃烧战车.exe',['System.Windows.Forms.dll','System.Drawing.dll','System.Web.Extensions.dll','System.Security.dll'],'winexe')]:
    if not (ROOT/'源码/launcher'/source).exists():continue
    sources=[ROOT/'源码/launcher'/source]
    resources=[]
    if source=='Launcher.cs':
        sources.append(ROOT/'源码/launcher/LauncherWindow.cs')
        resources=[('back',client/'assets/legacy/LobyBack.png'),('map',client/'assets/maps/9/background.jpg'),('tank',client/'assets/effects/TotUnit269/01.png'),('button',client/'assets/legacy/pop_ok.png'),('start',client/'assets/legacy/gl_start.png'),('title',client/'assets/legacy/TitleBack.png')]
        if not resources[1][1].exists():resources[1]=('map',client/'assets/maps/9/background.png')
    fingerprint=hashlib.sha256(b''.join(p.read_bytes() for p in sources)+b''.join(p.read_bytes()for _,p in resources)+('|'.join(refs)+target).encode()+(client/'assets/icon.ico').read_bytes()).hexdigest()
    cache=tools/'csharp-cache'/fingerprint/name;cache.parent.mkdir(parents=True,exist_ok=True)
    arguments=[framework,'/nologo','/optimize+','/target:'+target,'/out:'+str(cache)]
    if source=='Launcher.cs':arguments.append('/win32icon:'+str(client/'assets/icon.ico'))
    arguments.extend('/reference:'+x for x in refs)
    arguments.extend('/resource:'+str(p)+',art.'+label for label,p in resources)
    arguments.extend(sources)
    if not cache.exists():run(arguments,'compile-'+source+'.log')
    shutil.copy2(cache,output/name)
    if source=='Launcher.cs':shutil.copy2(cache,output/'LauncherHost.exe')
(output/'connection.json').write_text(json.dumps({'endpoint':args.endpoint.rstrip('/'),'edition':'hd'}),encoding='utf8')
certificate=client/'hd-public.crt'
if certificate.exists():shutil.copy2(certificate,output/'hd-public.crt')
entries=[]
for p in sorted(output.rglob('*')):
    if p.is_file() and p.name not in ['manifest.json','燃烧战车.exe'] and not any(x.startswith('.') for x in p.relative_to(output).parts):
        data=p.read_bytes();digest=hashlib.sha256(data).hexdigest();entries.append({'path':p.relative_to(output).as_posix(),'size':len(data),'sha256':digest,'url':'blobs/'+digest})
manifest={'version':version,'edition':'hd','files':entries}
(output/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'output':str(output),'files':len(entries),'bytes':sum(x['size'] for x in entries)},ensure_ascii=False))
