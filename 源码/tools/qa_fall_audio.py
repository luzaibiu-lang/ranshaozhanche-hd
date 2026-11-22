import argparse,json,pathlib,secrets,wave,array
from private_desktop import run
ROOT=pathlib.Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--client',type=pathlib.Path);a=p.parse_args()
out=ROOT/('.tools/qa/fall-audio-'+secrets.token_hex(4));out.mkdir(parents=True)
exe=a.client.resolve()/'Game.exe'if a.client else next(p for p in(ROOT/'.tools/godot').glob('*.exe')if not p.name.endswith('console.exe'))
args=[exe,'--audio-driver','Dummy']
if not a.client:args+=['--path',ROOT/'源码/client']
args+=['--script',ROOT/'源码/tools/fall_audio_acceptance.gd','--','--fixture='+str(ROOT/'.tools/qa/fallout-fixture.json'),'--output='+str(out)]
r=run(args,out/'acceptance.log',90);log=(out/'acceptance.log').read_text('utf8',errors='replace');assert not r['exit_code']and'ERROR:'not in log and'SCRIPT ERROR'not in log,log[-5000:]
report=json.loads((out/'report.json').read_text('utf8'))
with wave.open(str(ROOT/'源码/client/assets/audio/sound/dropping.wav'),'rb')as source:
 data=source.readframes(source.getnframes());assert source.getsampwidth()==2
 amplitudes=array.array('h',data);peak=max(abs(v)for v in amplitudes);assert peak>1000
 report.update(duration=source.getnframes()/source.getframerate(),pcm_peak=peak,non_silent_source=True)
report.update(r,evidence=str(out));(out/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8');(ROOT/'.tools/qa/fall-audio-acceptance.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(report,ensure_ascii=False))
