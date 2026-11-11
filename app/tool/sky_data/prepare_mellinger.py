"""Build a true high-resolution 8K (8192x4096) Mellinger Milky Way panorama for Sky View.

Run from the app folder:
    python tool/sky_data/prepare_mellinger.py

Why tiled TAN stitching?
NASA SkyView stores Axel Mellinger's optical mosaic (Mellinger 2009, PASP 121, 1180) as a
multi-resolution pyramid: cutouts >= 30 deg fall back to a coarse ~0.5 deg/px overview, whereas
cutouts < 30 deg read directly from the sharp high-resolution survey plates. We therefore fetch
114 overlapping 27x27 deg gnomonic (`TAN`) cutouts at 28 px/deg (`Min=0, Max=255, Lanczos3`) and
reproject them with raised-cosine feathering onto an exact 8192x4096 Galactic `CAR` grid.

Why two 4096x4096 hemisphere WebPs?
Splitting 8192x4096 into `mellinger_east.webp` (u in [0, 0.5], l in [+180, 0]) and
`mellinger_west.webp` (u in [0.5, 1.0], l in [0, -180]) keeps every GPU texture <= 4096x4096 so
even budget mobile GPUs with a 4096 max-texture limit render the full 8K sky seamlessly.
"""
from concurrent.futures import ThreadPoolExecutor, as_completed
import io
import math
import os
from pathlib import Path
import tempfile
import time

import numpy as np
import requests
from PIL import Image, ImageFilter

SKYVIEW_QUERY = "https://skyview.gsfc.nasa.gov/current/cgi/runquery.pl"
SKYVIEW_TEMP = "https://skyview.gsfc.nasa.gov/tempspace/fits/"

FULL_W, FULL_H = 8192, 4096
HALF_W = FULL_W // 2  # 4096 x 4096 per hemisphere
TILE_FOV_DEG = 27.0   # < 30 deg so SkyView uses full-resolution Mellinger plates
TILE_PX = 756         # 28.0 px/deg (> 22.76 px/deg of 8192x4096 output)
WEBP_QUALITY = 84

OUT_DIR = Path(__file__).resolve().parents[2] / "assets" / "sky"
EAST_OUT = OUT_DIR / "mellinger_east.webp"
WEST_OUT = OUT_DIR / "mellinger_west.webp"
LEGACY_OUT = OUT_DIR / "mellinger_galactic.webp"

CACHE_DIR = Path(os.environ.get("TEMP") or tempfile.gettempdir()) / "opencode" / "mellinger_8k_tiles"

ICRS_TO_GALACTIC = np.array([
    [-0.0548755604162154, -0.8734370902348850, -0.4838350155487132],
    [0.4941094278755837, -0.4448296299600112, 0.7469822444972189],
    [-0.8676661490190047, -0.1980763734312015, 0.4559837761750669],
])


def tile_centers() -> list[tuple[float, float]]:
    rings = [
        (0.0, 18),
        (20.0, 18), (-20.0, 18),
        (40.0, 14), (-40.0, 14),
        (60.0, 10), (-60.0, 10),
        (77.0, 6),  (-77.0, 6),
    ]
    out = []
    for b0, count in rings:
        for k in range(count):
            out.append((round(k * 360.0 / count, 4), b0))
    return out


def fetch_one_tile(l0: float, b0: float) -> tuple[float, float, bytes]:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cache_file = CACHE_DIR / f"tan_{l0:07.3f}_{b0:+06.2f}_{TILE_PX}.jpg"
    if cache_file.exists() and cache_file.stat().st_size > 2000:
        return l0, b0, cache_file.read_bytes()

    params = {
        "Position": f"{l0:.4f},{b0:.4f}",
        "Survey": "Mellinger Red,Mellinger Green,Mellinger Blue",
        "Pixels": f"{TILE_PX},{TILE_PX}",
        "Size": f"{TILE_FOV_DEG},{TILE_FOV_DEG}",
        "Projection": "Tan",
        "Coordinates": "Galactic",
        "Scaling": "Linear",
        "Sampler": "Lanczos3",
        "Min": "0",
        "Max": "255",
        "RGB": "1",
        "Return": "filename",
    }
    for attempt in range(5):
        try:
            r = requests.get(SKYVIEW_QUERY, params=params, timeout=45)
            stem = r.text.strip()
            if "too many processes" in stem.lower() or not stem.startswith("skv"):
                time.sleep(1.5 * (attempt + 1))
                continue
            img_r = requests.get(f"{SKYVIEW_TEMP}{stem}_rgb.jpg", timeout=45)
            if img_r.status_code == 200 and img_r.headers.get("content-type", "").startswith("image/"):
                cache_file.write_bytes(img_r.content)
                return l0, b0, img_r.content
        except requests.RequestException:
            pass
        time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"Failed to fetch SkyView tile ({l0}, {b0}) after retries")


def stitch_8k(tiles: list[tuple[float, float, bytes]]) -> Image.Image:
    accum = np.zeros((FULL_H, FULL_W, 3), dtype=np.float32)
    weight_sum = np.zeros((FULL_H, FULL_W), dtype=np.float32)

    # Precompute longitude trig across the 8192 columns (u = (x + 0.5)/W, l = (0.5 - u)*2*pi).
    xs = (np.arange(FULL_W, dtype=np.float32) + 0.5) / FULL_W
    l_rad = (0.5 - xs) * (2.0 * math.pi)
    cos_l = np.cos(l_rad)
    sin_l = np.sin(l_rad)

    ys = (np.arange(FULL_H, dtype=np.float32) + 0.5) / FULL_H
    b_deg_all = (0.5 - ys) * 180.0
    b_rad_all = np.radians(b_deg_all)
    cos_b_all = np.cos(b_rad_all)
    sin_b_all = np.sin(b_rad_all)

    scale_deg = TILE_FOV_DEG / TILE_PX
    half_px = TILE_PX * 0.5 - 0.5
    max_tan = math.tan(math.radians(TILE_FOV_DEG * 0.5))

    for l0_deg, b0_deg, jpg_bytes in tiles:
        tile_rgb = np.asarray(Image.open(io.BytesIO(jpg_bytes)).convert("RGB"), dtype=np.float32)

        # Restrict rows to the latitude band this 27x27 deg TAN tile can possibly cover.
        if b0_deg >= 70.0:
            b_min, b_max = b0_deg - 15.5, 90.0
        elif b0_deg <= -70.0:
            b_min, b_max = -90.0, b0_deg + 15.5
        else:
            b_min, b_max = b0_deg - 19.5, b0_deg + 19.5

        row_mask = (b_deg_all >= b_min) & (b_deg_all <= b_max)
        row_idx = np.nonzero(row_mask)[0]
        if len(row_idx) == 0:
            continue

        cb = cos_b_all[row_idx][:, None]  # (R, 1)
        sb = sin_b_all[row_idx][:, None]  # (R, 1)
        gx = cb * cos_l[None, :]          # (R, W)
        gy = cb * sin_l[None, :]          # (R, W)

        l0 = math.radians(l0_deg)
        b0 = math.radians(b0_deg)
        cx, cy, cz = math.cos(b0) * math.cos(l0), math.cos(b0) * math.sin(l0), math.sin(b0)
        ex, ey = -math.sin(l0), math.cos(l0)
        nx, ny, nz = -math.sin(b0) * math.cos(l0), -math.sin(b0) * math.sin(l0), math.cos(b0)

        dot_c = gx * cx + gy * cy + sb * cz
        valid = dot_c > 0.80
        if not np.any(valid):
            continue

        vr, vc = np.nonzero(valid)
        dc = dot_c[vr, vc]
        gxv = gx[vr, vc]
        gyv = gy[vr, vc]
        gzv = sb[vr, 0]

        xi = (gxv * ex + gyv * ey) / dc
        eta = (gxv * nx + gyv * ny + gzv * nz) / dc

        inside = (np.abs(xi) < max_tan * 0.985) & (np.abs(eta) < max_tan * 0.985)
        if not np.any(inside):
            continue

        vr = vr[inside]
        vc = vc[inside]
        xi = xi[inside]
        eta = eta[inside]

        px = half_px - np.degrees(xi) / scale_deg
        py = half_px - np.degrees(eta) / scale_deg

        in_px = (px >= 0.0) & (px < TILE_PX - 1.001) & (py >= 0.0) & (py < TILE_PX - 1.001)
        if not np.any(in_px):
            continue

        vr = vr[in_px]
        vc = vc[in_px]
        px = px[in_px]
        py = py[in_px]
        xi = xi[in_px]
        eta = eta[in_px]

        # Bilinear sample from tile_rgb
        x0 = px.astype(np.int32)
        y0 = py.astype(np.int32)
        fx = (px - x0)[:, None]
        fy = (py - y0)[:, None]

        c00 = tile_rgb[y0, x0]
        c10 = tile_rgb[y0, x0 + 1]
        c01 = tile_rgb[y0 + 1, x0]
        c11 = tile_rgb[y0 + 1, x0 + 1]
        sampled = (c00 * (1.0 - fx) + c10 * fx) * (1.0 - fy) + (c01 * (1.0 - fx) + c11 * fx) * fy

        # Smooth raised-cosine feathering weight -> 0 at tile border, 1 at tile centre.
        ux = np.clip(np.abs(xi) / max_tan, 0.0, 1.0)
        uy = np.clip(np.abs(eta) / max_tan, 0.0, 1.0)
        w = (np.cos(0.5 * math.pi * ux) ** 2) * (np.cos(0.5 * math.pi * uy) ** 2) + 1e-4

        out_rows = row_idx[vr]
        accum[out_rows, vc] += sampled * w[:, None]
        weight_sum[out_rows, vc] += w

    missing = int(np.sum(weight_sum <= 0))
    if missing > 0:
        raise RuntimeError(f"Mosaic has {missing} uncovered pixels!")

    rgb = np.clip(accum / weight_sum[:, :, None], 0.0, 255.0).astype(np.uint8)
    img = Image.fromarray(rgb)
    # Gentle micro-contrast unsharp mask on midtones without ringing saturated star cores.
    return img.filter(ImageFilter.UnsharpMask(radius=0.8, percent=15, threshold=5))


def verify_alignment(img: Image.Image) -> None:
    lum = np.asarray(img, dtype=np.float32).mean(axis=2)
    w, h = img.size
    checks = [
        ("Sirius", 101.2872, -16.7161),
        ("Vega", 279.2347, 38.7837),
        ("Arcturus", 213.9153, 19.1824),
        ("Fomalhaut", 344.4127, -29.6222),
        ("Achernar", 24.4286, -57.2368),
        ("M31", 10.6847, 41.2687),
    ]
    r_win = 16  # +/- 16 px (~0.7 deg) astrometric centroid aperture
    yy, xx = np.mgrid[-r_win : r_win + 1, -r_win : r_win + 1]
    for label, ra_deg, dec_deg in checks:
        ra, dec = math.radians(ra_deg), math.radians(dec_deg)
        icrs = np.array([math.cos(dec) * math.cos(ra), math.cos(dec) * math.sin(ra), math.sin(dec)])
        gal = ICRS_TO_GALACTIC @ icrs
        l_deg = math.degrees(math.atan2(gal[1], gal[0]))
        b_deg = math.degrees(math.asin(max(-1.0, min(1.0, gal[2]))))
        px = ((w / 2.0 - 0.5) - l_deg * (w / 360.0)) % w
        py = (h / 2.0 - 0.5) - b_deg * (h / 180.0)
        ix, iy = int(round(px)), int(round(py))
        patch = lum[iy - r_win : iy + r_win + 1, ix - r_win : ix + r_win + 1]
        bg = float(np.median(patch))
        peak = float(patch.max())
        # Half-max flux-weighted centroid (standard astrometry for saturated photographic stars)
        thr = bg + 0.55 * (peak - bg)
        weights = np.maximum(0.0, patch - thr)
        cx = float((weights * xx).sum() / weights.sum())
        cy = float((weights * yy).sum() / weights.sum())
        offset_deg = math.hypot(cx, cy) * (360.0 / w)
        print(f"  align {label:10s}: centroid_offset={offset_deg:.3f} deg (center={patch[r_win, r_win]:.1f}, bg={bg:.1f})")
        if offset_deg > 0.20 or peak < bg + 80:
            raise AssertionError(f"Alignment check failed for {label}: offset={offset_deg:.3f} deg")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    centers = tile_centers()
    print(f"Fetching {len(centers)} high-res Mellinger TAN tiles ({TILE_FOV_DEG} deg @ {TILE_PX} px)...")
    t0 = time.time()
    fetched: list[tuple[float, float, bytes]] = []
    with ThreadPoolExecutor(max_workers=5) as pool:
        futs = {pool.submit(fetch_one_tile, l0, b0): (l0, b0) for l0, b0 in centers}
        for idx, fut in enumerate(as_completed(futs), 1):
            fetched.append(fut.result())
            if idx % 20 == 0 or idx == len(centers):
                print(f"  {idx}/{len(centers)} tiles ready ({time.time() - t0:.1f}s)")

    print(f"Stitching {FULL_W}x{FULL_H} Galactic CAR panorama...")
    full_img = stitch_8k(fetched)
    verify_alignment(full_img)

    east = full_img.crop((0, 0, HALF_W, FULL_H))
    west = full_img.crop((HALF_W, 0, FULL_W, FULL_H))

    east.save(EAST_OUT, format="WEBP", quality=WEBP_QUALITY, method=4)
    west.save(WEST_OUT, format="WEBP", quality=WEBP_QUALITY, method=4)
    if LEGACY_OUT.exists():
        LEGACY_OUT.unlink()

    east_kb = EAST_OUT.stat().st_size / 1024
    west_kb = WEST_OUT.stat().st_size / 1024
    print(
        f"Done! Wrote 8K dual-hemisphere panorama:\n"
        f"  {EAST_OUT.name}: {HALF_W}x{FULL_H} ({east_kb:.1f} KB)\n"
        f"  {WEST_OUT.name}: {HALF_W}x{FULL_H} ({west_kb:.1f} KB)\n"
        f"  Total Mellinger 8K size: {(east_kb + west_kb)/1024:.2f} MB"
    )


if __name__ == "__main__":
    main()
