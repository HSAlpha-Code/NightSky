"""NASA SkyView (HEASARC/GSFC) provider."""
import logging
import re
import time

from django.conf import settings

from config.http import ExternalServiceError, http_get

from .base import ImageProvider, ProviderError

log = logging.getLogger(__name__)

TEMPSPACE = "https://skyview.gsfc.nasa.gov/tempspace/fits/"
BUSY_RETRIES = 2      # extra attempts when SkyView says "Too Many Processes"
BUSY_DELAY = 1.5      # seconds; multiplied by the attempt number


class SkyViewProvider(ImageProvider):
    service = "skyview"

    def __init__(self, key: str, surveys: list[str], name: str, description: str,
                 wavelength: str, scaling: str = "Log", native_arcsec: float = 0.0):
        self.key = key
        self.native_arcsec = native_arcsec   # source pixel scale; 0 = fine enough for any zoom
        self.surveys = surveys          # one survey = greyscale, three = R,G,B composite
        self.name = name
        self.description = description
        self.wavelength = wavelength
        self.scaling = scaling
        self.coverage = "all-sky"
        self.credit = f"{name} via NASA SkyView (HEASARC/GSFC)"

    def fetch_cutout(self, ra, dec, fov_deg, rotation_deg, width_px, height_px) -> bytes:
        rgb = len(self.surveys) == 3
        params = {
            "Position": f"{ra:.6f},{dec:.6f}",
            "Survey": ",".join(self.surveys),
            "Pixels": f"{int(width_px)},{int(height_px)}",
            "Size": f"{fov_deg:.6f},{fov_deg * height_px / width_px:.6f}",
            "Projection": "Tan",
            "Coordinates": "J2000",
            "Scaling": self.scaling,
            # SkyView rotates the image in the opposite sense to the position-angle convention.
            "Rotation": f"{-rotation_deg:.3f}",
        }
        try:
            if rgb:
                # Return=JPEG thumbnails RGB composites; the full-size file is "<name>_rgb.jpg".
                params.update(RGB="1", Return="filename")
                name = self._query(params).text.strip()
                if not name.startswith("skv"):
                    raise ProviderError(f"SkyView error: {_summarize(name)}")
                resp = http_get(f"{TEMPSPACE}{name}_rgb.jpg")
            else:
                params["Return"] = "JPEG"
                resp = self._query(params)
        except ExternalServiceError as exc:
            raise ProviderError(str(exc)) from exc
        if not resp.headers.get("content-type", "").startswith("image/"):
            raise ProviderError(f"SkyView returned non-image: {_summarize(resp.text)}")
        return resp.content

    def _query(self, params: dict):
        """GET runquery.pl, retrying while SkyView is overloaded.

        When busy it answers HTTP 200 with an HTML "Too Many Processes" page, so the status
        code alone can't be trusted. The condition is usually gone within a few seconds."""
        for attempt in range(BUSY_RETRIES + 1):
            resp = http_get(settings.SKYVIEW_URL, params=params)
            if not _is_busy(resp):
                return resp
            if attempt < BUSY_RETRIES:
                log.info("SkyView busy (too many processes), retrying in %.1fs", BUSY_DELAY * (attempt + 1))
                time.sleep(BUSY_DELAY * (attempt + 1))
        raise ProviderError("SkyView is overloaded (too many processes)")


def _is_busy(resp) -> bool:
    ctype = resp.headers.get("content-type", "")
    return not ctype.startswith("image/") and "too many processes" in resp.text.lower()


def _summarize(text: str) -> str:
    """Collapse an HTML error page to its readable text for logs."""
    plain = re.sub(r"<[^>]+>", " ", text)
    return re.sub(r"\s+", " ", plain).strip()[:200]
