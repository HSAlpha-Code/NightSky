# The Star Detective's Reception Desk (`backend/solver/services.py`, `views.py`, `serializers.py`, `urls.py`)

**Files covered in this guide:**
- `backend/solver/services.py`
- `backend/solver/views.py`
- `backend/solver/serializers.py`
- `backend/solver/urls.py`
- `backend/solver/apps.py`

---

## Role
These files are the **Star Detective's Office Door and Decision Playbook** — they check the visitor's photo envelope at `POST /api/solve`, run star-matching first, and fall back to the phone's compass if clouds or city glare hide too many stars.

## Why They Exist
Without these files, the phone app would have no `/api/solve` doorway to send photos to, invalid numbers (like a latitude of `500°` or a photo of your shoes!) wouldn't be caught politely, and there would be no smooth teamwork between exact star matching and approximate sensor pointing.

## What's Inside
- **`urls.py` & `views.py`**: Opens the `/api/solve` web address (with or without a trailing `/`), protects it with `HeavyRateThrottle`, unpacks the uploaded photo + JSON metadata, and sends back the solved sky coordinates.
- **`serializers.py` (The Form Inspector)**: Checks that the uploaded file is under 4 MB and validates optional sensor fields (`latitude`, `longitude`, `altitude`, `timestamp`, `quaternion` or `rotation_matrix`, `fov_deg`) before any math runs.
- **`services.py` (The Two-Step Playbook)**:
  1. Checks that the uploaded file actually opens as a real image.
  2. Computes the phone sensor pointing (if sensors and GPS were included).
  3. Tries exact star plate-solving (`Tetra3Solver`), passing the sensor guess as a hint.
  4. If stars matched → returns `approximate: False` (`source: "plate_solve"`).
  5. If too few stars matched → checks that the phone wasn't aimed at the ground (`alt < -5°`), then returns the sensor sky position marked `approximate: True` (`source: "sensors"`).

## Talks To
- Called by `app/lib/api_client.dart` (`solve()`).
- Calls `backend/solver/astro.py` and `backend/solver/plate_solver.py`.
- Raises `ApiError` handled by `backend/config/errors.py`.

---

## Important Code Blocks

### 1. The Detective's Two-Plan Strategy (Stars First, Sensors Second, Shoes Rejected!)
**File:** `backend/solver/services.py` (`solve`)
```python
result = get_solver().solve(image, hint)
if result is not None:
    return {"ra": result.ra, "dec": result.dec, "rotation": result.rotation, "fov": result.fov,
            "confidence": result.confidence, "approximate": False, "source": "plate_solve",
            "message": "", **alt_az}

if pointing is None:
    raise ApiError(SOLVE_FAILED, "We couldn't find enough stars in this photo...", 422)
if pointing.alt < BELOW_HORIZON_DEG:
    raise ApiError(SOLVE_FAILED, "The camera seems to be pointing below the horizon...", 422)
return {"ra": pointing.ra, "dec": pointing.dec, ..., "approximate": True, "source": "sensors"}
```
- **In plain words:** First try to recognize real stars in the photo. If that works, celebrate and return the exact coordinates! If not (for example, bright city streetlights washed out the stars), check whether the phone sensors know where you aimed — and make sure you weren't aiming down at the sidewalk (`< -5°` below the horizon) — before returning a helpful approximate sensor position.
- **Why it matters:** Real-world phone cameras struggle in suburbs and cities. Instead of showing an unhelpful error every time, NightSky still shows you what stars sit behind the city glow, while honestly labeling the result **"Approximate position"**.
- **What goes in / what comes out:** Raw JPEG bytes + sensor dictionary → sky pointing dictionary (`ra`, `dec`, `rotation`, `fov`, `approximate`, `source`).
