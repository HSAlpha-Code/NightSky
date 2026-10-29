"""Space-telescope mosaics: Hubble / JWST around a landmark, stitched and coloured.

ESA ESASky publishes all public HST and JWST imaging as HiPS (sky tiles in which the
individual frames are already stitched together). We render the area around the object from
those tiles, so neighbouring pointings fill in the field instead of one small preview frame.

The tiles are greyscale. They are colourised (a false-colour palette per mission: warm for
JWST infrared, natural blue-white-gold for Hubble) and blended with the colour of a
ground-based survey, which also fills any part of the field the telescope never imaged.
"""
import io
import logging
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass

import numpy as np
from django.conf import settings
from PIL import Image
from scipy.ndimage import binary_erosion, gaussian_filter, white_tophat

from providers.hips_render import HipsRenderError, output_wcs, sample

log = logging.getLogger(__name__)


@dataclass(frozen=True)
class Layer:
    key: str
    name: str
    path: str          # relative to settings.ESASKY_HIPS_URL
    ext: str
    max_order: int


# Ordered by preference within each mission (first wins where layers overlap).
MISSIONS = {
    "jwst": (Layer("jwst_nircam", "JWST NIRCam", "JWST/NIRCam_Imaging", "png", 15),
             Layer("jwst_miri", "JWST MIRI", "JWST/MIRI_Imaging", "png", 13)),
    "hst": (Layer("hst_acs", "Hubble ACS", "HST/ACS", "jpg", 14),
            Layer("hst_wfc3", "Hubble WFC3", "HST/WFC3", "jpg", 14),
            Layer("hst_wfpc2", "Hubble WFPC2", "HST/WFPC2", "jpg", 13)),
}
MISSION_NAMES = {"jwst": "James Webb Space Telescope", "hst": "Hubble Space Telescope"}
# Tint of the added detail: warm for JWST's infrared, cool blue-white for Hubble.
TINTS = {"jwst": (1.25, 0.95, 0.7), "hst": (0.9, 1.0, 1.2)}
MIN_COVERAGE = 0.02        # less than 2 % of the field imaged = not worth showing


@dataclass
class Mosaic:
    image: bytes
    layers: list[str]
    coverage: float        # fraction of the field with telescope data


def _base_url(layer: Layer) -> str:
    return f"{settings.ESASKY_HIPS_URL.rstrip('/')}/{layer.path}"


def layer_detail(grey: np.ndarray, mask: np.ndarray, sigma: float) -> np.ndarray:
    """Fine detail of one telescope layer, normalised, faded out at the footprint edges.

    Every Hubble/JWST frame has its own brightness level, so pasting frames in directly gives
    a patchwork of squares. Instead we keep only structure finer than `sigma` (stars, dust
    lanes, filaments) by subtracting a local mean computed inside the footprint."""
    # Frame borders, chip gaps and detector edges: shrink the footprint so they're excluded.
    mask = binary_erosion(mask, iterations=max(2, round(sigma / 3)))
    if not mask.any():
        return np.zeros(mask.shape, np.float32)
    t = gaussian_filter(grey.astype(np.float32), 0.8)    # tame JPEG/pixel noise
    # White top-hat = image minus its morphological opening: keeps bright features smaller
    # than the kernel (stars, knots, filaments) and removes *any* flat level or brightness
    # step, so overlapping frames with different levels leave no squares or wedges.
    size = max(5, int(sigma) | 1)
    detail = white_tophat(np.where(mask, t, 0.0), size=size) * mask
    vals = detail[mask]
    noise = 1.4826 * float(np.median(np.abs(vals - np.median(vals))))
    detail = np.clip(detail - np.median(vals) - 3.0 * max(noise, 0.5), 0, None)
    positive = detail[detail > 0]
    peak = float(np.percentile(positive, 99.5)) if positive.size else 1.0
    den = gaussian_filter(mask.astype(np.float32), sigma)
    edge_fade = np.clip((den - 0.6) * 3.0, 0, 1) ** 2   # wide, smooth fade: no seams
    return np.tanh(detail / max(peak, 1.0) * 1.5) * edge_fade   # 0..1, soft highlights


def compose(telescope: list[tuple[np.ndarray, np.ndarray, Layer]],
            background: np.ndarray | None, shape, tint) -> tuple[np.ndarray, float]:
    """Survey colour and brightness + telescope detail (first layer wins where they overlap)."""
    h, w = shape
    bg = (background.astype(np.float32) if background is not None
          else np.full((h, w, 3), 10.0, np.float32))
    detail = np.zeros((h, w), np.float32)
    covered = np.zeros((h, w), bool)
    sigma = max(h, w) / 60
    for rgb, mask, _layer in reversed(telescope):
        # Layers are combined with max(): where instruments overlap the sharpest detail wins,
        # and one instrument's frame edge can't cut a hole into another's image.
        detail = np.maximum(detail, layer_detail(rgb.mean(axis=2), mask, sigma))
        covered |= mask
    # Colour of the added light: the survey's own colour, nudged towards the mission tint.
    lum = bg.mean(axis=2, keepdims=True)
    hue = np.clip(bg / np.maximum(lum, 6.0), 0.4, 2.2)
    colour = 0.5 * hue + 0.5 * np.asarray(tint, np.float32)
    colour = colour / colour.max(axis=2, keepdims=True)
    # "Screen" blend: brightens with the telescope detail but can never blow out to white.
    # Less light is added where the survey is already bright (nebula and galaxy cores).
    light = np.clip(detail[..., None] * 230.0 * colour * (1.0 - 0.5 * lum / 255.0), 0, 255)
    out = 255.0 - (255.0 - bg) * (255.0 - light) / 255.0
    return np.clip(out, 0, 255).astype(np.uint8), float(covered.mean())


def _sample_layers(mission, ra, dec, fov_deg, size_px):
    """All instrument layers of a mission, fetched in parallel; layers without data dropped."""
    def one(layer):
        try:
            # A few slow/failed tiles only leave a gap that the survey fills, so don't let
            # them throw away the whole layer.
            rgb, mask, any_tile = sample(_base_url(layer), layer.max_order, ra, dec, fov_deg,
                                         0.0, size_px, size_px, ext=layer.ext,
                                         tolerate_missing=True)
        except HipsRenderError as exc:
            log.warning("%s tiles failed: %s", layer.key, exc)
            return None
        return (rgb, mask, layer) if any_tile and mask.any() else None

    layers = MISSIONS[mission]
    with ThreadPoolExecutor(max_workers=len(layers)) as pool:
        return [r for r in pool.map(one, layers) if r is not None]


def frame_field(mask: np.ndarray, ra: float, dec: float, fov_deg: float,
                min_fov: float, max_fov: float) -> tuple[float, float, float] | None:
    """Centre and size of a square that holds all imaged pixels of a quick-look mask.

    The object stays in view: the box is grown to include the field centre."""
    n = mask.shape[0]
    rows, cols = np.nonzero(mask)
    if len(rows) == 0:
        return None
    c0, c1 = min(cols.min(), n // 2), max(cols.max(), n // 2)
    r0, r1 = min(rows.min(), n // 2), max(rows.max(), n // 2)
    side = max(c1 - c0 + 1, r1 - r0 + 1) * 1.1               # 10 % margin
    fov = float(np.clip(side * fov_deg / n, min_fov, max_fov))
    wcs = output_wcs(ra, dec, fov_deg, 0.0, n, n)
    cx, cy = (c0 + c1) / 2, (r0 + r1) / 2
    new_ra, new_dec = wcs.wcs_pix2world([[cx, n - 1 - cy]], 0)[0]
    return float(new_ra) % 360, float(new_dec), fov


def locate(mission: str, ra: float, dec: float, search_fov: float, min_fov: float):
    """Quick low-res look at where the mission has data around the object.

    Returns (ra, dec, fov) framing all those frames, or None if there are none."""
    probe = 192
    found = _sample_layers(mission, ra, dec, search_fov, probe)
    if not found:
        return None
    mask = np.logical_or.reduce([m for _, m, _ in found])
    if mask.sum() < 4:                     # a few stray pixels: no real coverage
        return None
    return frame_field(mask, ra, dec, search_fov, min_fov, search_fov)


def render(mission: str, ra: float, dec: float, fov_deg: float, size_px: int,
           background: bytes | None) -> Mosaic | None:
    """Colour mosaic for 'jwst' or 'hst', or None if the mission barely covers the field."""
    found = _sample_layers(mission, ra, dec, fov_deg, size_px)
    if not found:
        return None
    bg = None
    if background:
        bg = np.asarray(Image.open(io.BytesIO(background)).convert("RGB")
                        .resize((size_px, size_px)))
    image, coverage = compose(found, bg, (size_px, size_px), TINTS[mission])
    if coverage < MIN_COVERAGE:
        return None
    buf = io.BytesIO()
    Image.fromarray(image).save(buf, "JPEG", quality=90)
    return Mosaic(buf.getvalue(), [layer.name for _, _, layer in found], coverage)
