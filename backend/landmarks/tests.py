import base64
from unittest.mock import patch

from django.core.cache import cache
from django.test import SimpleTestCase, override_settings
from rest_framework.test import APIClient

from config.http import ExternalServiceError

import numpy as np

from . import catalog as catalog_mod
from . import mast, mosaic, services, tone
from .catalog import Catalog, load_from_texts, priority
from .parsing import (merge_stars, parse_iau_stars, parse_openngc, parse_wgsn_csv, pretty_code,
                      wgsn_html_to_csv)

NGC_HEADER = ("Name;Type;RA;Dec;Const;MajAx;MinAx;PosAng;B-Mag;V-Mag;J-Mag;H-Mag;K-Mag;SurfBr;"
              "Hubble;Pax;Pm-RA;Pm-Dec;RadVel;Redshift;Cstar U-Mag;Cstar B-Mag;Cstar V-Mag;M;NGC;"
              "IC;Cstar Names;Identifiers;Common names;NED notes;OpenNGC notes;Sources")
NGC_ROWS = [
    "NGC1976;Cl+N;05:35:16.48;-05:23:22.8;Ori;90.00;60.00;;4.00;4.00;;;;;;;1.670;-0.300;28;"
    "0.000093;;;;042;;;;LBN 974;Great Orion Nebula,Orion Nebula;;;",
    "NGC2068;RfN;05:46:45.82;+00:04:45.5;Ori;4.50;;;8.00;8.00;;;;;;;;;63;;;;;078;;;;;;;;",
    "NGC1977;Neb;05:35:16.0;-04:49:00;Ori;20.0;;;7.00;;;;;;;;;;;;;;;;;;;;the Running Man Nebula;;;",
    "NGC1999;RfN;05:36:25.3;-06:42:57;Ori;2.0;;;;9.5;;;;;;;;;;;;;;;;;;;;;;",
    "NGC9999;G;05:35:00.0;-05:00:00;Ori;0.5;;;;15.5;;;;;;;;;;;;;;;;;;;;;;",   # too faint
    "NGC1982;Dup;05:35:31.0;-05:16:03;Ori;;;;;;;;;;;;;;;;;;;043;;;;;;;;",       # duplicate entry
    "NGC0224;G;00:42:44.35;+41:16:08.6;And;177.83;69.66;35;4.29;3.44;;;;;Sb;;;;-300;-0.001;;;;"
    "031;;;;;Andromeda Galaxy;;;",
    "Mel022;OCl;03:47:28.6;+24:06:19;Tau;150.00;150.00;90;;1.20;;;;;;7.3640;19.997;-45.548;6;"
    "0.000020;;;;045;;;;MWSC 0305;Pleiades;;;",
]
STARS = """#Name/ASCII       Name/Diacritics   Designation  ID    ID    Con #    WDS_J       mag  bnd  HIP     HD  RA(J2000)  Dec(J2000) Date       Notes
Betelgeuse        Betelgeuse        HR 2061      alf   α     Ori Aa   05552+0724  0.45  V  27989  39801  88.792939   7.407064 2016-06-30
Alnilam           Alnilam           HR 1903      eps   ε     Ori _    _           1.69  V  26311  37128  84.053389  -1.201919 2016-07-20
Absolutno         Absolutno         XO-5         _     _     Lyn _    _          11.95  G      _      _ 116.716506  39.094572 2019-12-17
"""


def small_catalog() -> Catalog:
    return load_from_texts("\n".join([NGC_HEADER, *NGC_ROWS]), NGC_HEADER, STARS)


class ParsingTests(SimpleTestCase):
    def test_openngc_rows(self):
        objs = {o.id: o for o in parse_openngc("\n".join([NGC_HEADER, *NGC_ROWS]))}
        self.assertNotIn("NGC1982", objs)                       # "Dup" rows are skipped
        m42 = objs["NGC1976"]
        self.assertEqual((m42.name, m42.messier, m42.type_label),
                         ("Great Orion Nebula", 42, "Star cluster with nebula"))
        self.assertAlmostEqual(m42.ra, 83.8187, places=3)
        self.assertAlmostEqual(m42.dec, -5.3897, places=3)
        self.assertIn("M42", m42.aliases)
        self.assertIsNone(m42.distance_ly)                      # OpenNGC has no parallax for it
        self.assertEqual(objs["Mel022"].distance_ly, 440.0)     # Pleiades: 7.364 mas parallax
        self.assertEqual(objs["NGC2068"].name, "M78")           # no common name -> Messier
        self.assertEqual(objs["NGC1977"].name, "The Running Man Nebula")
        self.assertEqual(objs["NGC1999"].name, "NGC 1999")

    def test_iau_star_names(self):
        stars = {s.name: s for s in parse_iau_stars(STARS)}
        self.assertEqual(set(stars), {"Betelgeuse", "Alnilam", "Absolutno"})
        self.assertEqual(stars["Betelgeuse"].id, "HIP27989")
        self.assertEqual(stars["Betelgeuse"].constellation, "Ori")
        self.assertAlmostEqual(stars["Betelgeuse"].magnitude, 0.45)
        self.assertTrue(stars["Absolutno"].id.startswith("STAR-"))  # no HIP number

    def test_pretty_code(self):
        self.assertEqual(pretty_code("NGC0224"), "NGC 224")
        self.assertEqual(pretty_code("IC0434"), "IC 434")

    def test_messier_objects_of_skipped_types_are_kept(self):
        rows = [
            "M040;**;12:22:16.1;+58:05:04;UMa;;;;;8.00;;;;;;;;;;;;;;040;;;;;;;;",
            "NGC6994;Other;20:58:55.97;-12:38:07.8;Aqr;;;;;8.90;;;;;;;;;;;;;;073;;;;;;;;",
            "M102;Dup;14:03:12.54;+54:20:56.2;UMa;;;;;;;;;;;;;;;;;;;101;;;;;;;;",
            "NGC5866;G;15:06:29.50;+55:45:47.6;Dra;6.31;;;10.74;9.89;;;;;;;;;;;;;;;;;;;;;;",
            "NGC7000;*;20:58:47;+44:19:48;Cyg;;;;;;;;;;;;;;;;;;;;;;;;;;;",      # plain star
            "IC0067;NonEx;01:00:00;+30:00:00;Psc;;;;;;;;;;;;;;;;;;;;;;;;;;;",
        ]
        objs = {o.id: o for o in parse_openngc("\n".join([NGC_HEADER, *rows]))}
        self.assertEqual(set(objs), {"M040", "NGC6994", "NGC5866"})
        self.assertEqual((objs["M040"].name, objs["M040"].type_label), ("M40", "Double star"))
        self.assertEqual(objs["M040"].aliases, ())             # "M 40" is not repeated
        self.assertEqual((objs["NGC6994"].name, objs["NGC6994"].type_label), ("M73", "Asterism"))
        self.assertEqual((objs["NGC5866"].messier, objs["NGC5866"].name), (102, "M102"))
        self.assertIn("NGC 5866", objs["NGC5866"].aliases)
        self.assertEqual(priority(objs["M040"], 60), (0, 8.0))   # Messier: always markable


WGSN_HTML = """<html><body><table id="table_2"><thead><tr><th> proper names</th><th> NEC+</th>
<th> Designation</th><th> HIP</th><th> Bayer ID</th><th> Constellation</th><th> Origin</th>
<th> Date of Adoption</th><th> RA</th><th> DEC</th><th> mag</th><th> band</th></tr></thead>
<tbody><tr><td>Bawy</td><td>692</td><td>HR 649</td><td>10324</td><td>ξ1 Cet</td><td>Cet</td>
<td>Egyptian <b>name</b>, two souls</td><td>2026/10/15</td><td>33.25000133</td>
<td>8.846702351</td><td>4.35</td><td></td></tr>
<tr><td>Betelgeuse</td><td>1</td><td>HR 2061</td><td>27989</td><td>α Ori</td><td>Ori</td><td>x</td>
<td>2016/06/30</td><td>88.792939</td><td>7.407064</td><td>0.45</td><td>V</td></tr>
<tr><td>Siwarha</td><td>10132</td><td>-</td><td></td><td>α Ori B</td><td>Ori</td><td>x</td>
<td>2025/09/22</td><td>88.79293899</td><td>7.407064</td><td>8.2</td><td></td></tr>
<tr><td>Broken</td><td></td><td></td><td></td><td></td><td></td><td></td><td></td><td>n/a</td>
<td>1</td><td></td><td></td></tr></tbody></table>
<table id="wp-calendar"><tr><th>M</th></tr><tr><td>1</td></tr></table></body></html>"""


class WgsnTests(SimpleTestCase):
    def test_html_table_to_stars(self):
        stars = {s.name: s for s in parse_wgsn_csv(wgsn_html_to_csv(WGSN_HTML))}
        self.assertEqual(set(stars), {"Bawy", "Betelgeuse", "Siwarha"})   # "Broken": no RA
        bawy = stars["Bawy"]
        self.assertEqual((bawy.id, bawy.constellation, bawy.magnitude), ("HIP10324", "Cet", 4.35))
        self.assertAlmostEqual(bawy.ra, 33.25, places=2)
        self.assertEqual(bawy.aliases, ("ξ1 Cet", "HR 649", "HIP 10324"))
        self.assertEqual(stars["Siwarha"].id, "STAR-Siwarha")             # no HIP number
        self.assertNotIn("-", stars["Siwarha"].aliases)

    def test_page_without_star_table_is_rejected(self):
        with self.assertRaises(ValueError):
            wgsn_html_to_csv("<table><tr><th>a</th></tr><tr><td>1</td></tr></table>")

    def test_new_names_are_added_without_duplicates(self):
        old = parse_iau_stars(STARS)
        merged = merge_stars(old, parse_wgsn_csv(wgsn_html_to_csv(WGSN_HTML)))
        names = [s.name for s in merged]
        self.assertEqual(names.count("Betelgeuse"), 1)     # already in IAU-CSN.txt
        self.assertEqual(merged[:len(old)], old)            # existing entries are unchanged
        self.assertIn("Bawy", names)
        self.assertIn("Siwarha", names)
        cat = load_from_texts(NGC_HEADER, NGC_HEADER, STARS, wgsn_html_to_csv(WGSN_HTML))
        self.assertEqual(cat.get("HIP10324").name, "Bawy")


class QueryTests(SimpleTestCase):
    def test_orion_belt_field(self):
        hits, total = small_catalog().query(84.05, -1.2, 10.0, 0.0, 4 / 3, 20)
        names = [h.landmark.name for h in hits]
        self.assertEqual(names[:2], ["Great Orion Nebula", "M78"])   # Messier objects first
        self.assertIn("Alnilam", names)
        self.assertNotIn("Andromeda Galaxy", names)                    # other side of the sky
        self.assertNotIn("NGC 9999", names)                            # too faint to mark
        self.assertEqual(total, len(hits))
        alnilam = next(h for h in hits if h.landmark.name == "Alnilam")
        self.assertAlmostEqual(alnilam.x, 0.5, delta=0.01)             # field centre
        self.assertAlmostEqual(alnilam.y, 0.5, delta=0.01)
        m42 = hits[0]
        self.assertGreater(m42.y, 0.5)                                 # south is down
        betelgeuse = small_catalog().query(86.0, 3.0, 20.0)[0]
        b = next(h for h in betelgeuse if h.landmark.name == "Betelgeuse")
        self.assertLess(b.x, 0.5)                                      # east is left

    def test_rotation_moves_markers(self):
        cat = small_catalog()
        north_up = next(h for h in cat.query(84.05, -1.2, 10)[0] if h.landmark.messier == 42)
        rotated = next(h for h in cat.query(84.05, -1.2, 10, 180.0)[0] if h.landmark.messier == 42)
        self.assertAlmostEqual(rotated.y, 1 - north_up.y, delta=0.01)

    def test_marker_cap_and_overlap(self):
        hits, total = small_catalog().query(84.05, -1.2, 10.0, max_markers=2)
        self.assertEqual(len(hits), 2)
        self.assertGreater(total, 2)

    def test_priority_hides_faint_stars_in_wide_fields(self):
        star = parse_iau_stars(STARS)[2]           # magnitude 11.95
        self.assertIsNone(priority(star, 50))
        self.assertIsNone(priority(star, 2))


class MastTests(SimpleTestCase):
    def setUp(self):
        cache.clear()

    def test_pick_best_prefers_jwst_then_exposure_and_skips_darks(self):
        rows = [
            {"obs_collection": "HST", "jpegURL": "mast:a.jpg", "t_exptime": 900, "target_name": "M42"},
            {"obs_collection": "HST", "jpegURL": "mast:dark.jpg", "t_exptime": 9e9, "target_name": "DARK"},
            {"obs_collection": "JWST", "jpegURL": "mast:b.jpg", "t_exptime": 100, "target_name": "ORION"},
            {"obs_collection": "JWST", "jpegURL": None, "t_exptime": 5000},
        ]
        best = mast.pick_best(rows)
        self.assertEqual((best["collection"], best["jpeg_uri"]), ("JWST", "mast:b.jpg"))
        self.assertEqual(mast.pick_best(rows[:2])["jpeg_uri"], "mast:a.jpg")
        self.assertIsNone(mast.pick_best([rows[1]]))

    def test_status_starts_background_lookup_then_returns_cached(self):
        lm = small_catalog().get("NGC1976")
        with patch.object(mast, "_executor") as ex:
            self.assertIsNone(mast.status(lm))           # pending, lookup submitted
            self.assertIsNone(mast.status(lm))           # still pending, not submitted twice
            self.assertEqual(ex.return_value.submit.call_count, 1)
        with patch.object(mast, "lookup", return_value={"jpeg_uri": "mast:x.jpg"}):
            mast._run(lm.id, lm.ra, lm.dec, 0.1)
        self.assertEqual(mast.status(lm), {"jpeg_uri": "mast:x.jpg"})

    def test_failed_lookup_is_cached_as_no_preview(self):
        lm = small_catalog().get("NGC2068")
        with patch.object(mast, "lookup", side_effect=ExternalServiceError("down")):
            mast._run(lm.id, lm.ra, lm.dec, 0.1)
        self.assertIs(mast.status(lm), False)

    def test_busy_field_timeout_retries_with_tiny_cone(self):
        calls = []

        def fake_search(ra, dec, radius, timeout):
            calls.append(radius)
            if radius > mast.TINY_RADIUS:
                raise ExternalServiceError("POST x failed: The read operation timed out")
            return {"jpeg_uri": "mast:jwst.jpg"}

        with patch.object(mast, "_search", side_effect=fake_search):
            self.assertEqual(mast.lookup(83.8, -5.4, 0.03), {"jpeg_uri": "mast:jwst.jpg"})
        self.assertEqual(calls, [0.03, mast.TINY_RADIUS])

    def test_search_radius_follows_object_size(self):
        self.assertEqual(mast.search_radius(None), mast.MIN_RADIUS)
        self.assertAlmostEqual(mast.search_radius(2.4), 0.02)
        self.assertEqual(mast.search_radius(500), mast.MAX_RADIUS)


@override_settings(LANDMARK_MAX_MARKERS=20)
class EndpointTests(SimpleTestCase):
    def setUp(self):
        cache.clear()
        self.client = APIClient()
        patcher = patch.object(catalog_mod, "_catalog", small_catalog())
        patcher.start()
        self.addCleanup(patcher.stop)
        mast_patch = patch.object(mast, "_executor")   # no real background MAST calls
        mast_patch.start()
        self.addCleanup(mast_patch.stop)

    def test_landmarks_endpoint(self):
        cache.set("mast:NGC1976", {"jpeg_uri": "mast:m42.jpg"})
        cache.set("mast:NGC2068", mast.NO_PREVIEW)
        resp = self.client.get("/api/landmarks", {"ra": 84.05, "dec": -1.2, "fov": 10})
        self.assertEqual(resp.status_code, 200)
        body = resp.json()
        by_name = {m["name"]: m for m in body["landmarks"]}
        self.assertIs(by_name["Great Orion Nebula"]["has_hires"], True)
        self.assertIs(by_name["M78"]["has_hires"], False)
        self.assertIs(by_name["Alnilam"]["has_hires"], False)        # stars: no MAST lookup
        self.assertIsNone(by_name["NGC 1999"]["has_hires"])           # still being looked up
        self.assertTrue(body["pending"])
        for field in ("id", "x", "y", "type_label", "magnitude", "kind"):
            self.assertIn(field, body["landmarks"][0])

    def test_landmarks_validation(self):
        resp = self.client.get("/api/landmarks/", {"ra": 1, "dec": 95, "fov": 10})
        self.assertEqual(resp.status_code, 400)
        self.assertEqual(resp.json()["error"]["code"], "INVALID_REQUEST")

    @patch("landmarks.services.get_sky_image")
    @patch("landmarks.mosaic.render")
    @patch("landmarks.mosaic.locate")
    def test_auto_view_prefers_jwst_mosaic(self, locate, render, sky):
        cache.set("mast:NGC1976", {"jpeg_uri": "mast:m42.jpg"})
        sky.return_value.data = _jpeg()
        locate.side_effect = lambda mission, *a: (83.8, -5.4, 0.2) if mission == "jwst" else None
        render.return_value = mosaic.Mosaic(_jpeg(), ["JWST NIRCam"], 0.4)
        resp = self.client.get("/api/landmark-detail", {"id": "NGC1976", "provider": "dss2_color"})
        self.assertEqual(resp.status_code, 200)
        body = resp.json()
        self.assertEqual((body["image_source"], body["view"]), ("jwst", "auto"))
        self.assertIn("James Webb", body["credit"])
        self.assertIn("40% of the field", body["caption"])
        self.assertAlmostEqual(body["fov"], 0.2)
        self.assertTrue(base64.b64decode(body["image_jpeg_base64"]).startswith(b"\xff\xd8"))
        self.assertEqual(body["landmark"]["messier"], 42)
        # The survey cutout used for colour covers the same framed field as the mosaic.
        self.assertEqual(sky.call_args.args[:3], (83.8, -5.4, 0.2))

    @patch("landmarks.mosaic.locate", return_value=None)
    def test_forced_view_without_coverage_is_no_coverage(self, _):
        resp = self.client.get("/api/landmark-detail", {"id": "NGC1976", "view": "hst"})
        self.assertEqual(resp.status_code, 404)
        self.assertEqual(resp.json()["error"]["code"], "NO_COVERAGE")
        self.assertIn("Hubble", resp.json()["error"]["message"])

    def test_invalid_view(self):
        resp = self.client.get("/api/landmark-detail", {"id": "NGC1976", "view": "xray"})
        self.assertEqual(resp.status_code, 400)

    @patch("landmarks.services.get_sky_image")
    @patch("landmarks.mosaic.locate")
    def test_survey_view_skips_telescopes(self, locate, sky):
        sky.return_value.data = _jpeg()
        sky.return_value.provider.credit = "2MASS"
        sky.return_value.provider.name = "2MASS Color"
        resp = self.client.get("/api/landmark-detail",
                               {"id": "NGC1976", "view": "survey", "provider": "2mass_color"})
        self.assertEqual(resp.json()["image_source"], "survey")
        locate.assert_not_called()
        self.assertEqual(sky.call_args.args[4], "2mass_color")

    @patch("landmarks.services.get_sky_image")
    def test_detail_falls_back_to_survey_cutout(self, sky):
        cache.set("mast:NGC2068", mast.NO_PREVIEW)
        sky.return_value.data = _jpeg()
        sky.return_value.provider.credit = "DSS2 Color via CDS hips2fits"
        sky.return_value.provider.name = "DSS2 Color"
        resp = self.client.get("/api/landmark-detail", {"id": "NGC2068", "provider": "dss2_color"})
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json()["image_source"], "survey")
        args = sky.call_args.args
        self.assertEqual(args[4], "dss2_color")                 # the user's provider
        self.assertAlmostEqual(args[2], 0.12)                  # tight field: 4.5' x 1.6

    def test_unknown_landmark(self):
        resp = self.client.get("/api/landmark-detail", {"id": "NOPE"})
        self.assertEqual(resp.status_code, 404)
        self.assertEqual(resp.json()["error"]["code"], "NOT_FOUND")


class MosaicTests(SimpleTestCase):
    def test_frame_field_holds_all_frames_and_the_object(self):
        mask = np.zeros((100, 100), bool)
        mask[10:20, 70:90] = True                   # frames up and to the right of centre
        ra, dec, fov = mosaic.frame_field(mask, 100.0, 20.0, 1.0, 0.03, 1.0)
        self.assertAlmostEqual(fov, 41 * 1.1 / 100, places=3)  # centre..frames box + 10%
        self.assertGreater(dec, 20.0)                  # moved north (up)
        self.assertLess(ra, 100.0)                     # moved west (right = west)
        self.assertIsNone(mosaic.frame_field(np.zeros((10, 10), bool), 1, 2, 1, 0.03, 1))

    def test_compose_adds_detail_without_frame_squares(self):
        rng = np.random.default_rng(1)
        bg = np.full((120, 120, 3), 20, np.uint8)
        tele = np.full((120, 120, 3), 140, np.uint8)        # frame with a bright flat level...
        tele += rng.integers(0, 4, tele.shape, dtype=np.uint8)
        tele[60, 60] = 255                                   # ...and one star
        mask = np.zeros((120, 120), bool)
        mask[30:90, 30:90] = True
        out, coverage = mosaic.compose([(tele, mask, mosaic.MISSIONS["hst"][0])], bg,
                                       (120, 120), mosaic.TINTS["hst"])
        self.assertAlmostEqual(coverage, 0.25, places=2)
        self.assertGreater(out[60, 60].mean(), 100)          # the star is added
        # The frame's flat level is NOT pasted in: inside ~= outside away from the star.
        self.assertLess(abs(float(out[40, 40].mean()) - float(out[5, 5].mean())), 8)
        self.assertTrue((out[:20, :20] == bg[:20, :20]).all())   # outside untouched


class ToneTests(SimpleTestCase):
    def _encode(self, arr) -> bytes:
        import io
        from PIL import Image
        buf = io.BytesIO()
        Image.fromarray(arr.astype(np.uint8)).save(buf, "JPEG", quality=95)
        return buf.getvalue()

    def test_normal_image_is_returned_untouched(self):
        rng = np.random.default_rng(0)
        sky = rng.integers(0, 60, (100, 100, 3))
        sky[50, 50] = 255                                     # one bright star is fine
        data = self._encode(sky)
        out, changed = tone.tame_jpeg(data)
        self.assertFalse(changed)
        self.assertIs(out, data)                              # same bytes, no re-encode

    def test_overexposed_image_is_compressed_and_keeps_colour(self):
        yy, xx = np.mgrid[0:100, 0:100]
        glow = np.clip(420 - np.hypot(xx - 50, yy - 50) * 3, 0, 255)[..., None]
        img = np.concatenate([glow, glow * 0.95, glow * 0.85], axis=2)  # big warm halo
        out, changed = tone.tame_array(img)
        self.assertTrue(changed)
        lum = out.astype(float).mean(axis=2)
        self.assertLess((lum >= 200).mean(), (img.mean(axis=2) >= 200).mean())
        self.assertLess(float(np.median(lum)), float(np.median(img.mean(axis=2))))
        r, g, b = out[50, 30].astype(float)
        self.assertGreater(r, b)                              # still warm, not grey

    def test_burnt_out_detection(self):
        flat_white = np.full((100, 100, 3), 235)
        self.assertTrue(tone.is_burnt_out(self._encode(flat_white)))
        rng = np.random.default_rng(1)
        textured = rng.integers(150, 255, (100, 100, 3))      # bright but full of structure
        self.assertFalse(tone.is_burnt_out(self._encode(textured)))
        self.assertFalse(tone.is_burnt_out(self._encode(np.full((100, 100, 3), 20))))


class DetailFieldTests(SimpleTestCase):
    def test_bright_stars_get_a_wider_field(self):
        cat = small_catalog()
        betelgeuse, alnilam = cat.get("HIP27989"), cat.get("HIP26311")
        faint = parse_iau_stars(STARS)[2]                     # magnitude 11.95
        self.assertEqual(services.detail_fov(betelgeuse), 1.5)   # mag 0.45
        self.assertEqual(services.detail_fov(alnilam), 1.0)      # mag 1.69
        self.assertEqual(services.detail_fov(faint), services.DETAIL_STAR_FOV)

    @patch("landmarks.services.get_sky_image")
    def test_burnt_out_background_falls_back_to_another_survey(self, sky):
        white = ToneTests._encode(None, np.full((60, 60, 3), 235))
        ok = ToneTests._encode(None, np.random.default_rng(2).integers(0, 80, (60, 60, 3)))

        def fake(ra, dec, fov, rot, key, w, h):
            result = type("R", (), {})()
            result.data = white if key == "dss2_color" else ok
            result.provider = type("P", (), {"name": key.upper()})()
            return result

        sky.side_effect = fake
        data, name = services._background(83.8, -5.4, 0.2, "dss2_color")
        self.assertEqual(name, "2MASS_COLOR")
        self.assertIs(data, ok)


def _jpeg() -> bytes:
    import io
    from PIL import Image
    out = io.BytesIO()
    Image.new("RGB", (40, 30), "navy").save(out, "JPEG")
    return out.getvalue()
