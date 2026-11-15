# The Museum Story Vault & Curator's Workshop (`backend/curated/` & `local_tools/curator/`)

**Files covered in this guide:**
- `backend/curated/models.py`, `repo.py`, `views.py`, `urls.py`, `apps.py`, `migrations/0001_initial.py`, `backend/curated_bundle/manifest.json`
- `local_tools/curator/README.md`, `run.py`, `curator_settings.py`, `curator_urls.py`, `curator_views.py`, `curator_images.py`, `curator_export.py`, `curator_page.html`

---

## Role
In our Planetarium analogy, `backend/curated/` is the **Read-Only Museum Exhibit Glass Case** that visitors browse on their phones, while `local_tools/curator/` is the **Private Curator's Workbench** kept locked on the project owner's personal computer for assembling new NASA/ESA story cards!

## Why They Exist
Cloud functions on Vercel have a **read-only filesystem** *(files cannot be edited once deployed)* and no paid database attached, AND you never want random strangers on the internet uploading pictures onto your server. Separating the private desktop editor (`local_tools/curator/`) from the read-only public glass case (`backend/curated/` + `backend/curated_bundle/`) makes Curated Cosmic Highlights completely free to host and impossible to vandalize!

## What's Inside
- **The Public Glass Case (`backend/curated/`)**:
  - `models.py`: Defines a `CuratedHighlight` card (`body_id`, `title`, `image_file`, `source_outlet`, `source_url`, `credit`, `caption`, `sort_order`, `enabled`).
  - `repo.py`: Reads highlights from `backend/curated_bundle/manifest.json` + `images/` in the cloud (or straight from SQLite during local editing) and computes a 16-character **fingerprint hash** *(a short summary code that changes whenever even one comma changes)*.
  - `views.py` & `urls.py`: Serves `GET /api/curated/index/`, `GET /api/curated/<body_id>/`, and `GET /api/curated/image/<name>`. Uses **ETags** *(version tags so if nothing changed since yesterday, the server replies with an instant empty `304 Not Modified` instead of resending everything!)* and strict file-name regex checks to block folder-traversal tricks.
- **The Private Curator's Workbench (`local_tools/curator/`)**:
  - `run.py` & `curator_settings.py`: Refuses to start unless `ENABLE_CURATOR=1` is set and binds strictly to `127.0.0.1` (your own machine only).
  - `curator_views.py` & `curator_page.html`: Serves a browser page to search OpenNGC/IAU objects, upload or paste an image URL, write captions/credits, reorder cards, and require a custom `X-Curator: 1` header so no other open browser tab can sneak requests in.
  - `curator_images.py`: Shrinks large NASA/ESA originals to a crisp `2048 px` JPEG plus a `480 px` thumbnail (`_t.jpg`).
  - `curator_export.py`: Packs all enabled cards and images into `backend/curated_bundle/` ready to commit and deploy!

## Talks To
- `backend/curated/` talks to `app/lib/curated.dart` and `app/lib/api_client.dart`.
- `local_tools/curator/` reads object names from `backend/landmarks/catalog.py` and writes exports into `backend/curated_bundle/`.

---

## Important Code Blocks

### 1. Instant "Nothing Changed!" Replies Using `ETag` Fingerprints
**File:** `backend/curated/views.py` (`_respond`)
```python
def _respond(request, version: str, payload: dict) -> Response:
    etag = f'"{version}"'
    resp = Response(status=304) if _etag_matches(request, etag) else Response(payload)
    resp["ETag"] = etag
    resp["Cache-Control"] = CACHE_CONTROL
    return resp
```
- **In plain words:** Every time the phone asks *"Which stars and nebulae have curated stories?"*, it includes the version tag it saved last time (`If-None-Match`). If the museum exhibit hasn't changed, the server replies *"304 — your copy is still fresh!"* in a few bytes instead of resending the list.
- **Why it matters:** Keeps app startup fast and saves mobile data while still picking up newly published stories automatically.
- **What goes in / what comes out:** Incoming HTTP request + data fingerprint + JSON payload → either tiny `304` response or `200` JSON with `ETag`.

### 2. Locking Down the Curator's Workbench to Your Own Machine
**File:** `local_tools/curator/curator_views.py` (`CuratorGuardMiddleware`)
```python
class CuratorGuardMiddleware:
    def __call__(self, request):
        if request.method not in ("GET", "HEAD") and request.headers.get("X-Curator") != "1":
            return HttpResponseForbidden("Missing X-Curator header")
        response = self.get_response(request)
        response["Cache-Control"] = "no-store"
        return response
```
- **In plain words:** Even while you run the curator tool on your own laptop, if a random website open in another browser tab tries to send a sneaky `POST` request to `127.0.0.1:8765`, this guard blocks it because browsers forbid outside sites from attaching custom headers like `X-Curator: 1` without permission.
- **Why it matters:** Protects your local curation database from cross-site browser tricks (`CSRF`).
- **What goes in / what comes out:** Local browser request → `403 Forbidden` if unverified, otherwise runs the curator action.
