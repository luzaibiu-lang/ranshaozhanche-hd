"""Download only the pinned Windows template using HTTP byte ranges."""
import hashlib, json, pathlib, requests, struct, zlib
ROOT = pathlib.Path(__file__).resolve().parents[2]
URL = 'https://github.com/godotengine/godot-builds/releases/download/4.5.1-stable/Godot_v4.5.1-stable_export_templates.tpz'
out = ROOT/'.tools/templates/windows_release_x86_64.exe'
out.parent.mkdir(parents=True, exist_ok=True)
if not out.exists():
    session=requests.Session()
    response=session.head(URL,allow_redirects=True,timeout=45);response.raise_for_status()
    size=int(response.headers['Content-Length']);url=response.url
    def fetch(start,end):
        r=session.get(url,headers={'Range':'bytes=%d-%d'%(start,end)},timeout=120);r.raise_for_status()
        if r.status_code!=206 or len(r.content)!=end-start+1:raise RuntimeError('Range request was not honored')
        return r.content
    tail=fetch(size-65536,size-1);i=tail.rfind(b'PK\x05\x06')
    fields=struct.unpack_from('<4s4H2LH',tail,i);cd_size,cd_offset=fields[5:7]
    directory=fetch(cd_offset,cd_offset+cd_size-1);at=0
    while at<len(directory):
        record=struct.unpack_from('<4s6H3L5H2L',directory,at);assert record[0]==b'PK\x01\x02'
        n,extra,comment=record[10:13];name=directory[at+46:at+46+n].decode('utf8')
        if name=='templates/windows_release_x86_64.exe':
            compressed,length,offset,method,crc=record[8],record[9],record[16],record[4],record[7]
            local=struct.unpack('<4s5H3L2H',fetch(offset,offset+29));start=offset+30+local[9]+local[10]
            archive=bytearray()
            for begin in range(start,start+compressed,4*1024*1024):
                archive.extend(fetch(begin,min(begin+4*1024*1024,start+compressed)-1))
                print('template %d/%d'%(len(archive),compressed),flush=True)
            data=zlib.decompress(archive,-15) if method==8 else bytes(archive)
            assert len(data)==length and zlib.crc32(data)==crc
            pending=out.with_suffix('.pending');pending.write_bytes(data);pending.replace(out);break
        at+=46+n+extra+comment
    else:raise RuntimeError('Windows template missing')
report={'version':'4.5.1','source':URL,'file':out.name,'sha256':hashlib.sha256(out.read_bytes()).hexdigest()}
(out.parent/'provenance.json').write_text(json.dumps(report,indent=2),encoding='utf8');print(json.dumps(report))
