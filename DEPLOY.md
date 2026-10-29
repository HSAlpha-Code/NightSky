# Deploying NightSky

Two parts: the **backend** (Django API) goes to Vercel, the **app** is an Android APK that
talks to it. The APK is built for `https://nightsky-backend.vercel.app`, so the Vercel project
must be named **`nightsky-backend`** (or rebuild the APK with your URL, see the end).

---

## 1. Backend on Vercel

### What's already set up in `backend/`
| File | Purpose |
|---|---|
| `requirements.txt` | Runtime packages. Vercel installs these (~320 MB of the 500 MB Python limit). |
| `.python-version` | Python **3.12** (Vercel supports 3.12-3.14). |
| `vercel.json` | 300 s max duration, 2 GB memory, region `fra1` (Frankfurt), excludes tests. |
| `.vercelignore` | Keeps `.venv`, `.env`, caches and tests out of the upload. |
| `data/catalogs/` | Landmark catalogue (OpenNGC + IAU star names, 4 MB). **Must be committed.** |

Vercel finds `manage.py`, reads `WSGI_APPLICATION = "config.wsgi.application"` and serves the
whole API from one function. No code changes are needed for deployment.

### Steps (GitHub + dashboard, recommended)
1. Push the project to a GitHub repository. Check the catalogue is included:
   `git ls-files backend/data/catalogs` must list `NGC.csv`, `addendum.csv`, `IAU-CSN.txt`.
2. On <https://vercel.com/new>, import the repository.
3. **Project Name:** `nightsky-backend`
4. **Root Directory:** click *Edit* and choose **`backend`**. (Important: the Django project
   lives in that folder.) Framework preset: *Django* (detected automatically).
5. **Environment Variables:** add
   | Name | Value |
   |---|---|
   | `DJANGO_SECRET_KEY` | a long random string, e.g. output of `python -c "import secrets; print(secrets.token_urlsafe(50))"` |
   | `DJANGO_ALLOWED_HOSTS` | `.vercel.app` |
   Optional: `CACHE_BACKEND=redis` + `CACHE_LOCATION=redis://...` (see *Caching* below).
6. Click **Deploy**. The first build takes a few minutes (scientific packages).
7. Test it in a browser:
   - `https://nightsky-backend.vercel.app/` → `{"status": "ok", ...}`
   - `https://nightsky-backend.vercel.app/api/providers` → the image-source list

### Alternative: Vercel CLI
```powershell
npm i -g vercel
cd C:\Projects\NightSky\backend
vercel link            # create/link the project; name it nightsky-backend
vercel env add DJANGO_SECRET_KEY production
vercel env add DJANGO_ALLOWED_HOSTS production     # value: .vercel.app
vercel --prod
```

### Good to know about running on Vercel
- **Region.** `vercel.json` uses `fra1` (Frankfurt), close to ESA's servers and reasonable
  from India. Change `"regions"` to `["bom1"]` (Mumbai) if you prefer lower latency to the phone.
  Pick one and keep it.
- **Time limit.** Requests can run up to 300 s (the Hobby maximum). A first-time Hubble/JWST
  mosaic takes 15-60 s, well inside that.
- **Cold starts.** After a few idle minutes the next request loads Django, astropy, numpy and
  scipy again: expect ~5-15 s extra on that first request.
- **Plate solving.** tetra3 is included. Solving a photo takes up to 10 s of CPU.
- **CDS is reachable from Vercel.** The DSS2/2MASS/AllWISE images that had to be rebuilt from
  ESA tiles on your home connection come straight from CDS hips2fits there (faster), and
  Pan-STARRS (HiPS) works too. The ESA fallback stays in place.
- **Caching.** The default cache is per-instance memory, so it's lost on cold starts and not
  shared between instances. It works, just with more repeated downloads. For a shared cache,
  add a Redis database (Vercel Marketplace → *Upstash Redis* or similar) and set
  `CACHE_BACKEND=redis` and `CACHE_LOCATION=<the redis:// or rediss:// URL>`.
- **"Has a Hubble/Webb image" markers.** Those MAST checks run in background threads. On
  Vercel, background work can be paused once a response is sent, so the gold markers may take
  a few more refreshes to fill in. Tapping a landmark always works (it checks on demand).
- **Read-only disk.** Only `/tmp` is writable; the settings already point astropy's cache
  there when the `VERCEL` environment variable is present (Vercel sets it automatically).

### Updating the backend
Push to the main branch: Vercel redeploys automatically. Or run `vercel --prod` again.

---

## 2. Android app (APK)

### The ready-made APK
`app/build/app/outputs/flutter-apk/app-release.apk`
- Name **NightSky**, new icon, version 1.0.0 (code 1).
- Talks to `https://nightsky-backend.vercel.app`.
- Signed with the NightSky release key (below).

### Install on a phone
- **USB:** `adb install -r app\build\app\outputs\flutter-apk\app-release.apk`
- **Without a PC:** copy the APK to the phone (Drive, WhatsApp, USB), open it and allow
  *Install unknown apps* for the app you opened it with.
- If a development build is already installed you'll see "App not installed" / a signature
  conflict: uninstall the old NightSky first (dev builds use a different key).

### The release key: back it up
Files (both git-ignored, **never commit them**):
- `app/android/nightsky-release.jks` (the key)
- `app/android/key.properties` (its passwords)

Copy both somewhere safe (password manager / private cloud). Every future update of the app
must be signed with this same key, otherwise phones refuse to install it over the old version.
If they're missing, release builds silently fall back to the debug key.

### Building a new APK
```powershell
cd C:\Projects\NightSky\app
# 1. bump the version in pubspec.yaml, e.g.  version: 1.0.1+2   (the +number must increase)
# 2. build
flutter build apk --release --dart-define=SERVER_URL=https://nightsky-backend.vercel.app
```
Use your own URL in `SERVER_URL` if the Vercel project has a different name or a custom domain.
Users can also change the server in the app (Settings), but that resets when the app restarts.

### Changing the icon
Replace `app/tool/icon/nightsky_icon_source.png` (a rounded-square tile on a plain background,
like the current one), then:
```powershell
cd C:\Projects\NightSky\app
python tool\icon\make_icons.py
```
and rebuild the APK.
