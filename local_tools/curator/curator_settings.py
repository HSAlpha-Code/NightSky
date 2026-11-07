"""Django settings for the LOCAL curator only. Not part of the deployable backend."""
import os
import sys
from pathlib import Path

CURATOR_DIR = Path(__file__).resolve().parent
BACKEND_DIR = CURATOR_DIR.parent.parent / "backend"
sys.path.insert(0, str(BACKEND_DIR))

if os.environ.get("ENABLE_CURATOR") != "1":
    raise RuntimeError("The curator is disabled. Set ENABLE_CURATOR=1 to run it (see README.md).")

from config.settings import *  # noqa: E402,F401,F403  (reuse the backend's catalogue/HTTP settings)

DEBUG = True
SECRET_KEY = "local-curator-only"
ALLOWED_HOSTS = ["127.0.0.1", "localhost"]
ROOT_URLCONF = "curator_urls"
INSTALLED_APPS = ["django.contrib.contenttypes", "curated", "landmarks"]
MIDDLEWARE = [
    "django.middleware.common.CommonMiddleware",
    "curator_views.CuratorGuardMiddleware",
]
DATABASES = {"default": {"ENGINE": "django.db.backends.sqlite3",
                         "NAME": CURATOR_DIR / "curator.sqlite3"}}
CURATED_SOURCE = "db"
CURATED_MEDIA_ROOT = CURATOR_DIR / "media"
CURATED_BUNDLE_DIR = BACKEND_DIR / "curated_bundle"
