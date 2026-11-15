# The Handheld Planetarium's Power Switch, Clipboard & Memory (`main.dart`, `settings.dart`, `state.dart`, `models.dart`)

**Files covered in this guide:**
- `app/lib/main.dart`
- `app/lib/settings.dart`
- `app/lib/state.dart`
- `app/lib/models.dart`

---

## Role
In our Handheld Planetarium (`app/`), these four files are the **Main Power Switch, User Preferences Notebook, Live Session Clipboard, and Label Cards** — they boot the app, remember your settings across restarts, and coordinate every step after you press the camera shutter!

## Why They Exist
Without these files, the app wouldn't know whether to open in **Camera** mode or **Sky View** mode, wouldn't remember your font size or red night-vision toggle when closed, and wouldn't know how to step cleanly from *"Preparing photo…"* → *"Finding your stars…"* → *"Fetching the survey image…"* → *"Done!"* (including letting you tap **Cancel** or **Retry** mid-flight).

## What's Inside
- **`main.dart` (The Power Switch & Theme Wrapper)**: Locks the screen upright (`portraitUp` — so sensor math always knows which edge of the phone is "up"), starts **Riverpod** *(a shared bulletin board (`ProviderScope`) that lets screens watch data and redraw automatically when it changes)*, quietly kicks off a background check for Curated Cosmic Highlights, multiplies the phone's text size by your chosen app font scale, and opens either `SkyViewScreen` or `CameraScreen`.
- **`settings.dart` (The User Preferences Notebook)**: Defines `AppSettings` (gyroscope vs. compass mode, smoothing level, steadiness strictness, 2-second auto-capture, font size `0.85×–1.3×`, Sky View quality `3.2K` / `6.4K` / `8K`, red night vision, manual offline location, and custom server URL) and saves/loads them via Android's `SharedPreferences` channel (`night_sky/settings`).
- **`state.dart` (The Photo-Session Clipboard)**: Runs `SessionNotifier`, which orchestrates one full capture run:
  1. Shrinks and straightens the raw photo on a background worker thread (**isolate** — *a separate mini-brain so the screen spinner never freezes*).
  2. Sends it to `/api/solve`.
  3. Simultaneously asks `/api/landmarks` for object pins (polling up to 6 times every 6 seconds if MAST is still checking for Webb/Hubble gold rings!) while downloading the `/api/sky-image` JPEG.
- **`models.dart` (The Structured Data Cards)**: Plain Dart classes (`SkyProviderInfo`, `SolveResult`, `SkyImage`, `Landmark`, `LandmarkDetail`, `CaptureMetadata`, `ApiException`) that unpack JSON from the Backstage Lab into safe, typed objects.

## Talks To
- Watched by every screen (`CameraScreen`, `ResultScreen`, `LandmarkDetailScreen`, `SkyViewScreen`, `SettingsScreen`).
- Calls `app/lib/api_client.dart`, `app/lib/photo_utils.dart`, and Android's `MainActivity.kt` (`night_sky/settings`).

---

## Important Code Blocks

### 1. Stepping a Captured Photo Through the Lab Without Freezing the Screen
**File:** `app/lib/state.dart` (`SessionNotifier.start`)
```dart
final run = ++_run;
state = const SessionState(stage: Stage.preparing);
final photo = await compute(preparePhotoIsolate, rawPhoto);
if (run != _run) return;
state = state.copyWith(stage: Stage.solving, photo: photo);
final solve = await _api.solve(photo.jpeg, meta);
if (run != _run) return;
state = state.copyWith(stage: Stage.fetchingImage, solve: solve);
unawaited(_loadLandmarks(run));
await _fetchImage(run);
```
- **In plain words:** Stamps a ticket number (`_run`) on this photo session. First, resize the huge camera photo on a side thread (`compute`). Next, ask the Star Detective where it points (`solve`). As soon as coordinates come back, fire off the landmark-pin lookup and the survey-picture download at the same time — checking the ticket number after every step so if you backed out or hit Cancel, old answers are ignored!
- **Why it matters:** Keeps animations silky smooth and prevents race conditions when users cancel or switch surveys quickly.
- **What goes in / what comes out:** Raw camera bytes + `CaptureMetadata` → live `SessionState` updates watched by `ResultScreen`.

### 2. Scaling Text App-Wide On Top of System Accessibility Settings
**File:** `app/lib/main.dart` (`NightSkyAppShell.build`)
```dart
builder: (context, child) {
  final media = MediaQuery.of(context);
  final phone = media.textScaler.scale(1);
  return MediaQuery(
    data: media.copyWith(textScaler: TextScaler.linear(phone * fontScale)),
    child: child!,
  );
},
```
- **In plain words:** Reads your phone's built-in text size multiplier and multiplies it by NightSky's own `Small / Normal / Large / Extra large` setting so labels stay easy to read outdoors in the dark without needing squinting!
- **Why it matters:** Outdoors at night, pupils dilate and small labels look blurry; letting stargazers boost text size across every screen at once helps everyone read star facts comfortably.
- **What goes in / what comes out:** Phone `MediaQuery` + `settings.fontSize.scale` → scaled typography across the entire app.
