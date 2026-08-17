#!/usr/bin/env python3
"""Generate placeholder backgrounds for the Story-share feature.

Six 1080x1920 backgrounds (one per StoryTemplate in
lib/data/models/story_template.dart) plus a bookmark ribbon glyph for the
card's top-right corner.

These are real, committable assets in Spine's own palette — the same kind of
placeholder the launcher icon and splash screen already are (see
generate_branding.py) — not stand-ins that block the feature from working.
Swap them for final template art by overwriting the files in assets/story/:
lib/data/models/story_template.dart references these paths directly, so no
code change is needed.

Usage:
    python3 tool/generate_story_templates.py
"""

from __future__ import annotations

import pathlib
import random

from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "story"

SIZE = (1080, 1920)
SUPERSAMPLE = 2

INK = (13, 12, 9)
BRASS = (201, 162, 39)
TEAL = (62, 112, 104)
BRICK = (177, 84, 63)
INDIGO = (74, 78, 124)
OLIVE = (107, 122, 61)
PARCHMENT = (241, 233, 214)

# Template id -> (accent colour, dark-text variant).
# Templates 1-3 specify dark main-title text, so those backgrounds carry a
# parchment field through the middle third, where the title sits. Templates
# 4-6 specify white text, so those stay dark throughout — the same
# "light source" language the app's own AmbientBackdrop uses on the feed.
TEMPLATES = {
    1: (BRASS, True),
    2: (OLIVE, True),
    3: (INDIGO, True),
    4: (TEAL, False),
    5: (BRICK, False),
    6: (BRASS, False),
}


def lerp(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    t = max(0.0, min(1.0, t))
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def vertical_gradient(size: tuple[int, int], stops: list[tuple[float, tuple[int, int, int]]]) -> Image.Image:
    """A smooth multi-stop vertical gradient, built row by row rather than by
    blurring a shape — accurate at any size, with no dependence on how large a
    blur kernel PIL is willing to apply."""
    w, h = size
    image = Image.new("RGB", size)
    draw = ImageDraw.Draw(image)

    for y in range(h):
        t = y / max(1, h - 1)
        for i in range(len(stops) - 1):
            t0, c0 = stops[i]
            t1, c1 = stops[i + 1]
            if t0 <= t <= t1:
                local_t = 0 if t1 == t0 else (t - t0) / (t1 - t0)
                colour = lerp(c0, c1, local_t)
                break
        else:
            colour = stops[-1][1]
        draw.line([(0, y), (w, y)], fill=colour)

    return image


def corner_bloom(size: tuple[int, int], centre: tuple[float, float], radius: int, colour: tuple[int, int, int], alpha: int) -> Image.Image:
    """A soft accent glow, kept small enough that its own blur radius is large
    relative to its size — this is what made the light-centre variant band
    earlier at full-canvas scale."""
    w, h = size
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    cx, cy = centre
    draw.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=colour + (alpha,))
    return layer.filter(ImageFilter.GaussianBlur(radius * 0.6))


def make_background(accent: tuple[int, int, int], light_center: bool) -> Image.Image:
    w, h = (v * SUPERSAMPLE for v in SIZE)

    if light_center:
        base = vertical_gradient(
            (w, h),
            [
                (0.0, lerp(INK, accent, 0.35)),
                (0.28, PARCHMENT),
                (0.62, PARCHMENT),
                (1.0, INK),
            ],
        ).convert("RGBA")
    else:
        base = vertical_gradient(
            (w, h),
            [(0.0, lerp(INK, accent, 0.45)), (0.55, INK), (1.0, INK)],
        ).convert("RGBA")

    base.alpha_composite(corner_bloom((w, h), (w * 0.78, h * 0.1), int(w * 0.35), accent, 120))

    # Grain: an 8-bit gradient this smooth bands visibly on a phone screen
    # without it.
    rng = random.Random(42)
    grain = Image.new("L", (w, h))
    grain.putdata([rng.randint(-6, 6) + 128 for _ in range(w * h)])
    noisy = Image.blend(base.convert("RGB"), Image.merge("RGB", (grain, grain, grain)), 0.02)

    return noisy.resize(SIZE, Image.LANCZOS)


def make_bookmark() -> Image.Image:
    """A single ribbon glyph — decorative, for the card corner, distinct from
    the in-app SpineRibbon (which is a five-segment progress bar)."""
    w, h = 140 * 4, 320 * 4
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)

    left, top = w * 0.2, 0.0
    right, body_bottom = w * 0.8, h * 0.82
    radius = int((right - left) * 0.18)
    draw.rounded_rectangle([left, top, right, body_bottom], radius=radius, fill=BRASS)

    notch = (right - left) * 0.5
    draw.polygon(
        [
            (left, body_bottom),
            ((left + right) / 2, body_bottom - notch),
            (right, body_bottom),
        ],
        fill=(0, 0, 0, 0),
    )

    return canvas.resize((140, 320), Image.LANCZOS)


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)

    for template_id, (accent, light_center) in TEMPLATES.items():
        image = make_background(accent, light_center)
        # JPEG to match the shipped art: these are photographs, and the
        # PNGs of the same images cost six times the bytes for no gain.
        path = OUT / f"image{template_id}.jpg"
        image.save(path, "JPEG", quality=85, optimize=True, subsampling=0)
        print(f"  {path.relative_to(ROOT)}")

    bookmark_path = OUT / "bookmark.png"
    make_bookmark().save(bookmark_path)
    print(f"  {bookmark_path.relative_to(ROOT)}")

    print(f"{len(TEMPLATES) + 1} placeholder asset(s) written.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
