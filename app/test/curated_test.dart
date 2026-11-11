import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:night_sky/api_client.dart';
import 'package:night_sky/curated.dart';
import 'package:night_sky/models.dart';
import 'package:night_sky/screens/landmark_detail_screen.dart';
import 'package:night_sky/state.dart';
import 'package:night_sky/widgets/curated_viewer.dart';

import 'fake_backend.dart';

List<CuratedHighlight> highlights(int n) => [
      for (var i = 0; i < n; i++)
        CuratedHighlight(
          id: i,
          imageUrl: 'http://test/img$i.jpg',
          title: 'Title $i',
          caption: 'Caption $i',
          credit: 'Credit $i',
          sourceOutlet: 'Outlet $i',
          sourceUrl: 'https://example.org/$i',
        ),
    ];

Widget viewer(List<CuratedHighlight> items,
        {ValueChanged<String>? onOpenLink, ValueChanged<int>? onPageChanged, int initial = 0}) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          // 400 wide -> 300 high image, so the dots below stay on the 800x600 test screen.
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 400,
              child: CuratedViewer(
                  highlights: items,
                  initialPage: initial,
                  onOpenLink: onOpenLink,
                  onPageChanged: onPageChanged),
            ),
          ),
        ),
      ),
    );

/// Lets the fake HTTP calls finish (real event loop) and fires the zero-length timers dio uses.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 10));
  }
}

/// A working survey close-up, so the detail screen's other source doesn't fail and retry.
void withDetailImage(FakeBackend backend) => backend.json('GET /api/landmark-detail', {
      'landmark': {},
      'view': 'auto',
      'image_source': 'survey',
      'credit': 'Survey',
      'caption': '',
      'fov': 0.2,
      'image_jpeg_base64': base64Encode(img.encodeJpg(img.Image(width: 8, height: 8))),
    });

/// Close the screen so providers' retry timers are cancelled before the test ends.
Future<void> leave(WidgetTester tester) => tester.pumpWidget(const SizedBox());

double dotWidth(WidgetTester t, int i) => t.getSize(find.byKey(Key('curated-dot-$i'))).width;

class _FixedServerUrl extends ServerUrlNotifier {
  _FixedServerUrl(this.url);

  final String url;

  @override
  String build() => url;
}

void main() {
  group('CuratedViewer', () {
    testWidgets('one image: no dots, no swiping', (tester) async {
      await tester.pumpWidget(viewer(highlights(1)));
      expect(find.byKey(const Key('curated-dot-0')), findsNothing);
      expect(find.byKey(const Key('curated-counter')), findsNothing);
      await tester.drag(find.byKey(const Key('curated-pages')), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.text('Caption 0'), findsOneWidget);
    });

    testWidgets('dots track the page, tapping jumps, caption follows', (tester) async {
      String? opened;
      await tester.pumpWidget(viewer(highlights(3), onOpenLink: (u) => opened = u));
      for (var i = 0; i < 3; i++) {
        expect(find.byKey(Key('curated-dot-$i')), findsOneWidget);
      }
      expect(find.byKey(const Key('curated-dot-3')), findsNothing);
      expect(dotWidth(tester, 0), greaterThan(dotWidth(tester, 1)));
      expect(find.text('Caption 0'), findsOneWidget);
      expect(find.text('Credit: Credit 0'), findsOneWidget);

      // While the finger is still down, the highlight is already moving.
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('curated-pages'))));
      await gesture.moveBy(const Offset(-100, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-100, 0));
      await tester.pump();
      expect(dotWidth(tester, 1), greaterThan(8.5));
      expect(dotWidth(tester, 0), lessThan(18));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(dotWidth(tester, 1), greaterThan(dotWidth(tester, 0)));
      expect(dotWidth(tester, 1), greaterThan(dotWidth(tester, 2)));
      expect(find.text('Caption 1'), findsOneWidget);
      expect(find.text('Caption 0'), findsNothing);

      await tester.tap(find.byKey(const Key('curated-dot-tap-2')));
      await tester.pumpAndSettle();
      expect(dotWidth(tester, 2), greaterThan(dotWidth(tester, 1)));
      expect(find.text('Caption 2'), findsOneWidget);
      expect(find.text('Outlet 2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('curated-source-link')));
      expect(opened, 'https://example.org/2');
    });

    testWidgets('dots have accessibility labels', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(viewer(highlights(5)));
      expect(find.bySemanticsLabel('Image 2 of 5'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('many images: compact counter instead of dots', (tester) async {
      await tester.pumpWidget(viewer(highlights(12)));
      expect(find.byKey(const Key('curated-dot-0')), findsNothing);
      expect(find.text('1 / 12'), findsOneWidget);
      await tester.drag(find.byKey(const Key('curated-pages')), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 / 12'), findsOneWidget);
    });

    testWidgets('starts on the remembered page and reports changes', (tester) async {
      final pages = <int>[];
      await tester.pumpWidget(viewer(highlights(4), initial: 2, onPageChanged: pages.add));
      expect(find.text('Caption 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('curated-dot-tap-0')));
      await tester.pumpAndSettle();
      expect(pages.last, 0);
    });
  });

  group('curated index sync', () {
    Map<String, dynamic> indexJson(String version, List<String> ids) => {
          'version': version,
          'bodies': [
            for (final id in ids) {'body_id': id, 'body_name': id, 'count': 2}
          ],
        };

    FakeBackend backendWith(Map<String, dynamic> json, {String etag = '"v1"'}) {
      final b = FakeBackend();
      b.handlers['GET /api/curated/index/'] = (o) {
        if (o.headers['If-None-Match'] == etag) return ResponseBody.fromString('', 304);
        return ResponseBody.fromString(jsonEncode(json), 200, headers: {
          Headers.contentTypeHeader: ['application/json'],
          'etag': [etag],
        });
      };
      return b;
    }

    ProviderContainer container(FakeBackend b, CacheStore store, {String server = 'http://test'}) {
      final c = ProviderContainer(overrides: [
        serverUrlProvider.overrideWith(() => _FixedServerUrl(server)),
        apiClientProvider.overrideWithValue(ApiClient(server, dio: fakeDio(b))),
        cacheStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    /// Waits for the background sync (up to ~1 s); null if nothing was loaded.
    Future<CuratedIndex?> load(ProviderContainer c) async {
      c.listen(curatedIndexProvider, (_, _) {});
      for (var i = 0; i < 100 && c.read(curatedIndexProvider) == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      return c.read(curatedIndexProvider);
    }

    test('downloads, caches, and revalidates with the ETag', () async {
      final store = MemoryCacheStore();
      final first = backendWith(indexJson('v1', ['NGC1976']));
      final index = await load(container(first, store));
      expect(index!.has('NGC1976'), isTrue);
      expect(index.has('M31'), isFalse);

      final second = backendWith(indexJson('v1', ['NGC1976']));
      final again = await load(container(second, store));
      expect(again!.has('NGC1976'), isTrue);
      expect(second.requests.single.headers['If-None-Match'], '"v1"'); // 304, nothing re-downloaded
    });

    test('offline: the cached index still works', () async {
      final store = MemoryCacheStore();
      await load(container(backendWith(indexJson('v1', ['NGC1976'])), store));
      final offline = FakeBackend()..fail('GET /api/curated/index/', DioExceptionType.connectionError);
      expect((await load(container(offline, store)))!.has('NGC1976'), isTrue);
    });

    test('no cache and a failing server: nothing (source stays hidden), no exception', () async {
      final b = FakeBackend()..fail('GET /api/curated/index/', DioExceptionType.connectionError);
      expect(await load(container(b, MemoryCacheStore())), isNull);
    });

    test('a cache from another server is ignored', () async {
      final store = MemoryCacheStore();
      await load(container(backendWith(indexJson('v1', ['NGC1976'])), store, server: 'http://a'));
      final b = FakeBackend()..fail('GET /api/curated/index/', DioExceptionType.connectionError);
      expect(await load(container(b, store, server: 'http://b')), isNull);
    });

    test('a changed index replaces the old one', () async {
      final store = MemoryCacheStore();
      await load(container(backendWith(indexJson('v1', ['NGC1976'])), store));
      final index = await load(container(backendWith(indexJson('v2', ['M31']), etag: '"v2"'), store));
      expect(index!.has('M31'), isTrue);
      expect(index.has('NGC1976'), isFalse);
    });
  });

  group('visibility rule in the detail screen', () {
    const orion = Landmark(
      id: 'NGC1976',
      name: 'Great Orion Nebula',
      kind: 'dso',
      typeLabel: 'Star cluster with nebula',
      x: 0.5,
      y: 0.5,
    );
    const m78 = Landmark(
        id: 'NGC2068', name: 'M78', kind: 'dso', typeLabel: 'Reflection nebula', x: 0.2, y: 0.2);
    const alnilam = Landmark(
        id: 'HIP26311', name: 'Alnilam', kind: 'star', typeLabel: 'Star', x: 0.2, y: 0.2);

    Future<ProviderContainer> open(WidgetTester tester, Landmark lm, List<String> curatedIds) async {
      final backend = FakeBackend()
        ..json('GET /api/providers', providersJson)
        ..json('GET /api/curated/index/', {
          'version': 'v',
          'bodies': [
            for (final id in curatedIds) {'body_id': id, 'body_name': id, 'count': 2}
          ],
        });
      withDetailImage(backend);
      for (final id in curatedIds) {
        backend.json('GET /api/curated/$id/', {
          'body_id': id,
          'body_name': id,
          'version': 'v',
          'highlights': [
            for (final h in highlights(2))
              {
                'id': h.id,
                'image_url': h.imageUrl,
                'title': h.title,
                'caption': h.caption,
                'credit': h.credit,
                'source_outlet': h.sourceOutlet,
                'source_url': h.sourceUrl,
              }
          ],
        });
      }
      final container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(ApiClient('http://test', dio: fakeDio(backend))),
        cacheStoreProvider.overrideWithValue(MemoryCacheStore()),
      ]);
      addTearDown(container.dispose);
      container.listen(curatedIndexProvider, (_, _) {});
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: LandmarkDetailScreen(landmark: lm)),
      ));
      await settle(tester);
      return container;
    }

    testWidgets('shown only for a body that has highlights', (tester) async {
      await open(tester, orion, ['NGC1976']);
      expect(find.text(curatedSourceLabel), findsOneWidget);
      expect(curatedSourceLabel, 'Curated Cosmic Highlights');
      await leave(tester);
    });

    testWidgets('hidden for a body without highlights', (tester) async {
      await open(tester, alnilam, ['NGC1976']);
      expect(find.text(curatedSourceLabel), findsNothing);
      expect(find.text('Best'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('hidden when there is no index at all', (tester) async {
      await open(tester, orion, []);
      expect(find.text(curatedSourceLabel), findsNothing);
      await leave(tester);
    });

    testWidgets('selecting it shows the swipe viewer', (tester) async {
      await open(tester, orion, ['NGC1976']);
      await tester.tap(find.text(curatedSourceLabel));
      await settle(tester);
      expect(find.byType(CuratedViewer), findsOneWidget);
      expect(find.text('Caption 0'), findsOneWidget); // captions are shown by default
      await tester.tap(find.byTooltip('Hide details'));
      await settle(tester);
      expect(find.text('Caption 0'), findsNothing);
      expect(find.byKey(const Key('curated-dot-1')), findsOneWidget);
      await leave(tester);
    });

    testWidgets('falls back to the previous source when the body has none', (tester) async {
      final backend = FakeBackend()
        ..json('GET /api/providers', providersJson)
        ..json('GET /api/curated/index/', {'version': 'v', 'bodies': []});
      withDetailImage(backend);
      final scoped = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(ApiClient('http://test', dio: fakeDio(backend))),
        cacheStoreProvider.overrideWithValue(MemoryCacheStore()),
      ]);
      addTearDown(scoped.dispose);
      // The user had picked "curated" (after "Webb") on another body.
      scoped.read(detailPreferenceProvider.notifier)
        ..choose(const DetailView('jwst', null, 'Webb'))
        ..choose(const DetailView('curated', null, curatedSourceLabel));
      final pref = scoped.read(detailPreferenceProvider);
      expect(pref.view!.view, 'curated');
      expect(pref.source!.view, 'jwst');
      scoped.listen(curatedIndexProvider, (_, _) {});
      await tester.pumpWidget(UncontrolledProviderScope(
        container: scoped,
        child: const MaterialApp(home: LandmarkDetailScreen(landmark: m78)),
      ));
      await settle(tester);
      final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
      expect(chips.firstWhere((c) => c.selected).label.toString(), contains('Webb'));
      expect(find.byType(CuratedViewer), findsNothing);
      await leave(tester);
    });
  });
}
