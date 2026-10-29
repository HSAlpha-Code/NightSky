from django.http import JsonResponse
from django.urls import include, path


def index(request):
    """Health/index so opening the server root in a browser doesn't 404."""
    return JsonResponse({"status": "ok", "endpoints": [
        "POST /api/solve", "GET /api/providers", "POST /api/sky-image",
        "GET /api/landmarks", "GET /api/landmark-detail"]})


urlpatterns = [
    path("", index),
    path("api", index),
    path("api/", index),
    path("api/", include("solver.urls")),
    path("api/", include("providers.urls")),
    path("api/", include("landmarks.urls")),
]
