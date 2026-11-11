import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sky/api_client.dart';
import 'package:night_sky/curated.dart';
import 'package:night_sky/screens/sky_view_screen.dart';
import 'package:night_sky/settings.dart';
import 'package:night_sky/sky_view/astro_math.dart';
import 'package:night_sky/sky_view/panorama_loader.dart';
import 'package:night_sky/sky_view/sky_catalog.dart';
import 'package:night_sky/state.dart';
import 'package:night_sky/widgets/curated_viewer.dart';

import 'fake_backend.dart';

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
        mellingerImageProvider.overrideWith((_) async => null),
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
    expect(find.text('Sky layers & display'), findsOneWidget);
    expect(find.textContaining('Axel Mellinger'), findsWidgets);
    expect(find.textContaining('BSD-3-Clause'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
