"""Run the normal channel flow silently, with a fresh profile on an inactive desktop."""
import argparse
import json
import pathlib
import secrets

from private_desktop import run

ROOT = pathlib.Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--endpoint', required=True)
parser.add_argument('--client', type=pathlib.Path)
args = parser.parse_args()
assert args.endpoint.startswith('http://127.0.0.1:'), 'This QA only creates local fixture accounts'
output = ROOT/('.tools/qa/channel-'+secrets.token_hex(4))
(output/'profile').mkdir(parents=True)
engine = (args.client.resolve()/'Game.exe' if args.client else
          next(p for p in (ROOT/'.tools/godot').glob('*.exe') if not p.name.endswith('console.exe')))
command = [engine, '--audio-driver', 'Dummy']
if not args.client:
    command += ['--path', ROOT/'源码/client']
command += ['--script', ROOT/'源码/tools/channel_gate_acceptance.gd', '--',
            '--qa-endpoint='+args.endpoint, '--profile='+str(output/'profile'),
            '--name=qa_gate'+secrets.token_hex(3), '--output='+str(output)]
result = run(command, output/'game.log', 120)
log = (output/'game.log').read_text('utf8', errors='replace')
if result['exit_code'] or 'SCRIPT ERROR' in log or 'ERROR:' in log:
    raise RuntimeError(json.dumps(result)+'\n'+log[-6500:])
report = json.loads((output/'report.json').read_text('utf8'))
assert report['passed']
print(json.dumps({'passed': True, 'checks': len(report['checks']),
                  'evidence': str(output), 'timings': report['timings']}, ensure_ascii=False))
