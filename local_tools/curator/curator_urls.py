from django.urls import path, re_path

from curated.views import curated_image

import curator_views as v

urlpatterns = [
    path("", v.page),
    path("api/bodies", v.bodies),
    path("api/highlights", v.highlights),
    path("api/highlights/reorder", v.reorder),
    path("api/highlights/<int:pk>", v.highlight_item),
    path("api/export", v.export_view),
    re_path(r"^media/(?P<name>[^/]+)$", curated_image),
]
