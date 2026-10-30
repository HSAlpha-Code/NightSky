from unittest.mock import patch

from django.core.cache import cache
from django.test import SimpleTestCase
from rest_framework.test import APIClient

from .base import ProviderError
from .hips2fits import Hips2FitsProvider
from .skyview import SkyViewProvider

JPEG = b"\xff\xd8fake-jpeg"


class ApiTestCase(SimpleTestCase):
    def setUp(self):
        cache.clear()
        self.client = APIClient()


class ProvidersEndpointTests(ApiTestCase):
    def test_lists_providers_with_metadata(self):
        resp = self.client.get("/api/providers")
        self.assertEqual(resp.status_code, 200)
        body = resp.json()
        self.assertEqual(body["default"], "dss2_color")
        keys = {p["key"] for p in body["providers"]}
        self.assertTrue({"dss2_color", "skyview_mellinger", "panstarrs"} <= keys)
        for field in ("name", "description", "wavelength", "coverage", "all_sky", "credit"):
            self.assertIn(field, body["providers"][0])


class SkyImageEndpointTests(ApiTestCase):
    body = {"ra": 83.82, "dec": -5.39, "fov": 2.0, "rotation": 10, "width": 300, "height": 400}

    @patch.object(Hips2FitsProvider, "fetch_cutout", return_value=JPEG)
    def test_returns_image_and_headers(self, mock_fetch):
        resp = self.client.post("/api/sky-image", self.body, format="json")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp["Content-Type"], "image/jpeg")
        self.assertEqual(resp.content, JPEG)
        self.assertEqual(resp["X-Provider"], "dss2_color")
        self.assertEqual(resp["X-Fallback-Used"], "false")
        mock_fetch.assert_called_once_with(83.82, -5.39, 2.0, 10.0, 300, 400)

    @patch.object(Hips2FitsProvider, "fetch_cutout", return_value=JPEG)
    def test_cached_second_request(self, mock_fetch):
        self.client.post("/api/sky-image", self.body, format="json")
        self.client.post("/api/sky-image", {**self.body, "ra": 83.8201}, format="json")
        self.assertEqual(mock_fetch.call_count, 1)  # rounded key -> cache hit

    @patch.object(SkyViewProvider, "fetch_cutout", side_effect=AssertionError("not expected"))
    @patch.object(Hips2FitsProvider, "fetch_cutout", return_value=JPEG)
    def test_no_coverage_falls_back(self, *_):
        resp = self.client.post("/api/sky-image",
                                {**self.body, "dec": -60, "provider": "panstarrs_hips"}, format="json")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp["X-Fallback-Used"], "true")
        self.assertEqual(resp["X-Fallback-Reason"], "NO_COVERAGE")
        self.assertEqual(resp["X-Provider"], "dss2_color")

    @patch.object(SkyViewProvider, "fetch_cutout", return_value=JPEG)
    @patch.object(Hips2FitsProvider, "fetch_cutout", side_effect=ProviderError("down"))
    def test_service_down_falls_back_to_other_service(self, hips, skyview):
        resp = self.client.post("/api/sky-image", self.body, format="json")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp["X-Fallback-Reason"], "PROVIDER_UNAVAILABLE")
        self.assertEqual(resp["X-Provider"], "skyview_mellinger")
        self.assertEqual(hips.call_count, 1)  # other hips2fits surveys skipped: service marked down

    @patch.object(SkyViewProvider, "fetch_cutout", side_effect=ProviderError("down"))
    @patch.object(Hips2FitsProvider, "fetch_cutout", side_effect=ProviderError("down"))
    def test_everything_down_returns_503(self, *_):
        resp = self.client.post("/api/sky-image", self.body, format="json")
        self.assertEqual(resp.status_code, 503)
        self.assertEqual(resp.json()["error"]["code"], "PROVIDER_UNAVAILABLE")

    def test_validation_error(self):
        resp = self.client.post("/api/sky-image", {"ra": 1, "dec": 95, "fov": 1}, format="json")
        self.assertEqual(resp.status_code, 400)
        self.assertEqual(resp.json()["error"]["code"], "INVALID_REQUEST")

    def test_unknown_provider(self):
        resp = self.client.post("/api/sky-image", {**self.body, "provider": "nope"}, format="json")
        self.assertEqual(resp.status_code, 400)


class SkyViewBusyTests(SimpleTestCase):
    BUSY = "<html><head><title>Too Many Processes</title></head><body>Sorry</body></html>"

    def _resp(self, text, ctype="text/html", content=b""):
        r = type("R", (), {})()
        r.text, r.headers, r.content = text, {"content-type": ctype}, content
        return r

    @patch("providers.skyview.time.sleep")
    @patch("providers.skyview.http_get")
    def test_retries_when_busy_then_succeeds(self, mock_get, _sleep):
        mock_get.side_effect = [self._resp(self.BUSY), self._resp("skv123"),
                                self._resp("", "image/jpeg", JPEG)]
        p = SkyViewProvider("t", ["A", "B", "C"], "t", "", "optical")
        self.assertEqual(p.fetch_cutout(10, 20, 2.0, 0, 400, 300), JPEG)
        self.assertEqual(mock_get.call_count, 3)

    @patch("providers.skyview.time.sleep")
    @patch("providers.skyview.http_get")
    def test_gives_up_with_short_message(self, mock_get, _sleep):
        mock_get.return_value = self._resp(self.BUSY)
        p = SkyViewProvider("t", ["A", "B", "C"], "t", "", "optical")
        with self.assertRaises(ProviderError) as ctx:
            p.fetch_cutout(10, 20, 2.0, 0, 400, 300)
        self.assertNotIn("<", str(ctx.exception))


class SkyViewParamTests(SimpleTestCase):
    @patch("providers.skyview.http_get")
    def test_rotation_is_negated_and_size_follows_aspect(self, mock_get):
        mock_get.return_value.headers = {"content-type": "image/jpeg"}
        mock_get.return_value.content = JPEG
        SkyViewProvider("t", ["DSS2 Red"], "t", "", "optical").fetch_cutout(10, 20, 2.0, 30, 400, 300)
        params = mock_get.call_args.kwargs["params"]
        self.assertEqual(params["Rotation"], "-30.000")
        self.assertEqual(params["Size"], "2.000000,1.500000")
        self.assertEqual(params["Return"], "JPEG")
