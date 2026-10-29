"""Plate-solver adapter. tetra3 is the default; add other solvers (Astrometry.net, ASTAP)
as another PlateSolver subclass and register it in SOLVERS."""
import io
import logging
import math
from abc import ABC, abstractmethod
from dataclasses import dataclass
from functools import lru_cache

from django.conf import settings
from PIL import Image, ImageOps

log = logging.getLogger(__name__)

MAX_SIDE_PX = 1600


@dataclass
class SolveHint:
    ra: float | None = None       # sensor-derived guess, degrees
    dec: float | None = None
    fov: float | None = None      # horizontal FOV estimate, degrees
    max_offset_deg: float = 25.0  # reject solutions farther than this from the guess


@dataclass
class SolveResult:
    ra: float
    dec: float
    rotation: float   # degrees, image "up" relative to celestial north (east of north)
    fov: float        # horizontal FOV, degrees
    confidence: float  # 0..1


class PlateSolver(ABC):
    @abstractmethod
    def solve(self, image_bytes: bytes, hint: SolveHint | None = None) -> SolveResult | None:
        """Return a solution, or None if the image cannot be solved."""


def load_image(image_bytes: bytes) -> Image.Image:
    """Decode, apply EXIF orientation, convert to grayscale and cap the long side.

    Works for 8-bit phone JPEGs and 16-bit TIFFs (PIL's "L" mode would clip 16-bit data).
    """
    img = ImageOps.exif_transpose(Image.open(io.BytesIO(image_bytes)))
    if img.mode in ("I;16", "I;16B", "I;16L", "I", "F"):
        img = img.convert("F")
    else:
        img = img.convert("L")
    scale = MAX_SIDE_PX / max(img.size)
    if scale < 1:
        img = img.resize((round(img.width * scale), round(img.height * scale)), Image.BILINEAR)
    return img


def angular_distance(ra1, dec1, ra2, dec2) -> float:
    r1, d1, r2, d2 = map(math.radians, (ra1, dec1, ra2, dec2))
    c = math.sin(d1) * math.sin(d2) + math.cos(d1) * math.cos(d2) * math.cos(r1 - r2)
    return math.degrees(math.acos(max(-1.0, min(1.0, c))))


def position_angle(ra1, dec1, ra2, dec2) -> float:
    """Position angle of point 2 as seen from point 1, degrees east of north, in [0, 360)."""
    r1, d1, r2, d2 = map(math.radians, (ra1, dec1, ra2, dec2))
    dra = r2 - r1
    y = math.sin(dra) * math.cos(d2)
    x = math.cos(d1) * math.sin(d2) - math.sin(d1) * math.cos(d2) * math.cos(dra)
    return math.degrees(math.atan2(y, x)) % 360.0


def _first(value) -> float:
    """tetra3 returns a scalar or a 1-element list for a single target pixel."""
    while isinstance(value, (list, tuple)) or getattr(value, "ndim", 0):
        value = value[0]
    return float(value)


@lru_cache(maxsize=1)
def _tetra3_instance():
    import numpy as np
    import tetra3  # heavy import, load once per process
    if not hasattr(np, "math"):  # tetra3 uses np.math.factorial, removed in NumPy 2
        np.math = math
    db = settings.TETRA3_DATABASE or "default_database"
    return tetra3.Tetra3(load_database=db)


class Tetra3Solver(PlateSolver):
    def solve(self, image_bytes, hint=None):
        hint = hint or SolveHint()
        try:
            t3 = _tetra3_instance()
        except (ImportError, OSError) as exc:  # not installed / database missing
            log.error("tetra3 unavailable, using phone sensors only: %s", exc)
            return None
        img = load_image(image_bytes)
        # A pixel straight above the centre gives the image "up" direction on the sky;
        # this avoids depending on tetra3's internal Roll convention.
        w, h = img.size
        up_pixel = [h / 2 - h / 10, w / 2]  # (y, x) from top-left
        kwargs = {"solve_timeout": settings.TETRA3_SOLVE_TIMEOUT_MS, "target_pixel": up_pixel}
        if hint.fov:
            kwargs.update(fov_estimate=hint.fov, fov_max_error=max(2.0, hint.fov * 0.25))
        try:
            sol = t3.solve_from_image(img, **kwargs)
        except Exception:  # tetra3 raises on degenerate images
            log.exception("tetra3 crashed")
            return None
        if sol.get("RA") is None:
            log.info("tetra3: no solution (%s ms)", sol.get("T_solve"))
            return None
        ra, dec = float(sol["RA"]), float(sol["Dec"])
        # tetra3 is lost-in-space; the sensor guess is used to reject false positives.
        if hint.ra is not None and hint.dec is not None:
            off = angular_distance(ra, dec, hint.ra, hint.dec)
            if off > hint.max_offset_deg:
                log.warning("tetra3 solution %.1f deg from sensor guess, rejected", off)
                return None
        prob = float(sol.get("Prob") or 0.0)
        up_ra, up_dec = _first(sol["RA_target"]), _first(sol["Dec_target"])
        return SolveResult(
            ra=ra % 360.0,
            dec=dec,
            rotation=position_angle(ra, dec, up_ra, up_dec),
            fov=float(sol["FOV"]),
            confidence=round(max(0.0, min(1.0, 1.0 - prob)), 4),
        )


SOLVERS: dict[str, type[PlateSolver]] = {
    "tetra3": Tetra3Solver,
}


def get_solver() -> PlateSolver:
    return SOLVERS[settings.PLATE_SOLVER]()
