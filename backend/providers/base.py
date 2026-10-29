"""Image provider adapter interface."""
from abc import ABC, abstractmethod


class ProviderError(Exception):
    """Provider failed to deliver an image (network, service down, bad response)."""


class ImageProvider(ABC):
    key: str = ""            # stable id used by the API, e.g. "dss2_color"
    name: str = ""           # human readable
    description: str = ""
    wavelength: str = ""     # e.g. "optical", "infrared"
    coverage: str = ""       # e.g. "all-sky", "dec > -30"
    all_sky: bool = True     # used to pick a fallback when supports() is False
    credit: str = ""
    service: str = ""        # upstream service id; fallback prefers a different service

    def supports(self, ra: float, dec: float, fov_deg: float | None = None) -> bool:
        return True

    @abstractmethod
    def fetch_cutout(self, ra: float, dec: float, fov_deg: float, rotation_deg: float,
                     width_px: int, height_px: int) -> bytes:
        """Return JPEG bytes centered on (ra, dec) with the given horizontal FOV.

        rotation_deg is the position angle of the image "up" direction, east of north.
        """

    def metadata(self) -> dict:
        return {
            "key": self.key,
            "name": self.name,
            "description": self.description,
            "wavelength": self.wavelength,
            "coverage": self.coverage,
            "all_sky": self.all_sky,
            "service": self.service,
            "credit": self.credit,
        }
