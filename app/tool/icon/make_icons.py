"""Generate the Android launcher icons from tool/icon/nightsky_icon_source.png.

Run from the app folder after changing the source image:
    python tool/icon/make_icons.py

The source is a rounded-square tile on a dark background. The tile is cropped out, its
corners are made transparent (so the launcher shows the tile's own rounded shape), and it's
written at every Android density. An adaptive icon (Android 8+) uses the same tile as its
foreground on a matching dark background, scaled into the adaptive-icon safe zone.
Needs Pillow and numpy.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "nightsky_icon_source.png"
RES = HERE.parents[1] / "android" / "app" / "src" / "main" / "res"

LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
ADAPTIVE = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
CORNER = 0.205        # tile corner radius as a fraction of its size (matches the artwork)
BACKGROUND = "#141826"  # adaptive icon background: the tile's dark navy edge
SAFE_ZONE = 72 / 108  # adaptive icons: only the centre 72dp of 108dp is always visible


def find_tile(img: Image.Image) -> tuple[int, int, int, int]:
    """Square bounding box of the tile: rows/columns that mostly differ from the plain
    background colour (sampled from the image's top and bottom edges)."""
    a = np.asarray(img.convert("RGB"), dtype=float)
    edge = np.concatenate([a[:20].reshape(-1, 3), a[-20:].reshape(-1, 3)])
    diff = np.abs(a - np.median(edge, axis=0)).sum(axis=2) > 40
    rows = np.nonzero(diff.mean(axis=1) > 0.3)[0]
    cols = np.nonzero(diff.mean(axis=0) > 0.3)[0]
    if len(rows) == 0 or len(cols) == 0:           # no plain background: use the whole image
        side = min(img.size)
        return 0, 0, side, side
    left, right, top, bottom = cols.min(), cols.max() + 1, rows.min(), rows.max() + 1
    side = max(right - left, bottom - top)          # keep it square
    cx, cy = (left + right) // 2, (top + bottom) // 2
    return cx - side // 2, cy - side // 2, cx + side // 2, cy + side // 2


def rounded_tile(img: Image.Image) -> Image.Image:
    tile = img.crop(find_tile(img)).convert("RGBA")
    size = tile.width
    big = size * 4                              # supersampled mask for smooth corners
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, big - 1, big - 1),
                                           radius=int(big * CORNER), fill=255)
    tile.putalpha(mask.resize((size, size), Image.LANCZOS))
    return tile


def main() -> None:
    tile = rounded_tile(Image.open(SOURCE))
    for density, px in LEGACY.items():
        folder = RES / f"mipmap-{density}"
        folder.mkdir(parents=True, exist_ok=True)
        tile.resize((px, px), Image.LANCZOS).save(folder / "ic_launcher.png")
        # Adaptive foreground: tile scaled into the safe zone, transparent around it.
        canvas = ADAPTIVE[density]
        inner = round(canvas * SAFE_ZONE)
        fg = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
        offset = (canvas - inner) // 2
        fg.alpha_composite(tile.resize((inner, inner), Image.LANCZOS), (offset, offset))
        fg.save(folder / "ic_launcher_foreground.png")

    anydpi = RES / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '</adaptive-icon>\n', encoding="utf-8")
    values = RES / "values"
    (values / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        f'    <color name="ic_launcher_background">{BACKGROUND}</color>\n</resources>\n',
        encoding="utf-8")
    print(f"icons written to {RES}")


if __name__ == "__main__":
    main()
