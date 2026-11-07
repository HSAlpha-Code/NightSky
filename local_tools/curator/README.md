# NightSky local curator

This tool is committed to the repo but never deployed (the Vercel project's root is `backend/`,
and a root-level `.vercelignore` also excludes it). Its working data stays on your machine and is
gitignored: the originals in `media/` and the database `curator.sqlite3`. What gets published is
the exported bundle (`backend/curated_bundle/`), which IS committed. Back up `media/` and
`curator.sqlite3` yourself if you want to keep editing from another machine.

## Run it

From the repo root (PowerShell):

```powershell
$env:ENABLE_CURATOR = "1"
backend\.venv\Scripts\python local_tools\curator\run.py
```

Open <http://127.0.0.1:8765/>. It listens on `127.0.0.1` only, refuses to start without
`ENABLE_CURATOR=1`, rejects other Host headers, and requires an `X-Curator` header on every write
(so other websites open in your browser can't post to it). It is not in `config/urls.py`, so the
deployed backend has no curator or admin routes at all.

In the UI: search a body (name, `M31`, `NGC 1976`, `Vega`), add an image by **file upload** or by
**pasting an image URL you have chosen** (downloaded once, here, and stored locally), fill in
outlet, source URL, credit and caption, then reorder (up/down), enable/disable or delete.
Images are normalised to JPEG (max 2048 px) with a 480 px thumbnail.

> Only use images you have the right to use. Always fill in the credit and source link.

## Getting content to the deployed backend (publish)

Vercel's filesystem is read-only and there is no production database, so published content is a
**bundle shipped with the deployment**:

1. Click **Export bundle for deploy** in the UI (or `run.py export`). This writes
   `backend/curated_bundle/manifest.json` and `backend/curated_bundle/images/` containing only
   *enabled* highlights.
2. Commit and push; Vercel redeploys with the new bundle:
   ```powershell
   git add backend/curated_bundle
   git commit -m "Update curated highlights"
   git push
   ```
3. Check: `https://nightsky-backend.vercel.app/api/curated/index/`

On Vercel (`CURATED_SOURCE=bundle`) the API reads `manifest.json` and serves the images straight
from the bundle. Locally the backend uses the bundle if it exists, otherwise the database; set
`CURATED_SOURCE=db` to make the local backend follow the curator database live.

### Tradeoffs
* **Pros:** no extra services, no cost, no secrets, no write path on the server, works with
  Vercel's read-only filesystem.
* **Cons:** every change needs a redeploy; images count towards the deployment size (keep the
  library modest, each image is ~0.3-1 MB); the images live in the git history
  (keep the library modest so the repo stays small).
* **Later upgrade:** Postgres + Vercel Blob would publish instantly without a redeploy but needs
  accounts, env vars and a production DB. The API layer (`backend/curated/repo.py`) is the only
  place that would change.
