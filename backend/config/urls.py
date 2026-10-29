from django.urls import include, path

urlpatterns = [
    path("api/", include("solver.urls")),
    path("api/", include("providers.urls")),
]
