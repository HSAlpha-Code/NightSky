import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sky/api_client.dart';
import 'package:night_sky/models.dart';

import 'fake_backend.dart';

void main() {
  late FakeBackend backend;
  late ApiClient api;

  setUp(() {
    backend = FakeBackend();
    api = ApiClient('http://test', dio: fakeDio(backend));
  });

  test('getProviders parses the catalog', () async {
    backend.json('GET /api/providers', providersJson);
    final c = await api.getProviders();
    expect(c.defaultKey, 'dss2_color');
    expect(c.providers.map((p) => p.key), ['dss2_color', 'panstarrs']);
    expect(c.providers[1].allSky, isFalse);
  });

  test('solve uploads multipart image + JSON metadata', () async {
    backend.json('POST /api/solve', solveJson);
    final meta = CaptureMetadata(timestampUtc: DateTime.utc(2026), latitude: 1, longitude: 2);
    final r = await api.solve(Uint8List.fromList([1, 2, 3]), meta);
    expect(r.approximate, isTrue);
    expect(r.ra, 83.82);

    final form = backend.requests.single.data as FormData;
    expect(form.files.single.key, 'image');
    expect(form.files.single.value.filename, 'sky.jpg');
    final metaField = form.fields.firstWhere((f) => f.key == 'metadata').value;
    expect(jsonDecode(metaField)['latitude'], 1);
  });

  test('skyImage returns bytes and fallback headers', () async {
    backend.image('POST /api/sky-image', [9, 9, 9], {
      'X-Provider': 'skyview_mellinger',
      'X-Provider-Name': 'Mellinger',
      'X-Credit': 'NASA SkyView',
      'X-Fallback-Used': 'true',
      'X-Fallback-Reason': 'PROVIDER_UNAVAILABLE',
      'X-Fallback-Message': 'DSS2 is down; showing Mellinger instead.',
    });
    final img = await api.skyImage(
        pointing: SolveResult.fromJson(solveJson), providerKey: 'dss2_color', width: 300, height: 400);
    expect(img.bytes, [9, 9, 9]);
    expect(img.providerKey, 'skyview_mellinger');
    expect(img.fallbackUsed, isTrue);
    expect(img.fallbackReason, 'PROVIDER_UNAVAILABLE');
    final body = backend.requests.single.data as Map;
    expect(body['provider'], 'dss2_color');
    expect(body['rotation'], 12.0);
    expect((body['width'], body['height']), (300, 400));
  });

  test('backend error body becomes ApiException with its code', () async {
    backend.json('POST /api/solve',
        {'error': {'code': 'SOLVE_FAILED', 'message': 'No stars found.'}}, status: 422);
    expect(
      () => api.solve(Uint8List(1), CaptureMetadata(timestampUtc: DateTime.utc(2026))),
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 'SOLVE_FAILED')
          .having((e) => e.message, 'message', 'No stars found.')),
    );
  });

  test('binary endpoint error body is decoded too', () async {
    backend.json('POST /api/sky-image',
        {'error': {'code': 'PROVIDER_UNAVAILABLE', 'message': 'All down.'}}, status: 503);
    expect(
      () => api.skyImage(
          pointing: SolveResult.fromJson(solveJson), providerKey: null, width: 1, height: 1),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'PROVIDER_UNAVAILABLE')),
    );
  });

  test('network failure has a friendly message', () async {
    backend.fail('GET /api/providers', DioExceptionType.connectionError);
    expect(api.getProviders(),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'NETWORK')));
  });

  test('base URL is normalised to /api', () {
    for (final url in ['http://h:8000', ' http://h:8000/', 'http://h:8000/api', 'http://h:8000/api/']) {
      expect(ApiClient.normaliseBaseUrl(url), 'http://h:8000/api');
    }
  });
}
