import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:night_sky/api_client.dart';
import 'package:night_sky/models.dart';
import 'package:night_sky/screens/camera_screen.dart';
import 'package:night_sky/screens/landmark_detail_screen.dart';
import 'package:night_sky/screens/result_screen.dart';
import 'package:night_sky/state.dart';
import 'package:night_sky/widgets/compare_view.dart';
import 'package:night_sky/widgets/landmark_overlay.dart';
import 'package:night_sky/widgets/magic_reveal.dart';
import 'package:night_sky/widgets/provider_picker.dart';

import 'fake_backend.dart';

void main() {
  final png = Uint8List.fromList(img.encodePng(img.Image(width: 30, height: 40)));

  testWidgets('provider list shows all providers and reports the tap', (tester) async {
    String? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProviderList(
          catalog: ProviderCatalog.fromJson(providersJson),
          selectedKey: 'dss2_color',
          onSelected: (k) => picked = k,
        ),
      ),
    ));
    expect(find.text('DSS2 Color'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    await tester.tap(find.text('Mellinger Color'));
    expect(picked, 'skyview_mellinger');
  });

  testWidgets('compare view drag moves the divider', (tester) async {
    final key = GlobalKey<CompareViewState>();
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 300,
          height: 400,
          child: CompareView(
            key: key,
            original: MemoryImage(png),
            replacement: MemoryImage(png),
            aspectRatio: 0.75,
          ),
        ),
      ),
    ));
    expect(tester.getSize(find.byType(AspectRatio)), const Size(300, 400));
    expect(key.currentState!.split, 0);
    // The image box is 300 wide (aspect 0.75 in 300x400) and the divider starts at its left
    // edge, so the drag starts on the divider strip. A slow gesture avoids touch-slop loss.
    final gesture = await tester.startGesture(
        tester.getTopLeft(find.byType(AspectRatio)).translate(1, 200));
    for (var i = 0; i < 15; i++) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    await gesture.up();
    // 150 px moved, minus the drag-start slop (≤ 18 px) -> between 0.44 and 0.5.
    expect(key.currentState!.split, inInclusiveRange(0.44, 0.5));
    // The divider follows the split.
    expect(find.byIcon(Icons.compare_arrows), findsOneWidget);
  });

  testWidgets('landmarks in the leftmost divider strip are clickable without zooming',
      (tester) async {
    final key = GlobalKey<CompareViewState>();
    final tapped = <String>[];
    const leftEdgeLandmark = Landmark(
      id: 'HIP1',
      name: 'Left Edge Star',
      kind: 'star',
      typeLabel: 'Star',
      x: 0.04, // 12 px from left in a 300 px box, inside the 48 px divider hit strip
      y: 0.5,
    );
    const midLandmark = Landmark(
      id: 'M42',
      name: 'Mid Nebula',
      kind: 'dso',
      typeLabel: 'Nebula',
      x: 0.53, // 159 px: 9 px right of a 0.5 split, still inside dividerHitWidth / 2 (24 px)
      y: 0.5,
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 400,
            child: CompareView(
              key: key,
              original: MemoryImage(png),
              replacement: MemoryImage(png),
              aspectRatio: 0.75,
              overlayBuilder: (scale) => LandmarkOverlay(
                landmarks: const [leftEdgeLandmark, midLandmark],
                scale: scale,
                onTap: (lm) => tapped.add(lm.id),
              ),
            ),
          ),
        ),
      ),
    ));

    // At split = 0 and 1x zoom, tapping a landmark near the left edge reaches it directly.
    await tester.tap(find.byTooltip('Left Edge Star'));
    await tester.pump();
    expect(tapped, ['HIP1']);

    // Horizontal drag starting in the leftmost strip still moves the divider cleanly
    // without panning, even when zoomed in.
    key.currentState!.zoom.value = Matrix4.diagonal3Values(2, 2, 1);
    await tester.pump();
    final beforeZoom = key.currentState!.zoom.value.clone();
    final gesture =
        await tester.startGesture(tester.getTopLeft(find.byType(AspectRatio)).translate(12, 100));
    for (var i = 0; i < 15; i++) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    await gesture.up();
    expect(key.currentState!.split, closeTo(0.5, 1e-6));
    expect(key.currentState!.zoom.value, beforeZoom);
    key.currentState!.resetZoom();
    await tester.pump();

    // Left of the divider is hidden under the original photo (not tappable); right of the
    // divider is tappable even within dividerHitWidth / 2 of the divider line.
    await tester.tap(find.byTooltip('Left Edge Star'), warnIfMissed: false);
    await tester.pump();
    expect(tapped, ['HIP1']);

    await tester.tap(find.byTooltip('Mid Nebula'));
    await tester.pump();
    expect(tapped, ['HIP1', 'M42']);
  });

  testWidgets('compare view: pinch zooms both images, markers keep their size, reset',
      (tester) async {
    final key = GlobalKey<CompareViewState>();
    double? overlayScale;
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 300,
          height: 400,
          child: CompareView(
            key: key,
            original: MemoryImage(png),
            replacement: MemoryImage(png),
            aspectRatio: 0.75,
            initialSplit: 0.5,
            overlayBuilder: (scale) {
              overlayScale = scale;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    ));
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byTooltip('Reset zoom'), findsNothing);

    // Pinch out around a point on the survey half (right of the divider).
    final centre = tester.getCenter(find.byType(AspectRatio)).translate(70, 50);
    final a = await tester.startGesture(centre.translate(-10, 0));
    final b = await tester.startGesture(centre.translate(10, 0), pointer: 2);
    for (var i = 0; i < 10; i++) {
      await a.moveBy(const Offset(-6, 0));
      await b.moveBy(const Offset(6, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();

    final state = key.currentState!;
    expect(state.scale, greaterThan(1.5));
    expect(overlayScale, closeTo(state.scale, 1e-6)); // overlay told the zoom level
    expect(state.split, 0.5); // pinching doesn't move the divider
    // The original photo is drawn with the same transform as the zoomed survey image.
    final photo = tester.widget<Transform>(find.descendant(
        of: find.byType(IgnorePointer), matching: find.byType(Transform)).first);
    expect(photo.transform, state.zoom.value);

    await tester.tap(find.byTooltip('Reset zoom'));
    await tester.pumpAndSettle();
    expect(state.scale, 1);
    expect(find.byTooltip('Reset zoom'), findsNothing);
  });

  testWidgets('markers stay the same on-screen size when zoomed', (tester) async {
    final lm = Landmark.fromJson((landmarksJson()['landmarks'] as List).first);
    Future<Size> markerSize(double scale) async {
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: SizedBox(
            width: 300,
            height: 300,
            child: LandmarkOverlay(landmarks: [lm], scale: scale, onTap: (_) {}),
          ),
        ),
      ));
      final box = tester.renderObject<RenderBox>(find.byKey(const Key('hires-marker')));
      final topLeft = box.localToGlobal(Offset.zero);
      final bottomRight = box.localToGlobal(box.size.bottomRight(Offset.zero));
      return Size(bottomRight.dx - topLeft.dx, bottomRight.dy - topLeft.dy);
    }

    expect(await markerSize(1), const Size(16, 16));
    expect(await markerSize(4), const Size(4, 4)); // the zoom (x4) brings it back to 16
  });

  testWidgets('result screen shows approximate notice, fallback notice and slider',
      (tester) async {
    final backend = FakeBackend()
      ..json('POST /api/solve', solveJson)
      ..image('POST /api/sky-image', png, {
        'X-Provider': 'skyview_mellinger',
        'X-Credit': 'NASA SkyView',
        'X-Fallback-Used': 'true',
        'X-Fallback-Message': 'DSS2 is down; showing Mellinger instead.',
      });
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(ApiClient('http://test', dio: fakeDio(backend))),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ResultScreen()),
    ));
    // compute() runs in a real isolate, so let it finish outside the fake clock.
    await tester.runAsync(() => container
        .read(sessionProvider.notifier)
        .start(png, CaptureMetadata(timestampUtc: DateTime.utc(2026))));
    await tester.pump();

    // Notices are compact chips over the image; tapping one shows the full text.
    expect(find.text('Approximate position'), findsOneWidget);
    expect(find.text('Different image source'), findsOneWidget);
    await tester.tap(find.text('Different image source'));
    await tester.pump();
    expect(find.text('DSS2 is down; showing Mellinger instead.'), findsOneWidget);
    expect(find.byKey(const Key('compare-slider')), findsOneWidget);

    await tester.tap(find.text('My photo'));
    await tester.pump();
    expect(tester.widget<Slider>(find.byKey(const Key('compare-slider'))).value, 1);

    // Coordinates and credit are hidden behind the ⓘ button.
    expect(find.textContaining('05h 35m 17s'), findsNothing);
    await tester.tap(find.byTooltip('Details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('NASA SkyView'), findsOneWidget);
    expect(find.textContaining('05h 35m 17s'), findsOneWidget);
  });

  testWidgets('"Fetching the survey image" shows Cancel, which stops the wait', (tester) async {
    final backend = FakeBackend()
      ..json('POST /api/solve', solveJson)
      ..hang('POST /api/sky-image');
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(ApiClient('http://test', dio: fakeDio(backend))),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ResultScreen()),
    ));
    final session = container.read(sessionProvider.notifier);
    await tester.runAsync(() async {
      unawaited(session.start(png, CaptureMetadata(timestampUtc: DateTime.utc(2026))));
      while (container.read(sessionProvider).stage != Stage.fetchingImage) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    expect(find.text('Fetching the survey image…'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pump();
    expect(find.text('Fetching the survey image…'), findsNothing);
    expect(find.textContaining('Survey image cancelled.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('landmark markers: styles, tap opens the detail view with credit',
      (tester) async {
    final jpeg = Uint8List.fromList(img.encodeJpg(img.Image(width: 8, height: 8)));
    final backend = FakeBackend()
      ..json('POST /api/solve', solveJson)
      ..image('POST /api/sky-image', png, {'X-Provider': 'dss2_color', 'X-Credit': 'DSS2'})
      ..json('GET /api/landmarks', landmarksJson())
      ..json('GET /api/providers', providersJson);
    backend.handlers['GET /api/landmark-detail'] = (o) {
      final survey = o.queryParameters['view'] == 'survey';
      return ResponseBody.fromString(
          jsonEncode({
            'landmark': {},
            'view': o.queryParameters['view'],
            'image_source': survey ? 'survey' : 'jwst',
            'available_views': ['jwst', 'hst', 'survey'],
            'credit': survey
                ? 'DSS2 Color via CDS hips2fits'
                : 'James Webb Space Telescope (NASA/ESA/CSA) via ESA ESASky HiPS',
            'caption': survey ? 'DSS2 Color · 9′ field' : 'JWST NIRCam · 40% of the field imaged',
            'fov': 0.2,
            'image_jpeg_base64': base64Encode(jpeg),
          }),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json']
          });
    };
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(ApiClient('http://test', dio: fakeDio(backend))),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ResultScreen()),
    ));
    await tester.runAsync(() async {
      await container
          .read(sessionProvider.notifier)
          .start(png, CaptureMetadata(timestampUtc: DateTime.utc(2026)));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    expect(find.byType(LandmarkMarker), findsNWidgets(2));
    // M42 has a Webb/Hubble image: a plain gold circle, no icon inside.
    expect(find.byKey(const Key('hires-marker')), findsOneWidget);
    final gold = tester.widget<Container>(find.byKey(const Key('hires-marker')));
    final deco = gold.decoration! as BoxDecoration;
    expect(deco.shape, BoxShape.circle);
    expect(deco.color, isNull);
    expect((deco.border! as Border).top.color, Colors.amber);
    expect(find.descendant(of: find.byType(LandmarkMarker), matching: find.byType(Icon)),
        findsNothing);
    expect(find.byTooltip('Hide landmarks'), findsOneWidget);

    await tester.tap(find.byTooltip('Great Orion Nebula'));
    await tester.pumpAndSettle(); // route transition; the detail request starts
    // The (fake) HTTP call and base64 decode complete on the real event loop.
    for (var i = 0; i < 20 && find.byType(InteractiveViewer).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    // Facts and credit are shown by default.
    // The detail list scrolls: facts and credit sit below the square image in a 800x600 test view.
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pump();
    expect(find.text('Great Orion Nebula'), findsOneWidget); // app bar of the detail view
    expect(find.text('James Webb Space Telescope mosaic'), findsOneWidget);
    expect(find.textContaining('ESA ESASky'), findsOneWidget);
    expect(find.text('Star cluster with nebula'), findsOneWidget);
    expect(find.text('M42, NGC 1976'), findsOneWidget);
    Map<String, dynamic> lastDetailQuery() =>
        backend.requests.lastWhere((r) => r.path == '/landmark-detail').queryParameters;
    expect(lastDetailQuery(), {'id': 'NGC1976', 'view': 'auto', 'provider': 'dss2_color'});

    // Only verified detail-capable views appear: Webb, Hubble, DSS2 Color (never field-only Mellinger).
    await tester.drag(find.byType(ListView).first, const Offset(0, 800)); // back to top
    await tester.pump();
    for (final label in ['Webb', 'Hubble', 'DSS2 Color']) {
      expect(find.widgetWithText(ChoiceChip, label), findsOneWidget, reason: label);
    }
    expect(find.widgetWithText(ChoiceChip, 'Mellinger Color'), findsNothing);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Webb')).selected, isTrue);

    final dssChip = find.widgetWithText(ChoiceChip, 'DSS2 Color');
    await tester.ensureVisible(dssChip);
    await tester.pumpAndSettle();
    await tester.tap(dssChip);
    expect(tester.widget<ChoiceChip>(dssChip).selected, isFalse); // not until rebuilt
    await tester.pump();
    expect(tester.widget<ChoiceChip>(dssChip).selected, isTrue);
    // Dio dispatches on a timer (fake clock) and decodes on the real event loop: drive both.
    for (var i = 0; i < 30 && find.byType(InteractiveViewer).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    expect(lastDetailQuery(), {'id': 'NGC1976', 'view': 'survey', 'provider': 'dss2_color'});
    await tester.drag(find.byType(ListView).first, const Offset(0, -600)); // credit is below
    await tester.pump();
    expect(find.text('Survey close-up'), findsOneWidget);
    expect(find.textContaining('DSS2 Color via CDS hips2fits'), findsOneWidget);

    // Back on the result screen, markers can be hidden.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Hide landmarks'));
    await tester.pump();
    expect(find.byType(LandmarkMarker), findsNothing);
  });

  testWidgets('detail screen hides Webb when unavailable and goes straight to DSS2 for stars',
      (tester) async {
    final jpeg = Uint8List.fromList(img.encodeJpg(img.Image(width: 8, height: 8)));
    const hubbleOnlyDso = Landmark(
      id: 'NGC6205',
      name: 'Hercules Cluster',
      kind: 'dso',
      typeLabel: 'Globular cluster',
      x: 0.5,
      y: 0.5,
      hasHires: true,
    );
    const star = Landmark(
      id: 'HIP91262',
      name: 'Vega',
      kind: 'star',
      typeLabel: 'Star',
      x: 0.3,
      y: 0.3,
      hasHires: false,
    );

    final backend = FakeBackend()..json('GET /api/providers', providersJson);
    backend.handlers['GET /api/landmark-detail'] = (o) {
      final id = o.queryParameters['id'];
      final isStar = id == 'HIP91262';
      return ResponseBody.fromString(
        jsonEncode({
          'landmark': {},
          'view': o.queryParameters['view'],
          'image_source': isStar ? 'survey' : 'hst',
          'available_views': isStar ? ['survey'] : ['hst', 'survey'],
          'credit': isStar ? 'DSS2' : 'Hubble Space Telescope',
          'caption': '',
          'fov': 0.2,
          'image_jpeg_base64': base64Encode(jpeg),
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    };

    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(ApiClient('http://test', dio: fakeDio(backend))),
    ]);
    addTearDown(container.dispose);

    // 1. DSO with Hubble only, opened from a Mellinger field view:
    //    Webb and Mellinger never appear; Hubble is selected with zero duplicate fetch.
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: LandmarkDetailScreen(landmark: hubbleOnlyDso, providerKey: 'skyview_mellinger'),
      ),
    ));
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.widgetWithText(ChoiceChip, 'Webb'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'Mellinger Color'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'Hubble'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'DSS2 Color'), findsOneWidget);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Hubble')).selected, isTrue);
    expect(
      backend.requests.where((r) => r.path == '/landmark-detail').length,
      1,
      reason: 'Resolving auto -> Hubble should reuse cached image without re-downloading',
    );

    // 2. Star: goes straight to view=survey&provider=dss2_color without probing telescopes.
    backend.requests.clear();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: LandmarkDetailScreen(landmark: star, providerKey: 'skyview_mellinger'),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.widgetWithText(ChoiceChip, 'Webb'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'Hubble'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'DSS2 Color'), findsOneWidget);
    final starQuery =
        backend.requests.singleWhere((r) => r.path == '/landmark-detail').queryParameters;
    expect(starQuery, {'id': 'HIP91262', 'view': 'survey', 'provider': 'dss2_color'});
  });

  testWidgets('magic reveal plays when a new image arrives, then gets out of the way',
      (tester) async {
    var taps = 0;
    Widget build(Object? trigger) => MaterialApp(
          home: SizedBox(
            width: 300,
            height: 400,
            child: MagicReveal(
              trigger: trigger,
              child: TextButton(onPressed: () => taps++, child: const Text('image')),
            ),
          ),
        );

    await tester.pumpWidget(build(null));
    expect(find.byKey(const Key('magic-reveal')), findsNothing); // nothing to reveal yet

    final first = Object();
    await tester.pumpWidget(build(first));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('magic-reveal')), findsOneWidget);
    // The image underneath stays usable while the ripple plays.
    await tester.tap(find.text('image'));
    expect(taps, 1);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('magic-reveal')), findsNothing);

    await tester.pumpWidget(build(first)); // same image: no replay
    expect(find.byKey(const Key('magic-reveal')), findsNothing);
    await tester.pumpWidget(build(Object())); // another image: plays again
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('magic-reveal')), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('magic reveal is skipped with reduced motion', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MagicReveal(trigger: Object(), child: const Text('image')),
      ),
    ));
    await tester.pump();
    expect(find.byKey(const Key('magic-reveal')), findsNothing);
    expect(find.text('image'), findsOneWidget);
  });

  testWidgets('landmark detail: facts are hidden until "Show details" is tapped',
      (tester) async {
    // Phone-shaped view, so the toggle under the square image is laid out.
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final lm = Landmark.fromJson((landmarksJson()['landmarks'] as List).first);
    final backend = FakeBackend()..json('GET /api/providers', providersJson);
    backend.hang('GET /api/landmark-detail');
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(ApiClient('http://test', dio: fakeDio(backend))),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: LandmarkDetailScreen(landmark: lm)),
    ));
    await tester.pump();

    // Shown by default. The image is still loading (spinner never settles), so pump past the
    // 250 ms animation after each toggle.
    expect(find.byKey(const Key('landmark-details')), findsOneWidget);
    expect(find.text('M42, NGC 1976'), findsOneWidget);
    expect(find.text('Hide details'), findsOneWidget);
    await tester.tap(find.byKey(const Key('details-toggle')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('landmark-details')), findsNothing);
    expect(find.text('M42, NGC 1976'), findsNothing);
    expect(find.text('Show details'), findsOneWidget);

    await tester.tap(find.byTooltip('Show details')); // the app-bar button toggles too
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('M42, NGC 1976'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // cancels the hanging request
  });

  test('formatDistance', () {
    expect(formatDistance(440), '440 light-years');
    expect(formatDistance(1344), '1344 light-years');
    expect(formatDistance(25000), '25 thousand light-years');
    expect(formatDistance(2.5e6), '2.5 million light-years');
  });

  testWidgets('solve failure shows a friendly error with "Take another"', (tester) async {
    final backend = FakeBackend()
      ..json('POST /api/solve',
          {'error': {'code': 'SOLVE_FAILED', 'message': 'Too cloudy.'}}, status: 422);
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(ApiClient('http://test', dio: fakeDio(backend))),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ResultScreen()),
    ));
    await tester.runAsync(() => container
        .read(sessionProvider.notifier)
        .start(png, CaptureMetadata(timestampUtc: DateTime.utc(2026))));
    await tester.pump();
    expect(find.text("We couldn't place this photo"), findsOneWidget);
    expect(find.text('Too cloudy.'), findsOneWidget);
    expect(find.text('Take another'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('CameraScreen, ResultScreen and LandmarkDetailScreen fit 800x360 landscape cleanly',
      (tester) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const sensorEventChannel = MethodChannel('night_sky/sensor_events');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      sensorEventChannel,
      (call) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        sensorEventChannel,
        null,
      ),
    );

    final landscapePng = Uint8List.fromList(img.encodePng(img.Image(width: 64, height: 48)));
    final backend = FakeBackend()
      ..json('POST /api/solve', solveJson)
      ..image('POST /api/sky-image', landscapePng, {'X-Provider': 'dss2_color', 'X-Credit': 'DSS2'})
      ..json('GET /api/landmarks', landmarksJson())
      ..json('GET /api/providers', providersJson);

    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(ApiClient('http://test', dio: fakeDio(backend))),
    ]);
    addTearDown(container.dispose);

    // 1. CameraScreen in 800x360 landscape with 1.3x text scale: right-side shutter, zero overflow.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const CameraScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    final shutterRect = tester.getRect(find.byKey(const Key('shutter')));
    expect(shutterRect.center.dx, greaterThan(600)); // ergonomic right-hand shutter rail
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    // 2. ResultScreen in 800x360 landscape (both solved and error states): zero overflow.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const ResultScreen(),
        ),
      ),
    );
    await tester.runAsync(
      () => container
          .read(sessionProvider.notifier)
          .start(landscapePng, CaptureMetadata(timestampUtc: DateTime.utc(2026))),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('compare-slider')), findsOneWidget);

    // Also check solve failure ErrorMessage on short 360dp landscape height.
    backend.json(
      'POST /api/solve',
      {'error': {'code': 'SOLVE_FAILED', 'message': 'Too cloudy.'}},
      status: 422,
    );
    await tester.runAsync(
      () => container
          .read(sessionProvider.notifier)
          .start(landscapePng, CaptureMetadata(timestampUtc: DateTime.utc(2026))),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Take another'), findsOneWidget);

    // 3. LandmarkDetailScreen in 800x360 landscape: compact image stage, zero overflow.
    final lm = Landmark.fromJson((landmarksJson()['landmarks'] as List).first);
    backend.hang('GET /api/landmark-detail');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: LandmarkDetailScreen(landmark: lm)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 20));
  });
}
