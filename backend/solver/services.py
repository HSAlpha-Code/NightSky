"""Solve service: plate-solve first, sensor-derived pointing as fallback."""
import logging
from datetime import datetime, timezone

from django.conf import settings
from PIL import UnidentifiedImageError

from config.errors import INVALID_REQUEST, SOLVE_FAILED, ApiError

from .astro import Pointing, SensorError, matrix_from_list, pointing_from_matrix, quaternion_to_matrix
from .plate_solver import SolveHint, get_solver, load_image

log = logging.getLogger(__name__)

BELOW_HORIZON_DEG = -5.0


def sensor_pointing(meta: dict) -> Pointing:
    """Raise SensorError if location/orientation are missing or invalid."""
    orientation = meta.get("orientation")
    if not orientation:
        raise SensorError("No orientation data.")
    if meta.get("latitude") is None or meta.get("longitude") is None:
        raise SensorError("No GPS location.")
    if "quaternion" in orientation:
        q = orientation["quaternion"]
        matrix = quaternion_to_matrix(q["x"], q["y"], q["z"], q["w"])
    else:
        matrix = matrix_from_list(orientation["rotation_matrix"])
    when = meta.get("timestamp") or datetime.now(timezone.utc)
    return pointing_from_matrix(matrix, meta["latitude"], meta["longitude"],
                                meta.get("altitude") or 0.0, when, orientation["reference"],
                                int(meta.get("image_rotation_deg", 0)))


def solve(image_bytes: bytes, meta: dict) -> dict:
    try:
        load_image(image_bytes)  # validate early so a bad upload is a 400, not a solve failure
    except (UnidentifiedImageError, OSError, ValueError) as exc:
        raise ApiError(INVALID_REQUEST, "The uploaded file is not a readable image.") from exc

    pointing, sensor_problem = None, ""
    try:
        pointing = sensor_pointing(meta)
    except SensorError as exc:
        sensor_problem = str(exc)
        log.info("sensor pointing unavailable: %s", exc)

    fov_hint = meta.get("fov_deg")
    hint = SolveHint(ra=pointing.ra if pointing else None, dec=pointing.dec if pointing else None,
                     fov=fov_hint)
    result = get_solver().solve(image_bytes, hint)
    alt_az = {"alt": pointing.alt if pointing else None, "az": pointing.az if pointing else None}

    if result is not None:
        return {"ra": result.ra, "dec": result.dec, "rotation": result.rotation, "fov": result.fov,
                "confidence": result.confidence, "approximate": False, "source": "plate_solve",
                "message": "", **alt_az}

    if pointing is None:
        raise ApiError(SOLVE_FAILED, "We couldn't find enough stars in this photo, and the phone's "
                       f"sensors gave no usable position ({sensor_problem}). Try again with a "
                       "clearer, darker sky and allow location access.", 422)
    if pointing.alt < BELOW_HORIZON_DEG:
        raise ApiError(SOLVE_FAILED, "The camera seems to be pointing below the horizon. "
                       "Point it at the sky and try again.", 422)
    return {"ra": pointing.ra, "dec": pointing.dec, "rotation": pointing.rotation,
            "fov": fov_hint or settings.DEFAULT_FOV_DEG, "confidence": 0.0, "approximate": True,
            "source": "sensors",
            "message": "Not enough stars were recognised, so this position comes from the phone's "
                       "sensors and may be off by several degrees.", **alt_az}
