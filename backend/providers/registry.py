"""Provider registry.

Only distinct, reliable all-sky optical surveys are exposed:
- DSS2 Color: sharp across both wide camera fields and star/object close-ups.
- NASA Deep Star Maps 2020: local wide-field star map (FOV >= 5 deg).
"""
from django.conf import settings

from .base import ImageProvider
from .hips2fits import Hips2FitsProvider
from .nasa_starmap import NasaStarMapProvider

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
    NasaStarMapProvider(),
]

_BY_KEY = {p.key: p for p in PROVIDERS}


def get_provider(key: str | None) -> ImageProvider | None:
    # Older clients may still send this key; never request the unlicensed survey.
    if key == "skyview_mellinger":
        key = "nasa_starmap_2020"
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
