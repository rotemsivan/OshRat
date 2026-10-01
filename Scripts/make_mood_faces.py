#!/usr/bin/env python3
"""Derive the rat's mood faces from the Bare bust head.

The mascot's mood (`MascotMood`) swaps the bust head for a variant with
different brows, eyes and mouth. Each variant is the base head with those
three features redrawn, so a change to the base head's shape or fur carries
over: edit `bare-bust-rig-head.svg`, rerun this, and the moods follow.

    python3 Scripts/make_mood_faces.py            # write the imagesets
    python3 Scripts/make_mood_faces.py --sheet out.svg   # also a contact sheet

Only the bust canvas has moods: the dashboard greeting and the profile picture
are both drawn on it, and the full-body wardrobe rat stays neutral on purpose.
"""

import argparse
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
POSES = ROOT / "OshRat/Assets.xcassets/Mascots/Bare/Poses"
BASE = POSES / "bare-bust-rig-head.imageset/bare-bust-rig-head.svg"

# The base head's features, matched verbatim so a changed base fails loudly
# instead of producing a face with two mouths.
BROWS = ('<g stroke="#6F6F79" stroke-width="6" stroke-linecap="round" fill="none">'
         '<path d="M142 138 L188 132"/><path d="M212 132 L258 138"/></g>')
SMILE = '<path d="M188 250 Q200 259 212 250" fill="none" stroke="#5A4A4E" stroke-width="3" stroke-linecap="round"/>'
EYES = [
    '<path d="M146 158 C150 142 186 140 190 156 C186 172 150 174 146 158 Z" fill="#FFFFFF"/>',
    '<path d="M254 158 C250 142 214 140 210 156 C214 172 250 174 254 158 Z" fill="#FFFFFF"/>',
    '<circle cx="172" cy="158" r="11" fill="#2B2B33"/><circle cx="228" cy="158" r="11" fill="#2B2B33"/>',
    '<circle cx="175" cy="154" r="4" fill="#FFFFFF"/><circle cx="231" cy="154" r="4" fill="#FFFFFF"/>',
]
PUPILS = EYES[2] + "\n  " + EYES[3]

# The fur gradient again, but in the canvas's own units and centred where the
# face's bounding box puts the original, so an eyelid drawn over the eye is
# shaded exactly like the face around it rather than as a flat patch.
LID_GRADIENT = ('<radialGradient id="lid" gradientUnits="userSpaceOnUse" cx="186" cy="155" r="133">'
                '<stop offset="0%" stop-color="#B4B4BC"/><stop offset="100%" stop-color="#80808A"/></radialGradient>')


def brows(left, right, width=6, color="#6F6F79"):
    return (f'<g stroke="{color}" stroke-width="{width}" stroke-linecap="round" fill="none">'
            f'<path d="{left}"/><path d="{right}"/></g>')


def mouth(d, width=3):
    return f'<path d="{d}" fill="none" stroke="#5A4A4E" stroke-width="{width}" stroke-linecap="round"/>'


# Each mood: what replaces the brows and mouth, what is drawn over the eyes
# (`lids`, before the brows), and optionally new eyes / pupils.
MOODS = {
    # Late afternoon with nothing logged, or a month over budget: a little
    # anxious, not yet unhappy.
    "worried": dict(
        brows=brows("M144 138 L188 128", "M212 128 L256 138"),
        mouth=mouth("M188 254 Q194 250 200 254 Q206 258 212 254"),
    ),
    # The evening with nothing logged.
    "sad": dict(
        brows=brows("M146 142 L186 124", "M214 124 L254 142"),
        mouth=mouth("M188 256 Q200 247 212 256"),
        pupils=('<circle cx="171" cy="161" r="11" fill="#2B2B33"/><circle cx="229" cy="161" r="11" fill="#2B2B33"/>\n  '
                '<circle cx="174" cy="157" r="4" fill="#FFFFFF"/><circle cx="232" cy="157" r="4" fill="#FFFFFF"/>'),
        # Heavy lids, lower at the outer corners.
        lids=('<path d="M146 158 C150 142 186 140 190 156 L190 151 Q168 149 146 162 Z" fill="url(#lid)"/>'
              '<path d="M254 158 C250 142 214 140 210 156 L210 151 Q232 149 254 162 Z" fill="url(#lid)"/>'
              '<path d="M150 178 Q143 190 150 195 Q157 190 150 178 Z" fill="#7FB8E6"/>'),
    ),
    # Too many luxuries today, or the day the month went over budget.
    "angry": dict(
        brows=brows("M142 130 L190 147", "M210 147 L258 130", width=7, color="#5A5A64"),
        mouth=mouth("M186 256 Q200 249 214 256", width=3.5),
        # Lids slanting down toward the nose, and a flush.
        lids=('<path d="M146 158 C150 142 186 140 190 156 L190 159 L146 147 Z" fill="url(#lid)"/>'
              '<path d="M254 158 C250 142 214 140 210 156 L210 159 L254 147 Z" fill="url(#lid)"/>'
              '<ellipse cx="146" cy="196" rx="14" ry="7" fill="#E07A7A" opacity="0.45"/>'
              '<ellipse cx="254" cy="196" rx="14" ry="7" fill="#E07A7A" opacity="0.45"/>'),
    ),
    # A level, a streak rung or a patch earned today.
    "happy": dict(
        brows=brows("M144 134 Q166 122 188 128", "M212 128 Q234 122 256 134"),
        mouth=mouth("M182 248 Q200 266 218 248", width=3.5),
        # Eyes closed in a smile: ^ ^
        eyes=('<g stroke="#2B2B33" stroke-width="6" stroke-linecap="round" fill="none">'
              '<path d="M150 162 Q168 144 186 162"/><path d="M214 162 Q232 144 250 162"/></g>'),
        lids=('<ellipse cx="146" cy="194" rx="14" ry="7" fill="#E89A9A" opacity="0.5"/>'
              '<ellipse cx="254" cy="194" rx="14" ry="7" fill="#E89A9A" opacity="0.5"/>'),
    ),
}


def make(base: str, spec: dict) -> str:
    for part in [BROWS, SMILE, *EYES]:
        if part not in base:
            sys.exit(f"The base head changed; update make_mood_faces.py. Missing: {part[:60]}…")
    svg = base.replace(BROWS, "").replace(SMILE, spec["mouth"])
    if "eyes" in spec:
        for part in EYES:
            svg = svg.replace(part, "")
        svg = svg.replace("</svg>", "  " + spec["eyes"] + "\n</svg>")
    elif "pupils" in spec:
        svg = svg.replace(PUPILS, spec["pupils"])
    if "lids" in spec:
        svg = svg.replace("</defs>", "  " + LID_GRADIENT + "\n  </defs>")
        svg = svg.replace("</svg>", "  " + spec["lids"] + "\n</svg>")
    svg = svg.replace("</svg>", "  " + spec["brows"] + "\n</svg>")
    return svg.replace("rig (bust): head", f"rig (bust): head, {next(k for k, v in MOODS.items() if v is spec)}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sheet", help="also write a contact sheet SVG here (big + icon size)")
    args = parser.parse_args()

    base = BASE.read_text()
    faces = {"calm": base}
    for name, spec in MOODS.items():
        svg = make(base, spec)
        faces[name] = svg
        folder = POSES / f"bare-bust-rig-head-{name}.imageset"
        folder.mkdir(exist_ok=True)
        (folder / f"bare-bust-rig-head-{name}.svg").write_text(svg)
        (folder / "Contents.json").write_text(json.dumps({
            "images": [{"filename": f"bare-bust-rig-head-{name}.svg", "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
            "properties": {"preserves-vector-representation": True},
        }, indent=2) + "\n")
        print("wrote", folder.relative_to(ROOT))

    if args.sheet:
        cells = []
        for i, (name, svg) in enumerate(faces.items()):
            inner = svg[svg.index(">", svg.index("<svg")) + 1: svg.rindex("</svg>")]
            inner = inner.replace('id="fur"', f'id="fur{i}"').replace("url(#fur)", f"url(#fur{i})")
            inner = inner.replace('id="lid"', f'id="lid{i}"').replace("url(#lid)", f"url(#lid{i})")
            cells.append(f'<g transform="translate({i * 400},0)">{inner}</g>')
            cells.append(f'<g transform="translate({i * 400 + 150},540) scale(0.25)">{inner}</g>')
        width = 400 * len(faces)
        pathlib.Path(args.sheet).write_text(
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{width}" viewBox="0 -{(width - 700) // 2} {width} {width}">'
            f'<rect y="-{(width - 700) // 2}" width="{width}" height="{width}" fill="#F4F1EA"/>{"".join(cells)}</svg>')


if __name__ == "__main__":
    main()
