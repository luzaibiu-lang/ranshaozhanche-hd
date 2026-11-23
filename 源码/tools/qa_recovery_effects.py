"""Render native recovery sequences on an inactive, silent Windows desktop."""
import argparse
import json
import pathlib
import secrets
from PIL import Image, ImageChops
from private_desktop import run

ROOT = pathlib.Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--client', type=pathlib.Path)
args = parser.parse_args()
out = ROOT / ('.tools/qa/recovery-effects-' + secrets.token_hex(4))
out.mkdir(parents=True)
if args.client:
    client = args.client.resolve()
    assert client.is_relative_to(ROOT)
    command = [client / 'Game.exe', '--audio-driver', 'Dummy']
else:
    executable = next(p for p in (ROOT / '.tools/godot').glob('*.exe') if not p.name.endswith('console.exe'))
    command = [executable, '--audio-driver', 'Dummy', '--path', ROOT / '源码/client']
command += ['--script', ROOT / '源码/tools/recovery_effect_acceptance.gd', '--', '--output=' + str(out)]
result = run(command, out / 'acceptance.log', 120)
log = (out / 'acceptance.log').read_text('utf8', errors='replace')
assert result['exit_code'] == 0 and 'ERROR:' not in log and 'SCRIPT ERROR' not in log, str(out) + '\n' + log[-7000:]
records = [line.removeprefix('RECOVERY_EFFECT_ACCEPTANCE ') for line in log.splitlines() if line.startswith('RECOVERY_EFFECT_ACCEPTANCE ')]
assert len(records) == 1, log[-4000:]
report = json.loads(records[0])
with Image.open(out / 'supply-frame-0.png') as first, Image.open(out / 'supply-frame-1.png') as second:
    assert ImageChops.difference(first.convert('RGB'), second.convert('RGB')).getbbox(), 'Native recovery animation did not change the rendered frame'
report['checks'].append('native recovery animation changes actual rendered pixels')
report.update(result, passed=True, evidence=str(out), source=args.client is None)
for target in [out / 'report.json', ROOT / '.tools/qa/recovery-effects-acceptance.json']:
    target.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
print(json.dumps({'passed': True, 'checks': len(report['checks']), 'evidence': str(out)}, ensure_ascii=False))
