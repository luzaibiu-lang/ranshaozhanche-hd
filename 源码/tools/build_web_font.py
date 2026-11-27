"""Rebuild the Web UI font with fonttools==4.61.1 and Python 3.11+."""
from pathlib import Path
import json

from fontTools import subset
from fontTools.ttLib import TTFont


SOURCE = Path(__file__).resolve().parents[1]
CLIENT = SOURCE / "client"
FONTS = CLIENT / "assets/fonts"


def strings_in(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from strings_in(item)
    elif isinstance(value, list):
        for item in value:
            yield from strings_in(item)


def project_characters():
    chars = set()
    files = list(CLIENT.glob("*.gd")) + list(CLIENT.glob("*.tscn"))
    files += [path for path in (SOURCE / "server").glob("*.go") if not path.name.endswith("_test.go")]
    for path in files:
        chars.update(path.read_text(encoding="utf-8-sig"))
    for path in (CLIENT / "assets").rglob("*.json"):
        for value in strings_in(json.loads(path.read_text(encoding="utf-8-sig"))):
            chars.update(value)
    return {ord(char) for char in chars if char.isprintable()}


def main():
    original = FONTS / "NotoSansSC-Regular.otf"
    output = FONTS / "NotoSansSC-UI.otf"
    with TTFont(original, recalcTimestamp=False) as font:
        available = set(font.getBestCmap())
        project = project_characters()
        # GB 2312 level one contains 3755 high-frequency simplified characters.
        common = {ord(char) for lead in range(0xB0, 0xD8) for trail in range(0xA1, 0xFF)
                  for char in bytes([lead, trail]).decode("gb2312", errors="ignore")}
        wanted = project | common | set(range(32, 127))
        for start, end in ((0x2000, 0x2070), (0x3000, 0x3040), (0xFF01, 0xFF61)):
            wanted.update(available.intersection(range(start, end)))
        options = subset.Options()
        options.name_IDs = ["*"]  # Retain the embedded license and attribution.
        options.name_languages = ["*"]
        options.layout_features = ["*"]
        sub = subset.Subsetter(options=options)
        sub.populate(unicodes=wanted)
        sub.subset(font)
        font.save(output)
    with TTFont(output) as check:
        covered = set(check.getBestCmap())
    if (wanted & available) - covered:
        raise RuntimeError("Subset lost characters present in the original font")
    print(f"{len(covered)} code points, {len(project & covered)}/{len(project)} project characters, "
          f"{len(common & covered)}/{len(common)} level-one Chinese characters")
    print("Missing in original:", " ".join(f"U+{cp:04X}" for cp in sorted(wanted - available)) or "none")
    print(f"{original.stat().st_size:,} -> {output.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
