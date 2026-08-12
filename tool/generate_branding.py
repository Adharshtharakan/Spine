#!/usr/bin/env python3
"""Draw Spine's launcher icon and splash mark.

The mark is the product's signature element: the bookmark ribbon, divided into
five — one segment per idea — with the first three filled, the way a card looks
mid-book.

Outputs (source images; flutter_launcher_icons and flutter_native_splash
generate the per-platform sizes from these):
    assets/branding/icon.png             1024×1024, full bleed
    assets/branding/icon_foreground.png  1024×1024, adaptive-icon safe area
    assets/branding/splash.png            512×1024, transparent

Usage:
    python3 tool/generate_branding.py
"""

from __future__ import annotations

import pathlib

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "branding"

INK = (22, 20, 15, 255)
BRASS = (201, 162, 39, 255)
BRASS_DIM = (201, 162, 39, 70)

SEGMENTS = 5
FILLED = 3
SUPERSAMPLE = 4


def draw_ribbon(size: tuple[int, int], height_ratio: float, width_ratio: float) -> Image.Image:
    """The ribbon mark on a transparent ground, drawn oversized then reduced."""
    width, height = (value * SUPERSAMPLE for value in size)
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)

    ribbon_w = int(width * width_ratio)
    ribbon_h = int(height * height_ratio)
    left = (width - ribbon_w) // 2
    top = (height - ribbon_h) // 2
    radius = ribbon_w // 8
    gap = max(2, ribbon_w // 22)

    segment_h = (ribbon_h - gap * (SEGMENTS - 1)) / SEGMENTS
    # Shallow enough that the tail still reads as one segment with a notch.
    notch = int(segment_h * 0.5)
    for index in range(SEGMENTS):
        y0 = top + index * (segment_h + gap)
        y1 = y0 + segment_h
        colour = BRASS if index >= SEGMENTS - FILLED else BRASS_DIM
        draw.rounded_rectangle([left, y0, left + ribbon_w, y1], radius=radius, fill=colour)

    # The bookmark notch: cut a wedge out of the bottom segment.
    draw.polygon(
        [
            (left, top + ribbon_h),
            (left + ribbon_w // 2, top + ribbon_h - notch),
            (left + ribbon_w, top + ribbon_h),
            (left + ribbon_w, top + ribbon_h + 4),
            (left, top + ribbon_h + 4),
        ],
        fill=(0, 0, 0, 0),
    )

    return canvas.resize(size, Image.LANCZOS)


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)

    icon = Image.new("RGBA", (1024, 1024), INK)
    icon.alpha_composite(draw_ribbon((1024, 1024), 0.60, 0.26))
    icon.convert("RGB").save(OUT / "icon.png")

    # Adaptive icons crop hard; keep the mark inside the safe circle.
    foreground = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    foreground.alpha_composite(draw_ribbon((1024, 1024), 0.44, 0.19))
    foreground.save(OUT / "icon_foreground.png")

    draw_ribbon((512, 1024), 0.55, 0.34).save(OUT / "splash.png")

    print(f"Wrote icon.png, icon_foreground.png and splash.png to {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
