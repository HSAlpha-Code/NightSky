# NightSky ELI5 Documentation Progress (Phase 0 Map)

## Running Analogy
**The Pocket Planetarium & Backstage Astronomy Lab**:
- **`app/` (The Handheld Planetarium Dome & Sky Binoculars)**: What you hold in your hand — either spinning an indoor 3D star dome (`SkyViewScreen`) or snapping a real night-sky photo through a steady viewfinder (`CameraScreen`) and sliding a magic transparency sheet over it (`ResultScreen`).
- **`backend/` (The Backstage Astronomy Lab)**: A team of specialist scientists on a cloud computer who examine your photo, match star triangles (`solver/`), print matching telescope maps (`providers/`), pin famous nebulae and stitch James Webb / Hubble close-ups (`landmarks/`), and serve museum story cards (`curated/`).
- **`local_tools/curator/` & `app/tool/` (The Exhibit Workshop)**: Offline workbench scripts used by the app's creators to curate museum cards, stitch the 8K Milky Way dome wallpaper, and stamp app icons.

---

## Project Map (Entry Points, Configs, Dependencies & External Services)

### Entry Points
- **Mobile App (`app/`)**: `app/lib/main.dart` (`main()` launches `NightSkyApp` -> `CameraScreen` or `SkyViewScreen`).
- **Backend API (`backend/`)**: `backend/manage.py` (CLI / dev server) and `backend/config/wsgi.py` (Vercel / Gunicorn production entry) routing through `backend/config/urls.py`.
- **Local Curator Tool (`local_tools/curator/`)**: `local_tools/curator/run.py` (local-only Django server on `127.0.0.1:8001`).
- **Asset Preparation Scripts (`app/tool/`)**: `prepare_mellinger.py`, `prepare_catalogs.py`, `make_icons.py`.

### Configuration Files
- `backend/.env.example` & `backend/config/settings.py` (environment-driven server settings)
- `backend/vercel.json` & `backend/.vercelignore` (Vercel serverless deployment rules)
- `backend/requirements.txt` & `backend/requirements-dev.txt` (Python packages)
- `app/pubspec.yaml` & `app/analysis_options.yaml` (Flutter packages, bundled sky assets, GLSL shader, lint rules)
- `app/android/app/src/main/AndroidManifest.xml` & `app/ios/Runner/Info.plist` (camera, GPS, and motion sensor permissions)

### Key Dependencies
- **Flutter App**: `flutter_riverpod` (shared memory board), `camera` (rear lens capture), `geolocator` (GPS coordinates), `dio` (HTTP messenger), `image` (photo resizing/decoding), `url_launcher` (opening NASA/ESA links).
- **Python Backend**: `Django` + `djangorestframework` (web server), `tetra3` (ESA star-pattern plate solver), `astropy` + `astropy-healpix` (sky coordinate math & HEALPix sky tiles), `pygeomag` (magnetic-to-true-north compass math), `numpy` + `scipy` + `Pillow` (image stretching, tile stitching, highlight compression), `httpx` (calling astronomy archives).

### External Astronomy Services & Data Archives
1. **CDS `hips2fits` (Strasbourg, France)**: Cuts out optical `DSS2 Color` sky survey images.
2. **ESA ESASky HiPS (`skies.esac.esa.int`)**: Backup tile mirror for `DSS2 Color`/`2MASS Color`, plus public **James Webb (`NIRCam`, `MIRI`)** and **Hubble (`ACS`, `WFC3`, `WFPC2`)** sky tiles.
3. **NASA SkyView (HEASARC/GSFC)**: Renders wide-field **Axel Mellinger** Milky Way cutouts and provides source plates for offline panorama preparation.
4. **STScI MAST (`mast.stsci.edu`)**: Checks whether a deep-sky object has been photographed by Webb or Hubble.
5. **OpenNGC, IAU WGSN & Hipparcos / `d3-celestial`**: Catalogs of nebulae, galaxies, star clusters, constellation stick figures, and official star names.

---

## Documentation Checklist

### Core Guides
- [x] `docs/eli5/00-OVERVIEW.md` — Phase 1: Big picture, analogy table, architecture diagram, inputs/outputs
- [x] `docs/eli5/10-RUNTIME-FLOW.md` — Phase 4: Step-by-step runtime data flow, sequence diagrams, error paths, concrete M42 example
- [x] `docs/eli5/GLOSSARY.md` — Phase 5: Plain-English dictionary of every technical term
- [x] `docs/eli5/README.md` — Phase 5: Reading guide and complete index

### Phase 2 & 3 File Guides (`docs/eli5/files/`)
- [x] `files/project-configs-and-build.md` — `README.md`, `LICENSE`, `.gitignore`, `backend/manage.py`, `backend/requirements.txt`, `backend/requirements-dev.txt`, `backend/.env.example`, `backend/.python-version`, `backend/vercel.json`, `backend/.vercelignore`, `app/pubspec.yaml`, `app/analysis_options.yaml`, `app/assets/sky/SOURCES.md`
- [x] `files/backend-config.md` — `backend/config/settings.py`, `urls.py`, `wsgi.py`, `middleware.py`, `errors.py`, `throttles.py`, `http.py`, `images.py`, `__init__.py`
- [x] `files/backend-solver-astro-and-plate.md` — `backend/solver/astro.py`, `plate_solver.py`
- [x] `files/backend-solver-api.md` — `backend/solver/services.py`, `views.py`, `serializers.py`, `urls.py`, `apps.py`, `__init__.py`
- [x] `files/backend-providers-core.md` — `backend/providers/base.py`, `registry.py`, `services.py`, `views.py`, `serializers.py`, `urls.py`, `apps.py`, `management/commands/cutout.py`
- [x] `files/backend-providers-adapters.md` — `backend/providers/hips2fits.py`, `hips_render.py`, `skyview.py`
- [x] `files/backend-landmarks-catalog-and-parsing.md` — `backend/landmarks/catalog.py`, `parsing.py`, `management/commands/fetch_catalogs.py`
- [x] `files/backend-landmarks-telescopes-and-tone.md` — `backend/landmarks/mast.py`, `mosaic.py`, `tone.py`
- [x] `files/backend-landmarks-api.md` — `backend/landmarks/services.py`, `views.py`, `serializers.py`, `urls.py`, `apps.py`
- [x] `files/backend-curated-and-curator-tool.md` — `backend/curated/*`, `backend/curated_bundle/manifest.json`, `local_tools/curator/*`
- [x] `files/app-entry-state-and-settings.md` — `app/lib/main.dart`, `settings.dart`, `state.dart`, `models.dart`
- [x] `files/app-network-photos-and-curated.md` — `app/lib/api_client.dart`, `photo_utils.dart`, `curated.dart`
- [x] `files/app-sensors-math-and-native-bridges.md` — `app/lib/sensors.dart`, `sky_math.dart`, `MainActivity.kt`, `AndroidManifest.xml`, `AppDelegate.swift`, `Info.plist`
- [x] `files/app-screens-camera-result-and-settings.md` — `app/lib/screens/camera_screen.dart`, `result_screen.dart`, `landmark_detail_screen.dart`, `settings_screen.dart`
- [x] `files/app-widgets.md` — `app/lib/widgets/compare_view.dart`, `landmark_overlay.dart`, `magic_reveal.dart`, `glass.dart`, `camera_hints.dart`, `provider_picker.dart`, `result_widgets.dart`, `curated_viewer.dart`
- [x] `files/app-sky-view-math-and-catalog.md` — `app/lib/sky_view/astro_math.dart`, `ephemeris.dart`, `sky_catalog.dart`, `panorama_loader.dart`
- [x] `files/app-sky-view-rendering-and-shader.md` — `app/lib/screens/sky_view_screen.dart`, `app/lib/sky_view/sky_sphere_painter.dart`, `sky_overlay_painter.dart`, `app/shaders/sky_sphere.frag`, `sky_sheets.dart`, `time_machine_bar.dart`
- [x] `files/offline-asset-and-test-suites.md` — `app/tool/sky_data/prepare_mellinger.py`, `prepare_catalogs.py`, `app/tool/icon/make_icons.py`, `backend/*/tests.py`, `backend/*/test_*.py`, `app/test/*.dart`

---

## Skipped Files & Folders (with Reasons)
- **`.git/`, `.idea/`, `.vscode/`, `app/.idea/`, `app/night_sky.iml`**: Editor settings and Git history internals (not part of the program).
- **`backend/.venv/`, `**/__pycache__/`, `app/.dart_tool/`, `app/build/`, `app/.flutter-plugins-dependencies`, `app/.metadata`**: Installed third-party libraries, compiled caches, and build outputs generated automatically by Python and Flutter.
- **`app/pubspec.lock`**: Auto-generated exact version lockfile for `pubspec.yaml`.
- **`backend/.env`**: Local private environment file (never read or documented directly to protect local secrets; `backend/.env.example` is documented instead).
- **`backend/db.sqlite3`, `local_tools/curator/curator.sqlite3`, `local_tools/curator/media/`**: Local SQLite binary database files and local scratch media uploads.
- **`backend/data/catalogs/*.csv` / `*.txt`, `backend/curated_bundle/images/*`, `app/assets/sky/*.webp`, `app/assets/sky/stars.bin`, `app/assets/sky/sky_catalog.json`**: Large raw data tables, binary star packs, and image files (their exact structure and generators are documented via `SOURCES.md`, `fetch_catalogs.py`, `prepare_mellinger.py`, `prepare_catalogs.py`, and `sky_catalog.dart`).
- **`app/windows/`, standard Flutter Gradle/Xcode scaffolding (`app/android/gradle*`, `app/ios/Runner.xcodeproj/*`, launcher PNG mipmaps, `GeneratedPluginRegistrant.*`)**: Auto-generated platform wrapper boilerplate from `flutter create` (we DO document the custom code inside `MainActivity.kt`, `AndroidManifest.xml`, `AppDelegate.swift`, and `Info.plist`).
