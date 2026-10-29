# Night Sky Replacement App

Status: **Phase 3** (backend API + Android Flutter app). Full docs are added in Phase 5.

## Flutter app (Android)
Requires the Android SDK (`flutter doctor` must show the Android toolchain).
```bash
cd app
flutter pub get
flutter test                      # unit + widget tests
# Backend must listen on all interfaces so the phone can reach it:
#   cd backend && .venv/bin/python manage.py runserver 0.0.0.0:8000
flutter run --dart-define=SERVER_URL=http://<your-computer-ip>:8000   # real phone
flutter run                                                          # emulator (uses 10.0.2.2:8000)
```
The server address can also be changed in the app (Settings → Save and test connection).
- Locked to portrait; capture orientation locked too, so `image_rotation_deg` is always 0.
- Orientation: Android rotation vector (fused, magnetic north) via `flutter_rotation_sensor`
  in the *device* coordinate system, averaged over the 0.6 s before the shutter.
- FOV: from camera2 focal length and sensor size (`MainActivity.kt`), portrait width.
- Photos are EXIF-rotated and downscaled to 1600 px (long side) in a background isolate.

## API (Phase 2)
| Endpoint | Description |
|---|---|
| `POST /api/solve` | multipart: `image` + `metadata` (JSON string, below) → `{ra, dec, rotation, fov, confidence, approximate, source, message, alt, az}` |
| `GET /api/providers` | `{default, providers: [{key, name, description, wavelength, coverage, all_sky, service, credit}]}` |
| `POST /api/sky-image` | JSON `{ra, dec, fov, rotation?, provider?, width?, height?}` → JPEG + headers `X-Provider`, `X-Provider-Name`, `X-Credit`, `X-Fallback-Used`, `X-Fallback-Reason`, `X-Fallback-Message` |

Errors: `{"error": {"code", "message", "details?"}}` with codes `SOLVE_FAILED` (422),
`PROVIDER_UNAVAILABLE` (503), `NO_COVERAGE` (404), `INVALID_REQUEST` (400).

`/solve` metadata (all optional; without location + orientation only plate solving is attempted):
```json
{"latitude": 51.48, "longitude": -0.01, "altitude": 30, "timestamp": "2026-10-29T22:00:00Z",
 "orientation": {"quaternion": {"x": 0, "y": 0, "z": 0, "w": 1}, "reference": "magnetic_north"},
 "image_rotation_deg": 0, "fov_deg": 65}
```
Orientation uses the Android/flutter_rotation_sensor convention: rotates device → world, world =
East/North/Up, device = right/top-of-screen/out-of-screen, rear camera looks along device −Z.
`rotation_matrix` (9 floats, row-major) may be sent instead of `quaternion`.
`image_rotation_deg` (0/90/180/270) says which device edge is "up" in the upright photo.
`rotation` in responses is the position angle of image-up, degrees east of north.

Run: `.venv/bin/python manage.py runserver 0.0.0.0:8000`, or for production (plate solving is CPU-heavy):
```bash
.venv/bin/gunicorn config.wsgi -w 2 --threads 2 --timeout 120 -b 0.0.0.0:8000
```

## Backend setup
```bash
cd backend
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt   # tetra3 is installed from GitHub (~50 MB database)
cp .env.example .env
.venv/bin/python manage.py check
```

### Save a cutout
```bash
.venv/bin/python manage.py cutout 83.82 -5.39 2.0 -o orion.jpg              # M42, default DSS2 colour
.venv/bin/python manage.py cutout 10.68 41.27 3 -p panstarrs_hips -o m31.jpg  # Pan-STARRS
```

### Tests
The tetra3 sample test needs tetra3's example image:
```bash
mkdir -p samples && curl -L -o samples/tetra3_alt40.tiff \
  https://raw.githubusercontent.com/esa/tetra3/master/examples/data/2019-07-29T204726_Alt40_Azi-135_Try1.tiff
.venv/bin/python manage.py test
```

## Notes
- tetra3's bundled database covers FOVs of **10–30°** (stars to mag 7). Phone main cameras
  (~60–70° FOV) may need a custom database built with `Tetra3.generate_database(max_fov=...)`;
  point `TETRA3_DATABASE` at the generated file.
- tetra3 uses `np.math`, which was removed in NumPy 2; `solver/plate_solver.py` patches it in.
