"""Pan-STARRS DR2 cutout service (STScI ps1images), g/r/i colour composite."""
import io
import math

from django.conf import settings
from PIL import Image

from config.http import ExternalServiceError, http_get

from .base import ImageProvider, ProviderError

PIXEL_ARCSEC = 0.25          # native PS1 stack pixel scale
MAX_SOURCE_PX = 6000         # service limit on the cutout size, in native pixels


class PanStarrsProvider(ImageProvider):
    key = "panstarrs"
    name = "Pan-STARRS DR2 (STScI)"
    description = "Deep g/r/i colour cutouts from the Pan-STARRS1 stacks. Small fields only (≤ 0.4°)."
    wavelength = "optical"
    coverage = "dec > -30, fov <= 0.4 deg"
    all_sky = False
    service = "panstarrs"
    credit = "Pan-STARRS1 Surveys (PS1) via STScI/MAST"
    min_dec = -30.0
    max_fov_deg = MAX_SOURCE_PX * PIXEL_ARCSEC / 3600  # ≈ 0.42°

    def supports(self, ra, dec, fov_deg=None):
        return dec >= self.min_dec and (fov_deg is None or fov_deg <= self.max_fov_deg)

    def fetch_cutout(self, ra, dec, fov_deg, rotation_deg, width_px, height_px) -> bytes:
        # Fetch a square covering the rotated output frame, then rotate and crop locally.
        diag_deg = fov_deg * math.hypot(1, height_px / width_px)
        size = min(MAX_SOURCE_PX, math.ceil(diag_deg * 3600 / PIXEL_ARCSEC))
        out_size = math.ceil(max(width_px, height_px) * math.hypot(1, height_px / width_px))
        try:
            listing = http_get(f"{settings.PANSTARRS_URL}/ps1filenames.py",
                               params={"ra": ra, "dec": dec, "filters": "grizy", "type": "stack"})
            channels = pick_channels(_parse_filenames(listing.text))
            if not channels:
                raise ProviderError("Pan-STARRS has no stack image at this position")
            resp = http_get(f"{settings.PANSTARRS_URL}/fitscut.cgi", params={
                **channels,
                "ra": ra, "dec": dec, "size": size, "output_size": min(out_size, 3000),
                "format": "jpg", "autoscale": 99.5,
            })
        except ExternalServiceError as exc:
            raise ProviderError(str(exc)) from exc
        if not resp.headers.get("content-type", "").startswith("image/"):
            raise ProviderError(f"Pan-STARRS returned non-image: {resp.text[:200]}")
        return _rotate_and_crop(resp.content, fov_deg, rotation_deg, width_px, height_px,
                                source_fov_deg=size * PIXEL_ARCSEC / 3600)


def pick_channels(files: dict[str, str]) -> dict[str, str]:
    """fitscut red/green/blue params. Prefer i/r/g; some sky cells lack a filter (e.g. no r at
    M42), so otherwise use the reddest, middle and bluest available; one filter = greyscale."""
    if all(f in files for f in "irg"):
        return {"red": files["i"], "green": files["r"], "blue": files["g"]}
    available = [f for f in "yzirg" if f in files]          # red -> blue
    if len(available) >= 3:
        r, g, b = available[0], available[len(available) // 2], available[-1]
        return {"red": files[r], "green": files[g], "blue": files[b]}
    if available:
        return {"red": files[available[0]]}
    return {}


def _parse_filenames(text: str) -> dict[str, str]:
    lines = text.strip().splitlines()
    if not lines:
        return {}
    header = lines[0].split()
    f_idx, n_idx = header.index("filter"), header.index("filename")
    return {row.split()[f_idx]: row.split()[n_idx] for row in lines[1:] if row.strip()}


def _rotate_and_crop(data, fov_deg, rotation_deg, width_px, height_px, source_fov_deg):
    """Source image is north-up, east-left. Rotate so image-up has the requested position angle."""
    img = Image.open(io.BytesIO(data)).convert("RGB")
    # Rotating the picture clockwise by PA puts the direction at PA (east of north) at the top.
    img = img.rotate(-rotation_deg, resample=Image.BICUBIC, expand=False)
    scale = img.width / source_fov_deg              # px per degree
    crop_w, crop_h = fov_deg * scale, fov_deg * scale * height_px / width_px
    cx, cy = img.width / 2, img.height / 2
    box = (round(cx - crop_w / 2), round(cy - crop_h / 2),
           round(cx + crop_w / 2), round(cy + crop_h / 2))
    img = img.crop(box).resize((int(width_px), int(height_px)), Image.LANCZOS)
    out = io.BytesIO()
    img.save(out, "JPEG", quality=90)
    return out.getvalue()
