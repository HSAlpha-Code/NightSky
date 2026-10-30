"""Landmark catalogue: field lookup, prioritisation and (lazy) loading.

Data: OpenNGC (Messier/NGC/IC objects) + IAU named stars, downloaded once into
settings.CATALOG_DIR (or with `manage.py fetch_catalogs`). SIMBAD isn't used because it is
hosted by CDS, which some ISPs can't reach.
"""
import logging
import math
import tempfile
import threading
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from django.conf import settings

from config.errors import CATALOG_UNAVAILABLE, ApiError
from config.http import ExternalServiceError, http_get
from providers.hips_render import output_wcs

from .parsing import (Landmark, merge_stars, parse_iau_stars, parse_openngc, parse_wgsn_csv,
                      wgsn_html_to_csv)

log = logging.getLogger(__name__)

NGC_FILE, ADDENDUM_FILE, STARS_FILE = "NGC.csv", "addendum.csv", "IAU-CSN.txt"
# Current IAU star names (the IAU-CSN.txt download stopped being updated in 2022). Optional:
# written by `manage.py fetch_catalogs` from the WGSN web page; used when present.
WGSN_FILE = "IAU-WGSN.csv"
MIN_SEPARATION = 0.035     # markers closer than this (fraction of image width) are dropped


@dataclass(frozen=True)
class Hit:
    landmark: Landmark
    x: float    # 0..1 from the left edge of the image
    y: float    # 0..1 from the top edge


def priority(lm: Landmark, fov_deg: float) -> tuple | None:
    """Sort key (lower = more important), or None if too faint to mark in this field."""
    mag = lm.magnitude if lm.magnitude is not None else 99.0
    if lm.kind == "star":
        limit = 3.5 if fov_deg > 30 else 5.0 if fov_deg > 8 else 6.5
        return None if mag > limit else (0 if mag < 1.5 else 1, mag)
    if lm.messier:
        return (0, mag)
    if lm.common_name:
        return None if fov_deg > 20 and mag > 11 else (1, mag)
    limit = 9.0 if fov_deg > 20 else 11.0 if fov_deg > 3 else 13.5
    return None if mag > limit else (2, mag)


class Catalog:
    def __init__(self, landmarks: list[Landmark]):
        self.by_id = {lm.id: lm for lm in landmarks}
        self.landmarks = list(self.by_id.values())
        self._ra = np.array([lm.ra for lm in self.landmarks])
        self._dec = np.array([lm.dec for lm in self.landmarks])
        r, d = np.radians(self._ra), np.radians(self._dec)
        self._xyz = np.column_stack([np.cos(d) * np.cos(r), np.cos(d) * np.sin(r), np.sin(d)])

    def get(self, landmark_id: str) -> Landmark | None:
        return self.by_id.get(landmark_id)

    def query(self, ra: float, dec: float, fov_deg: float, rotation_deg: float = 0.0,
              aspect: float = 4 / 3, max_markers: int = 20) -> tuple[list[Hit], int]:
        """Landmarks inside the image (aspect = height / width), most important first.

        Returns (markers, number of eligible objects in the field before the cap)."""
        width = 1000
        height = max(1, round(width * aspect))
        radius = min(89.0, fov_deg / 2 * math.hypot(1, aspect) * 1.2)
        r, d = math.radians(ra), math.radians(dec)
        centre = np.array([math.cos(d) * math.cos(r), math.cos(d) * math.sin(r), math.sin(d)])
        near = np.nonzero(self._xyz @ centre >= math.cos(math.radians(radius)))[0]
        if len(near) == 0:
            return [], 0
        wcs = output_wcs(ra, dec, fov_deg, rotation_deg, width, height)
        px, py = wcs.wcs_world2pix(self._ra[near], self._dec[near], 0)
        fx, fy = (px + 0.5) / width, 1 - (py + 0.5) / height

        candidates = []
        for i, x, y in zip(near, fx, fy):
            if not (0 <= x <= 1 and 0 <= y <= 1):
                continue
            lm = self.landmarks[i]
            key = priority(lm, fov_deg)
            if key is not None:
                candidates.append((key, Hit(lm, float(x), float(y))))
        candidates.sort(key=lambda c: c[0])

        chosen: list[Hit] = []
        for _, hit in candidates:
            if len(chosen) >= max_markers:
                break
            if all(math.hypot(hit.x - c.x, (hit.y - c.y) * aspect) >= MIN_SEPARATION
                   for c in chosen):
                chosen.append(hit)
        return chosen, len(candidates)


def _sources() -> dict[str, str]:
    base = settings.OPENNGC_URL.rstrip("/")
    return {NGC_FILE: f"{base}/NGC.csv", ADDENDUM_FILE: f"{base}/addendum.csv",
            STARS_FILE: settings.IAU_STAR_NAMES_URL}


def ensure_files(force: bool = False) -> Path:
    """Download any missing catalogue file. Raises ExternalServiceError on failure.

    The files are normally shipped with the code (backend/data/catalogs). If they're missing
    and that folder is read-only (Vercel), they're downloaded to the temp directory instead."""
    folder = Path(settings.CATALOG_DIR)
    if not force and all((folder / n).is_file() and (folder / n).stat().st_size
                         for n in _sources()):
        return folder
    try:
        folder.mkdir(parents=True, exist_ok=True)
        probe = folder / ".write-test"
        probe.write_bytes(b"")
        probe.unlink()
    except OSError:
        folder = Path(tempfile.gettempdir()) / "nightsky-catalogs"
        folder.mkdir(parents=True, exist_ok=True)
    for name, url in _sources().items():
        path = folder / name
        if force or not path.exists() or path.stat().st_size == 0:
            log.info("downloading %s", url)
            tmp = path.with_suffix(".part")
            tmp.write_bytes(http_get(url, timeout=60).content)
            tmp.replace(path)
    return folder


def fetch_wgsn(folder: Path) -> int:
    """Download the current IAU star-name table and save it as WGSN_FILE in `folder`.

    Returns the number of stars. Raises ExternalServiceError (download) or ValueError (the
    page no longer contains a usable table); the existing file is kept in both cases."""
    html = http_get(settings.IAU_WGSN_URL, timeout=60).text
    text = wgsn_html_to_csv(html)
    count = len(parse_wgsn_csv(text))
    path = folder / WGSN_FILE
    tmp = path.with_suffix(".part")
    tmp.write_text(text, encoding="utf-8")
    tmp.replace(path)
    return count


def load_from_texts(ngc: str, addendum: str, stars: str, wgsn: str = "") -> Catalog:
    named = merge_stars(parse_iau_stars(stars), parse_wgsn_csv(wgsn) if wgsn else [])
    return Catalog(parse_openngc(ngc) + parse_openngc(addendum) + named)


_lock = threading.Lock()
_catalog: Catalog | None = None


def get_catalog() -> Catalog:
    global _catalog
    if _catalog is None:
        with _lock:
            if _catalog is None:
                try:
                    folder = ensure_files()
                except (ExternalServiceError, OSError) as exc:
                    log.warning("landmark catalogue unavailable: %s", exc)
                    raise ApiError(CATALOG_UNAVAILABLE, "The landmark catalogue couldn't be "
                                   "downloaded. Try again later.", 503) from exc
                read = lambda n: (folder / n).read_text(encoding="utf-8", errors="replace")
                wgsn = next((p for p in (folder / WGSN_FILE,
                                         Path(settings.CATALOG_DIR) / WGSN_FILE) if p.is_file()),
                            None)
                _catalog = load_from_texts(
                    read(NGC_FILE), read(ADDENDUM_FILE), read(STARS_FILE),
                    wgsn.read_text(encoding="utf-8", errors="replace") if wgsn else "")
                log.info("landmark catalogue: %d objects", len(_catalog.landmarks))
    return _catalog
