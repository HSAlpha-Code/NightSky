"""MAST (STScI) lookups: is there a Hubble / JWST / Chandra preview image of a landmark?

A position search takes 10-20 s, so lookups run in a small background thread pool and the
result is cached. `status()` never blocks: it returns None while a lookup is still running.
"""
import json
import logging
import threading
from concurrent.futures import ThreadPoolExecutor

from django.conf import settings
from django.core.cache import cache

from config.http import ExternalServiceError, http_get, http_post

log = logging.getLogger(__name__)

COLLECTIONS = ("HST", "JWST", "CHANDRA")
COLLECTION_NAMES = {"HST": "Hubble Space Telescope", "JWST": "James Webb Space Telescope",
                    "CHANDRA": "Chandra X-ray Observatory"}
RESULT_TTL = 30 * 24 * 3600      # previews don't change often
FAILED_TTL = 10 * 60             # retry a failed lookup after 10 minutes
# Search cone, degrees. Kept small: big cones over busy regions (M42 has thousands of HST
# frames) make MAST time out, and a preview of the object's core is what we want anyway.
MIN_RADIUS, MAX_RADIUS = 0.01, 0.03
TINY_RADIUS = 0.0025     # 9 arcsec: last try for fields so busy that the normal cone times out
COLUMNS = "obs_collection,obs_id,target_name,instrument_name,filters,t_exptime,jpegURL,s_ra,s_dec"
NO_PREVIEW = "none"

_pool: ThreadPoolExecutor | None = None
_pool_lock = threading.Lock()
_pending: set[str] = set()


def search_radius(size_arcmin: float | None) -> float:
    return min(MAX_RADIUS, max(MIN_RADIUS, (size_arcmin or 0) / 60 / 2))


def _key(landmark_id: str) -> str:
    return f"mast:{landmark_id}"


def pick_best(rows: list[dict]) -> dict | None:
    """Best preview: JWST > HST > Chandra, then longest exposure."""
    order = {c: i for i, c in enumerate(("JWST", "HST", "CHANDRA"))}
    calibration = ("DARK", "BIAS", "FLAT", "EARTH-CALIB", "INTFLAT", "KSPOTS")
    usable = [r for r in rows if r.get("jpegURL") and r.get("obs_collection") in order
              and not any(c in str(r.get("target_name", "")).upper() for c in calibration)]
    if not usable:
        return None
    best = min(usable, key=lambda r: (order[r["obs_collection"]], -(r.get("t_exptime") or 0)))
    collection = best["obs_collection"]
    return {
        "collection": collection, "mission": COLLECTION_NAMES[collection],
        "obs_id": best.get("obs_id", ""), "target": best.get("target_name", ""),
        "instrument": best.get("instrument_name", ""), "filters": best.get("filters", ""),
        "jpeg_uri": best["jpegURL"],
    }


def lookup(ra: float, dec: float, radius_deg: float) -> dict | None:
    """Blocking MAST search. Returns the best preview, or None if there is none.

    Very busy fields (M42 has thousands of HST frames) can time out on the full cone; then
    a tiny cone on the exact centre is tried, which is enough to find a preview."""
    try:
        return _search(ra, dec, radius_deg, settings.MAST_TIMEOUT_SECONDS)
    except ExternalServiceError as exc:
        if radius_deg <= TINY_RADIUS or "timed out" not in str(exc):
            raise
        log.info("MAST cone %.3f deg timed out; retrying with a tiny cone", radius_deg)
        return _search(ra, dec, TINY_RADIUS, settings.MAST_TIMEOUT_SECONDS)


def _search(ra: float, dec: float, radius_deg: float, timeout: float) -> dict | None:
    request = {
        "service": "Mast.Caom.Filtered.Position", "format": "json", "pagesize": 50, "page": 1,
        "params": {
            "columns": COLUMNS,
            # No intentType filter: it makes MAST time out on busy fields like M42.
            # Calibration frames are skipped in pick_best instead.
            "filters": [{"paramName": "obs_collection", "values": list(COLLECTIONS)},
                        {"paramName": "dataproduct_type", "values": ["image"]}],
            "position": f"{ra:.6f}, {dec:.6f}, {radius_deg:.4f}",
        },
    }
    resp = http_post(settings.MAST_URL, data={"request": json.dumps(request)},
                     timeout=timeout, retries=0)
    body = resp.json()
    if body.get("status") not in ("COMPLETE", "EXECUTING"):
        raise ExternalServiceError(f"MAST status {body.get('status')}: {body.get('msg')}")
    return pick_best(body.get("data") or [])


def _run(landmark_id, ra, dec, radius):
    try:
        best = lookup(ra, dec, radius)
        cache.set(_key(landmark_id), best or NO_PREVIEW, RESULT_TTL)
    except (ExternalServiceError, ValueError) as exc:
        log.warning("MAST lookup for %s failed: %s", landmark_id, exc)
        cache.set(_key(landmark_id), NO_PREVIEW, FAILED_TTL)
    finally:
        with _pool_lock:
            _pending.discard(landmark_id)


def _executor() -> ThreadPoolExecutor:
    global _pool
    with _pool_lock:
        if _pool is None:
            _pool = ThreadPoolExecutor(max_workers=settings.MAST_WORKERS,
                                       thread_name_prefix="mast")
        return _pool


def status(landmark) -> dict | None | bool:
    """Cached result without blocking: a preview dict, False (no preview) or None (pending).

    A lookup is started in the background if there's no cached answer yet."""
    cached = cache.get(_key(landmark.id))
    if cached is not None:
        return False if cached == NO_PREVIEW else cached
    with _pool_lock:
        if landmark.id in _pending:
            return None
        _pending.add(landmark.id)
    _executor().submit(_run, landmark.id, landmark.ra, landmark.dec,
                       search_radius(landmark.size_arcmin))
    return None
