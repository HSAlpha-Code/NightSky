import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:night_sky/api_client.dart';
import 'package:night_sky/models.dart';
import 'package:night_sky/screens/landmark_detail_screen.dart';
import 'package:night_sky/screens/result_screen.dart';
import 'package:night_sky/state.dart';
import 'package:night_sky/widgets/compare_view.dart';
import 'package:night_sky/widgets/landmark_overlay.dart';
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
    await tester.tap(find.text('Pan-STARRS DR2 (STScI)'));
    expect(picked, 'panstarrs');
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
            'credit': survey
                ? 'Pan-STARRS1 via STScI'
                : 'James Webb Space Telescope (NASA/ESA/CSA) via ESA ESASky HiPS',
            'caption': survey ? 'Pan-STARRS · 9′ field' : 'JWST NIRCam · 40% of the field imaged',
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

    // Point-of-view chips: Best, Webb, Hubble + one per survey from /providers.
    await tester.drag(find.byType(ListView).first, const Offset(0, 800)); // back to top
    await tester.pump();
    for (final label in ['Best', 'Webb', 'Hubble', 'DSS2 Color', 'Pan-STARRS DR2 (STScI)']) {
      expect(find.widgetWithText(ChoiceChip, label), findsOneWidget, reason: label);
    }
    final panstarrs = find.widgetWithText(ChoiceChip, 'Pan-STARRS DR2 (STScI)');
    await tester.ensureVisible(panstarrs); // chip row scrolls horizontally
    await tester.pumpAndSettle();
    await tester.tap(panstarrs);
    expect(tester.widget<ChoiceChip>(panstarrs).selected, isFalse); // not until rebuilt
    await tester.pump();
    expect(tester.widget<ChoiceChip>(panstarrs).selected, isTrue);
    // Dio dispatches on a timer (fake clock) and decodes on the real event loop: drive both.
    for (var i = 0; i < 30 && find.byType(InteractiveViewer).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    expect(lastDetailQuery(), {'id': 'NGC1976', 'view': 'survey', 'provider': 'panstarrs'});
    await tester.drag(find.byType(ListView).first, const Offset(0, -600)); // credit is below
    await tester.pump();
    expect(find.text('Survey close-up'), findsOneWidget);
    expect(find.textContaining('Pan-STARRS1 via STScI'), findsOneWidget);

    // Back on the result screen, markers can be hidden.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Hide landmarks'));
    await tester.pump();
    expect(find.byType(LandmarkMarker), findsNothing);
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
}
