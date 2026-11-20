import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:night_sky/settings.dart';
import 'package:night_sky/sky_view/panorama_packs.dart';
import 'package:night_sky/sky_view/panorama_background.dart';

import 'fake_backend.dart';

class _BackgroundDownload implements PanoramaBackgroundDownloader {
  Map<String, dynamic>? job;
  int starts = 0;
  int cancellations = 0;
  @override
  Future<void> start(int resolution, String directory) async {
    starts++;
    job = {
      'id': 'job-$starts',
      'resolution': resolution,
      'status': 'RUNNING',
      'progress': .25,
    };
  }

  @override
  Future<Map<String, dynamic>?> status() async => job;
  @override
  Future<void> cancel() async {
    cancellations++;
    job = {...job!, 'status': 'CANCELLED'};
  }
}

void main() {
  late Directory root;
  late FakeBackend backend;
  late ProviderContainer container;
  const prefix =
      '/HSAlpha-Code/NightSky/releases/download/panorama-nasa2020-v1/nasa2020-16k-';
  final payload = List<int>.generate(16, (i) => i);
  Map<String, dynamic> manifest() => {
    'version': 1,
    'width': 16384,
    'height': 8192,
    'tileSize': 2048,
    'gutter': 1,
    'tiles': [
      for (var y = 0; y < 4; y++)
        for (var x = 0; x < 8; x++)
          {
            'file': '${x}_$y.webp',
            'bytes': payload.length,
            'sha256': sha256.convert(payload).toString(),
          },
    ],
  };

  ProviderContainer makeContainer({PanoramaBackgroundDownloader? background}) =>
      ProviderContainer(
        overrides: [
          panoramaDirectoryProvider.overrideWithValue(Future.value(root)),
          panoramaDioProvider.overrideWithValue(
            Dio()..httpClientAdapter = backend,
          ),
          panoramaBackgroundDownloaderProvider.overrideWithValue(background),
          settingsStoreProvider.overrideWithValue(
            MemorySettingsStore(
              jsonEncode(
                const AppSettings(
                  serverUrl: 'https://api-must-not-serve-downloads.invalid',
                ).toJson(),
              ),
            ),
          ),
        ],
      );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nasa-pack-test-');
    backend = FakeBackend()..json('GET ${prefix}manifest.json', manifest());
    for (final tile in manifest()['tiles'] as List) {
      backend.image('GET $prefix${tile['file']}', payload, {});
    }
    container = makeContainer();
  });
  tearDown(() async {
    container.dispose();
    await root.delete(recursive: true);
  });

  test(
    'default app renders 8K; malformed packs and traversal filenames rejected',
    () {
      expect(const AppSettings().skyQuality.panoramaWidth, 8192);
      final wrongSize = manifest()..['width'] = 32768;
      expect(
        () => PanoramaPack(PanoramaResolution.sixteenK, wrongSize),
        throwsFormatException,
      );
      final traversal = manifest();
      (traversal['tiles'] as List).first['file'] = '../secret.webp';
      expect(
        () => PanoramaPack(PanoramaResolution.sixteenK, traversal),
        throwsFormatException,
      );
    },
  );

  test(
    'installs verified tiles, restores offline, switches to 8K and removes download',
    () async {
      final notifier = container.read(panoramaPacksProvider.notifier);
      await notifier.install(PanoramaResolution.sixteenK);
      expect(
        container.read(panoramaPacksProvider).active,
        PanoramaResolution.sixteenK,
      );
      expect(container.read(panoramaPacksProvider).error, isNull);
      expect(
        backend.requests.every((request) => request.uri.host == 'github.com'),
        isTrue,
      );
      expect(
        backend.requests.every(
          (request) => request.uri.path.contains(
            '/releases/download/panorama-nasa2020-v1/',
          ),
        ),
        isTrue,
      );
      expect(File('${root.path}/16k/manifest.json').existsSync(), isTrue);
      container.dispose();
      container = makeContainer();
      container.read(panoramaPacksProvider);
      for (
        var i = 0;
        i < 100 && container.read(panoramaPacksProvider).installed.isEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(
        container.read(panoramaPacksProvider).active,
        PanoramaResolution.sixteenK,
      );
      await container
          .read(panoramaPacksProvider.notifier)
          .select(PanoramaResolution.eightK);
      expect(
        container.read(panoramaPacksProvider).active,
        PanoramaResolution.eightK,
      );
      await container
          .read(panoramaPacksProvider.notifier)
          .remove(PanoramaResolution.sixteenK);
      expect(Directory('${root.path}/16k').existsSync(), isFalse);
      expect(container.read(panoramaPacksProvider).installed, isEmpty);
    },
  );

  test(
    'corrupt download keeps 8K active and retry reuses verified completed tiles',
    () async {
      final completed = File('${root.path}/16k/0_0.webp');
      await completed.parent.create(recursive: true);
      await completed.writeAsBytes(payload);
      backend.image('GET ${prefix}1_0.webp', [255], {});
      final notifier = container.read(panoramaPacksProvider.notifier);
      await notifier.install(PanoramaResolution.sixteenK);
      expect(
        container.read(panoramaPacksProvider).active,
        PanoramaResolution.eightK,
      );
      expect(container.read(panoramaPacksProvider).error, isNotNull);
      expect(File('${root.path}/16k/manifest.json').existsSync(), isFalse);
      expect(File('${root.path}/16k/1_0.webp.part').existsSync(), isFalse);
      backend.image('GET ${prefix}1_0.webp', payload, {});
      await notifier.install(PanoramaResolution.sixteenK);
      expect(
        container.read(panoramaPacksProvider).active,
        PanoramaResolution.sixteenK,
      );
      expect(
        backend.requests.where((r) => r.uri.path == '${prefix}0_0.webp').length,
        0,
      );
    },
  );

  test(
    'cancels an in-flight download without activating an incomplete pack',
    () async {
      backend.hang('GET ${prefix}0_0.webp');
      final notifier = container.read(panoramaPacksProvider.notifier);
      final installing = notifier.install(PanoramaResolution.sixteenK);
      while (!backend.requests.any((r) => r.uri.path.endsWith('0_0.webp'))) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      notifier.cancel();
      await installing;
      expect(
        container.read(panoramaPacksProvider).active,
        PanoramaResolution.eightK,
      );
      expect(
        container.read(panoramaPacksProvider).error,
        contains('cancelled'),
      );
      expect(container.read(panoramaPacksProvider).installed, isEmpty);
    },
  );

  test('missing installed tile restores bundled 8K', () async {
    final notifier = container.read(panoramaPacksProvider.notifier);
    await notifier.install(PanoramaResolution.sixteenK);
    await File('${root.path}/16k/0_0.webp').delete();
    container.dispose();
    container = makeContainer();
    container.read(panoramaPacksProvider);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(
      container.read(panoramaPacksProvider).active,
      PanoramaResolution.eightK,
    );
    expect(container.read(panoramaPacksProvider).installed, isEmpty);
    expect(
      jsonDecode(
        File('${root.path}/16k/manifest.json').readAsStringSync(),
      )['width'],
      16384,
    );
  });

  test('four parallel requests have aggregate monotonic progress', () async {
    var active = 0, peak = 0;
    for (final tile in manifest()['tiles'] as List) {
      backend.handlers['GET $prefix${tile['file']}'] = (_) {
        Stream<Uint8List> bytes() async* {
          active++;
          if (active > peak) peak = active;
          try {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            yield Uint8List.fromList(payload);
          } finally {
            active--;
          }
        }

        return ResponseBody(bytes(), 200);
      };
    }
    final progress = <double>[];
    container.listen(panoramaPacksProvider, (_, next) {
      if (next.downloading != null) progress.add(next.progress);
    });
    await container
        .read(panoramaPacksProvider.notifier)
        .install(PanoramaResolution.sixteenK);
    expect(peak, 4);
    expect(active, 0);
    expect(progress.every((p) => p >= 0 && p <= 1), isTrue);
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
    }
    expect(
      container.read(panoramaPacksProvider).active,
      PanoramaResolution.sixteenK,
    );
  });

  test(
    'background job survives notifier disposal and reconnects on reopen',
    () async {
      final background = _BackgroundDownload();
      container.dispose();
      container = makeContainer(background: background);
      await container
          .read(panoramaPacksProvider.notifier)
          .install(PanoramaResolution.sixteenK);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(background.starts, 1);
      expect(
        container.read(panoramaPacksProvider).downloading,
        PanoramaResolution.sixteenK,
      );
      expect(backend.requests, isEmpty);
      container.dispose();
      expect(background.cancellations, 0);
      container = makeContainer(background: background);
      container.read(panoramaPacksProvider);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(container.read(panoramaPacksProvider).progress, .25);
      final folder = Directory('${root.path}/16k');
      await folder.create(recursive: true);
      for (final tile in manifest()['tiles'] as List) {
        await File('${folder.path}/${tile['file']}').writeAsBytes(payload);
      }
      await File(
        '${folder.path}/manifest.json',
      ).writeAsString(jsonEncode(manifest()));
      await File('${root.path}/active.txt').writeAsString('sixteenK');
      background.job = {...background.job!, 'status': 'SUCCEEDED'};
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      expect(container.read(panoramaPacksProvider).downloading, isNull);
      expect(
        container.read(panoramaPacksProvider).installed,
        contains(PanoramaResolution.sixteenK),
      );
      expect(
        container.read(panoramaPacksProvider).active,
        PanoramaResolution.sixteenK,
      );
    },
  );

  test('cancel delegates to Android and clears background progress', () async {
    final background = _BackgroundDownload();
    container.dispose();
    container = makeContainer(background: background);
    final notifier = container.read(panoramaPacksProvider.notifier);
    await notifier.install(PanoramaResolution.sixteenK);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    notifier.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(background.cancellations, 1);
    expect(container.read(panoramaPacksProvider).downloading, isNull);
    expect(container.read(panoramaPacksProvider).error, contains('cancelled'));
    expect(
      container.read(panoramaPacksProvider).active,
      PanoramaResolution.eightK,
    );
  });
}
