# NightSky

## Google Play release preparation

Start with [release/README.md](release/README.md) and
[remaining actions](release/remaining-actions.md). The app now includes bundled legal
documents, visible source/licence credits and photo-upload consent. Publication
requires completed publisher/privacy inputs and image-rights evidence;
unresolved items deliberately fail the publication preflight. Local release APKs
can be built with the configured release signing key while these inputs are pending.

Point your phone at the night sky, take a photo, and NightSky replaces it with a professional
survey image of the same patch of sky — or switch to **Sky View** to explore a live 3D virtual
night sky driven by the phone's orientation sensors, with no camera or internet connection needed.
Notable objects show up as tappable markers; tapping one opens rich facts, Curated Cosmic
Highlights, or a close-up from Hubble, JWST or any survey.

- `backend/`: Django REST API (plate solving, survey images, landmarks, Hubble/JWST mosaics)
- `app/`: Flutter Android app (Camera plate-solving mode + offline 3D Sky View mode)
- `local_tools/curator/`: local-only tool for managing curated highlights (never deployed)

## Modes

### Camera mode (photo -> survey replacement)
1. The app sends the photo plus GPS, time, phone orientation and camera field of view.
2. `POST /api/solve` converts the orientation to a sky position (astropy, pygeomag), then refines
   it by plate-solving the stars (tetra3). With too few stars it returns the sensor position,
   marked *approximate*.
3. `POST /api/sky-image` returns a survey cutout of that field. If the chosen source is down or
   lacks coverage, another is used and the app says so.
4. `GET /api/landmarks` lists Messier/NGC objects and named stars in view (OpenNGC, IAU names).
   Gold markers have Hubble/JWST data (checked via MAST).
5. `GET /api/landmark-detail` gives the close-up: JWST, then Hubble, then a survey. Hubble/JWST
   mosaics are stitched from ESA ESASky tiles.

### Sky View mode (offline 3D sensor sky map)
- **No camera & fully offline**: Renders NASA's Deep Star Maps 2020 panorama on a 3D GPU
  sky sphere (`app/shaders/sky_sphere.frag`, with automatic `Canvas.drawVertices` fallback),
  aligned to true astronomical north via offline NOAA WMM-2025 geomagnetic declination. Phones
  without a working camera can enable **Start in Sky View** in Settings to skip camera setup
  completely.
- **Bundled sky layers**:
  - `assets/sky/nasa_2020_east.webp` + `nasa_2020_west.webp`: NASA SVS #4851's corrected
    Galactic star map at **8192 x 4096 (8K)**, split into two 4096 x 4096 hemispheres.
    Balanced (default) and Max detail render the full 8K map; Power saver decodes at 3200 x 1600.
    The renderer uses sub-texel bilinear filtering. These are catalog-rendered stars, rather
    than Mellinger's photographic panorama; dust and nebulae are not depicted.
  - `assets/sky/stars.bin` (104 KB): 8,874 naked-eye stars down to magnitude 6.5 (sorted
    brightest-first, with Hipparcos IDs and B−V spectral colours).
  - `assets/sky/sky_catalog.json` (66 KB): 574 proper star names, all 88 IAU constellations
    (highlighting whichever constellation is centred in view), and 145 Messier / curated / bright
    deep-sky objects.
  - Real-time offline ephemeris (`app/lib/sky_view/ephemeris.dart`) for the **Sun**, **Moon**
    (topocentric parallax + illuminated phase disc), and **Mercury–Neptune**.
- **Interactive tools**: Time Machine scrubber (±12 h slider, ±1 h / ±1 d steps, 300× timelapse,
  date/time picker), manual coordinate/preset location picker when GPS is unavailable, object
  search with a 3D perimeter directional guide arrow, compass calibration diagnostics, red
  night-vision mode, and direct links to **Curated Cosmic Highlights** and Webb/Hubble close-ups.
- **Optional 16K and 32K maps**: Install under Settings or Sky Layers & Display > Panorama
  resolution. Downloads are verified with SHA-256, resume completed tiles after interruption,
  persist offline, and can be removed independently. Selecting 8K always uses the bundled map.
  All three resolutions use lossless WebP, verified pixel-for-pixel after converting NASA's
  linear HDR EXRs to display sRGB8. Native dimensions are preserved; the display conversion
  clips HDR highlights and is distinct from lossless compression.
  A bounded cache decodes visible 2048-pixel tiles; the 8K map fills tiles still loading or
  outside the memory budget. These maps add native detail when zoomed in.
  The fragment shader applies the same orientation, horizon shading and night vision at every
  resolution. Backends without custom shader support retain the bundled 8K mesh fallback.
- To prepare optional server packs: `python app/tool/sky_data/prepare_nasa.py --packs`
  (requires OpenEXR, numpy and Pillow; 8K preparation also requires OpenCV).
  Deploy `backend/panorama_packs/` with the backend; its versioned
  `/api/panorama/nasa2020-v1/{16k,32k}/manifest.json` endpoints deliver the packs.
  Builds of the app include only the 8K assets. Backend changes and packs must be deployed
  before downloads are available on the production server.
- To regenerate the bundled Sky View assets from upstream sources:
  `python app/tool/sky_data/prepare_nasa.py` and `python app/tool/sky_data/prepare_catalogs.py`.

### Image sources
| Key | Source | Coverage |
|---|---|---|
| `dss2_color` (default) | DSS2 colour, CDS hips2fits + ESA mirror | All-sky (field & close-ups) |
| `nasa_starmap_2020` | NASA Deep Star Maps 2020, locally rendered | All-sky (wide fields >= 5 degrees) |

To add a source, subclass `ImageProvider` in `backend/providers/` (see `base.py`), then add one
line to `PROVIDERS` in `providers/registry.py`. The app builds its pickers from `GET /api/providers`.

### Curated Cosmic Highlights
Hand-picked NASA/ESA images with captions, credits and source links, shown in a landmark's detail
view for objects that have them. They are managed with the local curator tool
(`local_tools/curator/README.md`, needs `ENABLE_CURATOR=1`) and shipped as a read-only bundle in
`backend/curated_bundle/`. Publish new ones by exporting, committing and pushing.

## Local development

**Backend**
```powershell
cd backend
python -m venv .venv
.venv\Scripts\pip install -r requirements-dev.txt     # tetra3 is fetched from GitHub (~50 MB)
copy .env.example .env
.venv\Scripts\python manage.py runserver 127.0.0.1:8000
```
All settings are environment variables, documented in `backend/.env.example`. Handy commands:
`manage.py test`, `manage.py fetch_catalogs`, `manage.py cutout 83.82 -5.39 2.0 -o orion.jpg`.
To self-host elsewhere: `gunicorn config.wsgi -w 2 --threads 4 --timeout 300`.

**App** (phone over USB, backend on port 8000)
```powershell
adb reverse tcp:8000 tcp:8000
cd app
flutter run --dart-define=SERVER_URL=http://127.0.0.1:8000
```
Tests: `flutter test`. The app defaults to `https://nightsky-backend.vercel.app`; change it in
Settings or at build time with `--dart-define=SERVER_URL=...`.

## Deployment

### Backend on Vercel
The APK targets `https://nightsky-backend.vercel.app`, so name the project **`nightsky-backend`**
(or rebuild the APK with your own URL).

1. Push the repo to GitHub. `backend/data/catalogs/` must be committed.
2. At <https://vercel.com/new>, import it and set **Root Directory** to `backend`.
3. Add environment variables:
   - `DJANGO_SECRET_KEY`: a random string (`python -c "import secrets; print(secrets.token_urlsafe(50))"`)
   - `DJANGO_ALLOWED_HOSTS`: `.vercel.app`
   - optional `CACHE_BACKEND=redis` and `CACHE_LOCATION=redis://...` for a shared cache
4. Deploy, then check `/` returns `{"status": "ok"}` and `/api/providers` lists the sources.

CLI alternative: `npm i -g vercel`, then in `backend/` run `vercel link`, `vercel env add ...`,
`vercel --prod`. Later pushes to `main` redeploy automatically.

Good to know: requests may run up to 300 s (`vercel.json`, region `fra1`; use `bom1` for India);
cold starts add ~5–15 s; the default cache is per-instance memory; gold "has Hubble/Webb image"
markers may fill in over a few refreshes; only `/tmp` is writable.

### Android APK
Build a signed release (bump `version` in `app/pubspec.yaml` first; the `+N` must increase):
```powershell
cd app
flutter build apk --release --dart-define=SERVER_URL=https://nightsky-backend.vercel.app
```
Output: `app/build/app/outputs/flutter-apk/app-release.apk`. Install with
`adb install -r <apk>`, or copy it to a phone and allow *Install unknown apps*. If a dev build is
installed, uninstall it first (different signing key).

**Release key:** `app/android/nightsky-release.jks` and `app/android/key.properties` are
git-ignored. Never commit them, and back them up: every update must be signed with the same key.
Without them, release builds fail. They never fall back to the debug key.

To change the icon, replace `app/tool/icon/nightsky_icon_source.png` and run
`python app/tool/icon/make_icons.py`.

## API
| Endpoint | Description |
|---|---|
| `POST /api/solve` | multipart `image` + `metadata` JSON → `{ra, dec, rotation, fov, confidence, approximate, source, message}` |
| `GET /api/providers` | Image sources and metadata |
| `POST /api/sky-image` | `{ra, dec, fov, rotation?, provider?, width?, height?}` → JPEG |
| `GET /api/landmarks?ra&dec&fov&rotation&aspect` | Landmarks in the field |
| `GET /api/landmark-detail?id&provider&view` | Close-up; `view` = `auto`/`jwst`/`hst`/`survey` |
| `GET /api/curated/index/`, `/api/curated/<body_id>/`, `/api/curated/image/<file>` | Curated highlights (public, read-only, ETag-cached) |

Errors: `{"error": {"code", "message"}}` with `SOLVE_FAILED` (422), `PROVIDER_UNAVAILABLE` (503),
`NO_COVERAGE` (404), `INVALID_REQUEST` (400), `NOT_FOUND` (404), `CATALOG_UNAVAILABLE` (503).

`/solve` metadata is optional: `latitude`, `longitude`, `altitude`, `timestamp`,
`orientation` (`quaternion` + `reference`), `image_rotation_deg`, `fov_deg`. Orientation uses the
Android rotation-vector convention (device → world ENU; the rear camera looks along −Z).

## Limitations
- tetra3's bundled database covers 10–30° fields, so wide phone photos (~50–70°) often fall back
  to the sensor position. A custom database (`TETRA3_DATABASE`) would fix that.
- Every external call has timeouts and a retry; failing sources are skipped for 2 minutes, and
  results are cached.


## Offline observing tools

Open the NightSky menu on the camera screen, or the calendar button in Sky View, for **Observing events** and **Solar system**. An event opens the chart at its UTC instant. Lunar events also select the Moon. Event details show the device's local time and approximate Sun and Moon altitudes for the selected or last saved coordinates. The shower times are predicted global maxima and can shift by hours. The app has no observing-site directory.

The bundled calendar covers all four primary lunar phases for 2025–2030 and four major meteor showers for 2026–2027. Updating coverage requires an app update. The lunar times are USNO public-domain astronomical data. The independently assembled meteor records contain factual names and peak estimates from the International Meteor Organization. [Calendar provenance and update procedure](app/assets/observing/README.md)

**Android reminders** are opt-in per event. Open its details to schedule or cancel the one-hour reminder. Android 13 and later asks for notification permission on opt-in. If notifications are disabled, use Android's notification settings to re-enable them. Inexact alarms can arrive late in battery-saving modes. The app skips expired events and restores outstanding requests on launch, device reboot, app update and clock changes. Android can suspend alarms and widget updates after a force-stop until you reopen NightSky.

**Android widgets** are available from the launcher's widget picker. Moon phase and Next observing event use the same bundled calendar as the app. Astronomical darkness uses the coordinates saved by Sky View. Widgets request updates every 30 minutes through Android's widget service, including when NightSky is closed. Android controls actual refresh times. Settings and system time changes also trigger updates. Taps open the associated app screen. The calendar and explorer work offline on other supported Flutter platforms. Reminders and launcher widgets require Android. No additional package or service is required.

The darkness widget estimates when the geometric center of the Sun is below −18° over the next 24 hours, within 2000–2050. Times use the device timezone. It handles continuous darkness, continuous twilight/daylight and uncertain grazing crossings. Moonlight, weather and terrain are outside this estimate. London reference nights agreed within two minutes, including a daylight-saving transition. Uncertainty increases near polar twilight limits. [USNO solar model](https://aa.usno.navy.mil/faq/sun_approx) · [Twilight definition](https://aa.usno.navy.mil/faq/RST_defs)

The solar-system explorer projects heliocentric positions onto the J2000 ecliptic plane for chart dates 1950–2050. The scale rings measure distance in AU, body symbols are enlarged, and Earth's marker represents the Earth–Moon barycenter. Mercury through Neptune use the existing JPL approximate orbital elements. Select a planet and date to locate it in Sky View. [JPL orbital model](https://ssd.jpl.nasa.gov/planets/approx_pos.html)



## Credits & data provenance
- **Sky panorama**: [NASA Deep Star Maps 2020](https://svs.gsfc.nasa.gov/4851/), by Ernie Wright.
  Credit: NASA/Goddard Space Flight Center Scientific Visualization Studio. Gaia DR2:
  ESA/Gaia/DPAC. Public domain under the [SVS usage policy](https://svs.gsfc.nasa.gov/help/),
  subject to [NASA media usage guidelines](https://www.nasa.gov/nasa-brand-center/images-and-media/).
  See `app/assets/sky/SOURCES.md` for processing details. NASA does not endorse NightSky.
- **Stars & 88 IAU constellations** (`app/assets/sky/stars.bin`, `sky_catalog.json`):
  [`ofrohn/d3-celestial`](https://github.com/ofrohn/d3-celestial) (`stars.8.json`,
  `starnames.json`, `constellations.lines.json`, `constellations.json`), Copyright © 2015 Olaf
  Frohn, **BSD-3-Clause License** (astrometry derived from ESA Hipparcos `I/239` & XHIP), merged
  with official proper star names from the **IAU Working Group on Star Names** (`IAU-WGSN.csv` /
  `IAU-CSN.txt`).
- **Deep-sky objects** (`sky_catalog.json` & `/api/landmarks`): **OpenNGC** (`NGC.csv` +
  `addendum.csv`, Mattia Verga), **CC BY-SA 4.0**.
- **Solar System & geomagnetism**: Planetary Keplerian elements from NASA JPL (Standish 1992);
  lunar periodic theory from Meeus (*Astronomical Algorithms*, Ch. 47); offline geomagnetic
  declination from **NOAA/NCEI WMM-2025** (public domain).
- **Online survey cutouts & space-telescope mosaics**: DSS2, 2MASS, AllWISE and Pan-STARRS via CDS
  hips2fits, NASA SkyView and STScI; Hubble and JWST data (NASA/ESA/CSA) via ESA ESASky and MAST.
  Full per-asset details are recorded in `app/assets/sky/SOURCES.md`.

Vercel serves the optional packs from its static CDN after collectstatic, with a rewrite
from the versioned API paths. The 16K/32K files are excluded from the Python function bundle.
Self-hosted Django serves the same paths directly from panorama_packs.
