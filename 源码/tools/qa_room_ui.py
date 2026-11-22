import argparse, json, pathlib, secrets
from private_desktop import run

ROOT = pathlib.Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser()
p.add_argument('--endpoint', default='http://127.0.0.1:18280')
p.add_argument('--client', type=pathlib.Path)
a = p.parse_args()
out = ROOT / ('.tools/qa/room-ui-' + secrets.token_hex(4))
out.mkdir(parents=True)
exe = a.client.resolve() / 'Game.exe' if a.client else next(p for p in (ROOT / '.tools/godot').glob('*.exe') if not p.name.endswith('console.exe'))
args = [exe, '--audio-driver', 'Dummy']
if not a.client:args += ['--path', ROOT / '源码/client']
args += ['--script', ROOT / '源码/tools/room_ui_acceptance.gd', '--',
        '--qa-endpoint=' + a.endpoint, '--profile=' + str(out / 'profile'),
        '--name=qa_room' + secrets.token_hex(3), '--output=' + str(out)]
result = run(args, out / 'acceptance.log', 120)
text = (out / 'acceptance.log').read_text('utf8', errors='replace')
markers = [line.removeprefix('ROOM_UI_ACCEPTANCE ') for line in text.splitlines()
           if line.startswith('ROOM_UI_ACCEPTANCE ')]
if result['exit_code'] or 'ERROR:' in text or 'SCRIPT ERROR' in text or len(markers) != 1:
    raise RuntimeError(str(out) + '\n' + text[-5000:])
report = json.loads(markers[0])
report.update(result, evidence=str(out))
(ROOT / '.tools/qa/room-ui-acceptance.json').write_text(
    json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
print(json.dumps({'passed': True, 'checks': len(report['checks']), 'evidence': str(out)}, ensure_ascii=False))
