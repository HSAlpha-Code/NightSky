# The Dome Wallpaper Press, Icon Stamper & Quality Inspectors (`app/tool/` & Test Suites)

**Files covered in this guide:**
- `app/tool/sky_data/prepare_mellinger.py`
- `app/tool/sky_data/prepare_catalogs.py`
- `app/tool/icon/make_icons.py`
- Backend test suites: `backend/solver/test_astro.py`, `solver/test_api.py`, `solver/tests.py`, `providers/tests.py`, `providers/test_api.py`, `landmarks/tests.py`, `curated/tests.py`
- App test suites: `app/test/fake_backend.dart`, `api_client_test.dart`, `session_test.dart`, `settings_test.dart`, `sky_math_test.dart`, `orientation_test.dart`, `widgets_test.dart`, `curated_test.dart`, `sky_view_math_and_alignment_test.dart`, `sky_view_widget_test.dart`

---

## Role
In our Planetarium analogy, `app/tool/` is the **Offline Printing Press** where the planetarium's 8K Milky Way dome wallpaper, pocket star book, and front-door sign (app icon) are manufactured before opening day — while the `tests` folders are the **Safety Inspectors** who check every gear, lens, and button automatically!

## Why They Exist
1. Asking NASA SkyView for a single giant all-sky picture gives a blurry low-resolution thumbnail because SkyView switches to a coarse overview above `30°`. `prepare_mellinger.py` bypasses that limit by downloading **114 overlapping `27°×27°` sharp camera plates** and feather-stitching them into a true 8K panorama!
2. Raw astronomy catalogs are tens of megabytes of text; `prepare_catalogs.py` distills them into a `104 KB` binary star file (`stars.bin`) + `66 KB` JSON file (`sky_catalog.json`) with matching IDs so Sky View and the Backstage Lab speak the exact same language.
3. Automated tests catch bugs (like left-edge touch dead-zones, narrow-screen button clipping, or stray space-telescope frames) in seconds without needing a clear night outside!

## What's Inside
- **`prepare_mellinger.py` (The 114-Plate 8K Dome Stitcher)**:
  - Downloads 114 `756×756` (`27°`) Mellinger plates from NASA SkyView in parallel, projects them onto an `8192×4096` Galactic map using raised-cosine edge feathering so tile borders vanish, verifies star alignment (`verify_alignment`) on 6 bright landmarks across both hemispheres (Sirius, Vega, Arcturus, Fomalhaut, Achernar, M31) to within `< 0.20°`, and splits the result into `mellinger_east.webp` and `mellinger_west.webp` (`4096×4096` each).
- **`prepare_catalogs.py` (The Star & Constellation Packer)**:
  - Combines `d3-celestial` Hipparcos stars with official IAU proper star names, sorts all 8,874 naked-eye stars (`V ≤ 6.5`) brightest-first so Power Saver mode can stop early, packs them into 12-byte binary rows (`NSKY` header), merges `Ser1`/`Ser2` into all 88 IAU constellations, selects 145 Messier/curated/bright deep-sky gems from OpenNGC, and regenerates `SOURCES.md`.
- **`make_icons.py` (The App Icon Stamper)**:
  - Pads `nightsky_icon_source.png` cleanly to a square by repeating edge colors and exports crisp Android legacy + adaptive launcher icons (`mdpi` through `xxxhdpi`).
- **Backend & App Test Suites**:
  - **Backend (`manage.py test`)**: Verifies quaternion-to-sky coordinate math, `tetra3` plate solving & sensor fallbacks, CDS-to-ESA mirror failover, `DSS2` vs. field-only `Mellinger` rules, OpenNGC/WGSN parsing, `MAST` background workers, `mosaic.locate` target-core validation, highlight tone-compression, and `ETag` curated bundles.
  - **Flutter (`flutter test`)**: Uses `FakeBackend` (an in-memory pretend server so tests never touch the real internet) to verify session state transitions, cancellations, left-edge landmark clicks, 360dp narrow-screen HUD layout, verified Star View telescope chips, curated swipe dots, and offline Solar System/WMM-2025 accuracy.

## Talks To
- `prepare_mellinger.py` and `prepare_catalogs.py` write `app/assets/sky/*`, which `panorama_loader.dart` and `sky_catalog.dart` load at runtime.
- `make_icons.py` writes `app/android/app/src/main/res/mipmap-*`.

---

## Important Code Blocks

### 1. Proving the 8K Milky Way Wallpaper Lines Up With Real Stars
**File:** `app/tool/sky_data/prepare_mellinger.py` (`verify_alignment`)
```python
px = ((w / 2.0 - 0.5) - l_deg * (w / 360.0)) % w
py = (h / 2.0 - 0.5) - b_deg * (h / 180.0)
...
cx = float((weights * xx).sum() / weights.sum())
cy = float((weights * yy).sum() / weights.sum())
offset_deg = math.hypot(cx, cy) * (360.0 / w)
if offset_deg > 0.20 or peak < bg + 80:
    raise AssertionError(f"Alignment check failed for {label}: offset={offset_deg:.3f} deg")
```
- **In plain words:** After stitching all 114 Milky Way tiles together, this quality inspector checks 6 famous stars and galaxies (like Sirius and Andromeda) on the finished 8K picture, measures the bright star dot's center of gravity, and refuses to save the file if any star is off by even a fifth of a degree!
- **Why it matters:** Guarantees that vector star dots painted on top of the Milky Way wallpaper in Sky View land dead-center on the photograph's own stars!
- **What goes in / what comes out:** Stitched `8192×4096` `PIL.Image` → verified alignment pass (or `AssertionError`).

### 2. Packing Each Star Into 12 Tight Binary Bytes Sorted Brightest-First
**File:** `app/tool/sky_data/prepare_catalogs.py` (`build_stars`)
```python
records.sort(key=lambda r: (r[0], r[1]))  # sort by magnitude (brightest first)
...
ra_q = int(round((ra % 360.0) / 360.0 * 65535)) & 0xFFFF
dec_q = max(-32767, min(32767, int(round(dec / 90.0 * 32767))))
mag_mmag = max(-32767, min(32767, int(round(mag * 1000.0))))
bv_c = max(-127, min(127, int(round(max(-0.5, min(2.5, bv)) * 50.0))))
buf.extend(struct.pack("<IHhhbB", hip, ra_q, dec_q, mag_mmag, bv_c, flags))
```
- **In plain words:** Sorts all 8,874 stars from brightest (Sirius at `-1.46`) to faintest (`+6.50`), then scales each decimal angle into whole-number ticks that fit neatly inside 16-bit and 8-bit integer slots.
- **Why it matters:** Because the list is pre-sorted brightest-first, when an older phone runs in *Power Saver* mode (stopping at magnitude `5.2`), the star loop in `sky_overlay_painter.dart` simply hits `break` partway through and skips thousands of fainter stars automatically!
- **What goes in / what comes out:** Hipparcos + IAU JSON/CSV catalogs → `104 KB` `stars.bin` file.
