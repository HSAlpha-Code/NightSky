"""NASA SkyView (HEASARC/GSFC) provider."""
from django.conf import settings

from config.http import ExternalServiceError, http_get

from .base import ImageProvider, ProviderError

TEMPSPACE = "https://skyview.gsfc.nasa.gov/tempspace/fits/"


class SkyViewProvider(ImageProvider):
    service = "skyview"

    def __init__(self, key: str, surveys: list[str], name: str, description: str,
                 wavelength: str, scaling: str = "Log"):
        self.key = key
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
                name = http_get(settings.SKYVIEW_URL, params=params).text.strip()
                if not name.startswith("skv"):
                    raise ProviderError(f"SkyView error: {name[:200]}")
                resp = http_get(f"{TEMPSPACE}{name}_rgb.jpg")
            else:
                params["Return"] = "JPEG"
                resp = http_get(settings.SKYVIEW_URL, params=params)
        except ExternalServiceError as exc:
            raise ProviderError(str(exc)) from exc
        if not resp.headers.get("content-type", "").startswith("image/"):
            raise ProviderError(f"SkyView returned non-image: {resp.text[:200]}")
        return resp.content
