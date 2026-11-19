import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sky/api_client.dart';
import 'package:night_sky/image_disk_cache.dart';
import 'package:night_sky/models.dart';

import 'fake_backend.dart';

void main() {
  late Directory directory;
  late ImageDiskCache cache;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nightsky-cache-test-');
    cache = ImageDiskCache(directory: () async => directory);
  });
  tearDown(() async => directory.delete(recursive: true));

  test('persists bytes across cache instances and evicts least recently used files', () async {
    cache = ImageDiskCache(directory: () async => directory, maxBytes: 6);
    await cache.write('old', [1, 2, 3]);
    await cache.write('recent', [4, 5, 6]);
    // Make eviction order deterministic without sleeping.
    for (final file in directory.listSync().whereType<File>()) {
      await file.setLastModified(DateTime(2000));
    }
    expect(await cache.read('recent'), [4, 5, 6]);
    await cache.write('new', [7, 8, 9]);
    final restarted = ImageDiskCache(directory: () async => directory, maxBytes: 6);
    expect(await restarted.read('old'), isNull);
    expect(await restarted.read('recent'), [4, 5, 6]);
    expect(await restarted.read('new'), [7, 8, 9]);
    await restarted.write('too-large', List.filled(7, 1));
    expect(await restarted.read('too-large'), isNull);
  });

  test('unavailable disk storage is a cache miss, not an image failure', () async {
    final unavailable = ImageDiskCache(directory: () async => throw const FileSystemException());
    await unavailable.write('image', [1]);
    expect(await unavailable.read('image'), isNull);
  });

  Map<String, dynamic> detail() => {
        'image_jpeg_base64': base64Encode([1, 2, 3]),
        'image_source': 'survey',
        'caption': 'Test star',
        'credit': 'DSS2',
        'available_views': ['survey'],
      };

  test('reopened details work offline after restart and keep metadata', () async {
    final backend = FakeBackend()..json('GET /api/landmark-detail', detail());
    final first = ApiClient('http://test', dio: fakeDio(backend), imageCache: cache);
    await first.landmarkDetail('HIP32349', providerKey: 'dss2_color');
    backend.fail('GET /api/landmark-detail', DioExceptionType.connectionError);
    final restarted = ApiClient('http://test/api/', dio: fakeDio(backend),
        imageCache: ImageDiskCache(directory: () async => directory));
    final result = await restarted.landmarkDetail('HIP32349', providerKey: 'dss2_color');
    final resolved = await restarted.landmarkDetail('HIP32349', providerKey: 'dss2_color', view: 'survey');
    expect(result.image, [1, 2, 3]);
    expect(resolved.credit, 'DSS2');
    expect(result.caption, 'Test star');
    expect(result.availableViews, ['survey']);
    expect(backend.requests, hasLength(1));
  });

  test('cache isolates servers, providers and views and never stores failures', () async {
    final backend = FakeBackend()..json('GET /api/landmark-detail', detail());
    final first = ApiClient('http://test', dio: fakeDio(backend), imageCache: cache);
    await first.landmarkDetail('HIP32349', providerKey: 'dss2_color', view: 'survey');
    await first.landmarkDetail('HIP32349', providerKey: 'other', view: 'survey');
    await first.landmarkDetail('HIP32349', providerKey: 'dss2_color', view: 'hst');
    await ApiClient('http://other', dio: fakeDio(backend), imageCache: cache)
        .landmarkDetail('HIP32349', providerKey: 'dss2_color', view: 'survey');
    expect(backend.requests, hasLength(4));
    backend.fail('GET /api/landmark-detail', DioExceptionType.connectionError);
    await expectLater(first.landmarkDetail('missing'), throwsA(isA<ApiException>()));
    backend.json('GET /api/landmark-detail', detail());
    await first.landmarkDetail('missing');
    expect(backend.requests, hasLength(6));
  });

  test('corrupt cached detail is replaced by a successful download', () async {
    final key = jsonEncode(['detail-v1', 'http://test/api', 'HIP32349', 'survey', 'dss2_color']);
    await cache.write(key, utf8.encode('corrupt'));
    final backend = FakeBackend()..json('GET /api/landmark-detail', detail());
    final api = ApiClient('http://test', dio: fakeDio(backend), imageCache: cache);
    final result = await api.landmarkDetail('HIP32349', providerKey: 'dss2_color', view: 'survey');
    expect(result.image, [1, 2, 3]);
    expect(backend.requests, hasLength(1));
    expect(jsonDecode(utf8.decode((await cache.read(key))!)), detail());
  });
}
