"""Verify original destruction timing, sound and rendered game pixels on a private desktop."""
import argparse
import json
import pathlib
import secrets

from PIL import Image, ImageChops
from private_desktop import run

root = pathlib.Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--client", type=pathlib.Path)
args = parser.parse_args()
out = root / ".tools/qa" / ("death-" + secrets.token_hex(4))
out.mkdir(parents=True)
if args.client:
    command = [args.client.resolve() / "Game.exe"]
else:
    executable = next(path for path in (root / ".tools/godot").glob("*.exe") if "console" not in path.name)
    command = [executable, "--path", root / "源码/client"]
command += ["--audio-driver", "Dummy", "--script", root / "源码/tools/death_acceptance.gd", "--", out]
result = run(command, out / "acceptance.log", 120)
log = (out / "acceptance.log").read_text("utf-8", errors="replace")
assert result["exit_code"] == 0 and "ERROR:" not in log, log[-6000:]
report = json.loads(next(line.removeprefix("DEATH_ACCEPTANCE ") for line in log.splitlines()
                         if line.startswith("DEATH_ACCEPTANCE ")))
pixels = {}
for phase in ("pulse", "flash", "expired"):
    on = Image.open(out / (phase + "-on.png")).convert("RGB")
    off = Image.open(out / (phase + "-off.png")).convert("RGB")
    difference = ImageChops.difference(on, off)
    pixels[phase] = sum(count for color, count in enumerate(difference.convert("L").histogram()) if color > 2)
assert pixels["pulse"] > 100 and pixels["flash"] > 100 and pixels["expired"] == 0, pixels
report.update(result, pixels=pixels, evidence=str(out))
(out / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({"passed": True, "checks": len(report["checks"]), "pixels": pixels,
                  "evidence": str(out)}, ensure_ascii=False))
