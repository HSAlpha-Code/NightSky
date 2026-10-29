from unittest.mock import patch

import httpx
import numpy as np
from django.core.cache import cache
from django.test import SimpleTestCase, override_settings

from config.http import ExternalServiceError, http_get

from . import hips_render
from .base import ProviderError
from .hips2fits import Hips2FitsProvider
from .panstarrs import pick_channels
from .registry import fallback_candidates, fallback_provider, get_provider


def _resp(status=200, content=b"\xff\xd8jpeg", ctype="image/jpeg"):
    return httpx.Response(status, content=content, headers={"content-type": ctype},
                          request=httpx.Request("GET", "https://example.test"))


class RegistryTests(SimpleTestCase):
    def test_default_provider(self):
        self.assertEqual(get_provider(None).key, "dss2_color")

    def test_panstarrs_partial_coverage_and_fallback(self):
        ps = get_provider("panstarrs_hips")
        self.assertTrue(ps.supports(10, 20))
        self.assertFalse(ps.supports(10, -60))
        fb = fallback_provider(10, -60, exclude=ps)
        self.assertTrue(fb.all_sky)
        self.assertEqual(fb.key, "dss2_color")

    def test_fallback_prefers_other_service_after_failure(self):
        dss = get_provider("dss2_color")
        candidates = fallback_candidates(10, 20, 2.0, exclude=dss, service_failed=True)
        self.assertNotEqual(candidates[0].service, "hips2fits")
        self.assertNotIn(dss, candidates)
        # Without a service failure the normal order (same service first) is kept.
        self.assertEqual(fallback_candidates(10, 20, 2.0, exclude=dss)[0].service, "hips2fits")

    def test_panstarrs_cutout_only_for_small_fields(self):
        ps = get_provider("panstarrs")
        self.assertTrue(ps.supports(10, 20, 0.2))
        self.assertFalse(ps.supports(10, 20, 5.0))
        self.assertFalse(ps.supports(10, -40, 0.2))


def _cds_only():
    """hips2fits provider without a mirror, so CDS failures surface as ProviderError."""
    return Hips2FitsProvider("cds_only", "CDS/P/DSS2/color", "CDS only", "", "optical")


class Hips2FitsTests(SimpleTestCase):
    def setUp(self):
        cache.clear()  # don't inherit a "CDS down" flag from other tests

    @patch("providers.hips2fits.http_get", return_value=_resp())
    def test_fetch_cutout_params(self, mock_get):
        data = get_provider("dss2_color").fetch_cutout(83.82, -5.39, 2.0, 15.0, 600, 400)
        self.assertEqual(data, b"\xff\xd8jpeg")
        params = mock_get.call_args.kwargs["params"]
        self.assertEqual(params["hips"], "CDS/P/DSS2/color")
        self.assertEqual((params["width"], params["height"]), (600, 400))
        self.assertEqual(params["rotation_angle"], "15.000")
        self.assertEqual(params["projection"], "TAN")

    @patch("providers.hips2fits.http_get", return_value=_resp(content=b"error", ctype="text/plain"))
    def test_non_image_response_raises(self, _):
        with self.assertRaises(ProviderError):
            _cds_only().fetch_cutout(0, 0, 1, 0, 100, 100)

    @patch("providers.hips2fits.http_get", side_effect=ExternalServiceError("down"))
    def test_service_down_raises_provider_error(self, _):
        with self.assertRaises(ProviderError):
            _cds_only().fetch_cutout(0, 0, 1, 0, 100, 100)


class MirrorFallbackTests(SimpleTestCase):
    def setUp(self):
        cache.clear()

    @patch("providers.hips2fits.hips_render.render", return_value=b"\xff\xd8mirror")
    @patch("providers.hips2fits.http_get", side_effect=ExternalServiceError("timed out"))
    def test_unreachable_cds_renders_from_mirror(self, mock_get, mock_render):
        dss = get_provider("dss2_color")
        self.assertEqual(dss.fetch_cutout(83.82, -5.39, 2.0, 0, 300, 400), b"\xff\xd8mirror")
        self.assertEqual(mock_get.call_args.kwargs["retries"], 0)  # no retries on a dead CDS
        self.assertTrue(mock_render.call_args.args[0].endswith("/DSSColor"))
        # CDS is now marked down: the next request goes straight to the mirror.
        get_provider("2mass_color").fetch_cutout(83.82, -5.39, 2.0, 0, 300, 400)
        self.assertEqual(mock_get.call_count, 1)

    @patch("providers.hips2fits.http_get", side_effect=ExternalServiceError("timed out"))
    def test_cds_down_fails_fast_for_providers_without_mirror(self, mock_get):
        cache.set("hips2fits_cds_down", True)
        with self.assertRaises(ProviderError):
            get_provider("panstarrs_hips").fetch_cutout(200, 40, 2.0, 0, 300, 400)
        mock_get.assert_not_called()

    @patch("providers.hips2fits.hips_render.render",
           side_effect=hips_render.HipsRenderError("mirror down"))
    @patch("providers.hips2fits.http_get", side_effect=ExternalServiceError("timed out"))
    def test_both_down_raises_provider_error(self, *_):
        with self.assertRaises(ProviderError):
            get_provider("dss2_color").fetch_cutout(0, 0, 1, 0, 100, 100)


class DownFlagTests(SimpleTestCase):
    def setUp(self):
        cache.clear()

    @patch("providers.skyview.SkyViewProvider.fetch_cutout", return_value=b"\xff\xd8skyview")
    @patch("providers.hips2fits.hips_render.render", return_value=b"\xff\xd8mirror")
    @patch("providers.hips2fits.http_get", side_effect=ExternalServiceError("timed out"))
    def test_failed_provider_without_mirror_does_not_block_mirrored_siblings(self, *_):
        from .services import get_sky_image
        # Pan-STARRS HiPS has no mirror: it fails and falls back...
        r = get_sky_image(200, 40, 2.0, 0, "panstarrs_hips", 100, 100)
        self.assertTrue(r.fallback_used)
        # ...but DSS2 (rendered from the ESA mirror) must still be served as DSS2.
        r = get_sky_image(200, 40, 2.0, 0, "dss2_color", 100, 100)
        self.assertFalse(r.fallback_used)
        self.assertEqual((r.provider.key, r.data), ("dss2_color", b"\xff\xd8mirror"))


class HipsRenderTests(SimpleTestCase):
    def test_wcs_north_up_east_left(self):
        w = hips_render.output_wcs(100.0, 20.0, 2.0, 0.0, 200, 100)
        (x_n, y_n), (x_e, y_e) = w.wcs_world2pix([[100.0, 20.5], [100.5, 20.0]], 0)
        self.assertAlmostEqual(float(x_n), 99.5, places=1)  # north is straight up
        self.assertGreater(float(y_n), 49.5)
        self.assertLess(float(x_e), 99.5)                    # east is to the left

    def test_wcs_rotation_puts_east_up_at_pa_90(self):
        w = hips_render.output_wcs(100.0, 20.0, 2.0, 90.0, 200, 200)
        x_e, y_e = w.wcs_world2pix([[100.5, 20.0]], 0)[0]
        self.assertAlmostEqual(float(x_e), 99.5, places=0)
        self.assertGreater(float(y_e), 99.5)

    def test_choose_order_matches_output_resolution(self):
        self.assertEqual(hips_render.choose_order(60.0, 1200, 9), 2)   # wide phone field
        self.assertEqual(hips_render.choose_order(0.1, 1200, 9), 9)    # capped at max order

    def test_tile_rows_cols_deinterleaves_bits(self):
        sub = np.array([0b00, 0b01, 0b10, 0b11, 0b0101])
        rows, cols = hips_render.tile_rows_cols(sub)
        self.assertEqual(rows.tolist(), [0, 1, 0, 1, 3])
        self.assertEqual(cols.tolist(), [0, 0, 1, 1, 0])


class PanStarrsChannelTests(SimpleTestCase):
    def test_prefers_irg_and_falls_back_when_a_filter_is_missing(self):
        full = {f: f"{f}.fits" for f in "grizy"}
        self.assertEqual(pick_channels(full), {"red": "i.fits", "green": "r.fits", "blue": "g.fits"})
        no_r = {f: f"{f}.fits" for f in "gizy"}                 # what PS1 has at M42
        # Available red->blue: y z i g -> reddest y, middle (index 2) i, bluest g.
        self.assertEqual(pick_channels(no_r), {"red": "y.fits", "green": "i.fits", "blue": "g.fits"})
        self.assertEqual(pick_channels({"z": "z.fits"}), {"red": "z.fits"})
        self.assertEqual(pick_channels({}), {})


@override_settings(HTTP_RETRIES=2)
class HttpRetryTests(SimpleTestCase):
    @patch("config.http.time.sleep")
    @patch("config.http.httpx.get", side_effect=[_resp(503), _resp(503), _resp()])
    def test_retries_then_succeeds(self, mock_get, _sleep):
        self.assertEqual(http_get("https://example.test").status_code, 200)
        self.assertEqual(mock_get.call_count, 3)

    @patch("config.http.time.sleep")
    @patch("config.http.httpx.get", side_effect=httpx.ConnectTimeout("t"))
    def test_gives_up_after_retries(self, mock_get, _sleep):
        with self.assertRaises(ExternalServiceError):
            http_get("https://example.test")
        self.assertEqual(mock_get.call_count, 3)

    @patch("config.http.httpx.get", return_value=_resp(404))
    def test_4xx_not_retried(self, mock_get):
        with self.assertRaises(ExternalServiceError):
            http_get("https://example.test")
        self.assertEqual(mock_get.call_count, 1)
