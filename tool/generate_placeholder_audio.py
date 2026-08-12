#!/usr/bin/env python3
"""Generate placeholder narration tracks for the bundled catalogue.

Spine's audio layer is real (just_audio), but the narration for the sample
catalogue hasn't been recorded. This produces short, correctly-timed WAV files
so the whole playback path — buffering, progress, completion, auto-advance to
the next idea — can be exercised on a device without shipping licensed audio.

Each track is a soft chime, silence for the body of the idea, then a closing
chime, at the exact duration declared in books.json.

Usage:
    python3 tool/generate_placeholder_audio.py [book-id ...]

Replace the generated files with real narration of the same name and the app
picks it up with no code change.
"""

from __future__ import annotations

import json
import math
import pathlib
import struct
import sys
import wave

ROOT = pathlib.Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "assets" / "content" / "books.json"
SAMPLE_RATE = 8000
AMPLITUDE = 0.16


def chime(t: float, length: float, root_hz: float) -> float:
    """A two-note chime that decays over `length` seconds."""
    if t >= length:
        return 0.0
    decay = math.exp(-4.0 * t / length)
    return decay * (
        math.sin(2 * math.pi * root_hz * t)
        + 0.5 * math.sin(2 * math.pi * root_hz * 1.5 * t)
    ) / 1.5


def render(path: pathlib.Path, seconds: float) -> None:
    frames = int(seconds * SAMPLE_RATE)
    tail_start = max(0.0, seconds - 1.0)
    samples = bytearray()

    for n in range(frames):
        t = n / SAMPLE_RATE
        value = chime(t, 0.9, 528.0) + chime(t - tail_start, 0.9, 396.0)
        clamped = max(-1.0, min(1.0, value * AMPLITUDE))
        samples += struct.pack("<h", int(clamped * 32767))

    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(SAMPLE_RATE)
        out.writeframes(bytes(samples))


def main(argv: list[str]) -> int:
    catalogue = json.loads(MANIFEST.read_text())
    wanted = set(argv) or None
    written = 0

    for book in catalogue["books"]:
        if wanted is not None and book["id"] not in wanted:
            continue
        for idea in book["ideas"]:
            ref = idea.get("audio")
            if not ref or not ref.startswith("asset:"):
                continue
            target = ROOT / ref[len("asset:"):]
            render(target, float(idea["seconds"]))
            print(f"  {target.relative_to(ROOT)}  ({idea['seconds']}s)")
            written += 1

    print(f"{written} placeholder track(s) written.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
