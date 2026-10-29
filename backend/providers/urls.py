from django.urls import re_path

from . import views

# Trailing slash optional: "/api/providers" and "/api/providers/" both work.
urlpatterns = [
    re_path(r"^providers/?$", views.providers, name="providers"),
    re_path(r"^sky-image/?$", views.sky_image, name="sky-image"),
]
