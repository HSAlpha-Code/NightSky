# NightSky ELI5 Guide — Start Here! (`README.md`)

Welcome to the plain-English guide to **NightSky**! Every document in this folder is written so someone with **zero programming background** can understand what NightSky does, why every single file exists, how its coolest tricks work, and what happens inside the phone and server from start to finish.

Throughout these pages, we use one consistent analogy: **The Pocket Planetarium & Backstage Astronomy Lab**.

---

## Recommended Reading Order

### Step 1 — Get the Big Picture (5 minutes)
1. **[`00-OVERVIEW.md`](./00-OVERVIEW.md)** — Start here! Explains what NightSky is, introduces our *Pocket Planetarium & Backstage Lab* analogy, maps every part of the project in a diagram, and shows what goes in and comes out.

### Step 2 — Watch the Movie From Start to Finish (8 minutes)
2. **[`10-RUNTIME-FLOW.md`](./10-RUNTIME-FLOW.md)** — Follow a real night-sky photo of the **Great Orion Nebula (`M42`)** step by step from pressing the camera shutter, through star-triangle matching and tile stitching, to tapping gold pins — plus how the offline 60 fps 3D Star Dome works without internet.

### Step 3 — Tour the Handheld Planetarium (`app/` — What Runs on Your Phone)
3. **[`files/app-entry-state-and-settings.md`](./files/app-entry-state-and-settings.md)** — The power switch (`main.dart`), user preferences notebook (`settings.dart`), photo-session clipboard (`state.dart`), and data cards (`models.dart`).
4. **[`files/app-sensors-math-and-native-bridges.md`](./files/app-sensors-math-and-native-bridges.md)** — How gravity + magnetism find North without a gyroscope, how hand shake is measured (`0.6s` window), and how Flutter talks to Android hardware (`MainActivity.kt`, `AndroidManifest.xml`).
5. **[`files/app-network-photos-and-curated.md`](./files/app-network-photos-and-curated.md)** — Shrinking 12-megapixel photos on a background thread (`photo_utils.dart`), talking to the server (`api_client.dart`), and caching museum stories offline (`curated.dart`).
6. **[`files/app-screens-camera-result-and-settings.md`](./files/app-screens-camera-result-and-settings.md)** — The four main visitor rooms: Camera Viewfinder, `"Your sky"` Magic Reveal, `"Star View"` Close-Up Kiosk (with verified telescope chips), and Settings.
7. **[`files/app-widgets.md`](./files/app-widgets.md)** — Frosted glass controls, the `[ 🌐 | 📷 ]` mode switcher, synchronized zoom-and-slide comparison curtain, constant-size sky pins, arrival sparkles, and swipeable story gallery.
8. **[`files/app-sky-view-math-and-catalog.md`](./files/app-sky-view-math-and-catalog.md)** — Offline Solar System orbits, Moon topocentric parallax, offline WMM-2025 compass map, 12-byte packed stars (`stars.bin`), and dual-hemisphere 8K textures.
9. **[`files/app-sky-view-rendering-and-shader.md`](./files/app-sky-view-rendering-and-shader.md)** — The custom GPU raytracing shader (`sky_sphere.frag`), sunlit Moon crescent painter, collision-free labels, Time Machine scrubber, and search guide arrow.

### Step 4 — Tour the Backstage Astronomy Lab (`backend/` — What Runs in the Cloud)
10. **[`files/backend-config.md`](./files/backend-config.md)** — The front desk, rate-limit hall monitors, dual memory cubbies (`default` vs. `images`), polite error envelopes, retry timers, and image-bomb X-ray scanner.
11. **[`files/backend-solver-astro-and-plate.md`](./files/backend-solver-astro-and-plate.md)** — How the Star Detective matches star triangles (`tetra3`) and converts phone tilt + compass readings into sky coordinates (`astropy` + `pygeomag`).
12. **[`files/backend-solver-api.md`](./files/backend-solver-api.md)** — The `/api/solve` office door and two-plan playbook (exact stars first, sensor fallback second, aimed-at-shoes rejected!).
13. **[`files/backend-providers-core.md`](./files/backend-providers-core.md)** — The Sky Map Print Shop menu (`DSS2 Color` for field + close-ups, `Mellinger Color` for wide fields), caching, and header credits.
14. **[`files/backend-providers-adapters.md`](./files/backend-providers-adapters.md)** — Printing sky cutouts via CDS Strasbourg, stitching HEALPix tiles locally from ESA's mirror (`hips_render.py`), and handling NASA SkyView's busy queue.
15. **[`files/backend-landmarks-catalog-and-parsing.md`](./files/backend-landmarks-catalog-and-parsing.md)** — Reading 14,000+ OpenNGC & IAU objects, computing light-year distances, and spacing up to 20 pins cleanly inside your photo.
16. **[`files/backend-landmarks-telescopes-and-tone.md`](./files/backend-landmarks-telescopes-and-tone.md)** — Background MAST scouts, verifying genuine target-core coverage, erasing patchwork seams on Webb/Hubble mosaics, and dimming blown-out nebula cores.
17. **[`files/backend-landmarks-api.md`](./files/backend-landmarks-api.md)** — Serving `/api/landmarks` and `/api/landmark-detail` with parallel telescope availability checks (`available_views`).

### Step 5 — Visit the Creator's Workshop & Reference Shelf
18. **[`files/backend-curated-and-curator-tool.md`](./files/backend-curated-and-curator-tool.md)** — How the private local curator (`local_tools/curator/`) builds read-only NASA/ESA highlight bundles (`backend/curated_bundle/`).
19. **[`files/offline-asset-and-test-suites.md`](./files/offline-asset-and-test-suites.md)** — Stitching 114 plates into the 8K Milky Way panorama (`prepare_mellinger.py`), packing `stars.bin` (`prepare_catalogs.py`), stamping icons, and running automated tests.
20. **[`files/project-configs-and-build.md`](./files/project-configs-and-build.md)** — Blueprints, dependency supply lists (`pubspec.yaml`, `requirements.txt`), and Vercel cloud deployment rules (`vercel.json`).
21. **[`GLOSSARY.md`](./GLOSSARY.md)** — Quick one-line plain-English meanings for every technical or astronomy word.
22. **[`PROGRESS.md`](./PROGRESS.md)** — Complete project checklist and list of skipped generated/binary files.
