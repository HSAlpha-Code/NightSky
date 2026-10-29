from django.urls import path

from . import views

urlpatterns = [
    path("providers", views.providers, name="providers"),
    path("sky-image", views.sky_image, name="sky-image"),
]
