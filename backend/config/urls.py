from django.http import JsonResponse
from django.urls import include, path

from .legal import document
from .panorama import panorama_file


def index(request):
    """Health/index so opening the server root in a browser doesn't 404."""
    return JsonResponse({"status": "ok", "endpoints": [
        "POST /api/solve", "GET /api/providers", "POST /api/sky-image",
        "GET /api/landmarks", "GET /api/landmark-detail",
        "GET /api/curated/index/", "GET /api/curated/<body_id>/"]})


urlpatterns = [
    path("api/panorama/nasa2020-v1/<str:resolution>/<str:filename>", panorama_file),
    path("privacy/", document, {"name": "privacy"}),
    path("terms/", document, {"name": "terms"}),
    path("credits/", document, {"name": "credits"}),
    path("legal/sky_catalog.json", document, {"name": "sky_catalog"}),
    path("", index),
    path("api", index),
    path("api/", index),
    path("api/", include("solver.urls")),
    path("api/", include("providers.urls")),
    path("api/", include("landmarks.urls")),
    path("api/", include("curated.urls")),
]
