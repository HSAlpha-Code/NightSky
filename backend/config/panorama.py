"""Versioned, read-only NASA mobile texture packs (no runtime conversion)."""
from pathlib import Path
import re

from django.conf import settings
from django.http import FileResponse, Http404
from django.views.decorators.http import require_safe


@require_safe
def panorama_file(request, resolution, filename):
    if resolution not in ("16k", "32k") or not re.fullmatch(r"(?:manifest\.json|\d{1,2}_\d{1,2}\.webp)", filename):
        raise Http404
    root = Path(getattr(settings, "PANORAMA_PACK_DIR", settings.BASE_DIR / "panorama_packs"))
    path = root / resolution / filename
    if not path.is_file():
        raise Http404("Panorama pack has not been prepared on this server")
    response = FileResponse(path.open("rb"), content_type="application/json" if filename.endswith("json") else "image/webp")
    response["Cache-Control"] = "public, max-age=31536000, immutable"
    response["X-Content-Type-Options"] = "nosniff"
    return response
