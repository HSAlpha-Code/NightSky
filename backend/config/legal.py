"""Public, offline-generated legal documents: no login, tracking, or templates."""
from pathlib import Path

from django.http import FileResponse, Http404
from django.views.decorators.http import require_safe

LEGAL_DIR = Path(__file__).resolve().parent.parent / "legal"
DOCUMENTS = {"privacy": "privacy.html", "terms": "terms.html", "credits": "credits.html",
             "sky_catalog": "sky_catalog.json"}


@require_safe
def document(request, name):
    filename = DOCUMENTS.get(name)
    if filename is None or not (LEGAL_DIR / filename).is_file():
        raise Http404
    content_type = "application/json" if filename.endswith(".json") else "text/html; charset=utf-8"
    response = FileResponse((LEGAL_DIR / filename).open("rb"), content_type=content_type)
    response["Cache-Control"] = "public, max-age=300, must-revalidate"
    response["X-Content-Type-Options"] = "nosniff"
    response["Content-Security-Policy"] = (
        "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'"
    )
    return response
