# Story card art

Drop-in art for the Instagram/Facebook Story cards. Everything here is
referenced by exact filename from `lib/data/models/story_template.dart` and
`lib/ui/sharing/story_card.dart`, so **replacing a file is the whole job** —
no code change, no rebuild of anything but the app itself.

| File | Size | Notes |
|---|---|---|
| `image1.jpg` … `image6.jpg` | 1080x1920 (9:16) | Backgrounds. Cropped with `BoxFit.cover`, so anything not 9:16 loses its edges, and **upscaled** if smaller — export at full size or the card goes soft. |
| `bookmark.png` | any, ~1:3 | The ribbon, top-right. Stays PNG: it needs its transparency. |

Backgrounds are **JPEG**, quality 85. They are photographs, and the same
images as PNG cost about six times the bytes for no visible difference —
8.7MB against 1.4MB across the six. Keep new art in JPEG; if you swap in a
`.png`, update the paths in `lib/data/models/story_template.dart` to match,
or the app falls through to its gradient fallback.

## Which templates take dark text

`StoryTemplate.lightText` decides the polarity of the scrim, the wordmark and
the footer, and the title's halo. It has to match the art:

| Template | Text | Background needs to be |
|---|---|---|
| 1, 2, 3 | Dark (navy / green / near-black) | **Light** — pale sky, parchment, washed-out photo |
| 4, 5, 6 | White | **Dark, or dark enough at the centre** |

Putting a bright photograph behind templates 1–3 is fine; putting one behind
4–6 is what makes white type vanish. If a photo has to go somewhere it
doesn't suit, flip that template's `lightText` **and** its `mainTitleColor`
together — a test in `test/story_template_test.dart` fails if only one moves.

## Cropping the bookmark

Export it tightly cropped to the ribbon — the file is trimmed to its opaque
bounds in the repo. Transparent margin left inside the PNG gets fitted along
with the art and shrinks the visible ribbon; a version with 29% padding
either side rendered the ribbon at about a third of its intended width.
