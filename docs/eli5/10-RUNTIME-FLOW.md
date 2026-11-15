# 10 — Runtime Flow: What Happens Step-by-Step When NightSky Runs?

Think of this document as a **backstage tour with a stopwatch**, following one night-sky photo and one 3D planetarium spin from the moment your thumb taps the NightSky app icon all the way to the finished cosmic portrait on screen!

---

## 1. Startup: Turning On the Pocket Planetarium

1. **Tapping the App Icon (`app/lib/main.dart` → `main()`)**:
   - Flutter wakes up, locks the screen upright (`DeviceOrientation.portraitUp`) so tilt math never gets confused by sideways rotation, and wraps the app in `ProviderScope` (our shared bulletin board).
2. **Restoring Your Saved Notebook (`app/lib/settings.dart` → `SettingsNotifier.build()` & `_restore()`)**:
   - Sends `"load"` over the `night_sky/settings` wire to `MainActivity.kt`, reading your saved JSON settings from Android's `SharedPreferences`.
3. **Quietly Checking Museum Stories (`app/lib/main.dart` → `NightSkyAppShell.build()` → `CuratedIndexNotifier._sync()`)**:
   - Loads any previously saved `CuratedIndex` from phone storage right away, then quietly asks `GET /api/curated/index/` (sending `If-None-Match` with its saved `ETag`) if any new stories were published. If you're offline, it fails silently without bothering you.
4. **Choosing the Starting Room (`app/lib/main.dart` → `NightSkyApp.build()`)**:
   - Checks `settings.startInSkyView`:
     - **`false` (default)** → opens **`CameraScreen`** (the Sky Viewfinder Window).
     - **`true`** → opens **`SkyViewScreen`** (the Offline 3D Star Dome, skipping camera hardware completely).

---

## 2. Main Happy Path: Taking a Sky Photo → Magic Reveal → Webb Close-Up

### Numbered Journey of the Data

1. **Warming Up the Viewfinder (`app/lib/screens/camera_screen.dart` → `_CameraScreenState.initState()`)**:
   - `OrientationTracker.start()` (`sensors.dart`) opens the `night_sky/sensor_events` stream in `MainActivity.kt`, feeding gravity + compass readings into `OrientationEngine` (`sky_math.dart`), which keeps a rolling `0.6`-second buffer of **quaternions**.
   - `_initCamera()` starts the rear camera (flash locked off) and asks `CameraOptics.portraitFovDeg()` (`MainActivity.kt` → `fovFromOptics()`) to compute the lens's portrait width in degrees (e.g. `52.4°`).
   - `_initLocation()` (`LocationService.warmUp()`) asks GPS satellites for your latitude and longitude in the background so it is ready before you shoot.
   - `_tick()` runs 4 times a second, checking `OrientationEngine.shake()`. When shake stays under `1.5°`, `SteadyIndicator` turns green (and if `autoCapture` is on, triggers `_capture()` after 2.0 seconds).

2. **Snapping the Shutter (`CameraScreen._capture()`)**:
   - Averages the phone's tilt from the moment *just before* your finger tapped (`_orientation.averaged()`), stamps the UTC clock (`DateTime.now().toUtc()`), grabs the GPS fix, reads the raw camera JPEG bytes, bundles them into `CaptureMetadata`, calls `SessionNotifier.start(raw, meta)` (`state.dart`), and slides open **`ResultScreen`** (`"Your sky"`).

3. **Trimming the Photo Off-Screen (`app/lib/state.dart` → `compute(preparePhotoIsolate, rawPhoto)`)**:
   - On a background worker isolate (`photo_utils.dart` → `preparePhoto()`), NightSky rotates the raw multi-megabyte photo upright and shrinks its long side to `1600 px` (`PreparedPhoto`), keeping the loading spinner smooth at 60 fps.

4. **Asking the Star Detective (`ApiClient.solve()` → `POST /api/solve`)**:
   - `solver/views.py` (`solve`) checks upload size and passes the photo + metadata to `solver/services.py` (`solve()`).
   - `sensor_pointing()` (`solver/astro.py` → `pointing_from_matrix()`) converts your quaternion + GPS + UTC time + `pygeomag` magnetic declination into a compass sky guess `(ra, dec, rotation, alt, az)`.
   - `Tetra3Solver.solve()` (`solver/plate_solver.py`) hunts for star patterns in the grayscale image, verifies the match is within `25°` of the compass guess, and returns exact `(ra, dec, rotation, fov, confidence, approximate: false)`.

5. **Parallel Fan-Out: Sky Map Print + Object Pins (`SessionNotifier.start()`)**:
   As soon as `solve` returns, the phone fires **two requests at the same time**:
   - **5a — Sky Map Cutout (`ApiClient.skyImage()` → `POST /api/sky-image`)**:
     - `providers/views.py` → `providers/services.py` (`get_sky_image()`) checks the `"images"` cache cubby.
     - On a cache miss, `Hips2FitsProvider.fetch_cutout()` (`hips2fits.py`) asks CDS Strasbourg for `DSS2 Color` (or stitches tiles locally from ESA's mirror via `hips_render.py` if CDS is down).
     - Returns raw JPEG bytes + headers (`X-Provider`, `X-Credit`, `X-Fallback-Used`).
     - Back on the phone, `ResultScreen` plays `MagicReveal`'s 1.8-second star sparkle and displays `CompareView`!
   - **5b — Sky Pins (`ApiClient.landmarks()` → `GET /api/landmarks`)**:
     - `landmarks/views.py` → `landmarks/services.py` (`landmarks_in_field()`) calls `Catalog.query()` (`catalog.py`), finding famous stars and OpenNGC nebulae inside your photo's exact `(ra, dec, fov, rotation)` frame and spacing them ≥3.5% apart.
     - For each deep-sky object, `mast.status()` (`mast.py`) checks cache or submits a non-blocking background MAST lookup.
     - Back on the phone, `LandmarkOverlay` draws constant-size tappable rings over the sky image!

6. **Tapping a Pin → Verified Close-Up Kiosk (`ResultScreen._openLandmark()` → `LandmarkDetailScreen`)**:
   - Tapping a **Star** (or a nebula with `hasHires == false`) skips telescope probing completely and immediately requests `GET /api/landmark-detail?view=survey&provider=dss2_color`.
   - Tapping a **Deep-Sky Object** requests `GET /api/landmark-detail?view=auto&provider=dss2_color`:
     - `landmarks/services.py` (`available_missions()`) probes **Webb** (`jwst`) and **Hubble** (`hst`) tiles in parallel (`mosaic.locate()`), rejecting off-target stray frames (`covers_target`) or tiny slivers (`< 12%` coverage).
     - `_space_telescope()` fetches ground color (`_background()`), stitches seamless multi-instrument tiles (`mosaic.render()`), compresses blown-out cores (`tone.tame_jpeg()`), caches the finished `Detail`, and returns the image alongside `"available_views"` (e.g. `["jwst", "hst", "survey"]` or `["hst", "survey"]`).
     - `LandmarkDetailScreen` stores the image in `resolvedDetailCacheProvider` (so zero second download happens!) and shows **only** the verified chips (`Webb`, `Hubble`, `DSS2 Color`, plus `Curated Cosmic Highlights` if `CuratedIndex.has(id)` is true).

---

## 3. Sequence Diagram of the Photo → Reveal → Close-Up Journey

```mermaid
sequenceDiagram
    autonumber
    actor User as Stargazer
    participant Cam as CameraScreen + Sensors
    participant State as SessionNotifier (App)
    participant Solver as POST /api/solve
    participant Prov as POST /api/sky-image
    participant Lmk as GET /api/landmarks
    participant Detail as GET /api/landmark-detail

    User->>Cam: Aim at sky & tap Shutter (or hold steady 2s)
    Cam->>State: start(rawJpeg, GPS + Quaternion + FOV)
    Note over State: Background isolate resizes JPEG to <=1600px
    State->>Solver: Upload JPEG + metadata JSON
    Note over Solver: astro.py computes compass hint;<br/>tetra3 matches star triangles
    Solver-->>State: {ra, dec, rotation, fov, approximate}

    par Fetch Sky Survey & Landmark Pins Together
        State->>Prov: {ra, dec, fov, rotation, width, height}
        Note over Prov: Cache check -> CDS hips2fits<br/>(or ESA HiPS tile mirror)
        Prov-->>State: JPEG bytes + X-Provider / X-Credit headers
    and
        State->>Lmk: ?ra&dec&fov&rotation&aspect
        Note over Lmk: Catalog.query() + non-blocking mast.status()
        Lmk-->>State: {landmarks: [...], pending: true/false}
    end

    Note over User,State: ResultScreen ("Your sky") sparkles in with CompareView + Pins!

    User->>Detail: Tap gold marker (LandmarkDetailScreen)
    Note over Detail: Parallel locate(jwst, hst) -> covers_target check<br/>-> mosaic.render + tone.tame_jpeg
    Detail-->>User: Mosaic JPEG + verified available_views chips
```

---

## 4. Alternate Paths, Error Handling & Background Tasks

### A. Cloudy / Suburban Sky (Too Few Stars for `tetra3`)
- `Tetra3Solver.solve()` returns `None`.
- `solver/services.py` checks `pointing`:
  - **If phone sensors + GPS exist AND `pointing.alt >= -5°`**: Returns the sensor-derived `(ra, dec, rotation)` with `approximate: true`. `ResultScreen` shows an amber frosted **`Approximate position`** pill over the sky image; tapping it explains that phone sensors were used.
  - **If aimed at the floor (`pointing.alt < -5°`)**: Raises `SOLVE_FAILED (422)` *"The camera seems to be pointing below the horizon."*
  - **If both stars AND sensors/GPS are missing**: Raises `SOLVE_FAILED (422)` → `ResultScreen` shows `ErrorMessage` with a **"Take another"** button.

### B. External Astronomy Server Outage or Slow Connection
- **CDS Strasbourg unreachable**: `Hips2FitsProvider` catches the timeout on try #1 (`retries=0`), sets `hips2fits_cds_down` for 120 seconds, and immediately renders the exact same `DSS2 Color` cutout locally from ESA's `DSSColor` HiPS tiles (`hips_render.py`).
- **User taps "Cancel" while waiting for survey image**: `SessionNotifier.cancelImage()` cancels the `CancelToken`, keeps your solved coordinates and original photo on screen, and shows a polite banner with a **`Retry`** button.

### C. Background Polling for Gold Space-Telescope Rings
- When `/api/landmarks` sees an object never checked in MAST before, `mast.status()` queues a background thread (`_executor().submit(_run, ...)`) and immediately returns `has_hires: null` (`pending: true`).
- `LandmarkOverlay` draws that marker in subtle grey while `SessionNotifier._loadLandmarks()` quietly re-polls every `6` seconds (up to `6` times). As soon as MAST answers, the marker upgrades live on screen to a **gold ring** (Webb/Hubble available) or **light-blue ring** (catalog info + DSS2 close-up).

### D. Offline 3D Sky View Loop (60 Frames Per Second, Zero Internet)
1. `SkyViewScreen._ticker` fires every ~16.6 ms (`_onTick`): blends the latest quaternion from `OrientationTracker` (or advances `_anchorUtc` at `300×` speed during Timelapse!).
2. `magneticDeclinationDeg()` (`astro_math.dart`) applies offline WMM-2025 compass correction; `computeSolarSystem()` (`ephemeris.dart`, memoized to recalculate only when time shifts >5s) updates the Sun, Moon phase, and Mercury–Neptune; `SkyCamera` builds the 3D view matrices.
3. `SkySpherePainter` runs `sky_sphere.frag` on the GPU to paint the 8K Milky Way + twilight + night-vision tint, then calls `SkySceneRenderer.paint()` (`sky_overlay_painter.dart`) to draw constellations, temperature-colored stars, Moon phase crescent, Saturn's rings, non-overlapping labels, and the green search guide arrow!

---

## 5. One Concrete End-to-End Example: Photographing Orion (`M42`)

Let's follow **one real photo** from start to finish!

- **1. Input at the Shutter (`CameraScreen`)**:
  - You stand in **Bhopal, India** (`latitude: 23.26°`, `longitude: 77.41°`, `altitude: 500 m`) at `2026-11-12T20:30:00Z`, aiming South-East halfway up the sky at Orion's Sword.
  - Phone rear camera shoots a `4000 × 3000` (`4.8 MB`) JPEG; `CameraOptics` reports `fovDeg: 54.0`; `OrientationTracker.averaged()` produces `quaternion: [-0.42, 0.18, 0.21, 0.86]`.
- **2. After `preparePhotoIsolate()` (`photo_utils.dart`)**:
  - Resized cleanly to `1200 × 1600` portrait (`~310 KB` JPEG).
- **3. Inside `POST /api/solve` (`solver/`)**:
  - `pointing_from_matrix()` applies `+0.6°` WMM magnetic declination and computes compass hint: `ra ≈ 84.1°`, `dec ≈ -4.8°`, `alt ≈ 51.2°`, `az ≈ 148.0°`.
  - `Tetra3Solver` spots Orion's Belt & Sword stars in `42 ms`! Since `0.7° < 25°` from the compass hint, it returns:
    ```json
    {"ra": 83.82, "dec": -5.39, "rotation": 14.2, "fov": 53.6, "confidence": 0.9998, "approximate": false, "source": "plate_solve"}
    ```
- **4. Inside `POST /api/sky-image` & `GET /api/landmarks`**:
  - `skyImageSize(1200, 1600)` requests a `900 × 1200` `dss2_color` cutout centered on `(83.82°, -5.39°)` rotated `14.2°` → returns crisp optical JPEG showing Orion's nebulous clouds aligned right over your photo!
  - `/api/landmarks` returns markers including:
    - `NGC1976` (**Great Orion Nebula**, `M42`, `x: 0.50, y: 0.50, has_hires: true` → **gold ring**)
    - `HIP27989` (**Betelgeuse**, `x: 0.31, y: 0.24, has_hires: false` → **white star ring**)
    - `HIP26311` (**Alnilam**, `x: 0.49, y: 0.42, has_hires: false` → **white star ring**)
- **5. Tapping the Gold Ring on `Great Orion Nebula` (`GET /api/landmark-detail?id=NGC1976&view=auto&provider=dss2_color`)**:
  - `available_missions()` probes `jwst` and `hst` concurrently → both cover M42's core (`available_views: ["jwst", "hst", "survey"]`).
  - `_background()` notices `DSS2 Color` is burnt-out pure white (`~95%` saturated) over M42's bright Trapezium heart and automatically fetches unsaturated `2MASS` color for the underlay!
  - `mosaic.render("jwst", ...)` stitches **JWST NIRCam** infrared filaments (`1000 × 1000 px`), `tone.tame_jpeg()` balances the highlights, and `LandmarkDetailScreen` displays the breathtaking Webb mosaic with verified chips: **`[Curated Cosmic Highlights]  [Webb ✓]  [Hubble]  [DSS2 Color]`**!
