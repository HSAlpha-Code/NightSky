# The Phone's Inner Compass, Steadiness Meter & Native Hardware Bridges (`sensors.dart`, `sky_math.dart`, Android/iOS Bridges)

**Files covered in this guide:**
- `app/lib/sensors.dart`
- `app/lib/sky_math.dart`
- `app/android/app/src/main/kotlin/com/nightsky/night_sky/MainActivity.kt`
- `app/android/app/src/main/AndroidManifest.xml`
- `app/ios/Runner/AppDelegate.swift`, `app/ios/Runner/Info.plist`

---

## Role
In our Handheld Planetarium, these files are the **Gyroscope, Magnetic Compass, Bubble Level, and Hardware Wiring** — they feel which way you tilt the phone, measure whether your hands are shaking, check the camera lens's zoom width, and ask GPS satellites where on Earth you are standing!

## Why They Exist
Flutter's built-in widgets know how to draw buttons and pictures, yet they don't speak directly to Android's low-level motion chips or camera-lens millimeter specs. By piping raw numbers across tiny bridges (`MainActivity.kt`) and doing all the 3D orientation math in pure Dart (`sky_math.dart` & `sensors.dart`), NightSky gets rock-solid, testable sky pointing and steadiness detection!

## What's Inside
- **`MainActivity.kt` (The Android Hardware Bridge)**: Opens four communication pipes (**platform channels** — *walkie-talkie wires between Flutter Dart code and native Android Kotlin code*):
  1. `night_sky/sensors`: Reports which chips this phone actually has (accelerometer, magnetometer, gyroscope, rotation vector).
  2. `night_sky/sensor_events`: Streams live motion readings + compass calibration accuracy (`0..3`) at game speed (`SENSOR_DELAY_GAME`).
  3. `night_sky/camera`: Reads the rear lens's physical focal length and sensor size in millimeters (`camera2` API) so Dart can compute exact field-of-view degrees.
  4. `night_sky/settings`: Saves and loads user settings and small JSON caches in Android `SharedPreferences`.
- **`AndroidManifest.xml`, `AppDelegate.swift`, `Info.plist` (App Permissions & Rules)**: Requests Camera, Internet, and GPS permissions while explicitly stripping `RECORD_AUDIO` (for privacy — NightSky never records sound!) and marking the camera hardware `required="false"` so tablets or phones without working cameras can still install NightSky for 3D Sky View!
- **`sky_math.dart` (Pure 3D Rotation & Optics Math)**: Cross-products gravity ("up") with Earth's magnetic pull ("north") to build a 3D rotation grid without needing a gyroscope, converts between matrices and **quaternions**, smooths jittery readings (`smoothQuaternion`), measures hand shake (`maxSpreadDeg`), computes camera lens FOV from millimeter specs (`fovFromOptics`), and formats sky coordinates (`05h 35m 17s`, `-05° 23′ 28″`).
- **`sensors.dart` (Live Sensor Tracker, Shake Window & GPS Warm-Up)**:
  - `OrientationEngine` & `OrientationTracker`: Keeps a rolling `0.6`-second history of phone tilts so right when you press the shutter, it averages the moment before your finger tapped and measures shake degrees for the `"Hold steady…"` / auto-capture ring!
  - `LocationService`: Warms up GPS in the background while you aim so coordinates are already waiting when you snap the photo.

## Talks To
- Used by `CameraScreen` (live pointing readout, steadiness indicator, auto-capture countdown, capture metadata) and `SkyViewScreen` (60 fps live 3D sky dome orientation and compass calibration warnings).

---

## Important Code Blocks

### 1. Finding "Up" and "North" From Gravity + Magnetism Alone
**File:** `app/lib/sky_math.dart` (`rotationFromGravityAndMagnetic`)
```dart
var h = _cross(m, g); // East = magnetic field × gravity
final hNorm = _norm(h);
if (hNorm < 1e-6 || hNorm / (gNorm * _norm(m)) < 0.1) return null;
h = [for (final v in h) v / hNorm];
final a = [for (final v in g) v / gNorm]; // Up = straight against gravity
final n = _cross(a, h); // North = Up × East
return [...h, ...n, ...a];
```
- **In plain words:** Gravity always pulls straight down toward the center of the Earth, giving us a rock-solid **"Up"** arrow (`a`). Crossing Earth's magnetic arrow (`m`) with **"Up"** points straight **"East"** (`h`), and crossing **"Up"** with **"East"** points **"North"** (`n`)!
- **Why it matters:** Budget phones often lack gyroscopes (or their gyroscopes drift sideways over time). Computing orientation directly from gravity + magnetism guarantees above-horizon vs. below-horizon never flips upside down!
- **What goes in / what comes out:** 3-number gravity reading + 3-number magnetic reading → 9-number 3×3 world rotation matrix (or `null` if in free-fall).

### 2. Measuring Hand Shake Over the Last 0.6 Seconds
**File:** `app/lib/sensors.dart` (`OrientationEngine.shake` & `averaged`) & `app/lib/sky_math.dart` (`maxSpreadDeg`)
```dart
double maxSpreadDeg(List<List<double>> samples) {
  if (samples.length < 2) return 0;
  final avg = averageQuaternion(samples);
  return samples.map((q) => quaternionAngleDeg(q, avg)).reduce(math.max);
}
```
- **In plain words:** Looks at every tilt reading from the last `0.6` seconds, calculates the average direction you held the phone, and checks the biggest wobble away from that average in degrees.
- **Why it matters:** Night sky photos blur if your hands wiggle more than ~`1.5°`. This single number drives both the green **"Steady"** badge on the camera screen and the hands-free 2-second **Auto-capture** timer!
- **What goes in / what comes out:** Recent list of unit quaternions → maximum wobble angle in degrees.

### 3. Reading Physical Camera Lens Millimeters on Android
**File:** `app/android/app/src/main/kotlin/com/nightsky/night_sky/MainActivity.kt` (`night_sky/camera`)
```kotlin
val chars = manager.getCameraCharacteristics(cameraId)
val focal = chars.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)?.firstOrNull()
val size = chars.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)
result.success(mapOf("focalLength" to focal.toDouble(),
                     "sensorWidth" to size.width.toDouble(), "sensorHeight" to size.height.toDouble()))
```
- **In plain words:** Asks the Android camera chip *"How many millimeters wide is your light sensor, and how many millimeters long is your lens?"* so `fovFromOptics` can use basic triangle math (`2 * atan(side / (2 * focalLength))`) to know whether your camera sees `52°` or `68°` of sky!
- **Why it matters:** Giving the Backstage Lab an accurate field-of-view angle helps `tetra3` match stars much faster and ensures sensor-fallback sky maps match your photo's zoom scale.
- **What goes in / what comes out:** Rear camera ID → `{focalLength, sensorWidth, sensorHeight}` in millimeters.
