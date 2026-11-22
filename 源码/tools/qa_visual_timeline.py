"""Run production visual-timeline boundary regressions on an inactive desktop."""
import argparse
import json
import pathlib
import secrets

from PIL import Image, ImageChops

from private_desktop import run

ROOT = pathlib.Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--client', type=pathlib.Path, help='Optional exported client directory; otherwise test current source')
arguments = parser.parse_args()
out = ROOT / ('.tools/qa/visual-timeline-' + secrets.token_hex(4))
out.mkdir(parents=True)
if arguments.client:
    client = arguments.client.resolve()
    assert client.is_relative_to(ROOT)
    executable = client / 'Game.exe'
    command = [executable, '--audio-driver', 'Dummy']
else:
    executable = next(path for path in (ROOT / '.tools/godot').glob('*.exe') if not path.name.endswith('console.exe'))
    command = [executable, '--audio-driver', 'Dummy', '--path', ROOT / '源码/client']
command += ['--script', ROOT / '源码/tools/visual_timeline_acceptance.gd', '--', '--output=' + str(out)]
result = run(command, out / 'acceptance.log', 90)
content = (out / 'acceptance.log').read_text('utf8', errors='replace')
assert result['exit_code'] == 0 and 'ERROR:' not in content and 'SCRIPT ERROR' not in content, content[-7000:]
records = [line.removeprefix('VISUAL_TIMELINE_ACCEPTANCE ') for line in content.splitlines() if line.startswith('VISUAL_TIMELINE_ACCEPTANCE ')]
assert len(records) == 1, content[-4000:]
report = json.loads(records[0])
with Image.open(out / 'stealth-with-history.png') as history, Image.open(out / 'stealth-baseline.png') as baseline:
    difference = ImageChops.difference(history.convert('RGB'), baseline.convert('RGB'))
    assert difference.getbbox() is None, 'An existing enemy damage number remained visible after stealth'
report['checks'].append('rendered stealth frame is pixel-identical with hidden hit numbers removed')
report.update(result, passed=True, evidence=str(out), source=arguments.client is None)
(out / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
(ROOT / '.tools/qa/visual-timeline-acceptance.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
print(json.dumps({'passed': True, 'checks': len(report['checks']), 'evidence': str(out)}, ensure_ascii=False))
