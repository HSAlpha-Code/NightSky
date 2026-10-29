import io
import json
from pathlib import Path
from unittest import skipUnless
from unittest.mock import patch

import numpy as np
from django.conf import settings
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import SimpleTestCase
from PIL import Image
from rest_framework.test import APIClient

from .plate_solver import SolveResult, angular_distance

SAMPLE = Path(settings.BASE_DIR) / "samples" / "tetra3_alt40.tiff"


def jpeg_upload(name="sky.jpg"):
    buf = io.BytesIO()
    Image.new("L", (400, 300)).save(buf, "JPEG")
    return SimpleUploadedFile(name, buf.getvalue(), content_type="image/jpeg")


def metadata(**overrides):
    # Phone screen-down (camera at zenith), top of the phone north, true-north frame.
    m = {"latitude": 51.4769, "longitude": 0.0, "altitude": 10, "timestamp": "1987-04-10T00:00:00Z",
         "orientation": {"rotation_matrix": [-1, 0, 0, 0, 1, 0, 0, 0, -1], "reference": "true_north"},
         "fov_deg": 65}
    m.update(overrides)
    return m


class SolveEndpointTests(SimpleTestCase):
    def setUp(self):
        self.client = APIClient()

    def post(self, meta, image=None):
        return self.client.post("/api/solve", {"image": image or jpeg_upload(),
                                               "metadata": json.dumps(meta)}, format="multipart")

    @patch("solver.services.get_solver")
    def test_plate_solve_success(self, get_solver):
        get_solver.return_value.solve.return_value = SolveResult(197.5, 51.5, 12.0, 64.0, 0.99)
        resp = self.post(metadata())
        self.assertEqual(resp.status_code, 200)
        body = resp.json()
        self.assertFalse(body["approximate"])
        self.assertEqual(body["source"], "plate_solve")
        self.assertEqual((body["ra"], body["rotation"], body["fov"]), (197.5, 12.0, 64.0))
        hint = get_solver.return_value.solve.call_args.args[1]
        self.assertEqual(hint.fov, 65)
        self.assertLess(angular_distance(hint.ra, hint.dec, 197.5, 51.5), 1.0)  # sensor guess passed

    @patch("solver.services.get_solver")
    def test_sensor_fallback_is_approximate(self, get_solver):
        get_solver.return_value.solve.return_value = None
        resp = self.post(metadata())
        self.assertEqual(resp.status_code, 200)
        body = resp.json()
        self.assertTrue(body["approximate"])
        self.assertEqual(body["source"], "sensors")
        self.assertEqual(body["confidence"], 0.0)
        self.assertEqual(body["fov"], 65)
        self.assertAlmostEqual(body["alt"], 90.0, places=4)
        # Zenith at Greenwich, 1987-04-10 0h UT: RA ~ sidereal time (197.7), Dec ~ latitude.
        self.assertLess(angular_distance(body["ra"], body["dec"], 197.5, 51.4), 0.5)
        self.assertTrue(body["message"])

    @patch("solver.services.get_solver")
    def test_no_solution_and_no_sensors_is_solve_failed(self, get_solver):
        get_solver.return_value.solve.return_value = None
        resp = self.post({})
        self.assertEqual(resp.status_code, 422)
        self.assertEqual(resp.json()["error"]["code"], "SOLVE_FAILED")

    @patch("solver.services.get_solver")
    def test_below_horizon_is_solve_failed(self, get_solver):
        get_solver.return_value.solve.return_value = None
        # Phone screen-up: rear camera points at the ground.
        resp = self.post(metadata(orientation={"quaternion": {"x": 0, "y": 0, "z": 0, "w": 1},
                                               "reference": "true_north"}))
        self.assertEqual(resp.status_code, 422)
        self.assertIn("horizon", resp.json()["error"]["message"])

    def test_invalid_metadata(self):
        resp = self.post(metadata(latitude=123))
        self.assertEqual(resp.status_code, 400)
        self.assertEqual(resp.json()["error"]["code"], "INVALID_REQUEST")

    def test_not_an_image(self):
        bad = SimpleUploadedFile("x.jpg", b"not an image", content_type="image/jpeg")
        resp = self.post(metadata(), image=bad)
        self.assertEqual(resp.status_code, 400)

    def test_missing_image(self):
        resp = self.client.post("/api/solve", {"metadata": "{}"}, format="multipart")
        self.assertEqual(resp.status_code, 400)

    @skipUnless(SAMPLE.exists(), "sample image not downloaded")
    def test_real_tetra3_solve_without_sensors(self):
        img = SimpleUploadedFile("s.tiff", SAMPLE.read_bytes(), content_type="image/tiff")
        resp = self.post({"fov_deg": 11}, image=img)
        self.assertEqual(resp.status_code, 200)
        body = resp.json()
        self.assertFalse(body["approximate"])
        self.assertLess(angular_distance(body["ra"], body["dec"], 230.668, 11.035), 0.5)


class Tetra3RotationTests(SimpleTestCase):
    """SkyView renders with a known rotation; tetra3 must recover it (sign convention check)."""

    @skipUnless(SAMPLE.exists(), "sample image not downloaded")
    def test_rotated_sample_recovers_rotation(self):
        from .plate_solver import SolveHint, Tetra3Solver
        base = Tetra3Solver().solve(SAMPLE.read_bytes(), SolveHint(fov=11))
        img = Image.open(io.BytesIO(SAMPLE.read_bytes()))
        arr = np.asarray(img).astype(np.float32)
        # Rotate the picture 90 deg counter-clockwise: what was "right" is now "up".
        rotated = Image.fromarray(np.rot90(arr).copy(), mode="F")
        buf = io.BytesIO()
        rotated.save(buf, "TIFF")
        rot = Tetra3Solver().solve(buf.getvalue(), SolveHint(fov=8.5))
        self.assertIsNotNone(rot)
        # The old image-right is PA(up) - 90 (east is left in a non-mirrored sky image).
        expected = (base.rotation - 90) % 360
        self.assertLess(abs((rot.rotation - expected + 180) % 360 - 180), 1.0)
