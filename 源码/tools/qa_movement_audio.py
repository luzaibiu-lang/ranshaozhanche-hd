"""Exercise real movement playback, quietly on an inactive Windows desktop."""
import argparse
import array
import json
import pathlib
import secrets
import wave

from private_desktop import run

ROOT = pathlib.Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--client', type=pathlib.Path)
args = parser.parse_args()
output = ROOT / ('.tools/qa/movement-audio-' + secrets.token_hex(4))
output.mkdir(parents=True)
executable = args.client.resolve() / 'Game.exe' if args.client else next(
    p for p in (ROOT / '.tools/godot').glob('*.exe') if not p.name.endswith('console.exe'))
command = [executable, '--verbose', '--audio-driver', 'Dummy']
if not args.client:
    command += ['--path', ROOT / '源码/client']
command += ['--script', ROOT / '源码/tools/movement_audio_acceptance.gd', '--',
            '--fixture=' + str(ROOT / '.tools/qa/fallout-fixture.json'), '--output=' + str(output)]
result = run(command, output / 'acceptance.log', 90)
log = (output / 'acceptance.log').read_text('utf8', errors='replace')
assert not result['exit_code'] and 'ERROR:' not in log and 'SCRIPT ERROR' not in log, str(output) + '\n' + log[-7000:]
report = json.loads((output / 'report.json').read_text('utf8'))
pcm = []
for filename in sorted({v['cue'] for v in report['vehicles']}):
    with wave.open(str(ROOT / '源码/client/assets/audio/sound' / filename), 'rb') as source:
        assert source.getsampwidth() == 2
        amplitudes = array.array('h', source.readframes(source.getnframes()))
        peak = max(abs(value) for value in amplitudes)
        assert peak > 1000
        pcm.append({'cue': filename, 'duration': source.getnframes() / source.getframerate(), 'pcm_peak': peak})
report.update(result, evidence=str(output), pcm_sources=pcm, source_audio_is_not_empty=True)
(output / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
(ROOT / '.tools/qa/movement-audio-acceptance.json').write_text(
    json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
print(json.dumps({'passed': True, 'checks': len(report['checks']), 'vehicles': len(report['vehicles']),
                  'continuous_starts': report['continuous_starts'], 'evidence': str(output)}, ensure_ascii=False))
