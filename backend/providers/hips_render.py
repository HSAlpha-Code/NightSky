"""Render a TAN cutout locally from HiPS tiles (used when the hips2fits service is unreachable).

HiPS = HEALPix-tiled sky images. We work out which HEALPix pixel every output pixel falls in,
download only the tiles needed (in parallel, cached), and sample them (nearest neighbour).
"""
import io
import math
from concurrent.futures import ThreadPoolExecutor

import astropy.units as u
import numpy as np
from astropy.wcs import WCS
from astropy_healpix import lonlat_to_healpix
from django.core.cache import cache
from PIL import Image

from config.http import ExternalServiceError, http_get

TILE_WIDTH = 512
MAX_TILES = 96               # drop an order rather than download more tiles than this
FULL_SKY_PIXEL_DEG = math.degrees(math.sqrt(4 * math.pi / 12))  # HEALPix order-0 pixel ≈ 58.6°


class HipsRenderError(Exception):
    pass


def output_wcs(ra, dec, fov_deg, rotation_deg, width_px, height_px) -> WCS:
    """TAN projection; image "up" points at position angle rotation_deg (east of north)."""
    s = fov_deg / width_px
    t = math.radians(rotation_deg)
    w = WCS(naxis=2)
    w.wcs.ctype = ["RA---TAN", "DEC--TAN"]
    w.wcs.crval = [ra, dec]
    w.wcs.crpix = [width_px / 2 + 0.5, height_px / 2 + 0.5]
    # Columns = image right / image up, rows = east / north (east is left when PA = 0).
    w.wcs.cd = [[-s * math.cos(t), s * math.sin(t)],
                [s * math.sin(t), s * math.cos(t)]]
    return w


def choose_order(fov_deg, width_px, max_order) -> int:
    """Lowest tile order whose pixels are at least as fine as the output pixels."""
    out_px_deg = fov_deg / width_px
    for order in range(0, max_order + 1):
        if FULL_SKY_PIXEL_DEG / (TILE_WIDTH * 2 ** order) <= out_px_deg:
            return order
    return max_order


def _compact_bits(v: np.ndarray) -> np.ndarray:
    """Keep the even bits of v and pack them together (inverse of bit interleaving)."""
    v = v & 0x5555555555555555
    v = (v | (v >> 1)) & 0x3333333333333333
    v = (v | (v >> 2)) & 0x0F0F0F0F0F0F0F0F
    v = (v | (v >> 4)) & 0x00FF00FF00FF00FF
    v = (v | (v >> 8)) & 0x0000FFFF0000FFFF
    v = (v | (v >> 16)) & 0x00000000FFFFFFFF
    return v


def tile_rows_cols(sub: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Nested index inside a tile -> (row, col) in the tile image (row 0 = top of the JPEG).

    Even bits of the nested sub-index give the row, odd bits the column. Verified against a
    SkyView DSS2 cutout of M42 (correlation 0.98; the other 7 flips/rotations score < 0.7).
    """
    return _compact_bits(sub), _compact_bits(sub >> 1)


def _tile_url(base_url, order, tile, ext="jpg") -> str:
    return f"{base_url}/Norder{order}/Dir{(tile // 10000) * 10000}/Npix{tile}.{ext}"


def _fetch_tile(base_url, order, tile, ext="jpg") -> np.ndarray | None:
    """RGBA tile, or None where the survey has no tile (outside its footprint)."""
    key = f"hipstile:{base_url}|{order}|{tile}|{ext}"
    data = cache.get(key)
    if data is None:
        try:
            data = http_get(_tile_url(base_url, order, tile, ext)).content
        except ExternalServiceError as exc:
            if "HTTP 404" in str(exc):
                cache.set(key, b"")
                return None
            raise
        cache.set(key, data)
    if not data:
        return None
    return np.asarray(Image.open(io.BytesIO(data)).convert("RGBA"))


def render(base_url, max_order, ra, dec, fov_deg, rotation_deg, width_px, height_px) -> bytes:
    """Return JPEG bytes for the requested field, built from the HiPS tiles at base_url."""
    rgb, _, any_tile = sample(base_url, max_order, ra, dec, fov_deg, rotation_deg,
                              width_px, height_px)
    if not any_tile:
        raise HipsRenderError("no HiPS tiles available for this field")
    buf = io.BytesIO()
    Image.fromarray(rgb).save(buf, "JPEG", quality=90)
    return buf.getvalue()


def sample(base_url, max_order, ra, dec, fov_deg, rotation_deg, width_px, height_px,
           ext="jpg", tolerate_missing=False) -> tuple[np.ndarray, np.ndarray, bool]:
    """Sample a HiPS survey onto the output grid.

    Returns (rgb uint8 HxWx3, has_data bool HxW, any tile found). Pixels count as data when
    a tile exists there, it isn't transparent and it isn't pure black (partial surveys like
    Hubble leave the rest of a tile black).

    tolerate_missing: tiles that fail to download are left empty instead of failing the
    whole image (for overlays, where a few missing tiles just leave a gap)."""
    w = output_wcs(ra, dec, fov_deg, rotation_deg, width_px, height_px)
    cols, rows = np.meshgrid(np.arange(width_px), np.arange(height_px))
    # FITS pixel y grows upwards; image row 0 is the top.
    lon, lat = w.wcs_pix2world(cols, height_px - 1 - rows, 0)
    valid = np.isfinite(lon) & np.isfinite(lat)
    lon, lat = np.where(valid, lon, 0.0), np.where(valid, lat, 0.0)

    order = choose_order(fov_deg, width_px, max_order)
    while True:
        nside = 2 ** order * TILE_WIDTH
        ipix = lonlat_to_healpix(lon * u.deg, lat * u.deg, nside, order="nested").astype(np.int64)
        tiles = ipix // (TILE_WIDTH * TILE_WIDTH)
        needed = np.unique(tiles[valid])
        if len(needed) <= MAX_TILES or order == 0:
            break
        order -= 1

    def fetch(tile):
        try:
            return _fetch_tile(base_url, order, tile, ext), None
        except ExternalServiceError as exc:
            return None, exc

    with ThreadPoolExecutor(max_workers=8) as pool:
        results = dict(zip(needed.tolist(), pool.map(fetch, needed.tolist())))
    errors = [err for _, err in results.values() if err is not None]
    if errors and (not tolerate_missing or len(errors) == len(results)):
        raise HipsRenderError(str(errors[0])) from errors[0]
    images = {tile: img for tile, (img, _) in results.items()}

    out = np.zeros((height_px, width_px, 4), dtype=np.uint8)
    tile_rows, tile_cols = tile_rows_cols(ipix - tiles * TILE_WIDTH * TILE_WIDTH)
    for tile, img in images.items():
        if img is None:
            continue
        mask = valid & (tiles == tile)
        out[mask] = img[tile_rows[mask], tile_cols[mask]]
    has_data = (out[..., 3] > 0) & (out[..., :3].max(axis=2) > 2)
    return out[..., :3].copy(), has_data, any(img is not None for img in images.values())
