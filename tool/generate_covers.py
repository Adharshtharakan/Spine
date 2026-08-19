#!/usr/bin/env python3
"""Generate a cover for every book in the catalogue.

Abstract rather than literal: no real jacket art, so nothing here depends on
publisher rights. Each cover is derived from the book's own `spine` colour, so
the art, the ribbon and the active controls already agree, and seeded from the
book id so a given book always gets the same cover — regenerating never
reshuffles the shelf's look.

    python3 tool/generate_covers.py

Writes assets/covers/<book-id>.jpg. Replacing any one of them with real art is
a file swap; nothing in the app names an individual cover.

The art is geometric rather than atmospheric. A soft coloured blur is what
`AmbientBackdrop` already draws, and stacking another one behind it just makes
a dim card dimmer — the covers have to bring *form*, the way a Penguin or
Pelican jacket does, or they are not worth the bytes.

Each cover puts its composition in the upper two thirds and falls to ink below,
because the idea's text sits over the lower half of the card. Bold art and
readable type, without a scrim heavy enough to grey the art out.
"""

from __future__ import annotations

import colorsys
import hashlib
import json
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
CATALOGUE = ROOT / "assets" / "content" / "books.json"
OUT = ROOT / "assets" / "covers"

# Rendered behind a scrim and softened, so it never needs to be sharp. Small
# files matter more than resolution here: 25 of these ship in the APK.
SIZE = (540, 960)

INK = (13, 12, 9)

SPINE_COLOURS = {
    "brass": "#C9A227",
    "teal": "#3E7068",
    "brick": "#B1543F",
    "indigo": "#4A4E7C",
    "olive": "#6B7A3D",
}


def parse_colour(value: str) -> tuple[int, int, int]:
    hex_value = SPINE_COLOURS.get(value, value).lstrip("#")
    return tuple(int(hex_value[i : i + 2], 16) for i in (0, 2, 4))


def shift(rgb, hue=0.0, sat=1.0, val=1.0):
    """Move a colour in HSV, staying in gamut."""
    h, s, v = colorsys.rgb_to_hsv(*[c / 255 for c in rgb])
    h = (h + hue) % 1.0
    s = max(0.0, min(1.0, s * sat))
    v = max(0.0, min(1.0, v * val))
    return tuple(round(c * 255) for c in colorsys.hsv_to_rgb(h, s, v))


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def vertical_gradient(size, stops):
    """Explicit per-row fill. Smooth by construction, unlike a blurred shape."""
    width, height = size
    image = Image.new("RGB", size)
    draw = ImageDraw.Draw(image)

    for y in range(height):
        t = y / max(height - 1, 1)
        lower = max([s for s in stops if s[0] <= t], key=lambda s: s[0])
        upper = min([s for s in stops if s[0] >= t], key=lambda s: s[0])
        span = upper[0] - lower[0]
        local = 0 if span == 0 else (t - lower[0]) / span
        draw.line([(0, y), (width, y)], fill=lerp(lower[1], upper[1], local))

    return image


def bloom(size, centre, radius, colour, alpha):
    """A soft light. Drawn small, scaled up — bicubic gives a clean falloff."""
    small = 64
    layer = Image.new("L", (small, small), 0)
    draw = ImageDraw.Draw(layer)

    # Concentric rings rather than one disc: the falloff is what makes it read
    # as light rather than as a circle.
    steps = 26
    for i in range(steps, 0, -1):
        t = i / steps
        r = (small / 2) * t
        value = int(alpha * 255 * (1 - t) ** 2.1)
        draw.ellipse(
            [small / 2 - r, small / 2 - r, small / 2 + r, small / 2 + r],
            fill=value,
        )

    box = round(radius * 2)
    layer = layer.resize((box, box), Image.BICUBIC)

    mask = Image.new("L", size, 0)
    mask.paste(
        layer,
        (round(centre[0] - radius), round(centre[1] - radius)),
    )
    mask = mask.filter(ImageFilter.GaussianBlur(radius * 0.10))

    tint = Image.new("RGB", size, colour)
    return tint, mask


def vignette(size, strength=0.55):
    width, height = size
    mask = Image.new("L", (64, 64), 0)
    draw = ImageDraw.Draw(mask)
    steps = 30
    for i in range(steps, 0, -1):
        t = i / steps
        r = 46 * t
        draw.ellipse([32 - r, 32 - r, 32 + r, 32 + r], fill=int(255 * (1 - t)))
    mask = mask.resize(size, Image.BICUBIC)
    mask = Image.eval(mask, lambda v: 255 - int(v * strength))
    return mask


def grain(image, amount=7):
    """Film grain. The catalogue's own photography is grainy; this matches it,
    and it doubles as dithering so the gradients don't band at 8 bits."""
    width, height = image.size
    noise = Image.effect_noise((width, height), amount).convert("L")
    return Image.blend(image, Image.merge("RGB", (noise, noise, noise)), 0.055)


ARCHETYPES = ("arc", "horizon", "columns", "orb", "diagonal")


def paper(size, tone):
    return Image.new("RGB", size, tone)


def draw_arc(draw, size, palette):
    w, h = size
    r = w * 0.86
    cx, cy = w * 0.5, h * 0.60
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=palette["accent"])
    draw.ellipse(
        [cx - r * 0.52, cy - r * 0.52, cx + r * 0.52, cy + r * 0.52],
        fill=palette["deep"],
    )


def draw_horizon(draw, size, palette):
    w, h = size
    draw.rectangle([0, 0, w, h * 0.30], fill=palette["accent"])
    draw.rectangle([0, h * 0.30, w, h * 0.46], fill=palette["deep"])
    r = w * 0.19
    draw.ellipse(
        [w * 0.68 - r, h * 0.15 - r, w * 0.68 + r, h * 0.15 + r],
        fill=palette["light"],
    )


def draw_columns(draw, size, palette):
    w, h = size
    bands = 5
    for i in range(bands):
        if i % 2:
            continue
        x = w * (i / bands)
        draw.rectangle([x, 0, x + w / bands, h * 0.58], fill=palette["accent"])
    draw.rectangle([0, h * 0.44, w, h * 0.52], fill=palette["light"])


def draw_orb(draw, size, palette):
    w, h = size
    r = w * 0.22
    cx, cy = w * 0.52, h * 0.17
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=palette["accent"])
    ring = r * 1.42
    draw.ellipse(
        [cx - ring, cy - ring, cx + ring, cy + ring],
        outline=palette["light"],
        width=round(w * 0.014),
    )


def draw_diagonal(draw, size, palette):
    w, h = size
    draw.polygon(
        [(0, 0), (w, 0), (w, h * 0.30), (0, h * 0.56)], fill=palette["accent"]
    )
    draw.polygon(
        [(0, h * 0.56), (w, h * 0.30), (w, h * 0.40), (0, h * 0.66)],
        fill=palette["light"],
    )


SHAPES = {
    "arc": draw_arc,
    "horizon": draw_horizon,
    "columns": draw_columns,
    "orb": draw_orb,
    "diagonal": draw_diagonal,
}


def fade_to_ink(image, start=0.24):
    """Falls to ink over the lower half, where the idea's text sits."""
    w, h = image.size
    mask = Image.new("L", (1, h))
    for y in range(h):
        t = (y / h - start) / (1 - start)
        mask.putpixel((0, y), 255 - round(255 * max(0.0, min(1.0, t)) ** 0.85))
    mask = mask.resize((w, h))
    return Image.composite(image, Image.new("RGB", (w, h), INK), mask)


def make_cover(spine: str, seed: str) -> Image.Image:
    rng = random.Random(int(hashlib.sha1(seed.encode()).hexdigest()[:8], 16))
    base = parse_colour(spine)

    palette = {
        "accent": shift(base, sat=1.0, val=1.0),
        "light": shift(base, hue=rng.uniform(-0.05, 0.05), sat=0.55, val=0.95),
        "deep": shift(base, hue=rng.uniform(-0.03, 0.03), sat=1.2, val=0.42),
    }

    ground = lerp(INK, palette["deep"], 0.55)
    image = paper(SIZE, ground)
    draw = ImageDraw.Draw(image)

    SHAPES[ARCHETYPES[rng.randrange(len(ARCHETYPES))]](draw, SIZE, palette)

    image = fade_to_ink(image)
    # Held well back: the masthead, book title and mode toggle all sit over the
    # top of this, and art that competes with them is worse than no art. It is
    # a ground, not an illustration.
    image = Image.blend(Image.new("RGB", SIZE, INK), image, 0.62)
    # Softens the geometry just enough that it reads as printed rather than
    # vector-crisp, which is what keeps it from fighting the type.
    image = image.filter(ImageFilter.GaussianBlur(1.1))
    return grain(image)
def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    data = json.loads(CATALOGUE.read_text())
    books = data["books"] if isinstance(data, dict) else data

    for book in books:
        cover = make_cover(book["spine"], book["id"])
        path = OUT / f"{book['id']}.jpg"
        cover.save(path, "JPEG", quality=82, optimize=True, progressive=True)

    total = sum(p.stat().st_size for p in OUT.glob("*.jpg"))
    print(f"{len(books)} covers written to {OUT.relative_to(ROOT)}")
    print(f"total {total / 1e6:.2f}MB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
