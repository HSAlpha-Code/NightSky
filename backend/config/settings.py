import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent


def _load_dotenv(path: Path) -> None:
    """Minimal .env loader (KEY=VALUE lines). Existing env vars win."""
    if not path.exists():
        return
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip())


_load_dotenv(BASE_DIR / ".env")

# Vercel: everything except /tmp is read-only, so libraries that keep config/cache folders
# in the home directory (astropy) must use /tmp.
ON_VERCEL = bool(os.environ.get("VERCEL"))
if ON_VERCEL:
    os.environ["HOME"] = "/tmp"
    os.environ.setdefault("XDG_CACHE_HOME", "/tmp/.cache")
    os.environ.setdefault("XDG_CONFIG_HOME", "/tmp/.config")


def env(key: str, default: str = "") -> str:
    return os.environ.get(key, default)


def env_bool(key: str, default: bool = False) -> bool:
    return env(key, "1" if default else "0").lower() in ("1", "true", "yes", "on")


SECRET_KEY = env("DJANGO_SECRET_KEY", "dev-insecure-key-change-me")
# Debug is on for local development and off on Vercel unless DJANGO_DEBUG says otherwise.
DEBUG = env_bool("DJANGO_DEBUG", not ON_VERCEL)
# Wildcard only for local development; deployments must be explicit (default: Vercel domains).
ALLOWED_HOSTS = [h.strip() for h in
                 env("DJANGO_ALLOWED_HOSTS", "*" if DEBUG else ".vercel.app").split(",")
                 if h.strip()]
if ON_VERCEL and not DEBUG and SECRET_KEY.startswith("dev-insecure"):
    raise RuntimeError("Set the DJANGO_SECRET_KEY environment variable in Vercel.")
if not DEBUG:
    # HTTPS-only API. Vercel terminates TLS and redirects HTTP itself, so no SSL redirect here.
    SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
    SECURE_HSTS_SECONDS = int(env("SECURE_HSTS_SECONDS", "31536000"))
    SECURE_CONTENT_TYPE_NOSNIFF = True
    X_FRAME_OPTIONS = "DENY"
    # The API is stateless (no cookies, sessions or forms), so CSRF/clickjacking middleware
    # and an SSL redirect add nothing; these checks don't apply.
    SILENCED_SYSTEM_CHECKS = ["security.W002", "security.W003", "security.W008"]

INSTALLED_APPS = [
    "django.contrib.contenttypes",
    "django.contrib.staticfiles",
    "corsheaders",
    "rest_framework",
    "providers",
    "solver",
    "landmarks",
    "curated",
]

MIDDLEWARE = [
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "django.middleware.common.CommonMiddleware",
    "config.middleware.SecurityHeadersMiddleware",
]

ROOT_URLCONF = "config.urls"
WSGI_APPLICATION = "config.wsgi.application"

# No models in v1; SQLite only satisfies Django's defaults.
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": BASE_DIR / "db.sqlite3",
    }
}

TEMPLATES = []
STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"   # the API serves no static files; set for collectstatic
USE_TZ = True
TIME_ZONE = "UTC"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

CORS_ALLOW_ALL_ORIGINS = env_bool("CORS_ALLOW_ALL_ORIGINS", True)

CORS_EXPOSE_HEADERS = ["X-Provider", "X-Provider-Name", "X-Credit", "X-Fallback-Used",
                       "X-Fallback-Reason", "X-Fallback-Message"]

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": [],
    "DEFAULT_PERMISSION_CLASSES": [],
    "UNAUTHENTICATED_USER": None,
    "DEFAULT_RENDERER_CLASSES": ["rest_framework.renderers.JSONRenderer"],
    "EXCEPTION_HANDLER": "config.errors.api_exception_handler",
    "DEFAULT_THROTTLE_CLASSES": ["rest_framework.throttling.AnonRateThrottle"],
    "DEFAULT_THROTTLE_RATES": {
        "anon": env("THROTTLE_RATE_ANON", "120/min"),
        # sky-image, solve and landmark-detail: expensive renders / upstream fan-out.
        "heavy": env("THROTTLE_RATE_HEAVY", "20/min"),
    },
    # Vercel sets X-Forwarded-For to the real client IP; without a trusted proxy count the
    # header is client-controlled and would let callers dodge the limit.
    "NUM_PROXIES": 1 if ON_VERCEL else None,
}

# Uploaded photos (downscaled on the phone to ~1600px) stay well below this. Vercel rejects
# bodies over ~4.5 MB itself (with a non-JSON error), so enforce a limit just under that.
MAX_UPLOAD_BYTES = 4 * 1024 * 1024
# Images above this many pixels are rejected before decoding (decompression-bomb guard).
MAX_IMAGE_PIXELS = int(env("MAX_IMAGE_PIXELS", str(64_000_000)))
# Same guard for images fetched from upstream services (tiles, cutouts, mosaics).
MAX_UPSTREAM_IMAGE_PIXELS = int(env("MAX_UPSTREAM_IMAGE_PIXELS", str(16_000_000)))
# Largest /api/sky-image render (width x height). A 3000x3000 render peaked at ~1.1 GB.
MAX_RENDER_PIXELS = int(env("MAX_RENDER_PIXELS", str(3_000_000)))
# Local HiPS renders allowed at once per instance (each holds several large arrays).
MAX_CONCURRENT_RENDERS = int(env("MAX_CONCURRENT_RENDERS", "2"))
DATA_UPLOAD_MAX_MEMORY_SIZE = MAX_UPLOAD_BYTES
FILE_UPLOAD_MAX_MEMORY_SIZE = MAX_UPLOAD_BYTES

# --- Cache ---
_cache_backend = env("CACHE_BACKEND", "locmem")
_cache_timeout = int(env("CACHE_TIMEOUT_SECONDS", "86400"))
# Two pools so a sky-image workload (large JPEGs, HiPS tiles) can't evict landmark details,
# MAST results and the provider-down flags, and vice versa.
if _cache_backend == "file":
    _cache_dir = env("CACHE_LOCATION", str(BASE_DIR / ".cache"))
    CACHES = {
        "default": {
            "BACKEND": "django.core.cache.backends.filebased.FileBasedCache",
            "LOCATION": _cache_dir, "TIMEOUT": _cache_timeout},
        "images": {
            "BACKEND": "django.core.cache.backends.filebased.FileBasedCache",
            "LOCATION": _cache_dir + "_images", "TIMEOUT": _cache_timeout},
    }
elif _cache_backend == "redis":
    _redis = {"BACKEND": "django.core.cache.backends.redis.RedisCache",
              "LOCATION": env("CACHE_LOCATION", "redis://localhost:6379/0"),
              "TIMEOUT": _cache_timeout}
    CACHES = {"default": _redis, "images": {**_redis, "KEY_PREFIX": "images"}}
else:
    # Entries can be ~800 KB images; the entry counts keep each pool's RAM bounded.
    CACHES = {
        "default": {
            "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
            "LOCATION": "default", "TIMEOUT": _cache_timeout,
            "OPTIONS": {"MAX_ENTRIES": 150}},
        "images": {
            "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
            "LOCATION": "images", "TIMEOUT": _cache_timeout,
            "OPTIONS": {"MAX_ENTRIES": 150}},
    }

# --- External services ---
HTTP_TIMEOUT_SECONDS = float(env("HTTP_TIMEOUT_SECONDS", "25"))
HTTP_CONNECT_TIMEOUT_SECONDS = float(env("HTTP_CONNECT_TIMEOUT_SECONDS", "5"))
HTTP_RETRIES = int(env("HTTP_RETRIES", "1"))

DEFAULT_PROVIDER = env("DEFAULT_PROVIDER", "dss2_color")
HIPS2FITS_URL = env("HIPS2FITS_URL", "https://alasky.cds.unistra.fr/hips-image-services/hips2fits")
# Copies of DSS2/2MASS/AllWISE HiPS tiles outside CDS; rendered locally if hips2fits is unreachable.
HIPS_MIRROR_URL = env("HIPS_MIRROR_URL", "https://skies.esac.esa.int")
SKYVIEW_URL = env("SKYVIEW_URL", "https://skyview.gsfc.nasa.gov/current/cgi/runquery.pl")
PANSTARRS_URL = env("PANSTARRS_URL", "https://ps1images.stsci.edu/cgi-bin")
# After a provider's service fails, skip it for this many seconds (avoids stacking timeouts).
PROVIDER_DOWN_SECONDS = int(env("PROVIDER_DOWN_SECONDS", "120"))

# --- Landmarks ---
# OpenNGC (Messier/NGC/IC) + IAU star names, downloaded once into CATALOG_DIR.
# (SIMBAD is not used: it's hosted by CDS, which some ISPs can't reach.)
CATALOG_DIR = Path(env("CATALOG_DIR", str(BASE_DIR / "data" / "catalogs")))
OPENNGC_URL = env("OPENNGC_URL",
                  "https://raw.githubusercontent.com/mattiaverga/OpenNGC/master/database_files")
IAU_STAR_NAMES_URL = env("IAU_STAR_NAMES_URL",
                         "https://www.pas.rochester.edu/~emamajek/WGSN/IAU-CSN.txt")
# The list above stopped being updated in 2022; the IAU WGSN now publishes the current names
# as a table on this page. `manage.py fetch_catalogs` saves it as data/catalogs/IAU-WGSN.csv.
IAU_WGSN_URL = env("IAU_WGSN_URL", "https://exopla.net/star-names/modern-iau-star-names/")
LANDMARK_MAX_MARKERS = int(env("LANDMARK_MAX_MARKERS", "20"))
MAST_URL = env("MAST_URL", "https://mast.stsci.edu/api/v0/invoke")
# MAST position searches take 10-35 s (busy fields like M42 the longest); they run in
# background threads and are cached for 30 days, so only the first view of a field waits.
MAST_TIMEOUT_SECONDS = float(env("MAST_TIMEOUT_SECONDS", "40"))
MAST_WORKERS = int(env("MAST_WORKERS", "4"))
# Cap on queued + running background lookups; further landmarks report "pending" until a slot frees.
MAST_MAX_PENDING = int(env("MAST_MAX_PENDING", "8"))
# ESA ESASky HiPS: all public Hubble and JWST imaging, already stitched into sky tiles.
ESASKY_HIPS_URL = env("ESASKY_HIPS_URL", "https://cdn.skies.esac.esa.int")

# --- Curated Cosmic Highlights ---
# Read-only content. On Vercel it comes from a bundle shipped with the deployment
# (curated_bundle/manifest.json + images/, produced by the local curator tool's export);
# locally it can come from the database + CURATED_MEDIA_ROOT. "auto" = bundle if present.
CURATED_SOURCE = env("CURATED_SOURCE", "bundle" if ON_VERCEL else "auto")
CURATED_BUNDLE_DIR = Path(env("CURATED_BUNDLE_DIR", str(BASE_DIR / "curated_bundle")))
CURATED_MEDIA_ROOT = Path(env("CURATED_MEDIA_ROOT",
                              str(BASE_DIR.parent / "local_tools" / "curator" / "media")))

PLATE_SOLVER = env("PLATE_SOLVER", "tetra3")
TETRA3_DATABASE = env("TETRA3_DATABASE", "")
TETRA3_SOLVE_TIMEOUT_MS = int(env("TETRA3_SOLVE_TIMEOUT_MS", "10000"))
# Used for the sensor fallback when the phone does not report a field of view.
DEFAULT_FOV_DEG = float(env("DEFAULT_FOV_DEG", "60"))
# astropy IERS (Earth rotation) tables: offline by default; bundled tables are accurate to
# well under an arcminute for this use.
ASTROPY_IERS_AUTO_DOWNLOAD = env_bool("ASTROPY_IERS_AUTO_DOWNLOAD", False)

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "handlers": {"console": {"class": "logging.StreamHandler"}},
    "root": {"handlers": ["console"], "level": "INFO"},
}
