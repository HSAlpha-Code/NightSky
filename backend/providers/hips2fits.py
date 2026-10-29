"""CDS hips2fits provider: renders a cutout from any HiPS survey."""
from django.conf import settings

from config.http import ExternalServiceError, http_get

from .base import ImageProvider, ProviderError


class Hips2FitsProvider(ImageProvider):
    service = "hips2fits"

    def __init__(self, key: str, hips_id: str, name: str, description: str, wavelength: str,
                 coverage: str = "all-sky", min_dec: float = -90.0, credit: str = ""):
        self.key = key
        self.hips_id = hips_id
        self.name = name
        self.description = description
        self.wavelength = wavelength
        self.coverage = coverage
        self.min_dec = min_dec
        self.all_sky = min_dec <= -90.0
        self.credit = credit or f"{name} via CDS hips2fits (Strasbourg)"

    def supports(self, ra: float, dec: float, fov_deg: float | None = None) -> bool:
        return dec >= self.min_dec

    def fetch_cutout(self, ra, dec, fov_deg, rotation_deg, width_px, height_px) -> bytes:
        params = {
            "hips": self.hips_id,
            "ra": f"{ra:.6f}",
            "dec": f"{dec:.6f}",
            "fov": f"{fov_deg:.6f}",       # horizontal (width) FOV in degrees
            "width": int(width_px),
            "height": int(height_px),
            "projection": "TAN",
            "coordsys": "icrs",
            "rotation_angle": f"{rotation_deg:.3f}",
            "format": "jpg",
        }
        try:
            resp = http_get(settings.HIPS2FITS_URL, params=params)
        except ExternalServiceError as exc:
            raise ProviderError(str(exc)) from exc
        if not resp.headers.get("content-type", "").startswith("image/"):
            raise ProviderError(f"hips2fits returned non-image: {resp.text[:200]}")
        return resp.content
