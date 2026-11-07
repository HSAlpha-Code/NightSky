import json
import tempfile
from pathlib import Path

from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from .models import CuratedHighlight


def make(body_id="NGC1976", name="Orion Nebula", **kw):
    kw.setdefault("image_file", f"{body_id}-1.jpg")
    return CuratedHighlight.objects.create(body_id=body_id, body_name=name, **kw)


class CuratedApiTests(TestCase):
    def setUp(self):
        self.media = tempfile.TemporaryDirectory()
        self.addCleanup(self.media.cleanup)
        override = override_settings(CURATED_SOURCE="db", CURATED_MEDIA_ROOT=Path(self.media.name))
        override.enable()
        self.addCleanup(override.disable)
        self.client = APIClient()

    def test_empty_index(self):
        r = self.client.get("/api/curated/index/")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()["bodies"], [])
        self.assertIn("ETag", r)
        self.assertIn("max-age", r["Cache-Control"])

    def test_index_lists_only_bodies_with_enabled_highlights(self):
        make(sort_order=1)
        make(image_file="b.jpg", sort_order=0)
        make("M31", "Andromeda Galaxy", enabled=False)
        make("HIP1", "Star", enabled=True)
        data = self.client.get("/api/curated/index/").json()
        self.assertEqual([(b["body_id"], b["count"]) for b in data["bodies"]],
                         [("HIP1", 1), ("NGC1976", 2)])
        self.assertEqual(set(data["bodies"][0]), {"body_id", "body_name", "count"})
        self.assertTrue(data["version"])

    def test_index_without_trailing_slash(self):
        self.assertEqual(self.client.get("/api/curated/index").status_code, 200)

    def test_etag_304_and_change(self):
        h = make()
        first = self.client.get("/api/curated/index/")
        etag = first["ETag"]
        again = self.client.get("/api/curated/index/", HTTP_IF_NONE_MATCH=etag)
        self.assertEqual(again.status_code, 304)
        self.assertEqual(again["ETag"], etag)
        weak = self.client.get("/api/curated/index/", HTTP_IF_NONE_MATCH=f'W/{etag}, "other"')
        self.assertEqual(weak.status_code, 304)
        h.caption = "changed"
        h.save()
        changed = self.client.get("/api/curated/index/", HTTP_IF_NONE_MATCH=etag)
        self.assertEqual(changed.status_code, 200)
        self.assertNotEqual(changed["ETag"], etag)

    def test_disabling_changes_version(self):
        h = make()
        etag = self.client.get("/api/curated/index/")["ETag"]
        h.enabled = False
        h.save()
        r = self.client.get("/api/curated/index/", HTTP_IF_NONE_MATCH=etag)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()["bodies"], [])

    def test_body_detail(self):
        make(title="Second", image_file="two.jpg", sort_order=2, source_outlet="ESA")
        make(title="First", image_file="one.jpg", sort_order=1, source_outlet="NASA",
             source_url="https://nasa.gov/x", credit="NASA/ESA", caption="Cap", ra=83.8, dec=-5.4)
        make(title="Hidden", image_file="hid.jpg", enabled=False)
        r = self.client.get("/api/curated/NGC1976/")
        self.assertEqual(r.status_code, 200)
        items = r.json()["highlights"]
        self.assertEqual([i["title"] for i in items], ["First", "Second"])
        first = items[0]
        self.assertTrue(first["image_url"].endswith("/api/curated/image/one.jpg"))
        self.assertTrue(first["thumbnail_url"].endswith("/api/curated/image/one_t.jpg"))
        self.assertEqual((first["source_outlet"], first["credit"], first["caption"]),
                         ("NASA", "NASA/ESA", "Cap"))
        self.assertEqual(first["source_url"], "https://nasa.gov/x")
        etag = r["ETag"]
        self.assertEqual(
            self.client.get("/api/curated/NGC1976/", HTTP_IF_NONE_MATCH=etag).status_code, 304)

    def test_body_detail_unknown_or_disabled_is_404(self):
        make("M31", "Andromeda", enabled=False)
        for body in ("M31", "NOPE"):
            r = self.client.get(f"/api/curated/{body}/")
            self.assertEqual(r.status_code, 404)
            self.assertEqual(r.json()["error"]["code"], "NOT_FOUND")

    def test_other_bodies_do_not_change_detail_etag(self):
        make()
        etag = self.client.get("/api/curated/NGC1976/")["ETag"]
        make("M31", "Andromeda")
        self.assertEqual(
            self.client.get("/api/curated/NGC1976/", HTTP_IF_NONE_MATCH=etag).status_code, 304)

    def test_read_only(self):
        make()
        for url in ("/api/curated/index/", "/api/curated/NGC1976/"):
            for method in ("post", "put", "patch", "delete"):
                self.assertEqual(getattr(self.client, method)(url).status_code, 405, (url, method))

    def test_image_served_as_is_with_safe_names(self):
        (Path(self.media.name) / "one.jpg").write_bytes(b"\xff\xd8jpegdata")
        r = self.client.get("/api/curated/image/one.jpg")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(b"".join(r.streaming_content), b"\xff\xd8jpegdata")
        self.assertEqual(r["Content-Type"], "image/jpeg")
        self.assertEqual(self.client.get("/api/curated/image/missing.jpg").status_code, 404)
        self.assertEqual(self.client.get("/api/curated/image/..%2Fsecret.jpg").status_code, 404)
        self.assertEqual(self.client.get("/api/curated/image/notes.txt").status_code, 404)
        etag = r["ETag"]
        self.assertEqual(
            self.client.get("/api/curated/image/one.jpg", HTTP_IF_NONE_MATCH=etag).status_code,
            304)


class CuratedBundleTests(TestCase):
    """Production mode (Vercel): read-only bundle, no database rows."""

    def test_bundle_served_without_database_rows(self):
        with tempfile.TemporaryDirectory() as d:
            bundle = Path(d)
            (bundle / "images").mkdir()
            (bundle / "images" / "a.jpg").write_bytes(b"x")
            rec = {"id": 1, "body_id": "M31", "body_name": "Andromeda", "title": "T",
                   "image_file": "a.jpg", "source_outlet": "NASA", "source_url": "",
                   "credit": "c", "caption": "", "ra": None, "dec": None, "sort_order": 0,
                   "updated_at": "2026-01-01T00:00:00+00:00", "enabled": True}
            off = {**rec, "id": 2, "body_id": "M45", "enabled": False}
            (bundle / "manifest.json").write_text(json.dumps({"highlights": [rec, off]}))
            with override_settings(CURATED_SOURCE="auto", CURATED_BUNDLE_DIR=bundle):
                c = APIClient()
                self.assertEqual([b["body_id"] for b in c.get("/api/curated/index/").json()["bodies"]],
                                 ["M31"])
                self.assertEqual(c.get("/api/curated/M31/").status_code, 200)
                self.assertEqual(c.get("/api/curated/M45/").status_code, 404)
                img = c.get("/api/curated/image/a.jpg")
                img.close()
                self.assertEqual(img.status_code, 200)

    def test_missing_bundle_in_bundle_mode_is_empty(self):
        with override_settings(CURATED_SOURCE="bundle",
                               CURATED_BUNDLE_DIR=Path(tempfile.gettempdir()) / "nope-nightsky"):
            r = APIClient().get("/api/curated/index/")
            self.assertEqual(r.status_code, 200)
            self.assertEqual(r.json()["bodies"], [])


class NoCuratorRoutesInDeployedConfigTests(TestCase):
    def test_no_curator_admin_or_write_routes(self):
        c = APIClient()
        for url in ("/curator/", "/admin/", "/api/highlights", "/api/export", "/api/bodies"):
            self.assertEqual(c.get(url).status_code, 404, url)
        self.assertEqual(c.post("/api/curated/index/").status_code, 405)
