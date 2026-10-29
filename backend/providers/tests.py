from unittest.mock import patch

import httpx
from django.test import SimpleTestCase, override_settings

from config.http import ExternalServiceError, http_get

from .base import ProviderError
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


class Hips2FitsTests(SimpleTestCase):
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
            get_provider("dss2_color").fetch_cutout(0, 0, 1, 0, 100, 100)

    @patch("providers.hips2fits.http_get", side_effect=ExternalServiceError("down"))
    def test_service_down_raises_provider_error(self, _):
        with self.assertRaises(ProviderError):
            get_provider("dss2_color").fetch_cutout(0, 0, 1, 0, 100, 100)


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
