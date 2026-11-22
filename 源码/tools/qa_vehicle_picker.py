import argparse, json, math, pathlib, secrets
from PIL import Image, ImageChops
from private_desktop import run

ROOT = pathlib.Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser()
p.add_argument('--endpoint', default='http://127.0.0.1:18326')
p.add_argument('--client', type=pathlib.Path)
p.add_argument('--capture-baseline', action='store_true')
a = p.parse_args()
out = ROOT / ('.tools/qa/vehicle-picker-' + secrets.token_hex(4))
out.mkdir(parents=True)
exe = a.client.resolve() / 'Game.exe' if a.client else next(p for p in (ROOT / '.tools/godot').glob('*.exe') if not p.name.endswith('console.exe'))
args = [exe, '--audio-driver', 'Dummy']
if not a.client:args += ['--path', ROOT / '源码/client']
args += ['--script', ROOT / '源码/tools/vehicle_picker_acceptance.gd', '--',
         '--qa-endpoint=' + a.endpoint, '--profile=' + str(out / 'profile'),
         '--name=qa_pick' + secrets.token_hex(3), '--output=' + str(out)]
result = run(args, out / 'acceptance.log', 150)
log = (out / 'acceptance.log').read_text('utf8', errors='replace')
markers = [line.removeprefix('VEHICLE_PICKER_ACCEPTANCE ') for line in log.splitlines() if line.startswith('VEHICLE_PICKER_ACCEPTANCE ')]
if result['exit_code'] or 'ERROR:' in log or 'SCRIPT ERROR' in log or len(markers) != 1:
    raise RuntimeError(str(out) + '\n' + log[-5000:])
report = json.loads(markers[0])
measurements = []
fixture = json.loads((ROOT / '源码/tools/native-picker-layout.json').read_text('utf8'))
native_positions = {entry['id']: entry['position'][:2] for entry in fixture['cell_frame_positions']}
native_measurements = []
for capture in report['captures']:
    frame = Image.open(ROOT / f'源码/client/assets/effects/TotUnit269/{capture["id"]:02d}.png').convert('RGBA')
    used = frame.getchannel('A').getbbox()
    for kind in ['cell', 'preview']:
        foreground = Image.open(out / (capture['prefix'] + '-' + kind + '.png')).convert('RGB')
        background = Image.open(out / (capture['prefix'] + '-' + kind + '-empty.png')).convert('RGB')
        delta = ImageChops.difference(foreground, background)
        # Original sprites include an opaque black outline on a dark blue
        # panel; keep its small but real color difference in the bounds.
        mask = delta.convert('L').point(lambda x: 255 if x > 0 else 0)
        bounds = mask.getbbox()
        scale = capture['scale']
        dimensions = capture[kind + '_size']
        expected = [(dimensions[0]-37)*.5*scale+used[0]*scale,
                    (dimensions[1]-34)*.5*scale+used[1]*scale,
                    (dimensions[0]-37)*.5*scale+used[2]*scale,
                    (dimensions[1]-34)*.5*scale+used[3]*scale]
        origin = capture[kind + '_origin']
        expected = [value + origin[i % 2] - math.floor(origin[i % 2])
                    for i, value in enumerate(expected)]
        deviation = max(abs(x-y) for x,y in zip(bounds or [0]*4, expected))
        measurements.append(dict(id=capture['id'], window=capture['window'], kind=kind,
                                 bounds=bounds, expected=expected, max_deviation=deviation,
                                 passed=bounds is not None and deviation <= 2.1))
        native_position = native_positions.get(capture['id']) if kind == 'cell' else (fixture['random_preview_frame_position'] if capture['id']==0 else None)
        if native_position and bounds:
            picker_origin = capture['picker_origin']
            observed_native = [(math.floor(origin[i%2])+value-picker_origin[i%2])/scale for i,value in enumerate(bounds)]
            expected_native = [(native_position[i%2]-fixture['picker_origin'][i%2])+used[i] for i in range(4)]
            error = max(abs(x-y) for x,y in zip(observed_native,expected_native))
            native_measurements.append(dict(id=capture['id'],window=capture['window'],kind=kind,
                                            observed=observed_native, original=expected_native,
                                            deviation=error,passed=error<=1.75))
report.update(result, evidence=str(out), measurements=measurements)
report['original_screenshot_position_checks'] = native_measurements
report['all_native_centers_and_sizes_match'] = all(m['passed'] for m in measurements + native_measurements)
(out / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
(ROOT / ('.tools/qa/vehicle-picker-' + ('baseline' if a.capture_baseline else 'acceptance') + '.json')).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
print(json.dumps(dict(checks=len(report['checks']), measured=len(measurements),
                      centers_and_sizes_match=report['all_native_centers_and_sizes_match'], evidence=str(out)), ensure_ascii=False))
if not a.capture_baseline and not report['all_native_centers_and_sizes_match']:
    failures=[m for m in measurements if not m['passed']]
    raise AssertionError(json.dumps(failures[:12], ensure_ascii=False))
