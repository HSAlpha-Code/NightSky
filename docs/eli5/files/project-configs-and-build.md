# Project Setup, Build & Deployment Files

**Files covered in this guide:**
- `README.md`, `LICENSE`, `.gitignore`
- `backend/manage.py`, `backend/requirements.txt`, `backend/requirements-dev.txt`, `backend/.env.example`, `backend/.python-version`, `backend/vercel.json`, `backend/.vercelignore`
- `app/pubspec.yaml`, `app/analysis_options.yaml`, `app/assets/sky/SOURCES.md`

---

## Role
These files are the **Planetarium Blueprints, Supply Lists, and Building Permits** — they tell computers what supplies to order, which offline sky pictures to pack inside the phone app, and how to set up the Backstage Astronomy Lab in the cloud.

## Why They Exist
Without these files, a new computer wouldn't know which astronomy math tools to install, the phone app wouldn't pack its offline 8K Milky Way map or custom graphics shader inside the app bundle, and the cloud host (**Vercel** — *a cloud service that runs server code on demand*) wouldn't give the lab enough memory or time to stitch space-telescope pictures.

## What's Inside
- **Owner's Manual & Credits (`README.md`, `LICENSE`, `app/assets/sky/SOURCES.md`)**: Explains both modes of NightSky, how to run everything on your own computer, where every star catalog and Milky Way tile came from, and license reminders (especially crediting Axel Mellinger's Milky Way panorama).
- **Lab Starter Switch (`backend/manage.py`)**: A tiny starter button for developers to run the Python server locally, run automated tests, or download updated star catalogs.
- **Lab Supply Lists (`backend/requirements.txt`, `backend/requirements-dev.txt`, `backend/.python-version`)**: Lists the Python libraries the Backstage Lab needs — including `astropy` *(astronomy coordinate math)*, `tetra3` *(the European Space Agency's star-pattern matcher)*, `pygeomag` *(compass magnetic correction)*, `Pillow` / `scipy` / `numpy` *(image math)*, and `Django` *(the web server framework)*.
- **Lab Control Dials & Cloud Rules (`backend/.env.example`, `backend/vercel.json`, `backend/.vercelignore`)**: Sample settings for timeouts, web addresses of space archives, and cloud rules giving the server 2 GB of memory and up to 5 minutes (`300` seconds) per request while leaving test files out of the cloud upload.
- **Handheld App Packing List (`app/pubspec.yaml`, `app/analysis_options.yaml`)**: Lists the phone app's toolkits (`camera`, `geolocator`, `dio`, `flutter_riverpod`) and tells Flutter to pack the four offline sky files (`mellinger_east.webp`, `mellinger_west.webp`, `stars.bin`, `sky_catalog.json`) plus the GPU star-dome program (`shaders/sky_sphere.frag`) right into the app.

## Talks To
- `backend/manage.py` loads `backend/config/settings.py`.
- `backend/vercel.json` points cloud traffic to `backend/config/wsgi.py`.
- `app/pubspec.yaml` feeds bundled sky files to `app/lib/sky_view/panorama_loader.dart`, `sky_catalog.dart`, and `sky_sphere_painter.dart`.

---

## Important Code Blocks

### 1. Packing the Offline Planetarium Inside the Phone App
**File:** `app/pubspec.yaml` (`flutter` section)
```yaml
  assets:
    - assets/sky/mellinger_east.webp
    - assets/sky/mellinger_west.webp
    - assets/sky/stars.bin
    - assets/sky/sky_catalog.json

  shaders:
    - shaders/sky_sphere.frag
```
- **In plain words:** This checklist tells Flutter to sew four sky data files (~9.1 MB total) and one tiny graphics-chip program directly inside the phone app when it is built.
- **Why it matters:** Because these files travel inside the app itself, **Sky View** works in the middle of a desert or forest with zero cell signal.
- **What goes in / what comes out:** Takes files from `app/assets/sky/` and `app/shaders/` at build time → produces an installable phone app with all stars, constellations, and the Milky Way built in.

### 2. Giving the Cloud Lab Enough Memory & Time for Space Mosaics
**File:** `backend/vercel.json`
```json
{
  "regions": ["fra1"],
  "functions": {
    "config/wsgi.py": {
      "maxDuration": 300,
      "memory": 2048,
      "excludeFiles": "{**/tests.py,**/test_*.py,samples/**,staticfiles/**,.cache/**}"
    }
  }
}
```
- **In plain words:** Tells Vercel to run the Backstage Lab in Frankfurt (`fra1` — close to European astronomy servers in France and Spain!), give it 2,048 MB (2 GB) of RAM, allow up to 300 seconds for tough telescope stitches, and skip uploading test files so the server package stays slim.
- **Why it matters:** Stitching high-resolution James Webb or Hubble tiles uses big image grids in memory; normal tiny web defaults (like 10 seconds) would cut the lab off mid-stitch.
- **What goes in / what comes out:** Deployment configuration → a cloud worker sized for astronomy image processing.
