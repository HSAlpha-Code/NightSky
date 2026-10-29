"""Phone orientation -> alt/az -> RA/Dec.

Frames (Android convention, also used by flutter_rotation_sensor on iOS):
- World: X = East, Y = North, Z = Up (ENU).
- Device: X = right, Y = top of the screen in natural portrait, Z = out of the screen.
- The orientation (quaternion or matrix) rotates device vectors into the world frame.
- The rear camera looks along device -Z.
- image_rotation_deg (0/90/180/270, Android Surface rotation): which device axis is "up" in the
  upright photo. 0 -> +Y (portrait), 90 -> +X, 180 -> -Y, 270 -> -X.
"""
import math
from dataclasses import dataclass
from datetime import datetime

import numpy as np
from astropy import units as u
from astropy.coordinates import AltAz, EarthLocation, SkyCoord
from astropy.time import Time
from astropy.utils import iers
from django.conf import settings

from .plate_solver import position_angle

iers.conf.auto_download = settings.ASTROPY_IERS_AUTO_DOWNLOAD
iers.conf.iers_degraded_accuracy = "warn"  # bundled tables are plenty for phone-sensor accuracy

UP_OFFSET_RAD = 0.01  # small step along image-up used to measure the sky rotation


class SensorError(ValueError):
    """Sensor data is missing or unusable."""


@dataclass
class Pointing:
    ra: float
    dec: float
    rotation: float   # position angle of image-up, degrees east of north
    alt: float
    az: float         # true azimuth, degrees from north through east
    declination_applied: float = 0.0


def quaternion_to_matrix(x: float, y: float, z: float, w: float) -> np.ndarray:
    q = np.array([x, y, z, w], dtype=float)
    n = np.linalg.norm(q)
    if not np.isfinite(n) or n < 1e-6:
        raise SensorError("Orientation quaternion is zero or invalid.")
    x, y, z, w = q / n
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])


def matrix_from_list(values) -> np.ndarray:
    m = np.array(values, dtype=float).reshape(3, 3)  # row-major, like Android getRotationMatrix
    if not np.all(np.isfinite(m)) or abs(np.linalg.det(m) - 1) > 0.1:
        raise SensorError("Rotation matrix is not a valid rotation.")
    return m


def magnetic_declination(lat: float, lon: float, alt_m: float, when: datetime) -> float:
    """World Magnetic Model declination in degrees (east positive)."""
    from pygeomag import GeoMag
    year_start = datetime(when.year, 1, 1, tzinfo=when.tzinfo)
    year_len = (datetime(when.year + 1, 1, 1, tzinfo=when.tzinfo) - year_start).total_seconds()
    decimal_year = when.year + (when - year_start).total_seconds() / year_len
    result = GeoMag().calculate(glat=lat, glon=lon, alt=alt_m / 1000.0, time=decimal_year,
                                allow_date_outside_lifespan=True)
    return float(result.d)


def _rotate_about_up(v: np.ndarray, deg: float) -> np.ndarray:
    """Rotate an ENU vector clockwise (seen from above) by deg: azimuth increases by deg."""
    d = math.radians(deg)
    e, n, up = v
    return np.array([e * math.cos(d) + n * math.sin(d), -e * math.sin(d) + n * math.cos(d), up])


def _enu_to_altaz(v: np.ndarray) -> tuple[float, float]:
    v = v / np.linalg.norm(v)
    alt = math.degrees(math.asin(max(-1.0, min(1.0, v[2]))))
    az = math.degrees(math.atan2(v[0], v[1])) % 360.0
    return alt, az


def device_vectors(rotation_matrix: np.ndarray, image_rotation_deg: int = 0):
    """World-frame camera direction and image-up direction."""
    r = math.radians(image_rotation_deg)
    up_device = np.array([math.sin(r), math.cos(r), 0.0])
    view = rotation_matrix @ np.array([0.0, 0.0, -1.0])
    up = rotation_matrix @ up_device
    return view, up


def pointing_from_matrix(rotation_matrix: np.ndarray, lat: float, lon: float, alt_m: float,
                         when: datetime, reference: str = "true_north",
                         image_rotation_deg: int = 0) -> Pointing:
    view, up = device_vectors(rotation_matrix, image_rotation_deg)
    declination = 0.0
    if reference == "magnetic_north":
        declination = magnetic_declination(lat, lon, alt_m, when)
        view, up = _rotate_about_up(view, declination), _rotate_about_up(up, declination)

    up_point = view + UP_OFFSET_RAD * up  # a sky point slightly "above" the image centre
    (alt0, az0), (alt1, az1) = _enu_to_altaz(view), _enu_to_altaz(up_point)

    frame = AltAz(obstime=Time(when), location=EarthLocation(lat=lat * u.deg, lon=lon * u.deg,
                                                             height=alt_m * u.m))
    sky = SkyCoord(az=[az0, az1] * u.deg, alt=[alt0, alt1] * u.deg, frame=frame).icrs
    ra, dec = float(sky.ra.deg[0]), float(sky.dec.deg[0])
    rotation = position_angle(ra, dec, float(sky.ra.deg[1]), float(sky.dec.deg[1]))
    return Pointing(ra=ra % 360.0, dec=dec, rotation=rotation, alt=alt0, az=az0,
                    declination_applied=declination)
