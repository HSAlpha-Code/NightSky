"""Highlight compression for detail images that come out over-exposed.

Bright stars and nebula cores burn out photographic surveys (DSS2 plates saturate), and the
Hubble/JWST blend adds light on top of already-bright cores. When most of an image is
near-white, a tone curve brings it back into range. Normal images are returned untouched
(same bytes, no re-encoding).
"""
import io

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

BRIGHT = 200                 # 0..255 luminance counted as "bright"
MAX_BRIGHT_FRACTION = 0.12   # over-exposed if more than this share of pixels is bright...
MAX_MEDIAN = 150             # ...or the typical pixel is this bright
TARGET_MEDIAN = 0.35         # where the median ends up after compression (0..1)
MAX_GAMMA = 2.5              # stronger curves turn burnt-out areas into muddy JPEG noise


BURNT_FRACTION = 0.15        # burnt out: this share of the image is bright AND featureless
BURNT_DETAIL = 3.0


def is_overexposed(lum: np.ndarray) -> bool:
    return (lum >= BRIGHT).mean() > MAX_BRIGHT_FRACTION or float(np.median(lum)) > MAX_MEDIAN


def burnt_fraction(data: bytes) -> float:
    """Share of the image that is bright AND flat: saturated areas with no structure a tone
    curve could bring back (e.g. DSS2 over the core of M42 is ~100 %)."""
    lum = np.asarray(Image.open(io.BytesIO(data)).convert("L"), np.float32)
    detail = gaussian_filter(np.abs(lum - gaussian_filter(lum, 4.0)), 3.0)
    return float(((lum >= BRIGHT) & (detail < BURNT_DETAIL)).mean())


def is_burnt_out(data: bytes) -> bool:
    return burnt_fraction(data) > BURNT_FRACTION


def tame_array(rgb: np.ndarray) -> tuple[np.ndarray, bool]:
    """(image, changed). Levels from the image's own 1st..99.9th percentile, then a gamma
    that puts the median at TARGET_MEDIAN. Colour ratios are kept, so burnt-out halos get
    some of their colour back instead of turning grey."""
    rgb = rgb.astype(np.float32)
    lum = rgb.mean(axis=2)
    if not is_overexposed(lum):
        return rgb.astype(np.uint8), False
    return _compress(rgb, lum), True


def _compress(rgb: np.ndarray, lum: np.ndarray) -> np.ndarray:
    """Gamma for the overall level + a soft shoulder that rolls off the top 25 % of the
    range, so cores show their structure instead of a flat white disc."""
    # Near-white areas only hold JPEG noise; smooth them so the curve doesn't amplify it.
    smooth = gaussian_filter(lum, 2.0)
    w = np.clip((smooth - 200.0) / 40.0, 0, 1)
    lum_t = lum * (1 - w) + smooth * w
    black = float(np.percentile(lum_t, 1))
    white = max(float(np.percentile(lum_t, 99.9)), black + 1.0)
    x = np.clip((lum_t - black) / (white - black), 0, 1)
    med = min(float(np.median(x)), 0.999)
    gamma = 1.0
    if med > TARGET_MEDIAN:
        gamma = float(np.clip(np.log(TARGET_MEDIAN) / np.log(med), 1.0, MAX_GAMMA))
    y = x ** gamma
    knee = 0.65                                    # above this, compress smoothly into 0.65..0.94
    over = np.clip(y - knee, 0, None)
    y = np.where(y > knee, knee + 0.29 * np.tanh(over / 0.29 * 1.2), y)
    target = y * 255.0
    out = rgb * (target / np.maximum(lum, 1.0))[..., None]
    return np.clip(out, 0, 255).astype(np.uint8)


def tame_jpeg(data: bytes) -> tuple[bytes, bool]:
    """JPEG in, JPEG out. Returns the original bytes when nothing needed changing."""
    rgb = np.asarray(Image.open(io.BytesIO(data)).convert("RGB"))
    out, changed = tame_array(rgb)
    if not changed:
        return data, False
    buf = io.BytesIO()
    Image.fromarray(out).save(buf, "JPEG", quality=90)
    return buf.getvalue(), True
