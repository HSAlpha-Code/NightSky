
You are working on an existing night-sky app. The Flutter mobile app captures a photo of the sky and the Django backend resolves coordinates and returns imagery from several selectable image sources. First read the codebase and match its existing conventions: how image providers are registered, how the settings screen is built, and how the app talks to the backend. Then implement the following without breaking existing providers.

**1. Curated Cosmic Highlights data model (backend)**
- Add a model, e.g. `CuratedHighlight`, with: `id`, `body_id` or `body_name` (matching however celestial bodies are already identified), `title`, `image_file` (stored locally and served by the backend), `source_outlet` (e.g. NASA, ESA, BBC), `source_url`, `credit`/`copyright_note`, `caption`, optional `ra`/`dec` or position data if bodies already use them, `enabled` (bool), `sort_order`, and timestamps.
- Add a migration.
- Images are "pre-rendered objects": the backend serves the stored file as-is (resizing or thumbnail generation is fine) and does not fetch anything from the news outlet at request time.

**2. Public API endpoints (backend)**
- `GET /api/curated/index/` returns a lightweight list of only the bodies that have at least one enabled highlight: `body_id`, `body_name`, `count`, and a version/ETag (or `updated_at`) so the phone can tell when the list changed. No full image data in this response.
- `GET /api/curated/<body_id>/` returns the highlights for one body, including image URLs, thumbnails, captions, credit and source link.
- Add caching headers and support for `If-None-Match`.
- These endpoints are read-only and public. They must not expose any write or admin functionality.

**3. Local-only curation UI (must NOT be in the GitHub repo)**
- Build a local UI/UX for me to curate highlights: browse or search celestial bodies, add an image to a body (upload a file or paste an image URL I have chosen), fill in outlet, source URL, credit and caption, reorder, enable/disable and delete.
- Keep this tool strictly separate from the deployable app. Put it in its own directory, e.g. `local_tools/curator/`, and add that directory, and any local curated image storage and local DB files, to `.gitignore`. Also make sure it is excluded from Vercel deployment (`.vercelignore` or equivalent).
- Bind it to `127.0.0.1` only and keep it out of the production URL config. Gate the curator behind an env flag such as `ENABLE_CURATOR=1` that is off by default. If it's built on Django admin or Django views, make sure those routes cannot be reached in production.
- Add a clear README note inside the ignored directory describing how I run it and how curated content gets from my machine to the deployed backend. Propose and implement one simple approach for that publish step (e.g. an export command that produces a bundle of images plus a JSON manifest, and an import command or script for the server), and explain the tradeoffs. Consider that Vercel's filesystem is read-only and ephemeral, so curated images and metadata must live in persistent storage such as a database plus object or blob storage. Flag this to me before assuming a design if the current backend setup makes it a problem.
- Show a small reminder in the curator UI that I should only use images I have the right to use, with the credit and source link filled in.

**4. Mobile app: new image source (Flutter)**
- Add a new image source named exactly **"Curated Cosmic Highlights"** to the existing image-source selector, using the same provider abstraction as the other sources.
- Visibility rule: this source appears in the selector only when the currently identified or selected body has curated highlights (based on the downloaded index). If the body has none, the option is not shown. If the user had it selected and then moves to a body without highlights, fall back gracefully to their previous or default source.
- When selected, show the curated image(s) for that body with caption, outlet credit and a tappable source link. Support multiple images per body, e.g. a swipeable carousel, and match the existing second-level detail view pattern if one exists.

**4a. Multi-image swipe viewer with page dots (Flutter)**
- When a body has more than one curated image, show them in a horizontally swipeable viewer, e.g. `PageView` or `PageView.builder`, with one image per page.
- Below the images, show a row of small dots, one per image, centered at the bottom of the viewer.
  - The active dot is larger or filled, with a clearly different color from the inactive dots.
  - The dots update live while the user swipes, using the `PageController`'s page value so the highlight follows the finger rather than jumping after the swipe ends. Animate the transition between active and inactive states.
  - Tapping a dot jumps to that image.
- If a body has only one curated image, hide the dots and disable swiping.
- If there are many images (more than about 8), keep the dot row from overflowing by showing a sliding window of dots, or switching to a compact "3 / 12" counter.
- Caption, outlet credit and the source link must update with the current page, so each image shows its own attribution.
- Keep the viewer's page position when the user rotates the phone or returns from a detail view, and reset it to the first image when they switch to a different body.
- Preload the adjacent images (next and previous) and show a placeholder or loading indicator while an image is downloading, so swiping feels smooth. Use the same image cache as the rest of the app.
- Keep gestures from conflicting with the sky view. If the viewer sits inside a scrollable or gesture-heavy screen, make sure horizontal swipes go to the viewer.
- Add a widget test covering: dots appear only when there are 2 or more images, the active dot tracks the page, tapping a dot navigates, and the caption changes with the page.
- Optional: add accessibility labels to the dots, like "Image 2 of 5".

**5. Mobile app: syncing the curated index**
- On connecting to the server (app start and whenever the server address changes), fetch `/api/curated/index/` and store it locally. Use the version/ETag so unchanged data is not re-downloaded, and cache the index so the feature still works offline once downloaded.
- Fetch per-body details and images lazily, with caching, when the user opens the source for a body.
- Handle failures quietly: if the index fetch fails, use the cached one. If there is no cache, simply hide the source. Never block the camera or core flow on this.

**6. Default server address**
- Change the default value of the app's "Server address" setting to `https://nightsky-backend.vercel.app`.
- Make sure people who already saved a custom address keep it. Only fresh installs, or users who never changed it, get the new default. If the old default was stored as an explicit value, add a small migration that updates it only when it equals the old default.
- Validate that the address is a well-formed URL, and don't hardcode the old address anywhere else (search the whole project for it).

**7. Quality and deliverables**
- Backend tests for the index and detail endpoints (empty case, disabled highlights excluded, ETag behavior). App tests for the visibility rule and the default-setting migration.
- Update documentation: the public README covers the API and the new source but says nothing about the curator tool beyond "local-only tooling exists and is gitignored", and the full instructions live in the ignored directory.
- Before finishing, run `git status` and confirm none of the curator code, curated images or local DB files are staged or tracked.
- Work in small steps, list the files you changed, and tell me about any assumptions or decisions that need my input. Keep token usage lean: do not re-read large files unnecessarily.

---