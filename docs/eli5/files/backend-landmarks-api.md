# The Tour Guide & Close-Up Desk (`backend/landmarks/services.py`, `views.py`, `serializers.py`, `urls.py`)

**Files covered in this guide:**
- `backend/landmarks/services.py`
- `backend/landmarks/views.py`
- `backend/landmarks/serializers.py`
- `backend/landmarks/urls.py`
- `backend/landmarks/apps.py`

---

## Role
In our Backstage Astronomy Lab, these files are the **Tour Guide's Service Counter** — answering *"What objects are inside my photo?"* (`GET /api/landmarks`) and *"Show me a close-up of this one object and tell me which telescopes actually have pictures of it!"* (`GET /api/landmark-detail`).

## Why They Exist
Without these files, the phone couldn't plot clickable markers on `"Your sky"` or open **Star View** (`LandmarkDetailScreen`) with verified telescope options (`Webb`, `Hubble`, `DSS2 Color`).

## What's Inside
- **`urls.py`, `serializers.py` & `views.py`**: Exposes `/api/landmarks` and `/api/landmark-detail`, checks query parameters (`ra`, `dec`, `fov`, `id`, `provider`, `view`), applies `HeavyRateThrottle` to close-up renders, and packages the close-up JPEG (as `base64` text — *binary image bytes spelled out using safe keyboard letters so they fit inside a JSON message*) alongside `available_views`, `credit`, `caption`, and `fov`.
- **`services.py` (Close-Up & Availability Coordinator)**:
  - `landmarks_in_field()`: Combines `Catalog.query()` with non-blocking `mast.status()` to return up to 20 markers plus `pending: True/False`.
  - `detail_fov()`: Picks a smart zoom width — wider (`0.75°–2.0°`) for dazzlingly bright stars like Betelgeuse so their glare doesn't fill the whole square, and tighter (`0.08°–5.0°`, 1.6× object size) for nebulae and galaxies.
  - `available_missions()`: Probes **Webb** (`jwst`) and **Hubble** (`hst`) in parallel and caches their exact sky boxes so the phone app learns immediately which telescope buttons really exist — and reuses those boxes so `locate()` never runs twice!
  - `_background()`: Uses `DSS2 Color` for color under telescope mosaics, quietly switching to an internal unsaturated infrared `2MASS` layer only when photographic DSS2 plates burn out to solid white on bright nebula cores.
  - `_resolve_detail_provider()`: Normalizes wide-field-only providers (like `Mellinger Color`) to sharp `DSS2 Color` on `auto` requests, and refuses to fake a survey image (`NO_COVERAGE`) if an unsupported survey is explicitly requested for a sub-degree close-up.

## Talks To
- Called by `app/lib/api_client.dart` (`landmarks()` and `landmarkDetail()`).
- Coordinates `catalog.py`, `mast.py`, `mosaic.py`, `tone.py`, and `providers/services.py` (`get_sky_image`).

---

## Important Code Blocks

### 1. Probing Both Space Telescopes in Parallel & Caching Verified Choices
**File:** `backend/landmarks/services.py` (`available_missions` & `landmark_detail`)
```python
def available_missions(lm) -> dict[str, tuple[float, float, float]]:
    if lm.kind != "dso" or mast.status(lm) is False:
        return {}
    cached = cache.get(_missions_key(lm.id))
    if cached is not None:
        return dict(cached)
    missions = ("jwst", "hst")
    with ThreadPoolExecutor(max_workers=len(missions)) as pool:
        boxes = list(pool.map(lambda m: _locate_mission(lm, m), missions))
    found = {m: box for m, box in zip(missions, boxes) if box is not None}
    cache.set(_missions_key(lm.id), found, MISSION_CACHE_TTL)
    return dict(found)
```
- **In plain words:** For stars (or deep-sky objects MAST already confirmed have no space-telescope photos), skip telescope checks in zero milliseconds! Otherwise, check both Webb and Hubble side-by-side at the same time, save whichever ones genuinely cover the target, and report that verified list (`available_views`) back to the phone app.
- **Why it matters:** Prevents the phone app from ever showing dead `Webb` or `Hubble` buttons when those telescopes haven't photographed that object, and pre-caches the framed coordinates so rendering the mosaic right afterward is twice as fast!
- **What goes in / what comes out:** A `Landmark` → dictionary mapping verified mission keys (`"jwst"`, `"hst"`) to `(ra, dec, fov)` framing boxes.
