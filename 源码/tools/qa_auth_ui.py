"""Exercise the normal release register/login screens and the actual vault.

Each process gets an isolated Windows profile and log. --qa is deliberately
absent: it bypasses both _login and _vault and cannot verify this regression.
"""
import argparse
import json
import pathlib
import secrets

from private_desktop import run

ROOT = pathlib.Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--client', type=pathlib.Path, default=ROOT/'客户端/燃烧战车 高清重制版')
parser.add_argument('--audio-driver', default='WASAPI', choices=['WASAPI','Dummy'])
parser.add_argument('--endpoint', help='Use an explicitly isolated HD endpoint for development QA')
arguments = parser.parse_args()
client = arguments.client.resolve()
assert client.is_relative_to(ROOT)
suffix = secrets.token_hex(3)
profile = ROOT/('.tools/qa/auth-profile-'+suffix)
profile.mkdir(parents=True)
name = 'qa_auth'+suffix
report = {'normal_login_code': True, 'normal_vault_code': True, 'isolated_profile': True,
          'private_desktop': True, 'audio_driver': arguments.audio_driver, 'master_muted_before_startup': True, 'stages': []}
for stage in ['register', 'resume', 'after-logout', 'not-remembered']:
    log = ROOT/('.tools/qa/auth-'+suffix+'-'+stage+'.log')
    screenshot = log.with_suffix('.png')
    command = [client/'Game.exe', '--verbose', '--audio-driver', arguments.audio_driver, '--log-file', log.with_suffix('.engine.log'),
                  '--script', ROOT/'源码/tools/auth_ui_acceptance.gd', '--',
                  '--profile='+str(profile), '--name='+name, '--stage='+stage, '--screenshot='+str(screenshot)]
    if arguments.endpoint:command.append('--qa-endpoint='+arguments.endpoint)
    result = run(command, log, 120)
    text = log.read_text('utf8', errors='replace')
    if result['exit_code'] or 'ERROR:' in text or 'SCRIPT ERROR' in text:
        raise RuntimeError(json.dumps(result, ensure_ascii=False)+'\n'+text[-6000:])
    markers = [line.removeprefix('AUTH_UI_ACCEPTANCE ') for line in text.splitlines() if line.startswith('AUTH_UI_ACCEPTANCE ')]
    assert len(markers) == 1, 'Normal UI verification did not complete: '+text[-3000:]
    value = json.loads(markers[0])
    assert value['normal_ui']
    value.update(exit_code=result['exit_code'], log=str(log), screenshot=str(screenshot))
    report['stages'].append(value)
    print(json.dumps({'stage': stage, 'passed': True, 'checks': len(value['checks'])}), flush=True)
(ROOT/'.tools/qa/auth-ui-acceptance.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
print(json.dumps({'passed': True, 'stages': len(report['stages']), 'normal_register_login_vault': True}))
