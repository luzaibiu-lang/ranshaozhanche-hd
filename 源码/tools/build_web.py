"""Export the shared Godot project and assemble the official website."""
import argparse
import gzip
import hashlib
import html
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
        release_id = artifact_hash(stage)
        release = releases / release_id
        if not release.exists():
            static_gzip(stage)
            stage.rename(release)
        assets = f"/hd/play/builds/{release_id}"
        homepage = (WEB / "home.html").read_text("utf-8").replace("@@ASSETS@@", assets)
        homepage = homepage.replace("@@CLASSIC@@", classic_url).replace("@@HD@@", hd_url)
        publish_index(releases.parent / "index.html", shell.replace("<!-- BUILD_BASE -->", f'<base href="{assets}/">'))
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
