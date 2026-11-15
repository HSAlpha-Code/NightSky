# The Handheld Rooms: Camera, "Your Sky", Star Close-Up & Settings (`app/lib/screens/*.dart`)

**Files covered in this guide:**
- `app/lib/screens/camera_screen.dart`
- `app/lib/screens/result_screen.dart`
- `app/lib/screens/landmark_detail_screen.dart`
- `app/lib/screens/settings_screen.dart`
*(Note: `sky_view_screen.dart` has its own dedicated guide alongside its 3D rendering engine in `app-sky-view-rendering-and-shader.md`!)*

---

## Role
In our Handheld Planetarium, these four files are the **Main Visitor Rooms** — the **Camera Viewfinder Window** (`CameraScreen`), the **"Your Sky" Magic Reveal Room** (`ResultScreen`), the **Close-Up Exhibit Kiosk** (`LandmarkDetailScreen`), and the **Control Closet** (`SettingsScreen`).

## Why They Exist
Without these screens, all the sensor math and backstage lab science would stay invisible inside the phone's memory — you need clear rooms to aim and shoot, compare your photo with deep-space maps, explore individual stars/nebulae, and customize controls.

## What's Inside
- **`camera_screen.dart` (The Sky Viewfinder Window)**:
  - Runs the rear camera edge-to-edge in portrait mode (flash locked off so it doesn't blind you!), asks for camera *then* GPS permission one at a time so pop-ups don't pile up, and checks hand shake 4 times per second (`_tick()`).
  - If **Auto-capture** is on and your hands stay steadier than `maxShakeDeg` for 2 full seconds, it snaps the photo automatically!
  - Features the `ModeSwitchPill` (`[ 🌐 | 📷 ]`) to hop into 3D Sky View (cleanly shutting down the camera lens first to save battery) and a survey source pill at bottom-left.
- **`result_screen.dart` ("Your Sky" — The Magic Reveal Room)**:
  - Shows frosted progress cards while the Backstage Lab solves your stars and fetches the survey picture, then frames the sky inside an optical card with `MagicReveal` sparkles, `CompareView` (syncing the on-image drag divider with the bottom `Survey ↔ My photo` slider dock), and clickable `LandmarkOverlay` pins.
  - Header buttons toggle pins on/off, open the `Details` sheet (`InfoBar` with RA/Dec, FOV, solve confidence, and credit), or switch between `DSS2 Color` and `Mellinger Color`.
- **`landmark_detail_screen.dart` ("Star View" — The Close-Up Kiosk)**:
  - Opens when you tap any star or nebula pin.
  - Smartly filters source chips so **only genuinely available views appear**: stars and `hasHires == false` objects jump straight to `DSS2 Color` (hiding `Webb` and `Hubble`), while deep-sky objects use the server's `available_views` list and `resolvedDetailCacheProvider` so unavailable telescope buttons never show up and already-loaded images never download twice!
- **`settings_screen.dart` (The Control Closet)**:
  - Lets you toggle gyroscope mode, sensor smoothing, steadiness strictness, auto-capture, Sky View graphics quality, red night vision, app-wide font size, and custom backend URL (with a live `"Save and test connection"` button).

## Talks To
- Watch and update `sessionProvider`, `settingsProvider`, `providerCatalogProvider`, and `curatedIndexProvider`.
- Compose UI pieces from `app/lib/widgets/*.dart`.

---

## Important Code Blocks

### 1. Hands-Free Auto-Capture After 2 Seconds of Steady Hands
**File:** `app/lib/screens/camera_screen.dart` (`_CameraScreenState._tick`)
```dart
final shake = _orientation.shake();
final steady = _orientation.hasData && shake <= settings.steadiness.maxShakeDeg;
final now = DateTime.now();
_steadySince = steady ? (_steadySince ?? now) : null;
...
if (settings.autoCapture &&
    _steadySince != null &&
    now.difference(_steadySince!) >= autoCaptureHold &&
    !_capturing &&
    ModalRoute.of(context)?.isCurrent == true) {
  _steadySince = null;
  _capture();
}
```
- **In plain words:** Every quarter-second, check if the phone wobbled less than `1.5°`. If you held still continuously for 2 seconds (`autoCaptureHold`) while looking at the camera screen, press the shutter for you automatically so tapping the glass with your thumb doesn't jiggle the stars!
- **Why it matters:** Thumb taps are the #1 cause of blurry night-sky phone photos.
- **What goes in / what comes out:** Rolling 0.6s sensor wobble → green progress ring + automatic `_capture()` call.

### 2. Showing Only Verified Telescope Chips in Star View (Zero Wasted Taps)
**File:** `app/lib/screens/landmark_detail_screen.dart` (`detailViews` & `ref.listen`)
```dart
final known = (lm.isStar || lm.hasHires == false) ? const {'survey'} : availableViews;
return [
  if (hasCurated) const DetailView('curated', null, curatedSourceLabel),
  if (known == null)
    DetailView('auto', surveyKey, 'Finding best view…')
  else ...[
    if (known.contains('jwst')) DetailView('jwst', surveyKey, 'Webb'),
    if (known.contains('hst')) DetailView('hst', surveyKey, 'Hubble'),
  ],
  ...surveyChips,
];
```
- **In plain words:** Stars (and nebulae we already know lack space-telescope photos) immediately show only `DSS2 Color` (plus `Curated` if available). For other nebulae/galaxies, once the first request comes back with `available_views`, only the telescopes that *actually* photographed that object (`Webb`, `Hubble`, or neither) appear as chips — and wide-field-only `Mellinger Color` is excluded via `supportsDetail`.
- **Why it matters:** Users never tap a `Webb` button only to wait 30 seconds for an error or a misleading fallback image.
- **What goes in / what comes out:** `Landmark` + `ProviderCatalog` + verified `availableViews` set → honest list of `DetailView` chips.
