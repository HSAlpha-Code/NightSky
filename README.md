# NightSky

Point your phone at the night sky, take a photo, and NightSky replaces it with a professional
survey image of the same patch of sky. Notable objects show up as tappable markers; tapping one
opens a close-up from Hubble, JWST or any survey.

- `backend/`: Django REST API (plate solving, survey images, landmarks, Hubble/JWST mosaics)
- `app/`: Flutter Android app

**Deploying (Vercel + APK): see [DEPLOY.md](DEPLOY.md).**

## How it works
1. The app takes a photo and records GPS, time, the fused phone orientation and the camera's
   field of view.
2. `POST /api/solve`: the backend turns the orientation into a sky position (astropy, magnetic
   declination via pygeomag), then refines it by plate-solving the stars (tetra3). With too few
   stars it returns the sensor position marked *approximate*.
3. `POST /api/sky-image`: a survey cutout of that field from the chosen image source. If the
   source doesn't cover the position or is down, another one is used and the app says so.
4. `GET /api/landmarks`: Messier/NGC objects and bright named stars in the field (OpenNGC + IAU
   star names), drawn as markers. Gold markers have Hubble/JWST data (checked via MAST).
5. `GET /api/landmark-detail`: the second-level view. *Best* = JWST, then Hubble, then a survey.
   Hubble/JWST mosaics are stitched from ESA ESASky tiles, so neighbouring frames fill the field,
   and coloured with a ground-based survey. Over-exposed images get their highlights compressed.

## Image sources
| Key | Source | Notes |
|---|---|---|
| `dss2_color` (default) | DSS2 colour via CDS hips2fits | All-sky. Renders ESA's copy of the tiles if CDS is unreachable. |
| `2mass_color` | 2MASS near-infrared | All-sky, same fallback. |
| `allwise_color` | AllWISE mid-infrared | All-sky, same fallback. |
| `panstarrs_hips` | Pan-STARRS DR1 via hips2fits | Dec > −30°. |
| `skyview_mellinger` | Mellinger colour mosaic via NASA SkyView | All-sky, best for wide phone fields. |
| `skyview_dss2_red` | DSS2 red via NASA SkyView | All-sky. |
| `panstarrs` | Pan-STARRS cutout service (STScI) | Dec > −30°, fields ≤ 0.4°. |

### How to add an image source
1. Write an adapter in `backend/providers/` that subclasses `ImageProvider` (`base.py`): set
   `key`, `name`, `description`, `wavelength`, `coverage`, `credit`, and implement
   `fetch_cutout(ra, dec, fov_deg, rotation_deg, width_px, height_px) -> JPEG bytes`. Override
   `supports(ra, dec, fov_deg)` for partial coverage and set `all_sky = False`. Raise
   `ProviderError` on failure; use `config.http.http_get` for timeouts and retries.
   For any HiPS survey on CDS no new file is needed: just add a `Hips2FitsProvider(...)`.
2. Add one line to `PROVIDERS` in `backend/providers/registry.py`.

The app's image-source picker and the landmark view chips are built from `GET /api/providers`,
so the app needs no change.

## Local development

### Backend
```powershell
cd backend
python -m venv .venv
.venv\Scripts\pip install -r requirements-dev.txt     # tetra3 comes from GitHub (~50 MB)
copy .env.example .env
.venv\Scripts\python manage.py runserver 127.0.0.1:8000
```
Self-hosting on a normal server (plate solving is CPU-heavy, keep generous timeouts):
```bash
gunicorn config.wsgi -w 2 --threads 4 --timeout 300 -b 0.0.0.0:8000
```
Useful: `manage.py cutout 83.82 -5.39 2.0 -o orion.jpg` (save a cutout),
`manage.py fetch_catalogs` (refresh the landmark catalogue), `manage.py test`.
All settings are environment variables, listed in `backend/.env.example`.

### App on a phone over USB
```powershell
# backend running on 127.0.0.1:8000, phone connected with USB debugging on
adb reverse tcp:8000 tcp:8000
cd app
flutter run --dart-define=SERVER_URL=http://127.0.0.1:8000
```
Run `adb reverse` again after every reconnect. App tests: `flutter test`.

## API
| Endpoint | Description |
|---|---|
| `POST /api/solve` | multipart `image` + `metadata` (JSON) -> `{ra, dec, rotation, fov, confidence, approximate, source, message}` |
| `GET /api/providers` | image sources with metadata |
| `POST /api/sky-image` | JSON `{ra, dec, fov, rotation?, provider?, width?, height?}` -> JPEG; headers `X-Provider`, `X-Credit`, `X-Fallback-Used`, `X-Fallback-Reason`, `X-Fallback-Message` |
| `GET /api/landmarks?ra&dec&fov&rotation&aspect` | `{landmarks: [{id, name, type_label, magnitude, x, y, has_hires, ...}], pending}` |
| `GET /api/landmark-detail?id&provider&view` | `view` = `auto`/`jwst`/`hst`/`survey` -> `{image_jpeg_base64, image_source, credit, caption, fov, landmark}` |

Errors are `{"error": {"code", "message"}}`: `SOLVE_FAILED` (422), `PROVIDER_UNAVAILABLE` (503),
`NO_COVERAGE` (404), `INVALID_REQUEST` (400), `NOT_FOUND` (404), `CATALOG_UNAVAILABLE` (503).

`/solve` metadata (all optional; without location + orientation only plate solving is tried):
```json
{"latitude": 51.48, "longitude": -0.01, "altitude": 30, "timestamp": "2026-10-29T22:00:00Z",
 "orientation": {"quaternion": {"x": 0, "y": 0, "z": 0, "w": 1}, "reference": "magnetic_north"},
 "image_rotation_deg": 0, "fov_deg": 65}
```
Orientation follows the Android rotation-vector convention: device -> world, world =
East/North/Up, device = right/top-of-screen/out-of-screen; the rear camera looks along device -Z.
`rotation` in responses is the position angle of image-up, degrees east of north.

## Rate limits and failures
- Every external call has timeouts and a retry; a source that fails is skipped for 2 minutes.
- Survey images, landmark checks and mosaics are cached (rounded position/FOV/source), so
  repeated views don't hit the public services again.
- If every source fails the app keeps your photo and offers *Retry*; landmarks are optional and
  never block the result. A slow survey image can be cancelled.

## Notes
- tetra3's bundled database covers fields of 10-30 deg. Wide phone photos (~50-70 deg) often
  can't be solved and use the sensor position instead; a custom database
  (`Tetra3.generate_database(max_fov=...)`, then `TETRA3_DATABASE`) would fix that.
- SIMBAD isn't used for landmarks because some ISPs (e.g. Jio) can't reach CDS servers.

## Credits
DSS2, 2MASS, AllWISE and Pan-STARRS via CDS hips2fits, NASA SkyView and STScI; Mellinger mosaic
(c) Axel Mellinger; Hubble and JWST data (NASA/ESA/CSA) via ESA ESASky and MAST; object data
from OpenNGC (CC BY-SA 4.0) and the IAU Catalog of Star Names.
