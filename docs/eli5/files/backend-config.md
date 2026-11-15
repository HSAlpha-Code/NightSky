# Backstage Lab Front Desk & Safety Rules (`backend/config/`)

**Files covered in this guide:**
- `backend/config/settings.py`
- `backend/config/urls.py`
- `backend/config/wsgi.py`
- `backend/config/middleware.py`
- `backend/config/errors.py`
- `backend/config/throttles.py`
- `backend/config/http.py`
- `backend/config/images.py`

---

## Role
`backend/config/` is the **Front Desk, Switchboard, Security Guard, and Mailroom** of the Backstage Astronomy Lab — every message from the phone enters here first, and every outgoing call to NASA or European space archives goes out through its safety checks.

## Why It Exists
Without `config/`, the lab wouldn't know which scientist handles which request, a prankster uploading a giant fake image could crash the server's memory, a slow external astronomy website could freeze the server forever, and errors would come back as ugly web crash pages instead of tidy messages the phone app can read.

## What's Inside
- **`settings.py` (The Master Rulebook)**: Reads `.env` settings, redirects temporary scratch folders to `/tmp` when running on read-only cloud servers, sets upload size limits (4 MB max photo, pixel caps against "decompression bombs"), creates **two separate memory caches** *(fast short-term cubbies — one for big JPEG pictures and one for small facts so big pictures don't push out small facts)*, and stores URLs for CDS, ESA ESASky, NASA SkyView, and MAST.
- **`urls.py` & `wsgi.py` (The Reception Switchboard & Front Door)**: `wsgi.py` is the plug where cloud servers connect to Django; `urls.py` routes `/api/solve` to the Star Detective, `/api/providers` and `/api/sky-image` to the Sky Map Printers, `/api/landmarks*` to the Tour Guide, and `/api/curated/*` to the Museum Story Vault.
- **`throttles.py` & `middleware.py` (The Hall Monitors)**: Limits each visitor IP address to `120` light requests per minute and `20` heavy image-building requests per minute (`HeavyRateThrottle`), and stamps strict browser security headers onto every reply.
- **`errors.py` (The Polite Note Writer)**: Catches every expected or unexpected problem and wraps it into one predictable **JSON** *(structured text format computers use to trade labeled values)* envelope: `{"error": {"code": "...", "message": "..."}}`.
- **`http.py` (The Outgoing Phone Operator)**: Makes all internet calls from the lab to space archives with strict time limits (`25s` read, `5s` connect) and automatic retries with **exponential backoff** *(waiting a little longer before trying a busy website again)*.
- **`images.py` (The Package X-Ray Scanner)**: Inspects the pixel dimensions of images downloaded from outside servers *before* decoding them into memory so a corrupted or huge file can never blow up RAM.

## Talks To
- Receives HTTP calls from `app/lib/api_client.dart`.
- Dispatches work to `solver/`, `providers/`, `landmarks/`, and `curated/`.
- Used by `providers/` and `landmarks/` whenever they call external astronomy servers (`http.py`) or open downloaded sky images (`images.py`).

---

## Important Code Blocks

### 1. Two Separate Memory Cubbies (`default` vs. `images`)
**File:** `backend/config/settings.py` (`CACHES`)
```python
CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
        "LOCATION": "default", "TIMEOUT": _cache_timeout,
        "OPTIONS": {"MAX_ENTRIES": 150}},
    "images": {
        "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
        "LOCATION": "images", "TIMEOUT": _cache_timeout,
        "OPTIONS": {"MAX_ENTRIES": 150}},
}
```
- **In plain words:** Instead of dumping everything into one storage bin, the lab keeps two separate bins: `"images"` for heavy sky photos and tiles, and `"default"` for lightweight notes like "Has Hubble photographed Orion?" or "Is SkyView busy right now?".
- **Why it matters:** Zooming around a single sky map downloads dozens of sky tiles. With one shared bin, those tiles would shove out hard-won telescope lookup answers that took 20 seconds to find!
- **What goes in / what comes out:** Cache reads and writes across the backend → fast repeat answers without running out of server RAM.

### 2. Turning Every Crash or Mistake Into One Tidy Error Note
**File:** `backend/config/errors.py` (`api_exception_handler`)
```python
def api_exception_handler(exc, context):
    if isinstance(exc, ApiError):
        return Response(error_body(exc.code, exc.message, exc.details), status=exc.http_status)
    response = exception_handler(exc, context)
    if response is None:
        log.exception("unhandled error in API view", exc_info=exc)
        return Response(error_body(INTERNAL_ERROR, "Something went wrong. Please try again."),
                        status=status.HTTP_500_INTERNAL_SERVER_ERROR)
```
- **In plain words:** Whenever any specialist in the lab raises an `ApiError` (like `SOLVE_FAILED` when clouds hide the stars) — or even if an unexpected bug happens — this function catches it and sends back a neat JSON card instead of a messy HTML crash page.
- **Why it matters:** The phone app (`ApiClient`) can always read `error.code` and `error.message` to decide whether to show a "Retry" button or a "Take another photo" screen.
- **What goes in / what comes out:** Any Python exception → a clean JSON HTTP response like `{"error": {"code": "SOLVE_FAILED", "message": "..."}}`.

### 3. Calling Space Archives With Timeouts & Polite Retries
**File:** `backend/config/http.py` (`_with_retries`)
```python
for attempt in range(retries + 1):
    try:
        resp = send(limits)
        if resp.status_code in RETRY_STATUS:
            last_error = ExternalServiceError(f"HTTP {resp.status_code} from {url}")
        else:
            resp.raise_for_status()
            return resp
    except httpx.HTTPStatusError as exc:  # non-retryable 4xx
        raise ExternalServiceError(f"HTTP {exc.response.status_code} from {url}") from exc
```
- **In plain words:** When calling NASA or European servers, if the remote server hiccups (`500`, `503`, `429` "too busy") or times out, wait `1.5` seconds and try once more; but if it says `404 Not Found` (meaning no tile exists there), fail right away without wasting time retrying.
- **Why it matters:** Public astronomy servers occasionally blink under heavy traffic, while missing tiles (`404`) happen normally at the edges of Hubble/Webb footprints and shouldn't slow things down.
- **What goes in / what comes out:** A URL and query parameters → a verified `httpx.Response`, or `ExternalServiceError` if all attempts fail.

### 4. Checking Image Size Before Unpacking Pixels
**File:** `backend/config/images.py` (`open_image`)
```python
def open_image(data: bytes) -> Image.Image:
    img = Image.open(io.BytesIO(data))
    if img.width * img.height > settings.MAX_UPSTREAM_IMAGE_PIXELS:
        raise BadUpstreamImageError(f"upstream image too large: {img.width}x{img.height}")
    return img
```
- **In plain words:** Peeks at the width and height written on the outside of an image envelope before unfolding all the pixels into memory, rejecting anything bigger than 16 million pixels.
- **Why it matters:** A tiny compressed file can expand into gigabytes of raw pixels (called a *decompression bomb*). Checking the header first protects the lab from running out of memory.
- **What goes in / what comes out:** Raw image bytes → a safe `PIL.Image` object ready to resize or blend.
