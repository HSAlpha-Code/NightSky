"""Provider registry. Adding a provider = one adapter file + one line here."""
from django.conf import settings

from .base import ImageProvider
from .hips2fits import Hips2FitsProvider
from .panstarrs import PanStarrsProvider
from .skyview import SkyViewProvider

PROVIDERS: list[ImageProvider] = [
    Hips2FitsProvider("dss2_color", "CDS/P/DSS2/color", "DSS2 Color",
                      "Digitized Sky Survey 2, colour composite of photographic plates.", "optical"),
    Hips2FitsProvider("2mass_color", "CDS/P/2MASS/color", "2MASS Color",
                      "Two Micron All Sky Survey, J/H/K colour composite.", "near-infrared"),
    Hips2FitsProvider("allwise_color", "CDS/P/allWISE/color", "AllWISE Color",
                      "WISE mid-infrared colour composite (W1/W2/W4).", "mid-infrared"),
    Hips2FitsProvider("panstarrs_hips", "CDS/P/PanSTARRS/DR1/color-z-zg-g", "Pan-STARRS DR1 (HiPS)",
                      "Pan-STARRS DR1 colour composite via hips2fits.", "optical",
                      coverage="dec > -30", min_dec=-30.0),
    SkyViewProvider("skyview_mellinger", ["Mellinger Red", "Mellinger Green", "Mellinger Blue"],
                    "Mellinger Color (SkyView)",
                    "Axel Mellinger's all-sky colour mosaic. Best for wide phone-camera fields.",
                    "optical", scaling="Linear"),
    SkyViewProvider("skyview_dss2_red", ["DSS2 Red"], "DSS2 Red (SkyView)",
                    "Digitized Sky Survey 2 red plates via NASA SkyView. Best below ~10°.", "optical"),
    PanStarrsProvider(),
]

_BY_KEY = {p.key: p for p in PROVIDERS}


def get_provider(key: str | None) -> ImageProvider | None:
    return _BY_KEY.get(key or settings.DEFAULT_PROVIDER)


def all_providers() -> list[ImageProvider]:
    return list(PROVIDERS)


def fallback_candidates(ra: float, dec: float, fov_deg: float | None = None,
                        exclude: ImageProvider | None = None,
                        service_failed: bool = False) -> list[ImageProvider]:
    """All-sky providers that cover the position, default first. If the excluded provider's
    service failed, providers on other upstream services are tried before its siblings."""
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
