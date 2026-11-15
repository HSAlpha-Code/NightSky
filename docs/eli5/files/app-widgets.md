# Reusable Glass Controls, Magic Curtain & Gallery Widgets (`app/lib/widgets/*.dart`)

**Files covered in this guide:**
- `app/lib/widgets/compare_view.dart`
- `app/lib/widgets/landmark_overlay.dart`
- `app/lib/widgets/magic_reveal.dart`
- `app/lib/widgets/glass.dart`
- `app/lib/widgets/camera_hints.dart`
- `app/lib/widgets/provider_picker.dart`
- `app/lib/widgets/result_widgets.dart`
- `app/lib/widgets/curated_viewer.dart`

---

## Role
In our Handheld Planetarium, these eight files are the **Interactive Gadgets and Frosted-Glass Display Cases** placed inside our rooms — the sliding before/after curtain, constant-size star pins, twinkling reveal stars, swipeable story gallery, and frosted-glass buttons.

## Why They Exist
Splitting tricky interactive pieces (like two-image synchronized pinch-zooming or smooth swipe dots) into dedicated widgets keeps screen files clean and lets multiple screens share the exact same look and touch behavior.

## What's Inside
- **`compare_view.dart` (The Synchronized Before/After Curtain)**: Stacks your original photo (clipped to the left of a vertical divider) over the survey sky map (with markers clipped to the right of the divider). Both zoom and pan together via `TransformationController` so stars stay perfectly aligned up to `8×` zoom! Uses `HitTestBehavior.translucent` on the 48 px divider drag strip so horizontal drags move the curtain while taps pass straight through to markers near the left edge.
- **`landmark_overlay.dart` (Zoom-Proof Sky Pins)**: Draws tappable circles over `(0..1, 0..1)` sky positions — **gold** for Webb/Hubble objects, **light blue** for catalog DSOs, **faint grey** while MAST is still checking, and **small white** for named stars — counter-scaled by `1 / scale` so pins stay the exact same finger-friendly size (`36×36` hit box) even when you zoom in `8×`!
- **`magic_reveal.dart` (The Twinkling Arrival Sparkle)**: Paints 35 tiny softly glowing four-pointed stars (`IgnorePointer`) that fade in and out for 1.8 seconds whenever a fresh survey image arrives (automatically skipped if your phone's "Reduce motion" accessibility setting is on).
- **`glass.dart` (Frosted Glass & Mode Switcher)**: Provides `Glass` (`BackdropFilter` blur + dark tint + hairline white border), `GlassIconButton`, and `ModeSwitchPill` (`[ 🌐 | 📷 ]`, the unmistakable 2-icon toggle between Sky View and Camera).
- **`camera_hints.dart`**: Floating camera pills — `CaptureTips`, `InfoBanner`, `SteadyIndicator`, and `PointingReadout` (`Alt +64° · S 176° · compass`).
- **`provider_picker.dart`**: Bottom sheet listing `/api/providers` (`DSS2 Color` and `Mellinger Color`) with descriptions and a `Default` badge.
- **`result_widgets.dart`**: Frosted `ProgressMessage` spinner card, `NoticeChip` floating pills, `Notice` retry banner, structured `InfoBar` coordinate/credit tiles, and full-screen `ErrorMessage` card.
- **`curated_viewer.dart`**: Horizontally swipeable `PageView` gallery for Curated Cosmic Highlights that pre-caches neighboring images (`_precacheAround`), animates pill-dots smoothly with your finger (switching to a `"3 / 12"` counter above 8 images), and opens NASA/ESA source articles in the browser.

## Talks To
- Assembled by `CameraScreen`, `ResultScreen`, `LandmarkDetailScreen`, and `SkyViewScreen`.

---

## Important Code Blocks

### 1. Letting Taps Reach Left-Edge Star Pins Through the Divider Drag Strip
**File:** `app/lib/widgets/compare_view.dart` (`CompareViewState.build`)
```dart
Positioned(
  key: const Key('compare-divider'),
  left: (x - CompareView.dividerHitWidth / 2).clamp(
      0.0, math.max(0.0, box.maxWidth - CompareView.dividerHitWidth)),
  top: 0, bottom: 0,
  width: math.min(CompareView.dividerHitWidth, box.maxWidth),
  child: GestureDetector(
    behavior: HitTestBehavior.translucent,
    dragStartBehavior: DragStartBehavior.down,
    onHorizontalDragUpdate: (d) => _dragSplit(split + d.delta.dx / box.maxWidth),
  ),
),
```
- **In plain words:** Places an invisible 48-pixel-wide strip around the curtain line. Marking it `translucent` lets both the strip *and* any star pin underneath enter Flutter's touch contest: if you slide sideways, the curtain wins and moves; if you tap without sliding, the curtain steps aside and the star pin underneath opens!
- **Why it matters:** When the curtain starts all the way on the left (`split = 0`), an opaque strip would swallow taps on stars near the left edge of the screen.
- **What goes in / what comes out:** Finger touch/drag events → either `_dragSplit(...)` curtain movement or `LandmarkMarker.onTap`.

### 2. Counter-Scaling Pins So Zooming In Doesn't Make Giant Circles
**File:** `app/lib/widgets/landmark_overlay.dart` (`LandmarkOverlay.build`)
```dart
Positioned(
  left: lm.x * box.maxWidth - hitSize / 2,
  top: lm.y * box.maxHeight - hitSize / 2,
  child: Transform.scale(
    scale: 1 / scale,
    child: LandmarkMarker(landmark: lm, onTap: () => onTap(lm)),
  ),
)
```
- **In plain words:** Because `LandmarkOverlay` sits *inside* the zoomable sky picture, zooming in `4×` would normally blow up every marker circle `4×` bigger too — so `Transform.scale(scale: 1 / scale)` shrinks each marker by `1/4` at the exact same moment, canceling the zoom!
- **Why it matters:** Markers stay glued to their exact stars when you pan around, yet always stay a neat, crisp size on glass.
- **What goes in / what comes out:** Landmark `(x, y)` fractions + current zoom `scale` → crisp constant-size tappable rings.
