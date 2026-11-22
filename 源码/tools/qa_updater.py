"""Exercise the shipped updater in an isolated full client copy."""
import hashlib,json,pathlib,secrets,shutil,subprocess,time
ROOT=pathlib.Path(__file__).resolve().parents[2];source=ROOT/'客户端/燃烧战车 高清重制版';target=ROOT/'.tools/qa/update-client'
target.mkdir(parents=True,exist_ok=True)
for p in source.rglob('*'):
 if p.is_file():
  q=target/p.relative_to(source);q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,q)
manifest=json.loads((target/'manifest.json').read_text('utf8'))
def invoke():
 r=subprocess.run([str(target/'燃烧战车.exe'),'--verify-update'],capture_output=True,text=True,encoding='utf8',errors='replace',creationflags=subprocess.CREATE_NO_WINDOW,timeout=60)
 if r.returncode:raise RuntimeError(r.stdout+r.stderr)
 text=r.stdout.strip();assert 'verified_update_files=' in text,text
 return int(text.split('verified_update_files=')[-1].splitlines()[0])
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
core=target/'Game.pck';good=core.read_bytes()
first=invoke();assert first==0
initial_size=sum(p.stat().st_size for p in target.rglob('*') if p.is_file())
times={f['path']:(target/f['path']).stat().st_mtime_ns for f in manifest['files'] if f['path']!='Game.pck'}
core.write_bytes(b'isolated corrupted pack')
changed=invoke();assert changed==1 and core.read_bytes()==good
assert all((target/path).stat().st_mtime_ns==stamp for path,stamp in times.items()),'Unchanged assets were rewritten'
second=invoke();assert second==0
assert not list((target/'.update').glob('*/'))
final_size=sum(p.stat().st_size for p in target.rglob('*') if p.is_file());assert final_size==initial_size
# Retired, previously managed packs must not accumulate indefinitely.
retired=target/'packs/retired-qa-only.pck';retired.write_bytes(b'old managed asset')
previous=json.loads((target/'manifest.json').read_text('utf8'));previous['files'].append({'path':'packs/retired-qa-only.pck','size':retired.stat().st_size,'sha256':digest(retired)})
(target/'manifest.json').write_text(json.dumps(previous),encoding='utf8');assert invoke()==0 and not retired.exists()
# Recover a transaction interrupted after moving the old pack into backup.
staging=target/'.update'/secrets.token_hex(16);(staging/'old').mkdir(parents=True);(staging/'old/Game.pck').write_bytes(good)
(staging/'transaction.json').write_text(json.dumps([{'path':'Game.pck','existed':True}]),encoding='utf8');core.write_bytes(b'interrupted apply')
assert invoke()==0 and core.read_bytes()==good and not staging.exists()
report={'first_start_changed_files':first,'repair_changed_files':changed,'second_start_changed_files':second,'unchanged_assets_untouched':True,'repaired_bytes':len(good),'size_did_not_grow':True,'retired_managed_pack_removed':True,'interrupted_update_recovered':True,'isolated_from_delivery_client':True}
(ROOT/'.tools/qa/updater-acceptance.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8');print(json.dumps(report,ensure_ascii=False))
