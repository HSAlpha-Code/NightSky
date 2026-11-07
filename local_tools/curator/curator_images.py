"""Turn a chosen image (uploaded bytes or a URL you pasted) into stored files.

Stores a normalised JPEG (max 2048 px, so it fits Vercel's ~4.5 MB response limit) and a
480 px thumbnail. This runs only on your machine, once, when you add the image.
"""
import io
import uuid
from pathlib import Path
from urllib.parse import urlparse

import httpx
from PIL import Image, ImageOps

from curated.repo import thumb_name

MAX_BYTES = 25 * 1024 * 1024
MAX_SIDE, THUMB_SIDE = 2048, 480
Image.MAX_IMAGE_PIXELS = 100_000_000


class ImageError(Exception):
    pass


def fetch_url(url: str) -> bytes:
    if urlparse(url).scheme not in ("http", "https"):
        raise ImageError("The image URL must start with http:// or https://")
    try:
        with httpx.stream("GET", url, follow_redirects=True, timeout=30,
                          headers={"User-Agent": "NightSkyCurator/1.0"}) as r:
            if r.status_code != 200:
                raise ImageError(f"Download failed (HTTP {r.status_code}).")
            data = bytearray()
            for chunk in r.iter_bytes():
                data += chunk
                if len(data) > MAX_BYTES:
                    raise ImageError("The image is larger than 25 MB.")
            return bytes(data)
    except httpx.HTTPError as exc:
        raise ImageError(f"Download failed: {exc}") from exc


def store_image(data: bytes, folder: Path) -> str:
    """Validate, normalise and save; returns the stored file name."""
    if len(data) > MAX_BYTES:
        raise ImageError("The image is larger than 25 MB.")
    try:
        img = Image.open(io.BytesIO(data))
        img.load()
    except Exception as exc:  # Pillow raises many types for bad data
        raise ImageError("That file is not a readable image.") from exc
    img = ImageOps.exif_transpose(img)
    if img.mode not in ("RGB", "L"):
        background = Image.new("RGB", img.size, (0, 0, 0))
        rgba = img.convert("RGBA")
        background.paste(rgba, mask=rgba.split()[3])
        img = background
    img = img.convert("RGB")
    img.thumbnail((MAX_SIDE, MAX_SIDE))
    folder.mkdir(parents=True, exist_ok=True)
    name = f"{uuid.uuid4().hex}.jpg"
    img.save(folder / name, "JPEG", quality=88, optimize=True)
    thumb = img.copy()
    thumb.thumbnail((THUMB_SIDE, THUMB_SIDE))
    thumb.save(folder / thumb_name(name), "JPEG", quality=82)
    return name


def delete_files(name: str, folder: Path) -> None:
    for n in (name, thumb_name(name)):
        (folder / n).unlink(missing_ok=True)
