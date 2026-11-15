# The Sky Map Print Shop Core (`backend/providers/` — Registry, Service & API)

**Files covered in this guide:**
- `backend/providers/base.py`
- `backend/providers/registry.py`
- `backend/providers/services.py`
- `backend/providers/views.py`
- `backend/providers/serializers.py`
- `backend/providers/urls.py`
- `backend/providers/apps.py`
- `backend/providers/management/commands/cutout.py`

---

## Role
In our Backstage Astronomy Lab, these files are the **Sky Map Print Shop Manager** — they keep the menu of available sky surveys, check the fast photo cubby before ordering a fresh print, switch to a backup printer if a server goes offline, and stamp credit labels onto every finished picture.

## Why They Exist
Without these files, the phone app wouldn't know which sky surveys exist (`GET /api/providers`), couldn't fetch a survey picture matching your photo (`POST /api/sky-image`), and would waste time re-downloading the exact same patch of sky or freezing for minutes when an outside server goes down.

## What's Inside
- **`base.py` (The Printer Blueprint)**: Defines `ImageProvider` — a standard contract every sky survey printer must follow (`supports()`, `fetch_cutout()`, `metadata()`, including `supports_detail` to separate sharp close-up surveys from wide-angle panoramas).
- **`registry.py` (The Curated Menu)**: Registers the two all-sky optical sources:
  1. **`DSS2 Color` (`dss2_color`)**: High-detail photographic sky plates suitable for both wide camera views and tight star/nebula close-ups (`supports_detail = True`).
  2. **`Mellinger Color` (`skyview_mellinger`)**: Axel Mellinger's wide-angle Milky Way panorama, built specifically for wide camera fields (`min_fov_deg = 5.0`, `supports_detail = False`).
- **`services.py` (The Smart Print Dispatcher)**: Rounds coordinates to ~3.6 arcseconds to check the `"images"` cache first, remembers if an external server failed in the last 2 minutes (`_down_key`) so future requests skip it immediately, and optionally falls back to another wide-field printer on server outages (or refuses substitution when `allow_fallback=False` in close-ups).
- **`views.py`, `serializers.py` & `urls.py`**: Exposes `/api/providers` and `/api/sky-image`, enforces a `3,000,000` max pixel cap (`width × height`) so nobody exhausts server RAM, and returns raw JPEG bytes with metadata tucked into custom **HTTP headers** *(short label lines attached to the outside of a web reply, like `X-Provider` and `X-Credit`)*.
- **`management/commands/cutout.py`**: A handy developer command (`python manage.py cutout 83.82 -5.39 2.0 -o orion.jpg`) to print a sky patch straight to disk from a terminal.

## Talks To
- Called by `app/lib/api_client.dart` (`/api/providers`, `/api/sky-image`) and by `backend/landmarks/services.py` (for Star View survey close-ups and mosaic color underlays).
- Delegates actual image fetching to `hips2fits.py` and `skyview.py`.

---

## Important Code Blocks

### 1. Caching Sky Prints & Skipping Recently Broken Servers
**File:** `backend/providers/services.py` (`_fetch` & `get_sky_image`)
```python
def _fetch(provider: ImageProvider, ra, dec, fov, rotation, width, height) -> bytes:
    key = cache_key(provider.key, ra, dec, fov, rotation, width, height)
    data = caches["images"].get(key)
    if data is not None:
        return data
    if cache.get(_down_key(provider)):
        raise ProviderError(f"{provider.name} recently failed; skipping for now")
    try:
        data = provider.fetch_cutout(ra, dec, fov, rotation, width, height)
    except ProviderError:
        cache.set(_down_key(provider), True, settings.PROVIDER_DOWN_SECONDS)
        raise
```
- **In plain words:** Before calling a space agency across the ocean, check if we already printed almost this exact sky rectangle recently. If not, check a sticky note to see if that space agency crashed within the last 2 minutes — if it did, skip straight to the backup instead of making the user wait 25 seconds for another timeout!
- **Why it matters:** Keeps the app feeling snappy and prevents one slow astronomy server from causing a traffic jam.
- **What goes in / what comes out:** Survey provider + sky coordinates/size → JPEG bytes (from cache or fresh download).

### 2. Sending Both Picture Pixels and Credits in a Single Reply
**File:** `backend/providers/views.py` (`sky_image`)
```python
resp = HttpResponse(result.data, content_type="image/jpeg")
resp["X-Provider"] = result.provider.key
resp["X-Provider-Name"] = _ascii(result.provider.name)
resp["X-Credit"] = _ascii(result.provider.credit)
resp["X-Fallback-Used"] = "true" if result.fallback_used else "false"
```
- **In plain words:** Sends the JPEG photo directly as binary bytes (much smaller and faster than converting it to text!) while writing the survey's name, scientific credit, and fallback status onto the envelope's header lines.
- **Why it matters:** Saves ~33% bandwidth compared to text encoding (`base64`) while still telling the phone app who deserves credit and whether a backup source stepped in.
- **What goes in / what comes out:** Validated sky rectangle request → binary `image/jpeg` HTTP response with `X-*` headers.
