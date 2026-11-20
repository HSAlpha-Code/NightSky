import io
import json
from pathlib import Path

from django.conf import settings
from django.test import SimpleTestCase
from rest_framework.test import APIClient
from PIL import Image
import numpy as np

from providers.nasa_starmap import NasaStarMapProvider
from providers.registry import get_provider


class PanoramaTests(SimpleTestCase):
    def test_manifest_and_tiles_have_matching_dimensions_and_hashes(self):
        import hashlib
        for resolution in ("16k", "32k"):
            root = settings.BASE_DIR / "panorama_packs" / resolution
            manifest = json.loads((root / "manifest.json").read_text())
            self.assertEqual(len(manifest["tiles"]), manifest["width"] * manifest["height"] // 2048 ** 2)
            for tile in manifest["tiles"]:
                path = root / tile["file"]
                self.assertEqual(path.stat().st_size, tile["bytes"])
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), tile["sha256"])
                self.assertEqual(path.read_bytes()[12:16], b"VP8L", "Expected lossless WebP bitstream")
                with Image.open(path) as image:
                    self.assertEqual(image.size, (2050, 2050))

    def test_serves_manifest_and_rejects_unknown_paths(self):
        response = self.client.get('/api/panorama/nasa2020-v1/16k/manifest.json')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(json.loads(b''.join(response.streaming_content))["width"], 16384)
        self.assertEqual(self.client.get('/api/panorama/nasa2020-v1/64k/manifest.json').status_code, 404)
        self.assertEqual(self.client.get('/api/panorama/nasa2020-v1/16k/private.txt').status_code, 404)

    def test_lossless_tile_gutters_match_neighbors_and_wrapped_seam(self):
        for resolution, columns in (("16k", 8), ("32k", 16)):
            root = settings.BASE_DIR / "panorama_packs" / resolution
            def pixels(name):
                with Image.open(root / name) as image:
                    return np.asarray(image.convert("RGB"))
            left, right = pixels('0_0.webp'), pixels('1_0.webp')
            last, below = pixels(f'{columns - 1}_0.webp'), pixels('0_1.webp')
            np.testing.assert_array_equal(left[:, -1], right[:, 1])
            np.testing.assert_array_equal(left[:, -2], right[:, 0])
            np.testing.assert_array_equal(last[:, -1], left[:, 1])
            np.testing.assert_array_equal(last[:, -2], left[:, 0])
            np.testing.assert_array_equal(left[-1], below[1])
            np.testing.assert_array_equal(left[-2], below[0])

    def test_old_mellinger_key_uses_nasa_without_skyview(self):
        self.assertIsInstance(get_provider('skyview_mellinger'), NasaStarMapProvider)
        data = get_provider('skyview_mellinger').fetch_cutout(101.287, -16.716, 10, 30, 100, 80)
        with Image.open(io.BytesIO(data)) as image:
            self.assertEqual(image.size, (100, 80))
            self.assertEqual(image.format, "PNG")

    def test_api_delivers_lossless_nasa_cutout_with_correct_headers(self):
        response = APIClient().post('/api/sky-image', {
            'ra': 101.287, 'dec': -16.716, 'fov': 10, 'rotation': 0,
            'width': 100, 'height': 80, 'provider': 'skyview_mellinger',
        }, format='json')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response['X-Provider'], 'nasa_starmap_2020')
        self.assertEqual(response['Content-Type'], 'image/png')
        self.assertIn('ESA/Gaia/DPAC', response['X-Credit'])
        self.assertTrue(response.content.startswith(b'\x89PNG\r\n\x1a\n'))
