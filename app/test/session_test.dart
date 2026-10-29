import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:night_sky/api_client.dart';
import 'package:night_sky/models.dart';
import 'package:night_sky/state.dart';

import 'fake_backend.dart';

void main() {
  late FakeBackend backend;
  late ProviderContainer container;
  final photo = Uint8List.fromList(img.encodeJpg(img.Image(width: 3000, height: 4000)));
  final meta = CaptureMetadata(timestampUtc: DateTime.utc(2026), latitude: 1, longitude: 2);

  setUp(() {
    backend = FakeBackend();
    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(ApiClient('http://test', dio: fakeDio(backend))),
    ]);
  });

  tearDown(() => container.dispose());

  SessionNotifier session() => container.read(sessionProvider.notifier);
  SessionState state() => container.read(sessionProvider);

  test('full flow: prepare -> solve -> sky image', () async {
    backend.json('POST /api/solve', solveJson);
    backend.image('POST /api/sky-image', [7], {'X-Provider': 'dss2_color', 'X-Credit': 'DSS2'});
    await session().start(photo, meta);

    final s = state();
    expect(s.stage, Stage.done);
    expect((s.photo!.width, s.photo!.height), (1200, 1600)); // downscaled before upload
    expect(s.solve!.approximate, isTrue);
    expect(s.skyImage!.bytes, [7]);
    final body = backend.requests.last.data as Map;
    expect((body['width'], body['height']), (900, 1200)); // same aspect as the photo
    expect(body.containsKey('provider'), isFalse); // server default
  });

  test('solve failure is a fatal error state', () async {
    backend.json('POST /api/solve',
        {'error': {'code': 'SOLVE_FAILED', 'message': 'Too cloudy.'}}, status: 422);
    await session().start(photo, meta);
    expect(state().stage, Stage.error);
    expect(state().error!.code, 'SOLVE_FAILED');
  });

  test('sky-image failure keeps the solve and allows retry', () async {
    backend.json('POST /api/solve', solveJson);
    backend.fail('POST /api/sky-image', DioExceptionType.receiveTimeout);
    await session().start(photo, meta);
    expect(state().stage, Stage.done);
    expect(state().solve, isNotNull);
    expect(state().imageError!.code, 'TIMEOUT');

    backend.image('POST /api/sky-image', [1], {'X-Provider': 'dss2_color'});
    await session().retry();
    expect(state().imageError, isNull);
    expect(state().skyImage!.bytes, [1]);
    expect(backend.requests.where((r) => r.path == '/solve').length, 1); // not re-solved
  });

  test('changing provider refetches only the image with the new key', () async {
    backend.json('POST /api/solve', solveJson);
    backend.image('POST /api/sky-image', [1], {'X-Provider': 'dss2_color'});
    await session().start(photo, meta);
    await session().changeProvider('panstarrs');
    expect(container.read(selectedProviderProvider), 'panstarrs');
    expect((backend.requests.last.data as Map)['provider'], 'panstarrs');
    expect(backend.requests.where((r) => r.path == '/solve').length, 1);
  });

  test('cancel stops waiting for the survey image and keeps the photo', () async {
    backend.json('POST /api/solve', solveJson);
    backend.hang('POST /api/sky-image');
    final run = session().start(photo, meta);
    // Wait until the image request is in flight.
    while (state().stage != Stage.fetchingImage) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    session().cancelImage();
    await run;
    expect(state().stage, Stage.done);
    expect(state().solve, isNotNull);
    expect(state().photo, isNotNull);
    expect(state().skyImage, isNull);
    expect(state().imageError!.code, 'CANCELLED');

    // Retry after cancelling fetches the image again.
    backend.hanging.clear();
    backend.image('POST /api/sky-image', [9], {'X-Provider': 'dss2_color'});
    await session().retry();
    expect(state().skyImage!.bytes, [9]);
    expect(state().imageError, isNull);
  });

  test('landmarks load with the sky image and re-poll while MAST is pending', () async {
    SessionNotifier.landmarkPollInterval = const Duration(milliseconds: 10);
    var calls = 0;
    backend.json('POST /api/solve', solveJson);
    backend.image('POST /api/sky-image', [1], {'X-Provider': 'dss2_color'});
    backend.handlers['GET /api/landmarks'] = (_) {
      calls++;
      final body = landmarksJson(m42Hires: calls == 1 ? null : true, pending: calls == 1);
      return ResponseBody.fromString(jsonEncode(body), 200, headers: {
        Headers.contentTypeHeader: ['application/json']
      });
    };
    await session().start(photo, meta);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(calls, 2); // pending -> asked once more -> done
    final m42 = state().landmarks!.landmarks.first;
    expect(m42.hasHires, isTrue);
    expect(state().landmarks!.pending, isFalse);
    final q = backend.requests.lastWhere((r) => r.path == '/landmarks').queryParameters;
    expect(q['aspect'], closeTo(4 / 3, 0.001)); // portrait photo: height / width
  });

  test('landmark failure does not break the result', () async {
    backend.json('POST /api/solve', solveJson);
    backend.image('POST /api/sky-image', [1], {});
    backend.json('GET /api/landmarks',
        {'error': {'code': 'CATALOG_UNAVAILABLE', 'message': 'x'}}, status: 503);
    await session().start(photo, meta);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(state().stage, Stage.done);
    expect(state().skyImage, isNotNull);
    expect(state().landmarks!.landmarks, isEmpty);
  });

  test('reset clears the session', () async {
    backend.json('POST /api/solve', solveJson);
    backend.image('POST /api/sky-image', [1], {});
    await session().start(photo, meta);
    session().reset();
    expect(state().stage, Stage.idle);
    expect(state().photo, isNull);
  });
}
