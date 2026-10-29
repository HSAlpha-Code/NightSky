"""CDS hips2fits provider: renders a cutout from any HiPS survey.

If CDS can't be reached (some ISPs can't route to Strasbourg) and the survey has a mirror
(`mirror`, e.g. ESA ESASky), the cutout is rendered locally from the mirror's HiPS tiles.
"""
import logging

from django.conf import settings
from django.core.cache import cache

from config.http import ExternalServiceError, http_get

from . import hips_render
from .base import ImageProvider, ProviderError

log = logging.getLogger(__name__)

CDS_DOWN_KEY = "hips2fits_cds_down"


class Hips2FitsProvider(ImageProvider):
    service = "hips2fits"

    def __init__(self, key: str, hips_id: str, name: str, description: str, wavelength: str,
                 coverage: str = "all-sky", min_dec: float = -90.0, credit: str = "",
                 mirror: str = "", mirror_max_order: int = 9):
        self.key = key
        self.hips_id = hips_id
        self.name = name
        self.description = description
        self.wavelength = wavelength
        self.coverage = coverage
        self.min_dec = min_dec
        self.all_sky = min_dec <= -90.0
        self.credit = credit or f"{name} via CDS hips2fits (Strasbourg)"
        self.mirror = mirror                  # HiPS base URL of a copy outside CDS, or ""
        self.mirror_max_order = mirror_max_order

    def supports(self, ra: float, dec: float, fov_deg: float | None = None) -> bool:
        return dec >= self.min_dec

    def fetch_cutout(self, ra, dec, fov_deg, rotation_deg, width_px, height_px) -> bytes:
        args = (ra, dec, fov_deg, rotation_deg, width_px, height_px)
        cds_down = cache.get(CDS_DOWN_KEY)
        if cds_down and not self.mirror:
            raise ProviderError("CDS hips2fits is unreachable right now")
        if not cds_down:
            try:
                return self._fetch_cds(*args)
            except ProviderError as exc:
                if "HTTP 4" not in str(exc):   # unreachable / 5xx, not a bad request
                    cache.set(CDS_DOWN_KEY, True, settings.PROVIDER_DOWN_SECONDS)
                if not self.mirror:
                    raise
                log.warning("hips2fits failed (%s); rendering %s from %s", exc, self.key,
                            self.mirror)
        try:
            return hips_render.render(self.mirror, self.mirror_max_order, *args)
        except hips_render.HipsRenderError as exc:
            raise ProviderError(f"HiPS mirror failed: {exc}") from exc

    def _fetch_cds(self, ra, dec, fov_deg, rotation_deg, width_px, height_px) -> bytes:
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
        # With a mirror available, don't spend retries on an unreachable CDS.
        retries = 0 if self.mirror else None
        try:
            resp = http_get(settings.HIPS2FITS_URL, params=params, retries=retries)
        except ExternalServiceError as exc:
            raise ProviderError(str(exc)) from exc
        if not resp.headers.get("content-type", "").startswith("image/"):
            raise ProviderError(f"hips2fits returned non-image: {resp.text[:200]}")
        return resp.content
