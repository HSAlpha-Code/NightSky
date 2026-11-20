"""Build NightSky's 8K NASA Deep Star Maps 2020 panorama.

Run from the repository root: python app/tool/sky_data/prepare_nasa.py
Requires numpy, Pillow and OpenCV with OpenEXR support. The original EXR is
cached outside the repository. No generated or upscaled stars are introduced.
Source and reuse policy: https://svs.gsfc.nasa.gov/4851/ and /help/.
"""

import argparse
import hashlib
import json
import os
import shutil
from pathlib import Path
import tempfile
import urllib.request
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image

SOURCE = "https://svs.gsfc.nasa.gov/vis/a000000/a004800/a004851/starmap_2020_8k_gal.exr"
OUT = Path(__file__).resolve().parents[2] / "assets" / "sky"


def save_lossless(pixels, target):
    """Require exact RGB round-trip, not just the lossy WebP quality=100 mode."""
    # Method controls compression effort/size, not pixel quality in lossless mode.
    # Favor larger files and faster reproducible preparation; validate exactness.
    temporary = target.with_suffix(".webp.part")
    Image.fromarray(pixels).save(temporary, "WEBP", lossless=True, quality=100, method=0, exact=True)
    with Image.open(temporary) as decoded:
        if not np.array_equal(np.asarray(decoded.convert("RGB")), pixels):
            raise ValueError(f"Lossless verification failed: {target}")
    temporary.replace(target)


def record_base_source(original):
    folder = OUT.parents[2] / "backend" / "panorama_packs" / "8k"
    outputs = []
    for side in ("east", "west"):
        path = folder / f"nasa_2020_{side}.webp"
        outputs.append({"file": path.name, "width": 4096, "height": 4096,
                        "bytes": path.stat().st_size,
                        "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    metadata = {"width": 8192, "height": 4096, "source": SOURCE,
                "sourceBytes": original.stat().st_size,
                "sourceSha256": hashlib.file_digest(original.open("rb"), "sha256").hexdigest(),
                "encoding": "WebP lossless RGB8; exact decoded-pixel verification",
                "conversion": "Native dimensions; linear HDR to sRGB8; values above display white clipped",
                "credit": "NASA/Goddard Space Flight Center Scientific Visualization Studio. Gaia DR2: ESA/Gaia/DPAC.",
                "license": "Public domain; https://svs.gsfc.nasa.gov/help/", "outputs": outputs}
    (folder / "source.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")


def download(url, target):
    """Fetch with bounded parallel range requests; never publish a partial file."""
    length = int(urllib.request.urlopen(urllib.request.Request(url, method="HEAD")).headers["Content-Length"])
    def part(i):
        start, end = length * i // 8, length * (i + 1) // 8 - 1
        path = target.with_suffix(f".part{i}")
        if path.exists() and path.stat().st_size == end - start + 1:
            return path
        req = urllib.request.Request(url, headers={"Range": f"bytes={start}-{end}"})
        with urllib.request.urlopen(req, timeout=120) as response, path.open("wb") as out:
            if response.status != 206:
                raise ValueError("NASA server did not honor byte range")
            while chunk := response.read(1024 * 1024):
                out.write(chunk)
        if path.stat().st_size != end - start + 1:
            raise ValueError("Incomplete NASA download")
        return path
    with ThreadPoolExecutor(max_workers=8) as pool:
        parts = list(pool.map(part, range(8)))
    with target.with_suffix(".part").open("wb") as out:
        for path in parts:
            with path.open("rb") as source:
                while chunk := source.read(1024 * 1024):
                    out.write(chunk)
            path.unlink()
    target.with_suffix(".part").replace(target)


def make_pack(k, cache):
    """Read strips from EXR, never allocating the entire 32K float image."""
    import OpenEXR
    import Imath
    url = SOURCE.replace("8k_gal", f"{k}k_gal")
    original = cache / url.rsplit("/", 1)[1]
    if not original.exists():
        print(f"Downloading {k}K NASA original", flush=True)
        download(url, original)
    width, height, tile_size = k * 1024, k * 512, 2048
    folder = OUT.parents[2] / "backend" / "panorama_packs" / f"{k}k"
    folder.mkdir(parents=True, exist_ok=True)
    source = OpenEXR.InputFile(str(original))
    box = source.header()["dataWindow"]
    if (box.min.x, box.min.y, box.max.x + 1, box.max.y + 1) != (0, 0, width, height):
        raise ValueError("Unexpected NASA map dimensions")
    tiles = []
    for y in range(0, height, tile_size):
        # One 2048-row strip, read one half-float channel at a time.
        strip = np.empty((tile_size, width, 3), dtype=np.uint8)
        for c, name in enumerate("RGB"):
            raw = source.channel(name, Imath.PixelType(Imath.PixelType.HALF), y, y + tile_size - 1)
            linear = np.frombuffer(raw, dtype=np.float16).reshape(tile_size, width).astype(np.float32)
            np.maximum(linear, 0, out=linear)
            srgb = np.where(linear <= 0.0031308, linear * 12.92,
                            1.055 * np.power(linear, 1 / 2.4) - 0.055)
            strip[:, :, c] = np.rint(np.clip(srgb, 0, 1) * 255).astype(np.uint8)
            del raw, linear, srgb
        for x in range(0, width, tile_size):
            name = f"{x // tile_size}_{y // tile_size}.webp"
            target = folder / name
            # A one-pixel gutter prevents bilinear seams between adjacent tiles.
            xs = np.arange(x - 1, x + tile_size + 1) % width
            # Vertical gutters fetched separately, including clamped poles.
            image = np.empty((tile_size + 2, tile_size + 2, 3), dtype=np.uint8)
            image[1:-1] = strip[:, xs]
            for dest, sy in [(0, max(0, y - 1)), (-1, min(height - 1, y + tile_size))]:
                for c, channel in enumerate("RGB"):
                    raw = source.channel(channel, Imath.PixelType(Imath.PixelType.HALF), sy, sy)
                    v = np.maximum(np.frombuffer(raw, dtype=np.float16).astype(np.float32)[xs], 0)
                    v = np.where(v <= 0.0031308, v * 12.92, 1.055 * np.power(v, 1 / 2.4) - 0.055)
                    image[dest, :, c] = np.rint(np.clip(v, 0, 1) * 255).astype(np.uint8)
            save_lossless(image, target)
            tiles.append({"file": name, "bytes": target.stat().st_size,
                          "sha256": hashlib.sha256(target.read_bytes()).hexdigest()})
        print(f"{k}K: rows {y + tile_size}/{height}", flush=True)
    source.close()
    manifest = {"version": 1, "width": width, "height": height, "tileSize": tile_size,
                "gutter": 1, "source": url, "sourceSha256": hashlib.file_digest(original.open("rb"), "sha256").hexdigest(),
                "sourceBytes": original.stat().st_size,
                "credit": "NASA/Goddard Space Flight Center Scientific Visualization Studio. Gaia DR2: ESA/Gaia/DPAC.",
                "license": "Public domain; https://svs.gsfc.nasa.gov/help/",
                "encoding": "WebP lossless RGB8; exact decoded-pixel verification",
                "conversion": "Native dimensions; linear HDR to sRGB8; values above display white clipped",
                "tiles": tiles}
    (folder / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"{k}K pack: {sum(t['bytes'] for t in tiles):,} bytes", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packs", action="store_true", help="Build downloadable 16K and 32K tile packs")
    args = parser.parse_args()
    cache = Path(tempfile.gettempdir()) / "nightsky-nasa"
    cache.mkdir(exist_ok=True)
    if args.packs:
        for k in (16, 32):
            make_pack(k, cache)
        return
    original = cache / SOURCE.rsplit("/", 1)[1]
    if not original.exists():
        partial = original.with_suffix(".part")
        print(f"Downloading {SOURCE}", flush=True)
        urllib.request.urlretrieve(SOURCE, partial)
        partial.replace(original)
    os.environ["OPENCV_IO_ENABLE_OPENEXR"] = "1"
    import cv2
    linear = cv2.imread(str(original), cv2.IMREAD_UNCHANGED)
    if linear is None or linear.shape != (4096, 8192, 3):
        raise ValueError("Expected NASA's 8192x4096 RGB OpenEXR")
    # NASA EXRs contain linear light. Convert to display sRGB, clipping HDR
    # highlights at white; preserve the exact Galactic plate-carree geometry.
    rgb = np.maximum(linear[:, :, ::-1], 0)
    srgb = np.where(rgb <= 0.0031308, 12.92 * rgb,
                    1.055 * np.power(rgb, 1 / 2.4) - 0.055)
    pixels = np.rint(np.clip(srgb, 0, 1) * 255).astype(np.uint8)
    OUT.mkdir(parents=True, exist_ok=True)
    for name, half in [("east", pixels[:, :4096]), ("west", pixels[:, 4096:])]:
        target = OUT / f"nasa_2020_{name}.webp"
        save_lossless(half, target)
        backend = OUT.parents[2] / "backend" / "panorama_packs" / "8k"
        backend.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(target, backend / target.name)
        print(f"{target.name}: {target.stat().st_size:,} bytes", flush=True)
    print(f"Source SHA-256: {hashlib.file_digest(original.open('rb'), 'sha256').hexdigest()}")
    record_base_source(original)


if __name__ == "__main__":
    main()
