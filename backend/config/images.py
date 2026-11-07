"""Safe decoding of images fetched from upstream services."""
import io

from django.conf import settings
from PIL import Image, UnidentifiedImageError

from .http import ExternalServiceError


class BadUpstreamImageError(ExternalServiceError):
    """Upstream sent something that isn't an image, or one that's too large to decode."""


def open_image(data: bytes) -> Image.Image:
    """Image.open() that checks the pixel count from the header before any decoding."""
    try:
        img = Image.open(io.BytesIO(data))
    except (UnidentifiedImageError, OSError, Image.DecompressionBombError) as exc:
        raise BadUpstreamImageError(f"unreadable upstream image: {exc}") from exc
    if img.width * img.height > settings.MAX_UPSTREAM_IMAGE_PIXELS:
        raise BadUpstreamImageError(f"upstream image too large: {img.width}x{img.height}")
    return img
