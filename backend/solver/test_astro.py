"""Orientation -> RA/Dec conversion tests against independent reference values
(Jean Meeus, Astronomical Algorithms, 2nd ed.)."""
import math
from datetime import datetime, timezone

import numpy as np
from astropy import units as u
from astropy.coordinates import TETE, SkyCoord
from astropy.time import Time
from django.test import SimpleTestCase
from scipy.spatial.transform import Rotation

from .astro import (SensorError, magnetic_declination, matrix_from_list, pointing_from_matrix,
                    quaternion_to_matrix)
from .plate_solver import angular_distance

# Meeus example 13.b: US Naval Observatory, 1987-04-10 19:21:00 UT.
USNO_LAT = 38 + 55 / 60 + 17 / 3600
USNO_LON = -(77 + 3 / 60 + 56 / 3600)
USNO_TIME = datetime(1987, 4, 10, 19, 21, 0, tzinfo=timezone.utc)
VENUS_ALT = 15.1249
VENUS_AZ = 68.0337 + 180.0          # Meeus measures azimuth from south; we use from north
VENUS_RA = (23 + 9 / 60 + 16.641 / 3600) * 15
VENUS_DEC = -(6 + 43 / 60 + 11.61 / 3600)
# Meeus example 12.b: apparent sidereal time at Greenwich, 1987-04-10 0h UT.
GREENWICH_LAT = 51.4769
GAST_RA = (13 + 10 / 60 + 46.1351 / 3600) * 15
GAST_TIME = datetime(1987, 4, 10, 0, 0, 0, tzinfo=timezone.utc)

TOL_DEG = 0.01  # 36 arcsec


def enu(alt_deg, az_deg):
    alt, az = math.radians(alt_deg), math.radians(az_deg)
    return np.array([math.cos(alt) * math.sin(az), math.cos(alt) * math.cos(az), math.sin(alt)])


def phone_matrix(view, up):
    """Device->world matrix for a phone whose rear camera looks along `view` with the top of
    the (portrait) screen towards `up`."""
    view = view / np.linalg.norm(view)
    y = up - np.dot(up, view) * view
    y /= np.linalg.norm(y)
    z = -view
    x = np.cross(y, z)
    return np.column_stack([x, y, z])


def phone_at(alt_deg, az_deg):
    """Phone in portrait, camera at (alt, az), top of the screen towards the zenith."""
    return phone_matrix(enu(alt_deg, az_deg), enu(alt_deg + 90, az_deg))


def to_tete(ra, dec, when):
    """ICRS -> true equator/equinox of date, the frame of Meeus' apparent coordinates."""
    c = SkyCoord(ra=ra * u.deg, dec=dec * u.deg, frame="icrs").transform_to(TETE(obstime=Time(when)))
    return c.ra.deg, c.dec.deg


class QuaternionTests(SimpleTestCase):
    def test_matches_scipy(self):
        for q in [(0, 0, 0, 1), (0.1, -0.4, 0.3, 0.85), (0.5, 0.5, -0.5, 0.5), (-0.2, 0.7, 0.1, -0.6)]:
            expected = Rotation.from_quat(q).as_matrix()   # scipy is scalar-last (x, y, z, w)
            np.testing.assert_allclose(quaternion_to_matrix(*q), expected, atol=1e-12)

    def test_unnormalised_quaternion_is_normalised(self):
        np.testing.assert_allclose(quaternion_to_matrix(0, 0, 0, 5), np.eye(3), atol=1e-12)

    def test_zero_quaternion_rejected(self):
        with self.assertRaises(SensorError):
            quaternion_to_matrix(0, 0, 0, 0)

    def test_invalid_matrix_rejected(self):
        with self.assertRaises(SensorError):
            matrix_from_list([1, 0, 0, 0, 1, 0, 0, 0, 0])



class PointingReferenceTests(SimpleTestCase):
    def test_meeus_13b_venus_altaz_to_radec(self):
        p = pointing_from_matrix(phone_at(VENUS_ALT, VENUS_AZ), USNO_LAT, USNO_LON, 0.0, USNO_TIME)
        self.assertAlmostEqual(p.alt, VENUS_ALT, places=6)
        self.assertAlmostEqual(p.az, VENUS_AZ, places=6)
        ra, dec = to_tete(p.ra, p.dec, USNO_TIME)
        self.assertLess(angular_distance(ra, dec, VENUS_RA, VENUS_DEC), TOL_DEG)

    def test_meeus_12b_zenith_is_sidereal_time_and_latitude(self):
        # Phone lying screen-down: the rear camera looks straight up.
        m = phone_matrix(np.array([0.0, 0.0, 1.0]), np.array([0.0, 1.0, 0.0]))
        p = pointing_from_matrix(m, GREENWICH_LAT, 0.0, 0.0, GAST_TIME)
        ra, dec = to_tete(p.ra, p.dec, GAST_TIME)
        self.assertLess(angular_distance(ra, dec, GAST_RA, GREENWICH_LAT), TOL_DEG)

    def test_quaternion_input_gives_same_pointing(self):
        m = phone_at(VENUS_ALT, VENUS_AZ)
        x, y, z, w = Rotation.from_matrix(m).as_quat()
        p = pointing_from_matrix(quaternion_to_matrix(x, y, z, w), USNO_LAT, USNO_LON, 0, USNO_TIME)
        ref = pointing_from_matrix(m, USNO_LAT, USNO_LON, 0, USNO_TIME)
        self.assertLess(angular_distance(p.ra, p.dec, ref.ra, ref.dec), 1e-6)

    def test_pointing_at_celestial_pole(self):
        # Camera at alt = latitude, due north -> the north celestial pole (refraction ignored).
        p = pointing_from_matrix(phone_at(GREENWICH_LAT, 0.0), GREENWICH_LAT, 0.0, 0.0,
                                 datetime(2026, 10, 29, 22, 0, tzinfo=timezone.utc))
        self.assertGreater(p.dec, 89.5)  # ICRS pole vs pole of date differ by precession


class RotationTests(SimpleTestCase):
    when = GAST_TIME

    def zenith_with_top(self, top_az, image_rotation_deg=0):
        m = phone_matrix(np.array([0.0, 0.0, 1.0]), enu(0, top_az))
        return pointing_from_matrix(m, GREENWICH_LAT, 0.0, 0.0, self.when,
                                    image_rotation_deg=image_rotation_deg).rotation

    def assertAngle(self, actual, expected, tol=0.5):
        self.assertLess(abs((actual - expected + 180) % 360 - 180), tol, f"{actual} vs {expected}")

    def test_zenith_top_north_is_north_up(self):
        self.assertAngle(self.zenith_with_top(0), 0)

    def test_zenith_top_east_is_east_up(self):
        self.assertAngle(self.zenith_with_top(90), 90)

    def test_landscape_uses_device_x_as_up(self):
        # Screen-down, top of phone north: device +X points west. Landscape (90) -> up = +X.
        self.assertAngle(self.zenith_with_top(0, image_rotation_deg=90), 270)

    def test_meridian_south_upright_is_north_up(self):
        # On the meridian due south, "towards the zenith" is towards the celestial pole.
        p = pointing_from_matrix(phone_at(30, 180), GREENWICH_LAT, 0.0, 0.0, self.when)
        self.assertAlmostEqual(p.az, 180.0, places=6)
        self.assertAngle(p.rotation, 0, tol=0.6)


class MagneticDeclinationTests(SimpleTestCase):
    when = datetime(2026, 10, 29, 4, 0, tzinfo=timezone.utc)

    def test_sign_and_magnitude(self):
        # WMM2025: Seattle ~15 deg E (positive), Sao Paulo ~22 deg W (negative).
        self.assertTrue(14 < magnetic_declination(47.61, -122.33, 0, self.when) < 16.5)
        self.assertTrue(-24 < magnetic_declination(-23.55, -46.63, 0, self.when) < -20)

    def test_magnetic_reference_is_corrected_to_true_north(self):
        lat, lon = 47.61, -122.33
        d = magnetic_declination(lat, lon, 0, self.when)
        true_p = pointing_from_matrix(phone_at(40, 100), lat, lon, 0, self.when, "true_north")
        # A magnetic-north sensor reports azimuths D degrees smaller than the true azimuth.
        mag_p = pointing_from_matrix(phone_at(40, 100 - d), lat, lon, 0, self.when, "magnetic_north")
        self.assertAlmostEqual(mag_p.az, true_p.az, places=6)
        self.assertLess(angular_distance(mag_p.ra, mag_p.dec, true_p.ra, true_p.dec), 1e-5)
        self.assertAlmostEqual(mag_p.declination_applied, d)
