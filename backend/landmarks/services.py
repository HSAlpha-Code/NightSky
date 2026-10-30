"""Landmark service: markers for a field, and the second-level detail image."""
import hashlib
import logging
from dataclasses import dataclass

from django.conf import settings
from django.core.cache import cache

from config.errors import NO_COVERAGE, NOT_FOUND, ApiError
from providers.registry import get_provider
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
# Tried (in order) when the chosen survey is burnt out under a mosaic. 2MASS is infrared,
# so its colour also suits JWST, and it rarely saturates on nebula cores.
BACKGROUND_FALLBACKS = ("2mass_color", "dss2_color")
MIN_BACKGROUND_PIXELS = 200   # native survey pixels needed across the mosaic, else it looks blocky


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


def detail_fov(lm) -> float:
    if lm.kind == "star":
        # Bright stars flood a tight field with their glare, so show them wider.
        mag = lm.magnitude if lm.magnitude is not None else 99.0
        return next((fov for limit, fov in STAR_FOV_BY_MAG if mag <= limit), DETAIL_STAR_FOV)
    return max(DETAIL_MIN_FOV, min(5.0, (lm.size_arcmin or 3) / 60 * 1.6))


def _caption(text: str, tamed: bool) -> str:
    return text + (" · highlights compressed" if tamed else "")


def _survey(lm, provider_key, view) -> Detail:
    fov = detail_fov(lm)
    sky = get_sky_image(lm.ra % 360, lm.dec, fov, 0.0, provider_key, DETAIL_SIZE, DETAIL_SIZE)
    image, tamed = tone.tame_jpeg(sky.data)
    return Detail(lm.to_dict(), image, "survey", sky.provider.credit,
                  _caption(f"{sky.provider.name} · {fov * 60:.0f}′ field", tamed), view, fov)


def _background(ra, dec, fov, provider_key) -> tuple[bytes | None, str]:
    """Survey colour under a mosaic. The chosen survey is used unless it's burnt out there
    (e.g. DSS2 over the M42 core is solid white); then the least burnt-out of the fallback
    surveys is used. Returns (jpeg, survey name)."""
    best, best_burnt = (None, ""), 2.0
    for key in dict.fromkeys([provider_key, *BACKGROUND_FALLBACKS]):
        # A coarse all-sky survey (Mellinger, 36"/px) would show as big blocks in a small field.
        native = getattr(get_provider(key), "native_arcsec", 0.0)
        if native and fov * 3600 / native < MIN_BACKGROUND_PIXELS:
            log.info("survey %s too coarse for a %.1f' mosaic background", key, fov * 60)
            continue
        try:
            sky = get_sky_image(ra, dec, fov, 0.0, key, MOSAIC_SIZE, MOSAIC_SIZE)
        except ApiError as exc:
            log.info("survey %s unavailable for mosaic background: %s", key, exc.message)
            continue
        burnt = tone.burnt_fraction(sky.data)
        if burnt <= tone.BURNT_FRACTION:
            return sky.data, sky.provider.name
        if burnt < best_burnt:
            best, best_burnt = (sky.data, sky.provider.name), burnt
    log.info("mosaic backgrounds all burnt out; least bad: %s (%.0f%%)", best[1],
             best_burnt * 100)
    return best


def _space_telescope(lm, mission, provider_key, view) -> Detail | None:
    """Stitched, coloured Hubble/JWST mosaic around the object, or None if there's no data."""
    base = detail_fov(lm)
    search = min(MOSAIC_MAX_FOV, max(base * 2, MOSAIC_MIN_SEARCH))
    box = mosaic.locate(mission, lm.ra, lm.dec, search, MOSAIC_MIN_FOV)
    if box is None:
        return None
    ra, dec, fov = box
    # Ground-based colour and brightness underneath the telescope detail. A bright one is
    # compressed first so the detail lands on mid-tones (detail on pure white is invisible).
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


def landmark_detail(landmark_id: str, provider_key: str | None = None,
                    view: str = "auto") -> Detail:
    lm = get_catalog().get(landmark_id)
    if lm is None:
        raise ApiError(NOT_FOUND, f"Unknown landmark {landmark_id!r}.", 404)
    if view not in VIEWS:
        raise ApiError("INVALID_REQUEST", f"Unknown view {view!r}.")
    key = "lmdetail7:" + hashlib.sha1(f"{lm.id}|{provider_key}|{view}".encode()).hexdigest()
    cached = cache.get(key)
    if cached is not None:
        return cached

    detail = None
    if view in ("jwst", "hst"):
        detail = _space_telescope(lm, view, provider_key, view)
        if detail is None:
            raise ApiError(NO_COVERAGE, f"No {mosaic.MISSION_NAMES[view]} images cover "
                                        f"{lm.name}. Try another view.", 404)
    elif view == "auto" and lm.kind == "dso" and mast.status(lm) is not False:
        for mission in ("jwst", "hst"):
            detail = _space_telescope(lm, mission, provider_key, view)
            if detail:
                break
    if detail is None:
        detail = _survey(lm, provider_key, view)
    cache.set(key, detail)
    return detail
