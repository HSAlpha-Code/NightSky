import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:night_sky/api_client.dart';
import 'package:night_sky/models.dart';
import 'package:night_sky/screens/result_screen.dart';
import 'package:night_sky/state.dart';
import 'package:night_sky/widgets/compare_view.dart';
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
    // The image box is 300 wide (aspect 0.75 in 300x400). A slow gesture avoids touch-slop loss.
    final gesture = await tester.startGesture(tester.getCenter(find.byType(GestureDetector).last)
        .translate(-150 + 1, 0));
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

    expect(find.textContaining('Approximate position'), findsOneWidget);
    expect(find.text('DSS2 is down; showing Mellinger instead.'), findsOneWidget);
    expect(find.byKey(const Key('compare-slider')), findsOneWidget);
    expect(find.textContaining('NASA SkyView'), findsOneWidget);
    expect(find.textContaining('05h 35m 17s'), findsOneWidget);

    await tester.tap(find.text('My photo'));
    await tester.pump();
    expect(tester.widget<Slider>(find.byKey(const Key('compare-slider'))).value, 1);
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
