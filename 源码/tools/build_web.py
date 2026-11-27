"""Export the shared Godot project and assemble the official website."""
import argparse
import gzip
import hashlib
import html
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from urllib.parse import quote, urlsplit

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "源码/client"
WEB = ROOT / "源码/web"


def artifact_hash(directory):
    digest = hashlib.sha256()
    for item in sorted(directory.iterdir()):
        if item.name == "game.pck":
            continue
        digest.update(item.name.encode("utf-8") + b"\0")
        with item.open("rb") as stream:
            digest.update(hashlib.file_digest(stream, "sha256").digest())
    return digest.hexdigest()[:20]


def static_gzip(directory):
    for item in directory.iterdir():
        if item.suffix not in (".wasm", ".js", ".pck"):
            continue
        packed = item.with_suffix(item.suffix + ".gz")
        with item.open("rb") as source, packed.open("wb") as compressed:
            with gzip.GzipFile(filename="", fileobj=compressed, mode="wb", compresslevel=6, mtime=0) as stream:
                shutil.copyfileobj(source, stream)
        if packed.stat().st_size >= item.stat().st_size:
            packed.unlink()


def download_path(value):
    parsed = urlsplit(value)
    if not value.startswith("/") or parsed.scheme or parsed.netloc or "\\" in value:
        raise ValueError("Download URLs must use a path on this website")
    return html.escape(quote(value, safe="/%?=&"), quote=True)


def publish_index(path, content):
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False, mode="w", encoding="utf-8") as temp:
        temp.write(content)
    os.replace(temp.name, path)


def build(output, engine, classic_url, hd_url):
    version = re.search(r'^config/version="([^"]+)"', (CLIENT / "project.godot").read_text("utf-8"), re.M)[1]
    hd_url = hd_url or f"/hd/download/燃烧战车高清版-{version}-Windows.zip"
    classic_url, hd_url = download_path(classic_url), download_path(hd_url)
    releases = output / "hd/play/builds"
    releases.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=releases.parent, prefix=".stage-") as temp:
        stage = Path(temp)
        exported = stage / "game.html"
        command = [str(engine), "--headless", "--audio-driver", "Dummy", "--path", str(CLIENT),
                   "--export-release", "Web", str(exported)]
        result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace",
                                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0), timeout=900)
        log = result.stdout + result.stderr
        if result.returncode or "SCRIPT ERROR" in log or "ERROR:" in log:
            raise RuntimeError("Godot Web export failed:\n" + log[-7000:])
        shell = exported.read_text("utf-8")
        if "<!-- BUILD_BASE -->" not in shell or "$GODOT_" in shell:
            raise RuntimeError("Check the Web preset's custom HTML shell (../web/play.html)")
        if "<!-- DEVICE_PROFILE -->" not in shell:
            raise RuntimeError("Web shell must include the shared device profile")
        profile = (CLIENT / "device_profile.js").read_text("utf-8")
        shell = shell.replace("<!-- DEVICE_PROFILE -->", "<script>\n" + profile + "\n</script>")
        for filename in ("game.wasm", "game.pck", "game.js"):
            if not (stage / filename).stat().st_size:
                raise RuntimeError(f"Missing Web export file: {filename}")
        # Compose original map layers without a capture's player names or HUD.
        assets_dir = CLIENT / "assets"
        with (Image.open(assets_dir / "maps/9/background.jpg") as sky,
              Image.open(assets_dir / "maps/9/terrain.png") as ground):
            field = sky.convert("RGBA")
            field.alpha_composite(ground)
            for vehicle, x in ((1, 1024), (8, 1320)):
                with Image.open(assets_dir / f"tanks/{vehicle}/preview.png") as sprite:
                    tank = sprite.crop(sprite.getbbox())
                    y = next(row for row in range(ground.height) if ground.getpixel((x, row))[3] > 200)
                    field.alpha_composite(tank, (x - tank.width // 2, y - tank.height + 2))
            field.crop((0, 270, field.width, 920)).convert("RGB").save(stage / "field.webp", quality=87, method=5)
        shutil.copyfile(CLIENT / "assets/app_icon.png", stage / "icon.png")
        shutil.copyfile(WEB / "home.css", stage / "home.css")
        exported.unlink()
        # Engine URLs depend only on engine/static bytes, not on game code or
        # maps. A new game release can reuse every unchanged browser cache key.
        release_id = artifact_hash(stage)
        assets = f"/hd/play/builds/{release_id}"
        packer = ROOT / ".tools/web-packer"
        packer.mkdir(parents=True, exist_ok=True)
        (packer / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Web Pack Builder"\n', encoding="utf8")
        shutil.copyfile(ROOT / "源码/tools/split_web_pack.gd", packer / "split_web_pack.gd")
        forced = {"res://assets/maps/17/background.jpg", "res://assets/maps/17/background.jpg.import"}
        for source in CLIENT.glob("*.gd"):
            for path in re.findall(r'preload\("(res://assets/[^\"]+)"\)', source.read_text("utf8")):
                forced.update((path, path + ".import"))
        settings = stage / "pack-settings.json"
        settings.write_text(json.dumps({"version":version,"core":sorted(forced)}), encoding="utf8")
        packs = stage / "packs"
        core = stage / "core.pck"
        result = subprocess.run([str(engine), "--headless", "--audio-driver", "Dummy", "--path", str(packer),
            "--script", str(packer / "split_web_pack.gd"), "--", str(stage / "game.pck"), str(packs), assets, str(core), str(settings)],
            capture_output=True, text=True, encoding="utf8", errors="replace", creationflags=getattr(subprocess,"CREATE_NO_WINDOW",0), timeout=240)
        if result.returncode or "ERROR:" in result.stdout + result.stderr:
            raise RuntimeError("Web pack split failed:\n" + result.stdout + result.stderr)
        manifest = packs / "stream.json"
        manifest_name = "stream-" + hashlib.sha256(manifest.read_bytes()).hexdigest()[:20] + ".json"
        manifest.rename(stage / manifest_name)
        for item in packs.iterdir():
            item.rename(stage / item.name)
        packs.rmdir()
        settings.unlink()
        (stage / "game.pck").unlink()
        core_name = hashlib.sha256(core.read_bytes()).hexdigest() + ".pck"
        core.rename(stage / core_name)
        config_match = re.search(r'(?:new Engine\(|const config = )(\{[^\n]+\})', shell)
        config = json.loads(config_match[1])
        config["mainPack"] = core_name
        config["fileSizes"] = {"game.wasm":(stage/"game.wasm").stat().st_size, core_name:(stage/core_name).stat().st_size}
        shell = shell[:config_match.start(1)] + json.dumps(config,ensure_ascii=False) + shell[config_match.end(1):]
        shell = shell.replace("<!-- BUILD_BASE -->", f'<base href="{assets}/"><meta name="game-stream-manifest" content="{assets}/{manifest_name}">')
        release = releases / release_id
        static_gzip(stage)
        current_files = {item.name for item in stage.iterdir()}
        if not release.exists():
            stage.rename(release)
        else:
            for item in stage.iterdir():
                target = release / item.name
                if target.exists():
                    if hashlib.sha256(target.read_bytes()).digest()!=hashlib.sha256(item.read_bytes()).digest():
                        raise RuntimeError("Immutable Web asset changed: " + item.name)
                else:item.rename(target)
            # Local candidates contain only this manifest's files. Production
            # publication remains additive so already open tabs keep working.
            for item in release.iterdir():
                if item.name not in current_files and (re.fullmatch(r"[0-9a-f]{64}\.pck(?:\.gz)?",item.name) or re.fullmatch(r"stream-[0-9a-f]{20}\.json",item.name)):
                    item.unlink()
        homepage = (WEB / "home.html").read_text("utf-8").replace("@@ASSETS@@", assets)
        homepage = homepage.replace("@@CLASSIC@@", classic_url).replace("@@HD@@", hd_url)
        publish_index(releases.parent / "index.html", shell)
        publish_index(output / "index.html", homepage)
        print(f"Web {version} ready: {output} ({assets})")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / ".tools/web-020")
    parser.add_argument("--godot", type=Path, help="Godot 4.5.1 Standard editor")
    parser.add_argument("--classic-url", default="/download/燃烧战车.zip")
    parser.add_argument("--hd-url", help="Site-relative URL for the HD Windows download")
    args = parser.parse_args()
    engine = args.godot or next((ROOT / ".tools/godot").glob("*console.exe"), None) or shutil.which("godot")
    if not engine:
        parser.error("Supply the Godot 4.5.1 editor with --godot")
    build(args.output.resolve(), engine, args.classic_url, args.hd_url)
