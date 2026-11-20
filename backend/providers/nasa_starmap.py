"""Local cutouts of the public-domain NASA Deep Star Maps 2020 image."""
from functools import lru_cache
import io
from pathlib import Path

import numpy as np
from PIL import Image

from .base import ImageProvider, ProviderError
from .hips_render import output_wcs


@lru_cache(maxsize=1)
def panorama():
    root = Path(__file__).resolve().parent.parent / "panorama_packs" / "8k"
    halves = []
    for side in ("east", "west"):
        with Image.open(root / f"nasa_2020_{side}.webp") as image:
            halves.append(np.asarray(image.convert("RGB")))
    return np.concatenate(halves, axis=1)


class NasaStarMapProvider(ImageProvider):
    key = "nasa_starmap_2020"
    name = "NASA Deep Star Maps 2020"
    description = "NASA's catalog-rendered optical star map. Best for wide sky fields."
    wavelength = "optical"
    coverage = "all-sky (wide fields >= 5 degrees)"
    supports_detail = False
    service = "nasa_starmap_local"
    credit = "NASA/Goddard Space Flight Center Scientific Visualization Studio. Gaia DR2: ESA/Gaia/DPAC."

    def supports(self, ra, dec, fov_deg=None):
        return fov_deg is None or fov_deg >= 5

    def fetch_cutout(self, ra, dec, fov_deg, rotation_deg, width_px, height_px):
        try:
            sky = panorama()
            wcs = output_wcs(ra, dec, fov_deg, rotation_deg, width_px, height_px)
            x, y = np.meshgrid(np.arange(width_px), np.arange(height_px))
            lon, lat = wcs.wcs_pix2world(x, height_px - 1 - y, 0)
            valid = np.isfinite(lon) & np.isfinite(lat)
            a, d = np.deg2rad(np.where(valid, lon, 0)), np.deg2rad(np.where(valid, lat, 0))
            equatorial = np.stack([np.cos(d) * np.cos(a), np.cos(d) * np.sin(a), np.sin(d)], axis=-1)
            matrix = np.array([[-.0548755604, -.8734370902, -.4838350155],
                               [.4941094279, -.4448296300, .7469822445],
                               [-.8676661490, -.1980763734, .4559837762]])
            gal = equatorial @ matrix.T
            u = (.5 - np.arctan2(gal[..., 1], gal[..., 0]) / (2 * np.pi)) % 1
            v = .5 - np.arcsin(np.clip(gal[..., 2], -1, 1)) / np.pi
            px, py = u * sky.shape[1] - .5, np.clip(v * sky.shape[0] - .5, 0, sky.shape[0] - 1)
            ix, iy = np.floor(px).astype(int), np.floor(py).astype(int)
            fx, fy = (px - ix)[..., None], (py - iy)[..., None]
            x0, x1 = ix % sky.shape[1], (ix + 1) % sky.shape[1]
            y1 = np.minimum(iy + 1, sky.shape[0] - 1)
            rgb = ((sky[iy, x0] * (1 - fx) + sky[iy, x1] * fx) * (1 - fy) +
                   (sky[y1, x0] * (1 - fx) + sky[y1, x1] * fx) * fy)
            rgb[~valid] = 0
            buf = io.BytesIO()
            Image.fromarray(np.rint(rgb).astype(np.uint8)).save(buf, "PNG")
            return buf.getvalue()
        except (OSError, ValueError) as error:
            raise ProviderError("NASA star-map assets are unavailable") from error
