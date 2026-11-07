"""Export enabled highlights as a bundle: images/ + manifest.json (see README.md)."""
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

from django.conf import settings

from curated.models import CuratedHighlight
from curated.repo import record_from_model, thumb_name


def export_bundle(dest: Path | None = None) -> dict:
    dest = Path(dest or settings.CURATED_BUNDLE_DIR)
    media = Path(settings.CURATED_MEDIA_ROOT)
    rows = list(CuratedHighlight.objects.filter(enabled=True).order_by("body_id", "sort_order", "id"))
    images = dest / "images"
    if images.exists():
        shutil.rmtree(images)
    images.mkdir(parents=True)
    records, missing = [], []
    for h in rows:
        files = [h.image_file, thumb_name(h.image_file)]
        if not all((media / f).is_file() for f in files):
            missing.append(h.image_file)
            continue
        for f in files:
            shutil.copy2(media / f, images / f)
        records.append({**record_from_model(h), "enabled": True})
    manifest = {"generated_at": datetime.now(timezone.utc).isoformat(), "highlights": records}
    (dest / "manifest.json").write_text(json.dumps(manifest, indent=1), encoding="utf-8")
    return {"path": str(dest), "highlights": len(records),
            "bodies": len({r["body_id"] for r in records}), "missing_files": missing}
