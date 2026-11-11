"""Download and process Axel Mellinger's All-Sky Milky Way Panorama for offline Sky View.

Run from the app folder:
    python tool/sky_data/prepare_mellinger.py

Source: Axel Mellinger's all-sky optical mosaic (Mellinger 2009, PASP 121, 1180) retrieved via
NASA SkyView (`Mellinger Red, Mellinger Green, Mellinger Blue`) in Galactic plate-carree (`CAR`)
coordinates at native 0.1 deg/px resolution (3600 x 1800):
- Image centre (u = 0.5, v = 0.5) is Galactic (l = 0 deg, b = 0 deg).
- Horizontal axis u in [0, 1]: Galactic longitude l from +180 deg (left) through 0 deg (centre)
  to -180 deg (right), i.e. u = 0.5 - l / 360.
- Vertical axis v in [0, 1]: Galactic latitude b from +90 deg (North Galactic Pole, top) to
  -90 deg (South Galactic Pole, bottom), i.e. v = 0.5 - b / 180.

Encoded as WebP (quality 82) so a single ~1.2 MB asset serves all three runtime quality tiers via
Flutter's `instantiateImageCodec(targetWidth: ...)`:
- Low:      1024 x 512  (~2 MB GPU texture)
- Balanced: 2048 x 1024 (~8 MB GPU texture, default)
- High:     3600 x 1800 (~25 MB GPU texture, native 0.1 deg/px)
"""
import io
import math
from pathlib import Path

import numpy as np
import requests
from PIL import Image

SKYVIEW_QUERY = "https://skyview.gsfc.nasa.gov/current/cgi/runquery.pl"
SKYVIEW_TEMP = "https://skyview.gsfc.nasa.gov/tempspace/fits/"
WIDTH, HEIGHT = 3600, 1800
WEBP_QUALITY = 82

OUT = Path(__file__).resolve().parents[2] / "assets" / "sky" / "mellinger_galactic.webp"

# IAU / Hipparcos ICRS (J2000) -> Galactic rotation matrix (Hipparcos Vol. 1, Sec. 1.5.3).
ICRS_TO_GALACTIC = np.array([
    [-0.0548755604162154, -0.8734370902348850, -0.4838350155487132],
    [0.4941094278755837, -0.4448296299600112, 0.7469822444972189],
    [-0.8676661490190047, -0.1980763734312015, 0.4559837761750669],
])


def fetch_mellinger_rgb() -> Image.Image:
    params = {
        "Position": "0,0",
        "Survey": "Mellinger Red,Mellinger Green,Mellinger Blue",
        "Pixels": f"{WIDTH},{HEIGHT}",
        "Size": "360,180",
        "Projection": "Car",
        "Coordinates": "Galactic",
        "Scaling": "Linear",
        "RGB": "1",
        "Return": "filename",
    }
    r = requests.get(SKYVIEW_QUERY, params=params, timeout=60)
    r.raise_for_status()
    stem = r.text.strip()
    if not stem.startswith("skv"):
        raise RuntimeError(f"Unexpected SkyView response: {stem[:200]}")
    img_resp = requests.get(f"{SKYVIEW_TEMP}{stem}_rgb.jpg", timeout=60)
    img_resp.raise_for_status()
    return Image.open(io.BytesIO(img_resp.content)).convert("RGB")


def verify_alignment(img: Image.Image) -> None:
    lum = np.asarray(img, dtype=float).mean(axis=2)
    w, h = img.size
    checks = [
        ("Sirius", 101.2872, -16.7161),
        ("Vega", 279.2347, 38.7837),
        ("Arcturus", 213.9153, 19.1824),
        ("Fomalhaut", 344.4127, -29.6222),
        ("Achernar", 24.4286, -57.2368),
        ("M31", 10.6847, 41.2687),
    ]
    for label, ra_deg, dec_deg in checks:
        ra, dec = math.radians(ra_deg), math.radians(dec_deg)
        icrs = np.array([math.cos(dec) * math.cos(ra), math.cos(dec) * math.sin(ra), math.sin(dec)])
        gal = ICRS_TO_GALACTIC @ icrs
        l_deg = math.degrees(math.atan2(gal[1], gal[0]))
        b_deg = math.degrees(math.asin(max(-1.0, min(1.0, gal[2]))))
        px = ((w / 2.0 - 0.5) - l_deg * (w / 360.0)) % w
        py = (h / 2.0 - 0.5) - b_deg * (h / 180.0)
        ix, iy = int(round(px)), int(round(py))
        patch = lum[iy - 6 : iy + 7, ix - 6 : ix + 7]
        dy, dx = np.unravel_index(np.argmax(patch), patch.shape)
        offset_deg = math.hypot(dx - 6, dy - 6) * (360.0 / w)
        if offset_deg > 0.25 or patch.max() < np.median(patch) + 80:
            raise AssertionError(f"Alignment check failed for {label}: offset={offset_deg:.2f} deg")


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img = fetch_mellinger_rgb()
    if img.size != (WIDTH, HEIGHT):
        raise RuntimeError(f"Expected {(WIDTH, HEIGHT)}, got {img.size}")
    verify_alignment(img)
    img.save(OUT, format="WEBP", quality=WEBP_QUALITY, method=6)
    size_kb = OUT.stat().st_size / 1024
    print(f"Wrote {OUT} ({WIDTH}x{HEIGHT} WebP q={WEBP_QUALITY}, {size_kb:.1f} KB)")


if __name__ == "__main__":
    main()
