# PROJECT: Night Sky Replacement App

## Goal
Build a mobile app where the user opens the camera, takes a photo of the night sky, and the app replaces that photo with a professional survey image of the exact same patch of sky. Sky coordinates come from a backend that processes the photo, using phone sensors as a hint. The user can switch between multiple image providers. Notable objects ("landmarks") in the field appear as small tappable markers that open a second-level, high-quality detail image.

## Tech stack (change only if you have a strong reason, and tell me why)
- Mobile: Flutter (Dart, null-safe). Packages: `camera`, `geolocator`, `dio`, and a fused-orientation package such as `flutter_rotation_sensor` (uses the Android rotation vector and iOS Core Motion). Do NOT use raw gyroscope data alone, it drifts. State management: Riverpod (or Provider, keep it simple).
- Backend: Python 3.11+, Django + Django REST Framework, `django-cors-headers`, astropy, astroquery, httpx, `pygeomag` (World Magnetic Model for declination).
- Plate solving: tetra3 (default, local) behind an adapter interface so Astrometry.net API or ASTAP can be swapped in.
- Caching: Django's cache framework (local-memory/file-based in dev, configurable for Redis later). No database models are required in v1; use SQLite only if Django needs it for defaults.
- Keep dependencies minimal. Config via environment variables and a `.env.example`; no secrets in code.

## Django project layout
- `config/` (settings, urls)
- `solver/` app: plate-solver adapter, sensor-to-RA/Dec conversion, `/api/solve`
- `providers/` app: image provider adapters, `/api/providers`, `/api/sky-image`
- `landmarks/` app: landmark lookup and detail, `/api/landmarks`, `/api/landmark-detail`
Keep business logic in plain Python service modules (not in views) so it can be unit tested without HTTP.

## Core flow
1. App captures a photo and, at the same moment, records: GPS lat/lon/altitude, UTC timestamp, fused device orientation (quaternion or rotation matrix plus the reference frame: true north or magnetic north), and camera field of view if available.
2. App uploads photo + metadata to `POST /api/solve`.
3. Backend converts the orientation to alt/az, applies magnetic declination if the reference is magnetic north, then to RA/Dec using astropy with the GPS location and time. This is the approximate pointing guess.
4. Backend plate-solves the photo using that guess and FOV as search constraints. Returns RA/Dec of center, rotation, field of view, and confidence.
5. If solving fails (clouds, light pollution, too few stars), return the sensor-derived position with `approximate: true`. The app must show a clear "approximate position" notice. If even sensors are unusable, return a friendly error.
6. App calls `POST /api/sky-image` with RA/Dec, rotation, FOV, and the chosen provider. The app shows the returned image in place of the user's photo, with a toggle/slider to compare against the original.
7. App calls `GET /api/landmarks` for the same field and draws a small dot/icon at each landmark's position over the image. Tapping one opens a second-level detail view with a high-quality image and info (name, type, magnitude/distance if known, source and credit).

## Image provider system (adapter pattern)
Abstract `ImageProvider` with:
- `name`, `description`, `wavelength/type`, `coverage`
- `fetch_cutout(ra, dec, fov_deg, rotation_deg, width_px, height_px) -> image bytes`
- `supports(ra, dec) -> bool` (handles partial coverage, e.g. Pan-STARRS only north of about -30 deg declination)

Implement:
1. CDS hips2fits (default; many HiPS surveys such as DSS2 color, 2MASS, WISE, Pan-STARRS)
2. NASA SkyView (HEASARC)
3. Pan-STARRS cutout (via hips2fits or its own service)
Adding a provider must be a one-file change plus one registry line. `GET /api/providers` returns metadata so the Flutter app builds its provider picker dynamically. If the selected provider doesn't cover the position, auto-fall back to an all-sky provider and tell the user.

## Landmark system (second level)
- Query SIMBAD (astroquery) and/or the OpenNGC catalog for Messier/NGC objects and bright named stars inside the field.
- For each landmark, check MAST (Hubble, JWST, Chandra previews) with a cone search; set `has_hires: true/false`.
- Landmarks without a high-res image still show as markers in a visually different style with basic info.
- Detail view fetches the best available image (MAST preview first, else a tight narrow-FOV cutout from the selected provider). Always show credit and data source.
- Cap the number of markers per view and prioritize by brightness/importance to avoid clutter.

## API contract
- `POST /api/solve` (multipart: image + JSON metadata) -> `{ra, dec, rotation, fov, confidence, approximate}`
- `GET /api/providers`
- `POST /api/sky-image` -> image bytes + metadata headers (provider used, fallback used)
- `GET /api/landmarks?ra&dec&fov`
- `GET /api/landmark-detail?id=...&provider=...`
Use DRF serializers and clear error codes (`SOLVE_FAILED`, `PROVIDER_UNAVAILABLE`, `NO_COVERAGE`).

## Non-functional requirements
- Cache provider responses and landmark queries (keyed by rounded RA/Dec/FOV/provider) to respect public-service rate limits.
- Timeouts and retries on all external calls; degrade gracefully when a service is down.
- Plate solving is CPU-heavy: set sensible server timeouts and note in the README how to run with gunicorn.
- Downscale uploaded photos before sending (max ~1600px long side).
- In the Flutter app: request camera and location permissions properly, handle denial, show loading and error states, and tell the user to hold steady, use Night mode, and avoid city lights.
- README with setup/run steps for both backend and app, and a short "how to add a provider" section.

## Phased delivery (stop after each phase and wait for my go-ahead)
Phase 1: Django backend with the provider adapter + hips2fits provider, plus a management command: given RA/Dec/FOV, save a cutout image. Add the plate-solver adapter with tetra3 tested on a sample image.
Phase 2: DRF endpoints (/solve, /providers, /sky-image) with sensor-based fallback and caching. Unit tests for the orientation -> RA/Dec conversion using known reference values.
Phase 3: Flutter app: camera capture, sensor/GPS/time collection, upload, display replaced image with compare toggle, provider picker.
Phase 4: Landmarks: backend endpoints, marker overlay in Flutter, second-level detail view with MAST high-res images.
Phase 5: Polish: error states, rate-limit handling, README.

## Working rules
- Before each phase, give a short plan (under 10 lines) and list the files you'll create.
- Write minimal, readable code; no abstractions beyond the provider/solver adapters.
- Don't re-print unchanged files; show only new files or diffs.
- If a requirement is ambiguous, pick the sensible default, state it in one line, and continue.
