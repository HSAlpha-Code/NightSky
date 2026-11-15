import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sky/api_client.dart';
import 'package:night_sky/curated.dart';
import 'package:night_sky/screens/sky_view_screen.dart';
import 'package:night_sky/sensors.dart';
import 'package:night_sky/settings.dart';
import 'package:night_sky/sky_math.dart';
import 'package:night_sky/sky_view/astro_math.dart';
import 'package:night_sky/sky_view/panorama_loader.dart';
import 'package:night_sky/sky_view/sky_catalog.dart';
import 'package:night_sky/sky_view/sky_overlay_painter.dart';
import 'package:night_sky/sky_view/sky_sheets.dart';
import 'package:night_sky/sky_view/sky_sphere_painter.dart';
import 'package:night_sky/state.dart';
import 'package:night_sky/widgets/curated_viewer.dart';

import 'fake_backend.dart';

class _NullPanoramaNotifier extends MellingerPanoramaNotifier {
  @override
  MellingerPanorama? build() => null;
}

void main() {
  late SkyCatalog catalog;

  setUpAll(() {
    final starsBytes = File('assets/sky/stars.bin').readAsBytesSync();
    final catalogJson = File('assets/sky/sky_catalog.json').readAsStringSync();
    catalog = SkyCatalog.parse(
      starsBin: ByteData.sublistView(starsBytes),
      catalogJson: catalogJson,
    );
  });

  ProviderContainer makeContainer({
    MemorySettingsStore? settingsStore,
    FakeBackend? backend,
  }) {
    final b = backend ?? FakeBackend();
    final c = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(settingsStore ?? MemorySettingsStore()),
        cacheStoreProvider.overrideWithValue(MemoryCacheStore()),
        apiClientProvider.overrideWithValue(ApiClient('http://test', dio: fakeDio(b))),
        skyCatalogProvider.overrideWith((_) async => catalog),
        mellingerImageProvider.overrideWith(_NullPanoramaNotifier.new),
        skyShaderProgramProvider.overrideWith((_) async => null),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  testWidgets('graceful manual drag fallback, Mellinger credit, and pan updates pointing',
      (tester) async {
    final c = makeContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: SkyViewScreen(
            initialManualMode: true,
            initialAltDeg: 35,
            initialAzDeg: 180,
            initialUtc: DateTime.utc(2026, 11, 11, 22, 0),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Axel Mellinger'), findsOneWidget);
    expect(find.byKey(const Key('resume-live-compass')), findsOneWidget);
    expect(find.textContaining('Alt +35° · S 180°'), findsOneWidget);

    // Drag across the sky canvas and verify azimuth/altitude respond smoothly.
    await tester.drag(find.byKey(const Key('sky-view-canvas')), const Offset(-120, 60));
    await tester.pump();
    expect(find.textContaining('Alt +35° · S 180°'), findsNothing);
  });

  testWidgets('Time Machine scrubber steps time and resets to Live', (tester) async {
    final c = makeContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          home: SkyViewScreen(initialManualMode: true),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('time-machine-pill')), findsOneWidget);
    expect(find.textContaining('Live ·'), findsOneWidget);

    await tester.tap(find.byKey(const Key('time-machine-pill')));
    await tester.pump();
    expect(find.byKey(const Key('time-machine-panel')), findsOneWidget);

    await tester.tap(find.text('+1h'));
    await tester.pump();
    expect(find.byKey(const Key('time-reset-now')), findsOneWidget);

    await tester.tap(find.byKey(const Key('time-reset-now')));
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byKey(const Key('time-reset-now')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('manual observer location picker saves preset offline', (tester) async {
    final store = MemorySettingsStore();
    final c = makeContainer(settingsStore: store);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          home: SkyViewScreen(initialManualMode: true),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('sky-location-pill')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Observer location'), findsOneWidget);
    await tester.ensureVisible(find.text('Sydney, Australia'));
    await tester.tap(find.text('Sydney, Australia'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final s = c.read(settingsProvider);
    expect(s.useManualLocation, isTrue);
    expect(s.manualLatitude, closeTo(-33.8688, 1e-3));
    expect(find.text('Sydney, Australia'), findsOneWidget);
  });

  testWidgets('Find object guides user toward target and locks on when centered', (tester) async {
    final c = makeContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: SkyViewScreen(
            initialManualMode: true,
            initialAltDeg: 20,
            initialAzDeg: 0,
            initialUtc: DateTime.utc(2026, 11, 11, 22, 0),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(const Key('sky-find-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.enterText(find.byKey(const Key('sky-search-input')), 'Saturn');
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, 'Saturn').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const Key('sky-guide-banner')), findsOneWidget);
    expect(find.textContaining('Saturn'), findsOneWidget);

    if (find.byKey(const Key('guide-pan-button')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('guide-pan-button')));
      await tester.pump();
    }
    expect(find.textContaining('Centered on Saturn'), findsOneWidget);
  });

  testWidgets('tapping an object shows details and links to Curated Cosmic Highlights',
      (tester) async {
    final utc = DateTime.utc(2026, 11, 11, 22, 0);
    const lat = 28.6139, lon = 77.2090;
    final orion = catalog.deepSkyObjects.firstWhere((d) => d.id == 'NGC1976');
    final orionHor = raDecToAltAz(
      raDeg: orion.raDeg,
      decDeg: orion.decDeg,
      latitudeDeg: lat,
      longitudeDeg: lon,
      when: utc,
    );

    final backend = FakeBackend()
      ..json('GET /api/providers', providersJson)
      ..json('GET /api/curated/index/', {
        'version': 'v1',
        'bodies': [
          {'body_id': 'NGC1976', 'body_name': 'Great Orion Nebula', 'count': 1},
        ],
      })
      ..json('GET /api/curated/NGC1976/', {
        'body_id': 'NGC1976',
        'body_name': 'Great Orion Nebula',
        'version': 'v1',
        'highlights': [
          {
            'id': 1,
            'image_url': 'http://test/m42.jpg',
            'title': 'Orion Nebula in Infrared',
            'caption': 'JWST NIRCam view of the Trapezium.',
            'credit': 'NASA/ESA/CSA',
            'source_outlet': 'ESA/Webb',
            'source_url': 'https://esawebb.org',
          },
        ],
      });

    final c = makeContainer(backend: backend);
    c.listen(curatedIndexProvider, (_, _) {});
    for (var i = 0; i < 20 && c.read(curatedIndexProvider) == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
      await tester.pump();
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: SkyViewScreen(
            initialManualMode: true,
            initialAltDeg: orionHor.altitudeDeg,
            initialAzDeg: orionHor.azimuthDeg,
            initialUtc: utc,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Tap the exact centre of the sky canvas where NGC1976 (M42) is aimed.
    await tester.tapAt(tester.getCenter(find.byKey(const Key('sky-view-canvas'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Great Orion Nebula'), findsOneWidget);
    expect(find.byKey(const Key('sky-curated-link')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sky-curated-link')));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 30));
    }

    expect(find.byType(CuratedViewer), findsOneWidget);
    expect(find.text('JWST NIRCam view of the Trapezium.'), findsOneWidget);

    // Unmount cleanly so ticker stops before test tearDown.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('calibration sheet and layers/credits sheet open cleanly', (tester) async {
    final c = makeContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          home: SkyViewScreen(initialManualMode: true),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('sky-calibrate-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Sensors & compass calibration'), findsOneWidget);
    expect(find.textContaining('figure-8'), findsOneWidget);

    await tester.tapAt(const Offset(20, 20)); // dismiss modal sheet
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.byKey(const Key('sky-layers-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Sky Layers & Display'), findsOneWidget);
    expect(find.text('Graphics Quality'), findsOneWidget);
    expect(find.textContaining('Axel Mellinger'), findsWidgets);
    expect(find.textContaining('BSD-3-Clause'), findsOneWidget);

    // Toggling Milky Way, Stars, and Constellations updates the open sheet's chips live
    // without needing to close and reopen the panel.
    for (final (chipKey, readFlag) in <(String, bool Function(SkyLayerVisibility))>[
      ('layer-chip-milky-way', (l) => l.milkyWay),
      ('layer-chip-stars', (l) => l.stars),
      ('layer-chip-constellations', (l) => l.constellations),
    ]) {
      final finder = find.byKey(Key(chipKey));
      expect(tester.widget<FilterChip>(finder).selected, isTrue, reason: chipKey);
      await tester.tap(finder);
      await tester.pump();
      expect(tester.widget<FilterChip>(finder).selected, isFalse, reason: '$chipKey off');
      expect(readFlag(c.read(skyLayersProvider)), isFalse);
      await tester.tap(finder);
      await tester.pump();
      expect(tester.widget<FilterChip>(finder).selected, isTrue, reason: '$chipKey back on');
      expect(readFlag(c.read(skyLayersProvider)), isTrue);
    }

    // Horizon Shading chip toggles AppSettings.horizonShading and updates SkySpherePainter live.
    final shadingChip = find.byKey(const Key('layer-chip-horizon-shading'));
    expect(tester.widget<FilterChip>(shadingChip).selected, isTrue);
    await tester.tap(shadingChip);
    await tester.pump();
    expect(tester.widget<FilterChip>(shadingChip).selected, isFalse);
    expect(c.read(settingsProvider).horizonShading, isFalse);
    final spherePaint = tester.widget<CustomPaint>(
      find.byWidgetPredicate((w) => w is CustomPaint && w.painter is SkySpherePainter),
    );
    expect((spherePaint.painter! as SkySpherePainter).horizonShading, isFalse);
    await tester.tap(shadingChip);
    await tester.pump();
    expect(c.read(settingsProvider).horizonShading, isTrue);

    // Switching Graphics Quality keeps the SkyLayersSheet height completely stable (no jump).
    final initialHeight = tester.getSize(find.byType(SkyLayersSheet)).height;
    for (final label in ['Power saver', 'Max detail', 'Balanced']) {
      await tester.tap(find.text(label));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.getSize(find.byType(SkyLayersSheet)).height,
        closeTo(initialHeight, 0.01),
        reason: 'Panel height should not jump when selecting $label',
      );
    }

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('top toolbar fits on a narrow 360dp phone without clipping mode switch or settings',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final c = makeContainer();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const SkyViewScreen(initialManualMode: true),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);

    final modeSwitchRect = tester.getRect(find.byKey(const Key('switch-to-camera')));
    final settingsRect = tester.getRect(find.byTooltip('Settings'));
    expect(modeSwitchRect.left, greaterThanOrEqualTo(0));
    expect(modeSwitchRect.right, lessThanOrEqualTo(360));
    expect(settingsRect.left, greaterThanOrEqualTo(modeSwitchRect.right));
    expect(settingsRect.right, lessThanOrEqualTo(360));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets('sky_sphere.frag renders two-part shading when on and uniform brightness when off',
      (tester) async {
    Future<ui.Image> makeSolidTexture(int edge, int r, int g, int b) async {
      final pixels = Uint8List(edge * edge * 4);
      for (var i = 0; i < pixels.length; i += 4) {
        pixels[i] = r;
        pixels[i + 1] = g;
        pixels[i + 2] = b;
        pixels[i + 3] = 255;
      }
      final completer = ui.ImmutableBuffer.fromUint8List(pixels);
      final buffer = await completer;
      final desc = ui.ImageDescriptor.raw(
        buffer,
        width: edge,
        height: edge,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final codec = await desc.instantiateCodec();
      final frame = await codec.getNextFrame();
      codec.dispose();
      desc.dispose();
      buffer.dispose();
      return frame.image;
    }

    late final ui.FragmentProgram? program;
    late final MellingerPanorama pano;
    late final ByteData shadedRgba;
    late final ByteData uniformRgba;

    const w = 80, h = 80;
    final cam = SkyCamera.fromAltAz(
      altitudeDeg: 0.0,
      azimuthDeg: 180.0,
      latitudeDeg: 28.6139,
      longitudeDeg: 77.2090,
      when: DateTime.utc(2026, 11, 11, 12, 0),
      fovDeg: 60.0,
    );

    await tester.runAsync(() async {
      program = await ui.FragmentProgram.fromAsset(skySphereShaderAsset);
      final east = await makeSolidTexture(16, 110, 120, 140);
      final west = await makeSolidTexture(16, 110, 120, 140);
      pano = MellingerPanorama(east: east, west: west);

      Future<ByteData> renderFrame({required bool horizonShading}) async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        SkySpherePainter(
          camera: cam,
          panorama: pano,
          shaderProgram: program,
          sunAltitudeDeg: 15.0,
          showMilkyWay: true,
          showHorizon: false,
          horizonShading: horizonShading,
        ).paint(canvas, const Size(80, 80));
        final pic = recorder.endRecording();
        final image = await pic.toImage(w, h);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        image.dispose();
        pic.dispose();
        return bytes;
      }

      shadedRgba = await renderFrame(horizonShading: true);
      uniformRgba = await renderFrame(horizonShading: false);
      pano.dispose();
    });

    expect(program, isNotNull);

    double rowLum(ByteData rgba, int y) {
      var sum = 0.0;
      for (var x = 10; x < w - 10; x++) {
        final o = (y * w + x) * 4;
        sum += 0.299 * rgba.getUint8(o) +
            0.587 * rgba.getUint8(o + 1) +
            0.114 * rgba.getUint8(o + 2);
      }
      return sum / (w - 20);
    }

    // With horizonShading ON: upper sky (y=12, above horizon) is much brighter than ground (y=68).
    final shadedTop = rowLum(shadedRgba, 12);
    final shadedBottom = rowLum(shadedRgba, 68);
    expect((shadedTop - shadedBottom).abs(), greaterThan(40.0));

    // With horizonShading OFF: upper and lower halves have identical brightness!
    final uniformTop = rowLum(uniformRgba, 12);
    final uniformBottom = rowLum(uniformRgba, 68);
    expect((uniformTop - uniformBottom).abs(), lessThan(0.5));
  });

  testWidgets(
      'holding phone in landscape and touching for manual mode preserves landscape orientation without snapping to portrait',
      (tester) async {
    // Simulate a portrait-locked OS viewport (360x800) while the user physically holds the phone
    // sideways in landscape (90° CCW, earpiece on left, +X_dev pointing towards zenith).
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final utc = DateTime.utc(2026, 11, 11, 22, 0);
    final fwd = altAzToEnu(35.0, 180.0).normalized;
    final hRight = fwd.cross(Vec3.up).normalized;
    final hUp = hRight.cross(fwd).normalized;
    final m = Mat3.fromColumns(hUp, -hRight, -fwd);
    final q = matrixToQuaternion([
      m.m00, m.m01, m.m02,
      m.m10, m.m11, m.m12,
      m.m20, m.m21, m.m22,
    ]);

    final tracker = OrientationTracker(mode: SensorMode.gyro, alpha: 1.0);
    tracker.handleEventForTest([2, q[0], q[1], q[2], q[3], 3, 1000000, 0]);

    final c = makeContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: SkyViewScreen(
            initialManualMode: false,
            initialUtc: utc,
            orientationTracker: tracker,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    SkyCamera currentCam() {
      final cp = tester.widget<CustomPaint>(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter is SkySpherePainter),
      );
      return (cp.painter! as SkySpherePainter).camera;
    }

    // Live sensor mode: sky is oriented sideways (+90° roll) to match the landscape phone.
    expect(find.byKey(const Key('resume-live-compass')), findsNothing);
    final beforeTouch = currentCam();
    expect(beforeTouch.screenRollDeg, closeTo(90.0, 1.0));

    // Touch and drag in the user's landscape hand (+dy) — sky MUST stay at +90° (never snap to 0°!).
    final center = tester.getCenter(find.byKey(const Key('sky-view-canvas')));
    final gesture = await tester.startGesture(center);
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(0, 12));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    expect(find.byKey(const Key('resume-live-compass')), findsOneWidget);
    final afterTouch = currentCam();
    expect(
      afterTouch.screenRollDeg,
      closeTo(90.0, 1e-3),
      reason: 'Sky view must remain in landscape orientation and not snap to portrait mode',
    );
    // Dragging +dy (rightward in a 90° CCW landscape hand) decreases azimuth, leaving altitude ~steady.
    expect(afterTouch.centerAltAz.altitudeDeg, closeTo(beforeTouch.centerAltAz.altitudeDeg, 0.5));
    expect(afterTouch.centerAltAz.azimuthDeg, lessThan(beforeTouch.centerAltAz.azimuthDeg - 2.0));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets(
      'native landscape Sky View renders upright panoramic sky, handles manual drag, and toggles orientation mode',
      (tester) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final utc = DateTime.utc(2026, 11, 11, 22, 0);
    final fwd = altAzToEnu(35.0, 180.0).normalized;
    final hRight = fwd.cross(Vec3.up).normalized;
    final hUp = hRight.cross(fwd).normalized;
    final m = Mat3.fromColumns(hUp, -hRight, -fwd);
    final q = matrixToQuaternion([
      m.m00, m.m01, m.m02,
      m.m10, m.m11, m.m12,
      m.m20, m.m21, m.m22,
    ]);

    final tracker = OrientationTracker(mode: SensorMode.gyro, alpha: 1.0);
    tracker.handleEventForTest([2, q[0], q[1], q[2], q[3], 3, 1000000, 90]);

    final c = makeContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.2)),
            child: child!,
          ),
          home: SkyViewScreen(
            initialManualMode: false,
            initialUtc: utc,
            orientationTracker: tracker,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);

    SkyCamera currentCam() {
      final cp = tester.widget<CustomPaint>(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter is SkySpherePainter),
      );
      return (cp.painter! as SkySpherePainter).camera;
    }

    // In native landscape UI (displayRotation = 90°), horizon is upright (roll = 0°) and wide!
    expect(currentCam().screenRollDeg, closeTo(0.0, 1e-3));
    expect(currentCam().horizontalFovDeg(const Size(800, 360)), greaterThan(95.0));

    // Drag to enter manual mode in native landscape: roll stays 0° and HUD stays compact.
    await tester.drag(find.byKey(const Key('sky-view-canvas')), const Offset(-80, 30));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('resume-live-compass')), findsOneWidget);
    expect(currentCam().screenRollDeg, closeTo(0.0, 1e-3));

    // Expand Time Machine in short 360dp landscape and verify zero overflow.
    await tester.tap(find.byKey(const Key('time-machine-pill')));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('time-machine-panel')), findsOneWidget);

    // Open Sky Layers & Display sheet and switch Screen Orientation to Landscape.
    await tester.tap(find.byKey(const Key('sky-layers-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const Key('sky-orientation-segmented')), findsOneWidget);
    await tester.ensureVisible(find.text('Landscape'));
    await tester.tap(find.text('Landscape'));
    await tester.pump();
    expect(c.read(settingsProvider).orientationMode, ScreenOrientationMode.landscape);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 20));
  });
}
