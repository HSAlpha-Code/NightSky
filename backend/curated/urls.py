from django.urls import re_path

from . import views

# Read-only. Order matters: "index" and "image/..." before the generic body id.
urlpatterns = [
    re_path(r"^curated/index/?$", views.curated_index, name="curated-index"),
    re_path(r"^curated/image/(?P<name>[^/]+)$", views.curated_image, name="curated-image"),
    re_path(r"^curated/(?P<body_id>[A-Za-z0-9_.\-]+)/?$", views.curated_body,
            name="curated-body"),
]
