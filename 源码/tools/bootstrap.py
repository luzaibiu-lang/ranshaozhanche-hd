"""Install a pinned local Godot editor; never modifies the legacy project."""
import hashlib
import json
import pathlib
import urllib.request
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
VERSION = '4.5.1'
TOOLS = ROOT / '.tools'
TOOLS.mkdir(exist_ok=True)
archive = TOOLS / ('Godot-' + VERSION + '.zip')
url = 'https://downloads.godotengine.org/?version=' + VERSION + '&flavor=stable&slug=win64.exe.zip'
if not archive.exists():
    pending = archive.with_suffix('.pending')
    request = urllib.request.Request(url, headers={'User-Agent': 'BurningChariotHD-Builder'})
    with urllib.request.urlopen(request, timeout=60) as source, pending.open('wb') as output:
        while True:
            block = source.read(1024 * 1024)
            if not block:
                break
            output.write(block)
    pending.replace(archive)
destination = TOOLS / 'godot'
destination.mkdir(exist_ok=True)
with zipfile.ZipFile(archive) as source:
    for entry in source.infolist():
        assert pathlib.PurePosixPath(entry.filename).name == entry.filename
        if not (destination / entry.filename).exists():
            source.extract(entry, destination)
report = dict(version=VERSION, url=url, archive_sha256=hashlib.sha256(archive.read_bytes()).hexdigest(),
              executables=[str(p) for p in destination.glob('*.exe')])
(TOOLS / 'godot.json').write_text(json.dumps(report, indent=2), encoding='utf8')
print(json.dumps(report))
