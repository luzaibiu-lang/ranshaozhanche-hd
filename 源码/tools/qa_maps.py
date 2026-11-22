"""Render every original map in real staged clients on silent private desktops."""
import argparse
import concurrent.futures
import json
import pathlib
import secrets

from private_desktop import run

ROOT=pathlib.Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser()
parser.add_argument('--client',type=pathlib.Path,required=True)
parser.add_argument('--endpoint',required=True)
args=parser.parse_args()
client=args.client.resolve()
assert client.is_relative_to(ROOT)
output=ROOT/'.tools/qa/map-migration'
output.mkdir(parents=True,exist_ok=True)

def check_map(map_id):
    log=output/('map-%02d.log'%map_id)
    screenshot=output/('map-%02d.png'%map_id)
    result=run([client/'Game.exe','--audio-driver','Dummy','--','--qa',
                '--qa-endpoint='+args.endpoint,'--qa-scene=battle','--qa-map='+str(map_id),
                '--qa-user=qa_map'+secrets.token_hex(4),
                '--qa-size=1280x720','--qa-wait=0.4','--qa-screenshot='+str(screenshot)],log,60)
    text=log.read_text('utf8',errors='replace')
    assert result['exit_code']==0 and 'ERROR:' not in text and 'SCRIPT ERROR' not in text, text[-4000:]
    assert screenshot.exists()
    return {'map':map_id,'exit_code':result['exit_code'],'screenshot':screenshot.name,'private_desktop':True,'silent':True}

with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
    reports=list(pool.map(check_map,range(1,20)))
report={'maps':reports,'client':str(client),'passed':True,'edition':'hd','endpoint':args.endpoint}
(output/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'passed':True,'maps':len(reports),'evidence':str(output)},ensure_ascii=False))
