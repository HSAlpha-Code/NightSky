"""Provider registry.

Only distinct, reliable all-sky optical surveys are exposed:
- DSS2 Color: sharp across both wide camera fields and star/object close-ups.
- Mellinger Color: wide-angle Milky Way panorama for camera-field views (FOV >= 5 deg).
"""
from django.conf import settings

from .base import ImageProvider
from .hips2fits import Hips2FitsProvider
from .skyview import SkyViewProvider

MIRROR = settings.HIPS_MIRROR_URL.rstrip("/")  # ESA ESASky copy of the CDS surveys ("" = off)

PROVIDERS: list[ImageProvider] = [
    Hips2FitsProvider(
        "dss2_color",
        "CDS/P/DSS2/color",
        "DSS2 Color",
        "Digitized Sky Survey 2 colour composite. Sharp for both wide fields and star close-ups.",
        "optical",
        mirror=MIRROR and f"{MIRROR}/DSSColor",
    ),
    SkyViewProvider(
        "skyview_mellinger",
        ["Mellinger Red", "Mellinger Green", "Mellinger Blue"],
        "Mellinger Color",
        "Axel Mellinger's all-sky Milky Way mosaic. Best for wide phone-camera sky fields.",
        "optical",
        scaling="Linear",
        coverage="all-sky (wide fields >= 5°)",
        min_fov_deg=5.0,
        supports_detail=False,
    ),
]

_BY_KEY = {p.key: p for p in PROVIDERS}


def get_provider(key: str | None) -> ImageProvider | None:
    return _BY_KEY.get(key or settings.DEFAULT_PROVIDER)


def all_providers() -> list[ImageProvider]:
    return list(PROVIDERS)


def detail_providers() -> list[ImageProvider]:
    return [p for p in PROVIDERS if p.supports_detail]


def fallback_candidates(ra: float, dec: float, fov_deg: float | None = None,
                        exclude: ImageProvider | None = None,
                        service_failed: bool = False) -> list[ImageProvider]:
    """All-sky providers that cover the position and field size, default first."""
    default = get_provider(None)
    ordered = ([default] if default else []) + [p for p in PROVIDERS if p is not default]
    candidates = [p for p in ordered
                  if p is not exclude and p.all_sky and p.supports(ra, dec, fov_deg)]
    if exclude is not None and service_failed:
        candidates.sort(key=lambda p: p.service == exclude.service)  # stable sort
    return candidates


def fallback_provider(ra: float, dec: float, fov_deg: float | None = None,
                      exclude: ImageProvider | None = None) -> ImageProvider | None:
    candidates = fallback_candidates(ra, dec, fov_deg, exclude)
    return candidates[0] if candidates else None
