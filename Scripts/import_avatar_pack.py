#!/usr/bin/env python3
"""Import a layered avatar pack (oshrat-avatar-assets.zip) into the asset catalog.

    python3 Scripts/import_avatar_pack.py path/to/oshrat-avatar-assets.zip

What it does, and why each step exists:

1. **Splits the Bare rat into rig parts.** The pack's base bodies are single
   drawings with the arms and legs painted in, so a sleeve could never follow
   a raised arm. The script cuts `full/base/mascot-base.svg` into tail / body /
   two arms / head (legs come from the pack's own `full/base/rig/` files) and
   `bust/base/mascot-bust-base.svg` into body / two arms / head. Every part
   keeps the whole canvas, so the parts still register with each other and
   with every wardrobe layer; `AvatarLayers` rotates each limb group about its
   pivot. Poses are angles now, so the pack's per-pose drawings aren't used.
2. **Replaces the one-piece outfits** (`item-outfit-<name>-<format>`) with
   the split tops (`-torso-`, `-sleeve-left-`, `-sleeve-right-`).
3. **Adds pants and shoes** (full format only) in their own slot folders.

Pack files are copied verbatim (their provenance metadata included, like the
rest of the catalog), after checking each one parses; `SKIPPED_ITEMS` lists
the ones left out and why. Rerunning is safe: every imageset it writes is replaced.
"""

import json
import re
import shutil
import sys
import tempfile
import zipfile
from xml.etree import ElementTree
from pathlib import Path

CATALOG = Path(__file__).resolve().parent.parent / "OshRat" / "Assets.xcassets"

IMAGESET_CONTENTS = {
    "images": [{"filename": None, "idiom": "universal"}],
    "info": {"author": "xcode", "version": 1},
    "properties": {"preserves-vector-representation": True},
}
FOLDER_CONTENTS = {"info": {"author": "xcode", "version": 1}}


def write_imageset(folder: Path, name: str, svg: str) -> None:
    imageset = folder / f"{name}.imageset"
    if imageset.exists():
        shutil.rmtree(imageset)
    imageset.mkdir(parents=True)
    (imageset / f"{name}.svg").write_text(svg)
    contents = json.loads(json.dumps(IMAGESET_CONTENTS))
    contents["images"][0]["filename"] = f"{name}.svg"
    (imageset / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def ensure_folder(folder: Path) -> Path:
    folder.mkdir(parents=True, exist_ok=True)
    contents = folder / "Contents.json"
    if not contents.exists():
        contents.write_text(json.dumps(FOLDER_CONTENTS, indent=2) + "\n")
    return folder


# MARK: - Rig parts

def svg_elements(path: Path) -> tuple[str, str, list[str]]:
    """(opening <svg> tag, <defs> block, drawing lines) with metadata, titles
    and comments stripped."""
    text = re.sub(r"<metadata>.*?</metadata>", "", path.read_text(), flags=re.S)
    opening = re.search(r"<svg[^>]*>", text).group(0)
    opening = re.sub(r'\s+xmlns:c2pa="[^"]*"', "", opening)
    defs = re.search(r"<defs>.*?</defs>", text, flags=re.S).group(0)
    body = text[text.index("</defs>") + len("</defs>"): text.rindex("</svg>")]
    body = re.sub(r"<!--.*?-->", "", body, flags=re.S)
    lines = [line.strip() for line in body.splitlines() if line.strip()]
    return opening, defs, lines


def part_svg(opening: str, defs: str, title: str, lines: list[str]) -> str:
    return "\n".join([opening, f"  <title>{title}</title>", f"  {defs}", *(f"  {l}" for l in lines), "</svg>", ""])


def split(lines: list[str], rules: dict[str, tuple[str, ...]], rest: str) -> dict[str, list[str]]:
    """Files each line under the first part whose markers it contains, and
    everything unmatched under `rest`."""
    parts: dict[str, list[str]] = {name: [] for name in [*rules, rest]}
    for line in lines:
        for name, markers in rules.items():
            if any(marker in line for marker in markers):
                parts[name].append(line)
                break
        else:
            parts[rest].append(line)
    return parts


def build_full_rig(pack: Path) -> dict[str, str]:
    opening, defs, lines = svg_elements(pack / "full/base/mascot-base.svg")
    parts = split(lines, {
        "tail": ('M200 460',),
        # The pack ships the legs as parts of their own (below), so they're
        # dropped from the body rather than kept twice.
        "legs": ('M152 442', 'M208 442', 'cx="160" cy="56', 'cx="202" cy="56'),
        "body": ('M118 268', 'cx="180" cy="356"', 'M170 238'),
        "arm-left": ('M122 270', 'cx="119" cy="432"'),
        "arm-right": ('M238 270', 'cx="241" cy="432"'),
    }, rest="head")
    assert len(parts["legs"]) == 6, parts["legs"]
    assert parts["head"][0].startswith('<g transform='), parts["head"][0]
    rig = {
        name: part_svg(opening, defs, f"OshRat rig (full): {name}", parts[name])
        for name in ("tail", "body", "arm-left", "arm-right", "head")
    }
    for side in ("left", "right"):
        rig[f"leg-{side}"] = (pack / f"full/base/rig/mascot-base-leg-{side}.svg").read_text()
    return rig


def build_bust_rig(pack: Path) -> dict[str, str]:
    opening, defs, lines = svg_elements(pack / "bust/base/mascot-bust-base.svg")
    parts = split(lines, {
        "body": ('M120 520', 'cx="200" cy="404"', 'M184 256'),
        "arm-left": ('M134 350', 'cx="116" cy="508"'),
        "arm-right": ('M266 350', 'cx="284" cy="508"'),
    }, rest="head")
    for name in ("body", "arm-left", "arm-right"):
        assert parts[name], name
    return {
        name: part_svg(opening, defs, f"OshRat rig (bust): {name}", lines)
        for name, lines in parts.items()
    }


# Items left out of the import. The first pack shipped sequin-gold's torso
# (both formats) with its left sleeve pasted onto the end and the file cut
# off part-way through the right one: unparseable, so it breaks the asset
# build. The top is dropped from the catalogue rather than patched; bring it
# back when the pack ships a fixed torso.
SKIPPED_ITEMS = ("item-outfit-sequin-gold",)


def is_skipped(svg: Path) -> bool:
    return svg.stem.startswith(SKIPPED_ITEMS)


def assert_parses(svg: Path) -> None:
    """A malformed SVG fails the whole asset catalog with an unhelpful
    'Exception Raised during asset import' — say which file instead."""
    try:
        ElementTree.parse(svg)
    except ElementTree.ParseError as error:
        sys.exit(f"{svg.name} is not valid SVG ({error}); fix it or add it to SKIPPED_ITEMS")


# MARK: - Import

def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    source = Path(sys.argv[1])
    with tempfile.TemporaryDirectory() as tmp:
        if source.suffix == ".zip":
            zipfile.ZipFile(source).extractall(tmp)
            pack = next(Path(tmp).rglob("README.txt")).parent
        else:
            pack = source

        # 1. Rig parts. The per-pose drawings they replace are removed.
        bare = CATALOG / "Mascots/Bare"
        for old in [*bare.glob("Rig/bare-fullbody-*.imageset"), *bare.glob("Poses/bare-bust-*.imageset")]:
            shutil.rmtree(old)
        for name, svg in build_full_rig(pack).items():
            write_imageset(ensure_folder(bare / "Rig"), f"bare-fullbody-rig-{name}", svg)
        for name, svg in build_bust_rig(pack).items():
            write_imageset(ensure_folder(bare / "Poses"), f"bare-bust-rig-{name}", svg)

        # 2. Tops: out with every old one-piece outfit, in with the layers.
        outfits = ensure_folder(CATALOG / "Accessories/Outfits")
        for old in outfits.glob("item-outfit-*.imageset"):
            shutil.rmtree(old)
        for svg in sorted(pack.glob("*/outfits/item-outfit-*.svg")):
            if is_skipped(svg):
                continue
            assert_parses(svg)
            write_imageset(outfits, svg.stem, svg.read_text())

        # 3. Pants and shoes, new slots.
        for slot, folder in (("pants", "Pants"), ("shoes", "Shoes")):
            target = ensure_folder(CATALOG / "Accessories" / folder)
            for old in target.glob(f"item-{slot}-*.imageset"):
                shutil.rmtree(old)
            for svg in sorted(pack.glob(f"full/{slot}/item-{slot}-*.svg")):
                if is_skipped(svg):
                    continue
                assert_parses(svg)
                write_imageset(target, svg.stem, svg.read_text())

    print("Imported into", CATALOG)


if __name__ == "__main__":
    main()
