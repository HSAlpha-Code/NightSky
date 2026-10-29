import io
from pathlib import Path
from unittest import skipUnless

import numpy as np
from django.conf import settings
from django.test import SimpleTestCase
from PIL import Image

from .plate_solver import SolveHint, Tetra3Solver, angular_distance, load_image

SAMPLE = Path(settings.BASE_DIR) / "samples" / "tetra3_alt40.tiff"
# Reference solution for tetra3's example image examples/data/2019-07-29T204726_Alt40_Azi-135_Try1.tiff
SAMPLE_RA, SAMPLE_DEC = 230.668, 11.035


class LoadImageTests(SimpleTestCase):
    def test_downscales_long_side(self):
        buf = io.BytesIO()
        Image.new("RGB", (4000, 3000)).save(buf, "JPEG")
        img = load_image(buf.getvalue())
        self.assertEqual(img.size, (1600, 1200))
        self.assertEqual(img.mode, "L")

    def test_keeps_16bit_dynamic_range(self):
        buf = io.BytesIO()
        Image.fromarray(np.full((10, 10), 30000, dtype=np.uint16)).save(buf, "TIFF")
        self.assertEqual(np.asarray(load_image(buf.getvalue())).max(), 30000)

    def test_angular_distance(self):
        self.assertAlmostEqual(angular_distance(0, 0, 90, 0), 90.0, places=6)
        self.assertAlmostEqual(angular_distance(10, 89, 190, 89), 2.0, places=6)


@skipUnless(SAMPLE.exists(), "samples/tetra3_alt40.tiff not downloaded (see README)")
class Tetra3SampleTests(SimpleTestCase):
    def test_solves_sample_image(self):
        result = Tetra3Solver().solve(SAMPLE.read_bytes(), SolveHint(fov=11.0))
        self.assertIsNotNone(result)
        self.assertLess(angular_distance(result.ra, result.dec, SAMPLE_RA, SAMPLE_DEC), 1.0)
        self.assertAlmostEqual(result.fov, 11.4, delta=0.5)
        self.assertGreater(result.confidence, 0.9)

    def test_rejects_solution_far_from_sensor_guess(self):
        far = SolveHint(ra=(SAMPLE_RA + 180) % 360, dec=-SAMPLE_DEC, fov=11.0)
        self.assertIsNone(Tetra3Solver().solve(SAMPLE.read_bytes(), far))

    def test_blank_image_returns_none(self):
        buf = io.BytesIO()
        Image.new("L", (800, 600)).save(buf, "PNG")
        self.assertIsNone(Tetra3Solver().solve(buf.getvalue()))
