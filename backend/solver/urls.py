from django.urls import re_path

from . import views

# Trailing slash optional: "/api/solve" and "/api/solve/" both work.
urlpatterns = [
    re_path(r"^solve/?$", views.solve, name="solve"),
]
