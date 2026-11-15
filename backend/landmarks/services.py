"""Landmark service: markers for a field, and the second-level detail image."""
import hashlib
import logging
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, replace

from django.conf import settings
from django.core.cache import cache

from config.errors import NO_COVERAGE, NOT_FOUND, ApiError
from providers.base import ProviderError
from providers.hips2fits import Hips2FitsProvider
from providers.registry import MIRROR, get_provider
from providers.services import get_sky_image

from . import mast, mosaic, tone
from .catalog import get_catalog

log = logging.getLogger(__name__)

DETAIL_SIZE = 1200            # px, square survey close-up
DETAIL_MIN_FOV = 0.08         # degrees; tight cutout around small objects
DETAIL_STAR_FOV = 0.5         # faint stars; brighter ones get a wider field:
STAR_FOV_BY_MAG = ((0.0, 2.0), (1.0, 1.5), (2.0, 1.0), (4.0, 0.75))  # (max magnitude, deg)
MOSAIC_SIZE = 1000            # px, square Hubble/JWST mosaic
MOSAIC_MIN_FOV = 0.03         # never zoom in further than ~2'
MOSAIC_MIN_SEARCH = 0.15      # look this far around the object for neighbouring frames
MOSAIC_MAX_FOV = 1.0
MISSION_CACHE_TTL = 24 * 3600

# Internal-only unsaturated infrared colour fallback used solely under space-telescope mosaics
# when optical DSS2 plates saturate to pure white on bright nebula cores (e.g. M42 Trapezium).
# Not exposed as a selectable survey provider.
_UNSATURATED_MOSAIC_BG = Hips2FitsProvider(
    "2mass_color",
    "CDS/P/2MASS/color",
    "2MASS Color",
    "",
    "near-infrared",
    mirror=MIRROR and f"{MIRROR}/2MASSColor",
)


def landmarks_in_field(ra, dec, fov, rotation=0.0, aspect=4 / 3, limit=None) -> dict:
    limit = limit or settings.LANDMARK_MAX_MARKERS
    hits, total = get_catalog().query(ra, dec, fov, rotation, aspect, limit)
    markers = []
    for hit in hits:
        lm = hit.landmark
        state = mast.status(lm) if lm.kind == "dso" else False
        markers.append({**lm.to_dict(), "x": round(hit.x, 4), "y": round(hit.y, 4),
                        "has_hires": state if state is None else bool(state)})
    return {
        "landmarks": markers,
        "total_in_field": total,
        "pending": any(m["has_hires"] is None for m in markers),
        "source": "OpenNGC (CC-BY-SA 4.0), IAU Catalog of Star Names",
    }


VIEWS = ("auto", "jwst", "hst", "survey")


@dataclass
class Detail:
    landmark: dict
    image: bytes
    image_source: str        # "jwst" | "hst" | "survey"
    credit: str
    caption: str
    view: str                # the view that was asked for
    fov_deg: float
    available_views: list[str] | None = None


def detail_fov(lm) -> float:
    if lm.kind == "star":
        # Bright stars flood a tight field with their glare, so show them wider.
        mag = lm.magnitude if lm.magnitude is not None else 99.0
        return next((fov for limit, fov in STAR_FOV_BY_MAG if mag <= limit), DETAIL_STAR_FOV)
    return max(DETAIL_MIN_FOV, min(5.0, (lm.size_arcmin or 3) / 60 * 1.6))


def _caption(text: str, tamed: bool) -> str:
    return text + (" · highlights compressed" if tamed else "")


def _missions_key(landmark_id: str) -> str:
    return f"lmmissions1:{landmark_id}"


def _locate_mission(lm, mission: str):
    base = detail_fov(lm)
    search = min(MOSAIC_MAX_FOV, max(base * 2, MOSAIC_MIN_SEARCH))
    return mosaic.locate(mission, lm.ra, lm.dec, search, MOSAIC_MIN_FOV, base)


def available_missions(lm) -> dict[str, tuple[float, float, float]]:
    """Probe which space telescopes ('jwst', 'hst') genuinely cover `lm` and cache their boxes."""
    if lm.kind != "dso" or mast.status(lm) is False:
        return {}
    key = _missions_key(lm.id)
    cached = cache.get(key)
    if cached is not None:
        return dict(cached)
    missions = ("jwst", "hst")
    with ThreadPoolExecutor(max_workers=len(missions)) as pool:
        boxes = list(pool.map(lambda m: _locate_mission(lm, m), missions))
    found = {m: box for m, box in zip(missions, boxes) if box is not None}
    cache.set(key, found, MISSION_CACHE_TTL)
    return dict(found)


def _resolve_detail_provider(provider_key: str | None, *, strict: bool) -> str:
    """Ensure close-ups use a detail-capable provider; reject unsupported explicit choices."""
    if not provider_key:
        return settings.DEFAULT_PROVIDER
    provider = get_provider(provider_key)
    if provider is None:
        raise ApiError("INVALID_REQUEST", f"Unknown provider {provider_key!r}.")
    if not provider.supports_detail:
        if strict:
            raise ApiError(
                NO_COVERAGE,
                f"{provider.name} is only available for wide sky fields, not close-ups.",
                404,
            )
        return settings.DEFAULT_PROVIDER
    return provider.key


def _survey(lm, provider_key: str, view: str,
            available_views: list[str] | None = None) -> Detail:
    fov = detail_fov(lm)
    sky = get_sky_image(
        lm.ra % 360,
        lm.dec,
        fov,
        0.0,
        provider_key,
        DETAIL_SIZE,
        DETAIL_SIZE,
        allow_fallback=False,
    )
    image, tamed = tone.tame_jpeg(sky.data)
    return Detail(
        lm.to_dict(),
        image,
        "survey",
        sky.provider.credit,
        _caption(f"{sky.provider.name} · {fov * 60:.0f}′ field", tamed),
        view,
        fov,
        available_views,
    )


def _background(ra, dec, fov, provider_key: str) -> tuple[bytes | None, str]:
    """Survey colour under a mosaic. Uses the detail survey unless its core is burnt out to
    solid white (e.g. DSS2 on M42's Trapezium); then falls back to unsaturated 2MASS colour."""
    best, best_burnt = (None, ""), 2.0
    try:
        sky = get_sky_image(ra, dec, fov, 0.0, provider_key, MOSAIC_SIZE, MOSAIC_SIZE,
                            allow_fallback=False)
        burnt = tone.burnt_fraction(sky.data)
        if burnt <= tone.BURNT_FRACTION:
            return sky.data, sky.provider.name
        best, best_burnt = (sky.data, sky.provider.name), burnt
    except ApiError as exc:
        log.info("survey %s unavailable for mosaic background: %s", provider_key, exc.message)

    try:
        ir_data = _UNSATURATED_MOSAIC_BG.fetch_cutout(ra, dec, fov, 0.0, MOSAIC_SIZE, MOSAIC_SIZE)
        burnt = tone.burnt_fraction(ir_data)
        if burnt <= tone.BURNT_FRACTION:
            return ir_data, _UNSATURATED_MOSAIC_BG.name
        if burnt < best_burnt:
            best, best_burnt = (ir_data, _UNSATURATED_MOSAIC_BG.name), burnt
    except ProviderError as exc:
        log.info("unsaturated mosaic background unavailable: %s", exc)

    log.info("mosaic backgrounds all burnt out; least bad: %s (%.0f%%)", best[1],
             best_burnt * 100)
    return best


def _space_telescope(lm, mission: str, provider_key: str, view: str,
                     box: tuple[float, float, float] | None = None) -> Detail | None:
    """Stitched, coloured Hubble/JWST mosaic around the object, or None if there's no data."""
    if box is None:
        box = _locate_mission(lm, mission)
    if box is None:
        return None
    ra, dec, fov = box
    background, survey_name = _background(ra, dec, fov, provider_key)
    tamed = False
    if background:
        background, tamed = tone.tame_jpeg(background)
    result = mosaic.render(mission, ra, dec, fov, MOSAIC_SIZE, background)
    if result is None:
        return None
    image, tamed_out = tone.tame_jpeg(result.image)
    name = mosaic.MISSION_NAMES[mission]
    colour = f"colour from {survey_name}" if survey_name else "no survey colour"
    caption = _caption(f"{', '.join(result.layers)} · {result.coverage:.0%} of the field "
                       f"imaged · {fov * 60:.0f}′ field, {colour}", tamed or tamed_out)
    credit = (f"{name} (NASA/ESA/CSA) via ESA ESASky HiPS; "
              f"colour: {survey_name or 'none'}")
    return Detail(lm.to_dict(), image, mission, credit, caption, view, fov)


def _detail_cache_key(landmark_id: str, provider_key: str, view: str) -> str:
    return "lmdetail7:" + hashlib.sha1(f"{landmark_id}|{provider_key}|{view}".encode()).hexdigest()


def landmark_detail(landmark_id: str, provider_key: str | None = None,
                    view: str = "auto") -> Detail:
    lm = get_catalog().get(landmark_id)
    if lm is None:
        raise ApiError(NOT_FOUND, f"Unknown landmark {landmark_id!r}.", 404)
    if view not in VIEWS:
        raise ApiError("INVALID_REQUEST", f"Unknown view {view!r}.")

    strict_provider = view == "survey" and bool(provider_key)
    eff_provider = _resolve_detail_provider(provider_key, strict=strict_provider)
    key = _detail_cache_key(lm.id, eff_provider, view)
    cached = cache.get(key)
    if cached is not None:
        return cached

    if view == "survey":
        if lm.kind != "dso" or mast.is_known_empty(lm):
            avail: list[str] | None = ["survey"]
        else:
            known = cache.get(_missions_key(lm.id))
            avail = [*(m for m in ("jwst", "hst") if m in known), "survey"] if known is not None else None
        detail = _survey(lm, eff_provider, view, avail)
        cache.set(key, detail)
        return detail

    if view in ("jwst", "hst"):
        if lm.kind != "dso":
            raise ApiError(NO_COVERAGE, f"No {mosaic.MISSION_NAMES[view]} images cover "
                                        f"{lm.name}. Try another view.", 404)
        known = cache.get(_missions_key(lm.id))
        box = known.get(view) if known is not None else _locate_mission(lm, view)
        detail = _space_telescope(lm, view, eff_provider, view, box=box) if box is not None else None
        if detail is None:
            if known is not None and view in known:
                updated = {k: v for k, v in known.items() if k != view}
                cache.set(_missions_key(lm.id), updated, MISSION_CACHE_TTL)
            raise ApiError(NO_COVERAGE, f"No {mosaic.MISSION_NAMES[view]} images cover "
                                        f"{lm.name}. Try another view.", 404)
        detail.available_views = (
            [*(m for m in ("jwst", "hst") if m in known), "survey"]
            if known is not None
            else [view, "survey"]
        )
        cache.set(key, detail)
        return detail

    # view == "auto": probe available telescopes concurrently so the client learns immediately
    # which options truly exist and never offers unavailable buttons.
    missions = available_missions(lm)
    detail = None
    for mission in ("jwst", "hst"):
        if mission not in missions:
            continue
        detail = _space_telescope(lm, mission, eff_provider, view, box=missions[mission])
        if detail is not None:
            break
        missions.pop(mission, None)
        cache.set(_missions_key(lm.id), missions, MISSION_CACHE_TTL)

    avail = [*(m for m in ("jwst", "hst") if m in missions), "survey"]
    if detail is None:
        detail = _survey(lm, eff_provider, view, avail)
    else:
        detail.available_views = avail

    cache.set(key, detail)
    # Seed the resolved source's own cache entry so switching to that chip is instantaneous.
    resolved_view = detail.image_source
    cache.set(
        _detail_cache_key(lm.id, eff_provider, resolved_view),
        replace(detail, view=resolved_view),
    )
    return detail
