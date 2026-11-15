# The Walkie-Talkie Messenger, Photo Shrinker & Story Sync (`api_client.dart`, `photo_utils.dart`, `curated.dart`)

**Files covered in this guide:**
- `app/lib/api_client.dart`
- `app/lib/photo_utils.dart`
- `app/lib/curated.dart`

---

## Role
In our Handheld Planetarium, `api_client.dart` is the **Walkie-Talkie Messenger** that talks to the Backstage Lab, `photo_utils.dart` is the **Pocket Photo Trimmer** that shrinks huge camera files before sending them over cell data, and `curated.dart` is the **Museum Pamphlet Keeper** that caches NASA/ESA highlight stories for offline reading!

## Why They Exist
Modern phone cameras shoot 12-to-50-megapixel files (5–15 MB each) — uploading one raw over weakrural cell signal would take ages and exceed cloud upload limits (`4.5 MB`). Meanwhile, network hiccups need friendly plain-English messages instead of cryptic computer codes, and curated stories should still work offline once downloaded.

## What's Inside
- **`api_client.dart` (The HTTP Messenger)**:
  - Normalizes server addresses (`http://host:8000` → `http://host:8000/api`) and sets smart timeouts (`10s` connect, `90s` sky solve/cutout, `150s` first-time Webb/Hubble mosaic stitch).
  - Provides one clean method per lab doorway: `getProviders()`, `solve()`, `skyImage()`, `landmarks()`, `landmarkDetail()`, `curatedIndex()`, and `curatedBody()`.
  - Translates ugly network crashes (`DioException`) into friendly `ApiException` messages (even unpacking JSON error notes tucked inside binary image responses!).
- **`photo_utils.dart` (The Photo Trimmer)**:
  - `preparePhoto()`: Decodes raw camera bytes, bakes in **EXIF** rotation so "up" in the pixels really is the top of the image, shrinks the long edge to `1600 px` with smooth area-averaging, and re-saves a compact JPEG (`quality: 90`).
  - `skyImageSize()`: Computes matching dimensions capped at `1200 px` so the downloaded survey overlay has the exact same width-to-height shape as your photo!
- **`curated.dart` (The Story Cache & Sync)**:
  - Quietly syncs `/api/curated/index/` on app start using **ETags** (`If-None-Match`), saving both the index and opened object stories in persistent phone storage tagged with the server URL so previously viewed stories open instantly — even offline!

## Talks To
- `api_client.dart` talks over HTTPS to `backend/config/urls.py`.
- `photo_utils.dart` is run in a background isolate by `app/lib/state.dart`.
- `curated.dart` feeds `LandmarkDetailScreen`, `SkyViewScreen`, and `SkyObjectSheet`.

---

## Important Code Blocks

### 1. Shrinking Camera Photos Before Upload Without Losing Stars
**File:** `app/lib/photo_utils.dart` (`preparePhoto`)
```dart
var image = img.bakeOrientation(decoded);
if (math.max(image.width, image.height) > maxSide) {
  final landscape = image.width >= image.height;
  image = img.copyResize(
    image,
    width: landscape ? maxSide : null,
    height: landscape ? null : maxSide,
    interpolation: img.Interpolation.average,
  );
}
return PreparedPhoto(Uint8List.fromList(img.encodeJpg(image, quality: 90)), image.width, image.height);
```
- **In plain words:** Rotates the photo upright, and if it is wider or taller than `1,600` pixels, shrinks it by averaging neighboring pixels together (`Interpolation.average` — which actually reduces speckly camera dark-noise while keeping stars round!) before packing it into a crisp, small JPEG.
- **Why it matters:** Cuts upload size roughly 10× so photos upload in a second over mobile data and never hit Vercel's 4.5 MB ceiling.
- **What goes in / what comes out:** Multi-megabyte raw camera bytes → compact `PreparedPhoto(jpeg, width, height)`.

### 2. Offline-Friendly Story Sync With Server-Tagged `ETag` Cache
**File:** `app/lib/curated.dart` (`CuratedIndexNotifier._sync`)
```dart
final cached = await _readCache(store, _indexKey, server);
if (cached != null) state = CuratedIndex.fromJson(cached.json);
final fresh = await api.curatedIndex(etag: cached?.etag);
if (fresh.json == null) return; // 304: cached copy is current
state = CuratedIndex.fromJson(fresh.json!);
await _writeCache(store, _indexKey, server, fresh.etag, fresh.json!);
```
- **In plain words:** Load yesterday's saved list of highlighted objects right away so gold museum badges show up immediately, then ask the server *"Did anything change since version X?"*. If the server replies `304` (nothing changed), stop right there; if new highlights arrived, update the screen and save the new version!
- **Why it matters:** Works offline using the saved copy and fails silently if you have no internet so it never interrupts stargazing.
- **What goes in / what comes out:** Saved cache + optional server check → live `CuratedIndex` across the app.
