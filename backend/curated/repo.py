"""Where curated highlights are read from.

* "bundle": a read-only folder shipped with the deployment (settings.CURATED_BUNDLE_DIR with
  manifest.json + images/). This is what runs on Vercel, whose filesystem is read-only and has
  no database.
* "db": the CuratedHighlight table + settings.CURATED_MEDIA_ROOT (local curation / self-hosting).
* "auto" (default locally): bundle if a manifest exists, otherwise the database.
"""
import hashlib
import json
import logging
from pathlib import Path

from django.conf import settings
from django.db import DatabaseError

log = logging.getLogger(__name__)

_manifest_cache: dict = {"key": None, "records": []}


def thumb_name(image_file: str) -> str:
    return Path(image_file).stem + "_t.jpg"


def _manifest_path() -> Path:
    return Path(settings.CURATED_BUNDLE_DIR) / "manifest.json"


def source_mode() -> str:
    mode = settings.CURATED_SOURCE
    if mode in ("bundle", "db"):
        return mode
    return "bundle" if _manifest_path().is_file() else "db"


def image_dir() -> Path:
    if source_mode() == "bundle":
        return Path(settings.CURATED_BUNDLE_DIR) / "images"
    return Path(settings.CURATED_MEDIA_ROOT)


def record_from_model(h) -> dict:
    return {
        "id": h.id, "body_id": h.body_id, "body_name": h.body_name, "title": h.title,
        "image_file": h.image_file, "source_outlet": h.source_outlet,
        "source_url": h.source_url, "credit": h.credit, "caption": h.caption,
        "ra": h.ra, "dec": h.dec, "sort_order": h.sort_order,
        "updated_at": h.updated_at.isoformat(),
    }


def _from_db() -> list[dict]:
    from .models import CuratedHighlight
    try:
        rows = CuratedHighlight.objects.filter(enabled=True).order_by(
            "body_id", "sort_order", "id")
        return [record_from_model(h) for h in rows]
    except DatabaseError:
        log.warning("curated highlights: database unavailable, serving none")
        return []


def _from_bundle() -> list[dict]:
    path = _manifest_path()
    try:
        stat = path.stat()
        key = (str(path), stat.st_mtime_ns, stat.st_size)
        if _manifest_cache["key"] != key:
            data = json.loads(path.read_text(encoding="utf-8"))
            _manifest_cache.update(key=key, records=[
                r for r in data.get("highlights", []) if r.get("enabled", True)])
        return _manifest_cache["records"]
    except (OSError, ValueError):
        log.warning("curated highlights: bundle manifest unreadable, serving none")
        return []


def enabled_highlights() -> list[dict]:
    """Enabled highlights, ordered by body then sort_order."""
    records = _from_bundle() if source_mode() == "bundle" else _from_db()
    return sorted(records, key=lambda r: (r["body_id"], r["sort_order"], r["id"]))


def fingerprint(records: list[dict]) -> str:
    """Stable hash of the data; changes whenever any field of any record changes."""
    blob = json.dumps(records, sort_keys=True, separators=(",", ":"))
    return hashlib.sha1(blob.encode()).hexdigest()[:16]
