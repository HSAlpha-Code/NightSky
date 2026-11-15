# The 3D Star Dome Projector, GPU Shader & Time Machine (`sky_view_screen.dart`, `sky_sphere_painter.dart`, `sky_overlay_painter.dart`, `sky_sphere.frag`, `sky_sheets.dart`, `time_machine_bar.dart`)

**Files covered in this guide:**
- `app/lib/screens/sky_view_screen.dart`
- `app/lib/sky_view/sky_sphere_painter.dart`
- `app/lib/sky_view/sky_overlay_painter.dart`
- `app/shaders/sky_sphere.frag`
- `app/lib/sky_view/sky_sheets.dart`
- `app/lib/sky_view/time_machine_bar.dart`

---

## Role
In our Handheld Planetarium, these files are the **Planetarium Dome Projector, Graphics-Chip Raytracer, Star & Moon Brush, Time Machine Lever, and Visitor Guidebooks** — painting the living 3D night sky on every frame and letting you search, scrub time, or aim at any world!

## Why They Exist
Drawing an 8K curved Milky Way photograph, thousands of glowing stars, constellation lines, a sunlit crescent Moon rotated toward the real Sun, and collision-free text labels 60 times every second would bog down a normal app unless the phone's **GPU** *(Graphics Processing Unit — the specialized chip built for super-fast pixel math)* and smart culling tricks work together.

## What's Inside
- **`sky_sphere.frag` (The GPU Pixel Raytracer)**: A tiny program written in **GLSL** *(OpenGL Shading Language — code that runs simultaneously for every single pixel on the phone's graphics chip)*. For each pixel on screen, it shoots a 3D ray into the Milky Way galaxy, blends four neighboring pixels smoothly across both `East` and `West` 4K textures (**bilinear filtering**) so there are zero blocky pixels or seam lines, adds blue twilight glow when the Sun is near the horizon, dims below-horizon ground gently, and applies a pure deep-red filter in **Night Vision** mode!
- **`sky_sphere_painter.dart` (The Dome Backdrop & Horizon Painter)**: Feeds camera vectors into `sky_sphere.frag` (with an automatic 24×16 triangle-mesh `drawVertices` fallback if a device lacks custom shader support), then draws the curved horizon line, `N / NE / E / SE / S / SW / W / NW` compass ticks, and center aiming reticle.
- **`sky_overlay_painter.dart` (The Star, Planet, Moon & Label Artist)**:
  - Highlights whichever constellation sits nearest the center of your view ("Constellation Spotlight").
  - Draws stars sorted brightest-first (stopping early at `effectiveLimitingMag`, and revealing fainter stars as you pinch-zoom in!), deep-sky diamonds/gold rings, Saturn's tilted ring oval, and a custom **Moon phase disc whose bright crescent automatically rotates to face the Sun's direction on screen**!
  - Places text labels in priority order while checking bounding boxes (`occupied.any((r) => r.overlaps(box))`) so two names never scribble over each other, and draws a green edge chevron pointing toward your searched target!
- **`sky_view_screen.dart` (The Dome Control Room)**: Runs a 60 fps `Ticker` for silky quaternion camera smoothing and `300×` timelapse playback (5 minutes of sky per real second!), handles pinch-to-zoom (`20°–95°` FOV) and 1-finger manual drag, and hosts the compact top HUD (`Search`, `Location`, `Layers`, `Calibrate`, `ModeSwitchPill`, `Settings`) + bottom HUD.
- **`time_machine_bar.dart` & `sky_sheets.dart`**: Expandable Time Machine scrubber (`±12h` slider, `-1d/-1h/+1h/+1d`, `300×` play, calendar picker, `Now` reset) plus five bottom sheets: `SkyObjectSheet`, `SkySearchSheet` (`Up tonight`, `Solar System`, `Highlights`, `Stars`, `Constellations`, `Deep sky`), `SkyLocationSheet` (offline world observatory presets), `SensorCalibrationSheet` (figure-8 compass guide), and `SkyLayersSheet`.

## Talks To
- Uses `SkyCamera`, `computeSolarSystem`, `SkyCatalog`, `MellingerPanorama`, `settingsProvider`, and `curatedIndexProvider`.
- Links directly to `CameraScreen` (via `ModeSwitchPill`) and `LandmarkDetailScreen` (via `Telescope close-up` / `Survey close-up` or `Curated Cosmic Highlights`).

---

## Important Code Blocks

### 1. Shooting One Ray Per Pixel Into the 8K Milky Way on the GPU
**File:** `app/shaders/sky_sphere.frag` (`main`)
```glsl
vec3 dir = normalize(fwd + (nx * uTanHalfFov) * rightV + (ny * uTanHalfFov) * upV);
float l = atan(dir.y, dir.x);
float b = asin(clamp(dir.z, -1.0, 1.0));
float u = fract(0.5 - l / TWO_PI);
float v = clamp(0.5 - b / PI, 0.0002, 0.9998);
vec3 sky = samplePanoramaBilinear(u, v, uHemiSize) * uExposure;
```
- **In plain words:** Every screen pixel `(nx, ny)` shoots a 3D laser pointer (`dir`) out from your phone into the Milky Way galaxy, converts that 3D arrow into galactic longitude (`l`) and latitude (`b`), and blends the exact color from the 8K Axel Mellinger panorama — millions of pixels calculated in parallel in ~1 millisecond!
- **Why it matters:** Produces zero distortion even at wide `95°` zoom-outs and zero seam lines where the East and West halves meet.
- **What goes in / what comes out:** Camera Galactic vectors + two 4K textures → full-screen perspective Milky Way backdrop.

### 2. Drawing the Moon's Lit Crescent Facing the Real Sun
**File:** `app/lib/sky_view/sky_overlay_painter.dart` (`_paintMoonPhaseDisc`)
```dart
final sunGuide = camera.guideTowards(sys.sun.icrs, size);
final angleToSun = math.atan2(sunGuide.screenDir.dy, sunGuide.screenDir.dx);
...
canvas.translate(center.dx, center.dy);
canvas.rotate(angleToSun);
final path = Path()..addArc(Rect.fromCircle(center: Offset.zero, radius: r), -math.pi / 2, math.pi);
final k = (2.0 * illum - 1.0) * r;
path.arcTo(Rect.fromCenter(center: Offset.zero, width: (k.abs() * 2).clamp(0.2, r * 2), height: r * 2),
           math.pi / 2, k >= 0 ? math.pi : -math.pi, false);
```
- **In plain words:** Finds which direction on screen the Sun sits relative to the Moon (`angleToSun`), rotates the paintbrush toward the Sun, and draws a half-circle combined with a stretched oval (**terminator** — *the shadow line between lunar day and night*) matching today's exact illumination fraction!
- **Why it matters:** Just like in the real sky, the bright horn of the Moon always points toward the Sun — even if the Sun has already set below the horizon!
- **What goes in / what comes out:** Moon screen position + `illum` (`0..1`) + Sun direction → realistic tilted lunar crescent/gibbous disc.
