from django.urls import re_path

from . import views

# Trailing slash optional, like the other apps.
urlpatterns = [
    re_path(r"^landmarks/?$", views.landmarks, name="landmarks"),
    re_path(r"^landmark-detail/?$", views.landmark_detail_view, name="landmark-detail"),
]
