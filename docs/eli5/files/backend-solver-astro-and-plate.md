# The Star Detective's Magnifying Glass & Compass Math (`backend/solver/astro.py` & `plate_solver.py`)

**Files covered in this guide:**
- `backend/solver/astro.py`
- `backend/solver/plate_solver.py`

---

## Role
In our Backstage Astronomy Lab, these two files are the **Star Detective's Toolkit** — `plate_solver.py` is the magnifying glass that recognizes star patterns in a photo, while `astro.py` is the compass-and-globe calculator that works out where the phone was pointing from its motion sensors.

## Why They Exist
Without `plate_solver.py`, NightSky could never lock onto exact stars with pinpoint accuracy. Without `astro.py`, city light pollution or wide phone camera lenses (where stars look faint) would make the app fail completely instead of giving a smart sensor-based sky estimate — and `plate_solver.py` wouldn't have a compass sanity check to reject look-alike star triangles on the wrong side of the Earth!

## What's Inside
- **`astro.py` (Phone Tilt → Sky Coordinates)**:
  - Turns the phone's 3D tilt (**quaternion** or **rotation matrix**) into two arrows in the real world: which way the back camera looks (`view`) and which way the top edge of the photo points (`up`).
  - Uses the **World Magnetic Model** (`pygeomag`) to fix **magnetic declination** *(the angle difference between where a magnetic compass needle points and true geographic North at your spot on Earth)*.
  - Uses `astropy` alongside your GPS location and exact clock time to convert ground angles (**Altitude** — *how high above the horizon*, and **Azimuth** — *compass direction*) into eternal star-map coordinates (**RA** and **Dec**) plus the photo's tilt angle on the sky (`rotation`).
- **`plate_solver.py` (Star Fingerprint Matcher)**:
  - Prepares the uploaded photo (`load_image`): fixes sideways camera tags (**EXIF** — *hidden camera notes inside a photo file*), turns it black-and-white, and shrinks huge photos to `1600` pixels so star-finding stays fast.
  - Runs **`tetra3`** *(a fast star-pattern matcher created for spacecraft by the European Space Agency)* once in memory (`@lru_cache`) to find bright star dots and match four-star shapes against a built-in star catalog.
  - Double-checks `tetra3`'s answer against the phone's compass guess (`max_offset_deg = 25°`) so a random noisy speck pattern never tricks the detective into picking the wrong hemisphere.

## Talks To
- Called by `backend/solver/services.py` during `POST /api/solve`.
- Calls third-party science libraries `astropy`, `pygeomag`, `Pillow`, and `tetra3`.

---

## Important Code Blocks

### 1. Fixing Compass Drift & Turning Phone Tilt Into Sky Coordinates
**File:** `backend/solver/astro.py` (`pointing_from_matrix`)
```python
view, up = device_vectors(rotation_matrix, image_rotation_deg)
if reference == "magnetic_north":
    declination = magnetic_declination(lat, lon, alt_m, when)
    view, up = _rotate_about_up(view, declination), _rotate_about_up(up, declination)

up_point = view + UP_OFFSET_RAD * up
(alt0, az0), (alt1, az1) = _enu_to_altaz(view), _enu_to_altaz(up_point)
frame = AltAz(obstime=Time(when), location=EarthLocation(lat=lat * u.deg, lon=lon * u.deg, height=alt_m * u.m))
sky = SkyCoord(az=[az0, az1] * u.deg, alt=[alt0, alt1] * u.deg, frame=frame).icrs
```
- **In plain words:** First it finds which compass direction and height angle the phone's back camera is aiming, nudging the compass angle so magnetic North becomes true North. Then, knowing where on Earth you stand and what minute it is (since Earth spins!), it translates both the center of your photo and a tiny spot just "above" center onto the star map so it knows both *where* you aimed and *how crooked* you held the phone.
- **Why it matters:** Without measuring that second tiny spot (`up_point`), the sky image would be centered on the right stars but spun upside-down or sideways compared to your photo!
- **What goes in / what comes out:** Phone 3×3 rotation grid + GPS `(lat, lon, alt)` + UTC timestamp → `Pointing(ra, dec, rotation, alt, az)`.

### 2. Matching Star Patterns & Sanity-Checking Against the Compass
**File:** `backend/solver/plate_solver.py` (`Tetra3Solver.solve`)
```python
up_pixel = [h / 2 - h / 10, w / 2]  # (y, x) straight above image centre
kwargs = {"solve_timeout": settings.TETRA3_SOLVE_TIMEOUT_MS, "target_pixel": up_pixel}
if hint.fov:
    kwargs.update(fov_estimate=hint.fov, fov_max_error=max(2.0, hint.fov * 0.25))
sol = t3.solve_from_image(img, **kwargs)
if sol.get("RA") is None:
    return None
if hint.ra is not None and hint.dec is not None:
    if angular_distance(float(sol["RA"]), float(sol["Dec"]), hint.ra, hint.dec) > hint.max_offset_deg:
        return None
```
- **In plain words:** Hands the grayscale photo (plus the phone lens's width hint) to `tetra3` to hunt for star constellations. If `tetra3` finds a match, we check how far away that match is from where the phone's sensors say you were pointing — if they disagree by more than 25°, we throw the match out as a false alarm!
- **Why it matters:** Phone night photos have hot pixels and sensor grain that can occasionally mimic real stars. Requiring agreement with the phone's compass prevents wild mistakes.
- **What goes in / what comes out:** Grayscale `PIL.Image` + optional `SolveHint(ra, dec, fov)` → exact `SolveResult(ra, dec, rotation, fov, confidence)` or `None`.
