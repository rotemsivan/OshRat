#!/usr/bin/env python3
"""Prepares the app's celebration sounds into OshRat/Sounds/.

    python3 Scripts/prepare_sounds.py

The sounds come from Kenney's audio packs (www.kenney.nl), which are CC0 —
public domain, free for commercial use, no attribution required (credited in
Scripts/SOUNDS_CREDITS.md anyway). An earlier version synthesised its own
chimes; they came out thin and sharp next to sounds made by a sound designer.

This script downloads the packs, takes the three picks below, gives each a
short fade-in and fade-out so nothing clicks, sets it to a gentle peak level,
and converts it to CAF with `afconvert` (ships with macOS). To try a different
sound, change its source name and rerun — then re-time the matching haptic
taps in `CelebrationFeedback.Moment.taps` to the new sound's notes (the note
onsets are printed below).
"""
import io, math, os, struct, subprocess, tempfile, urllib.request, wave, zipfile

PACKS = {
    "interface": "https://kenney.nl/media/pages/assets/interface-sounds/fa43c1dd4d-1677589452/kenney_interface-sounds.zip",
    "jingles": "https://kenney.nl/media/pages/assets/music-jingles/f37e530b9e-1677590399/kenney_music-jingles.zip",
}

# (output name, pack, file inside the pack, target peak level)
PICKS = [
    # A single warm "confirmation" tone — the smallest moment.
    ("transaction", "interface", "Audio/confirmation_001.ogg", 0.11),
    # Bronze and silver achievements — a two-note steel-drum phrase.
    ("achievement", "jingles", "Audio/Steel jingles/jingles_STEEL04.ogg", 0.13),
    # Gold achievements — its sibling phrase, a touch louder for the rarest patches.
    ("achievement-gold", "jingles", "Audio/Steel jingles/jingles_STEEL08.ogg", 0.14),
    # Four plucked notes rising — the same voice, a bigger moment.
    ("levelup", "jingles", "Audio/Pizzicato jingles/jingles_PIZZI15.ogg", 0.14),
]

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "OshRat", "Sounds")
TMP = tempfile.mkdtemp()


def read_wav(path):
    with wave.open(path) as w:
        rate, n = w.getframerate(), w.getnframes()
        samples = [v / 32768 for v in struct.unpack("<%dh" % n, w.readframes(n))]
    return rate, samples


def write_wav(path, rate, samples):
    with wave.open(path, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in samples))


def onsets(rate, samples, frame=0.01):
    """Note starts, in seconds — what the haptic taps are timed to."""
    f = int(frame * rate)
    env = [math.sqrt(sum(s * s for s in samples[i:i + f]) / f) for i in range(0, len(samples) - f, f)]
    peak, found, last = max(env), [0.0], 0
    for i in range(1, len(env)):
        if env[i] - env[i - 1] > 0.25 * peak and (i - last) * frame > 0.08:
            found.append(round(i * frame, 2)); last = i
    return sorted(set(found))


archives = {}
for name, url in PACKS.items():
    with urllib.request.urlopen(url) as response:
        archives[name] = zipfile.ZipFile(io.BytesIO(response.read()))

for out_name, pack, member, peak in PICKS:
    ogg = os.path.join(TMP, out_name + ".ogg")
    with open(ogg, "wb") as f:
        f.write(archives[pack].read(member))
    raw = os.path.join(TMP, out_name + "-raw.wav")
    subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@44100", "-c", "1", ogg, raw], check=True)

    rate, x = read_wav(raw)
    scale = peak / max(abs(s) for s in x)
    fade_in, fade_out = int(0.004 * rate), int(0.03 * rate)
    shaped = []
    for i, s in enumerate(x):
        g = min(1.0, i / fade_in) * min(1.0, (len(x) - i) / fade_out)
        shaped.append(s * scale * g)

    wav = os.path.join(TMP, out_name + ".wav")
    write_wav(wav, rate, shaped)
    caf = os.path.join(OUT, f"celebration-{out_name}.caf")
    subprocess.run(["afconvert", "-f", "caff", "-d", "LEI16", wav, caf], check=True)
    print(f"{os.path.basename(caf)}: {len(x) / rate:.2f}s, peak {peak}, note onsets {onsets(rate, shaped)}")
