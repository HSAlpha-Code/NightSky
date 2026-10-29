"""Sky-image service: coverage check, provider fallback, caching."""
import hashlib
import logging
from dataclasses import dataclass

from django.conf import settings
from django.core.cache import cache

from config.errors import NO_COVERAGE, PROVIDER_UNAVAILABLE, ApiError

from .base import ImageProvider, ProviderError
from .registry import fallback_candidates, get_provider

log = logging.getLogger(__name__)


@dataclass
class SkyImage:
    data: bytes
    provider: ImageProvider
    requested: ImageProvider
    fallback_used: bool = False
    fallback_reason: str = ""      # "" | NO_COVERAGE | PROVIDER_UNAVAILABLE
    message: str = ""


def cache_key(provider_key, ra, dec, fov, rotation, width, height) -> str:
    """Rounded so near-identical requests share an entry (~0.001° ≈ 3.6")."""
    raw = (f"{provider_key}|{ra % 360:.3f}|{dec:.3f}|{fov:.3f}|{rotation % 360:.1f}"
           f"|{int(width)}x{int(height)}")
    return "skyimg:" + hashlib.sha1(raw.encode()).hexdigest()


def _down_key(provider: ImageProvider) -> str:
    """Skip-for-a-while flag. Shared by all providers on one upstream service, except those
    with their own mirror: they keep working when the service is down (e.g. Pan-STARRS HiPS
    failing on CDS must not take DSS2/2MASS/AllWISE, which render from ESA, down with it)."""
    if getattr(provider, "mirror", ""):
        return f"provider_down:key:{provider.key}"
    return f"provider_down:{provider.service or provider.key}"


def _fetch(provider: ImageProvider, ra, dec, fov, rotation, width, height) -> bytes:
    key = cache_key(provider.key, ra, dec, fov, rotation, width, height)
    data = cache.get(key)
    if data is not None:
        return data
    if cache.get(_down_key(provider)):
        raise ProviderError(f"{provider.name} recently failed; skipping for now")
    try:
        data = provider.fetch_cutout(ra, dec, fov, rotation, width, height)
    except ProviderError:
        cache.set(_down_key(provider), True, settings.PROVIDER_DOWN_SECONDS)
        raise
    cache.set(key, data)
    return data


def get_sky_image(ra: float, dec: float, fov: float, rotation: float = 0.0,
                  provider_key: str | None = None, width: int = 1200, height: int = 1600) -> SkyImage:
    requested = get_provider(provider_key)
    if requested is None:
        raise ApiError("INVALID_REQUEST", f"Unknown provider {provider_key!r}.")
    args = (ra, dec, fov, rotation, width, height)

    reason, message = "", ""
    if requested.supports(ra, dec, fov):
        try:
            return SkyImage(_fetch(requested, *args), requested, requested)
        except ProviderError as exc:
            log.warning("provider %s failed: %s", requested.key, exc)
            reason = PROVIDER_UNAVAILABLE
            message = f"{requested.name} is unavailable right now"
    else:
        reason = NO_COVERAGE
        message = f"{requested.name} does not cover this area ({requested.coverage})"

    candidates = fallback_candidates(ra, dec, fov, exclude=requested,
                                     service_failed=reason == PROVIDER_UNAVAILABLE)
    for candidate in candidates:
        try:
            data = _fetch(candidate, *args)
        except ProviderError as exc:
            log.warning("fallback provider %s failed: %s", candidate.key, exc)
            continue
        return SkyImage(data, candidate, requested, True, reason,
                        f"{message}; showing {candidate.name} instead.")

    if reason == NO_COVERAGE:
        raise ApiError(NO_COVERAGE, f"{message}, and no fallback provider is available.", 404)
    raise ApiError(PROVIDER_UNAVAILABLE,
                   "Sky image services are unavailable right now. Please try again later.", 503)
