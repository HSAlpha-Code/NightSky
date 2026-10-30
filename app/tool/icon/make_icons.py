"""Generate the Android launcher icons from tool/icon/nightsky_icon_source.png.

Run from the app folder after changing the source image:
    python tool/icon/make_icons.py

The source is used as-is, full bleed (no cropping or masking): it's only made square (by
extending its edge colours if the sides differ by a few pixels) and resized for every Android
density. Android 8+ gets an adaptive icon with the image filling the whole layer, so each
launcher applies its own shape (circle, squircle, ...). Needs Pillow and numpy.
"""
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "nightsky_icon_source.png"
RES = HERE.parents[1] / "android" / "app" / "src" / "main" / "res"

LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
ADAPTIVE = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}


def make_square(img: Image.Image) -> Image.Image:
    """Pad the shorter side by repeating the edge rows/columns (no cropping, no borders)."""
    a = np.asarray(img.convert("RGB"))
    h, w, _ = a.shape
    if h == w:
        return Image.fromarray(a)
    pad = abs(h - w)
    before, after = pad // 2, pad - pad // 2
    widths = ((before, after), (0, 0), (0, 0)) if h < w else ((0, 0), (before, after), (0, 0))
    return Image.fromarray(np.pad(a, widths, mode="edge"))


def edge_colour(img: Image.Image) -> str:
    """Average colour of the image border, for the adaptive icon's background layer."""
    a = np.asarray(img.convert("RGB"), dtype=float)
    border = np.concatenate([a[:4].reshape(-1, 3), a[-4:].reshape(-1, 3),
                             a[:, :4].reshape(-1, 3), a[:, -4:].reshape(-1, 3)])
    r, g, b = border.mean(axis=0).round().astype(int)
    return f"#{r:02X}{g:02X}{b:02X}"


def main() -> None:
    source = Image.open(SOURCE)
    icon = make_square(source)
    for density, px in LEGACY.items():
        folder = RES / f"mipmap-{density}"
        folder.mkdir(parents=True, exist_ok=True)
        icon.resize((px, px), Image.LANCZOS).save(folder / "ic_launcher.png")
        # Adaptive foreground: the whole image fills the 108dp layer (full bleed). Launchers
        # mask it to their shape and show the centre ~66 %, where the artwork's subject is.
        size = ADAPTIVE[density]
        icon.resize((size, size), Image.LANCZOS).save(folder / "ic_launcher_foreground.png")

    anydpi = RES / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '</adaptive-icon>\n', encoding="utf-8")
    (RES / "values" / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        f'    <color name="ic_launcher_background">{edge_colour(icon)}</color>\n'
        '</resources>\n', encoding="utf-8")
    print(f"icons written to {RES} (source {source.size} -> {icon.size})")


if __name__ == "__main__":
    main()
