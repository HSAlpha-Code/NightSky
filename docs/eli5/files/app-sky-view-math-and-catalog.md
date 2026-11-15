# The 3D Star Dome's Offline Clockwork, Orbits & Star Book (`astro_math.dart`, `ephemeris.dart`, `sky_catalog.dart`, `panorama_loader.dart`)

**Files covered in this guide:**
- `app/lib/sky_view/astro_math.dart`
- `app/lib/sky_view/ephemeris.dart`
- `app/lib/sky_view/sky_catalog.dart`
- `app/lib/sky_view/panorama_loader.dart`

---

## Role
In our Handheld Planetarium, these four files are the **Mechanical Orrery (Planet Gearwork), Offline Star Atlas, and Dome Wallpaper Unroller** — calculating where every star, constellation, planet, the Sun, and the Moon sit at any minute between 1950 and 2050 with zero internet connection!

## Why They Exist
While stars stay in almost the exact same pattern for human lifetimes, Earth spins once every 23 hours 56 minutes, Earth's axis slowly wobbles like a spinning top (**precession**), compass needles drift away from true North, and the Moon and planets wander across constellations every night! Without these four offline engines, Sky View couldn't work in airplane mode or scrub smoothly through time.

## What's Inside
- **`astro_math.dart` (3D Sky Camera, Earth Spin & Offline Magnetic Map)**:
  - Computes **Sidereal Time** *(star-clock time telling which constellations are overhead at your longitude right now)* and Earth's axis wobble (`precessionJ2000ToDate`).
  - Bundles NOAA's **World Magnetic Model (`WMM-2025`)** right inside Dart (`magneticDeclinationDeg`) so your phone's compass aligns to true North offline anywhere on Earth!
  - Builds `SkyCamera`, which projects 3D star directions onto 2D phone pixels (`projectIcrs`), unprojects finger taps back into space (`unprojectToIcrs`), and computes the perimeter arrow toward off-screen targets (`guideTowards`).
- **`ephemeris.dart` (The Solar System Gearwork)**:
  - Computes **ephemeris** *(a fancy astronomy word for a schedule of where the Sun, Moon, and planets are at a chosen moment)* using NASA JPL's orbital formulas (**Kepler's equation**) — even subtracting **light-time** *(the minutes sunlight takes to bounce off Jupiter or Saturn and reach your eyes!)*
  - Computes the Moon's exact position using Jean Meeus's lunar wave formulas plus **topocentric parallax** *(nudging the Moon by up to ~1° depending on which continent you stand on, because the Moon is close enough to Earth that two cities see it against slightly different background stars!)* and calculates its lit crescent percentage (`New Moon`, `Waxing Crescent`, `Full Moon`, etc.).
- **`sky_catalog.dart` (The Super-Compact Offline Star Book)**:
  - Unpacks `stars.bin` — **8,874 naked-eye stars** squeezed into just **12 bytes per star** (`104 KB` total!), sorted brightest-first, and colors each star by surface temperature (`bvToStarColor` — hot blue-white Rigel to cool orange-red Betelgeuse!).
  - Loads `sky_catalog.json` (574 proper star names, all 88 constellation stick figures pre-converted into 3D vectors so drawing needs zero slow trig math, and 145 bright deep-sky objects).
- **`panorama_loader.dart` (The Dual-Hemisphere 8K Wallpaper Loader)**:
  - Decodes the Milky Way panorama split into two square `East` and `West` halves (`1600²` Power Saver, `3200²` Balanced Retina, or `4096²` full `8192×4096` 8K Max Detail) so older mobile graphics chips whose texture limit is `4096 px` never choke, and retires old resolutions after the current frame finishes drawing (`addPostFrameCallback`) so textures never blink black!

## Talks To
- Watched and driven at up to 60 frames per second by `SkyViewScreen`, `SkySpherePainter`, `SkySceneRenderer`, and `SkySearchSheet`.

---

## Important Code Blocks

### 1. Unpacking 8,874 Colored Stars From Just 12 Bytes Per Star
**File:** `app/lib/sky_view/sky_catalog.dart` (`SkyCatalog.parse`)
```dart
final hip = starsBin.getUint32(base, Endian.little);
final raQ = starsBin.getUint16(base + 4, Endian.little);
final decQ = starsBin.getInt16(base + 6, Endian.little);
final magMmag = starsBin.getInt16(base + 8, Endian.little);
final bvCent = starsBin.getInt8(base + 10);
final raDeg = (raQ / 65535.0) * 360.0;
final decDeg = (decQ / 32767.0) * 90.0;
```
- **In plain words:** Instead of a bulky text file, every star is packed into 12 tiny bytes: 4 bytes for its Hipparcos ID number, 2 bytes each for sky longitude (`RA`), sky latitude (`Dec`), and brightness (`mag`), and 1 byte for its color temperature (`B−V`)! At load time, all 8,874 stars unpack into flat number lists (`Float32List`) in a few milliseconds.
- **Why it matters:** Keeps the app download tiny (`104 KB`) and lets the star painter loop through thousands of stars at 60 frames per second without creating garbage memory.
- **What goes in / what comes out:** `stars.bin` bytes + `sky_catalog.json` text → ready-to-draw `SkyCatalog`.

### 2. Shifting the Moon for Your Exact Spot on Earth's Surface
**File:** `app/lib/sky_view/ephemeris.dart` (`_computeMoon`)
```dart
final obsX = math.cos(lat) * math.cos(lst);
final obsY = math.cos(lat) * math.sin(lst);
final obsZ = math.sin(lat);
final topoDate = Vec3(xDate - obsX, yDate - obsY, zDate - obsZ);
```
- **In plain words:** Standard formulas place the Moon as seen from the *center* of the Earth (`xDate, yDate, zDate`, measured in Earth-radii `~60 R⊕`). Subtracting `(obsX, obsY, obsZ)` — your actual position standing on Earth's crust 1 Earth-radius out from the center — shifts the Moon to where *you* really see it overhead!
- **Why it matters:** Without this 1-Earth-radius shift, the Moon in Sky View could sit up to two full Moon-widths (`~1°`) off from where it hangs in your real window!
- **What goes in / what comes out:** UTC time + observer `(lat, lon)` → topocentric `SkyObject` for the Moon with exact phase and distance in km.
