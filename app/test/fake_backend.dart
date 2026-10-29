import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// In-memory dio adapter: maps "METHOD /path" to a handler.
class FakeBackend implements HttpClientAdapter {
  final handlers = <String, ResponseBody Function(RequestOptions)>{};
  final requests = <RequestOptions>[];

  void json(String route, Object body, {int status = 200}) {
    handlers[route] = (_) => ResponseBody.fromString(jsonEncode(body), status,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        });
  }

  void image(String route, List<int> bytes, Map<String, String> headers) {
    handlers[route] = (_) => ResponseBody.fromBytes(Uint8List.fromList(bytes), 200, headers: {
          Headers.contentTypeHeader: ['image/jpeg'],
          for (final e in headers.entries) e.key.toLowerCase(): [e.value],
        });
  }

  void fail(String route, DioExceptionType type) {
    handlers[route] = (o) => throw DioException(requestOptions: o, type: type);
  }

  /// Requests to [route] never answer (until cancelled), like a slow upstream service.
  void hang(String route) => hanging.add(route);
  final hanging = <String>{};

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    final route = '${options.method} ${options.uri.path}';
    if (hanging.contains(route)) {
      await (cancelFuture ?? Completer<void>().future);
      throw DioException.requestCancelled(requestOptions: options, reason: 'cancelled');
    }
    final handler = handlers[route];
    if (handler == null) return ResponseBody.fromString('not found', 404);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

Dio fakeDio(FakeBackend backend, {String baseUrl = 'http://test/api'}) =>
    Dio(BaseOptions(baseUrl: baseUrl))..httpClientAdapter = backend;

const providersJson = {
  'default': 'dss2_color',
  'providers': [
    {
      'key': 'dss2_color',
      'name': 'DSS2 Color',
      'description': 'Digitized Sky Survey 2',
      'wavelength': 'optical',
      'coverage': 'all-sky',
      'all_sky': true,
      'service': 'hips2fits',
      'credit': 'DSS2 via CDS',
    },
    {
      'key': 'panstarrs',
      'name': 'Pan-STARRS DR2 (STScI)',
      'description': 'Deep cutouts',
      'wavelength': 'optical',
      'coverage': 'dec > -30, fov <= 0.4 deg',
      'all_sky': false,
      'service': 'panstarrs',
      'credit': 'PS1',
    },
  ],
};

Map<String, dynamic> landmarksJson({bool? m42Hires = true, bool pending = false}) => {
      'landmarks': [
        {
          'id': 'NGC1976',
          'name': 'Great Orion Nebula',
          'kind': 'dso',
          'type': 'Cl+N',
          'type_label': 'Star cluster with nebula',
          'ra': 83.82,
          'dec': -5.39,
          'magnitude': 4.0,
          'size_arcmin': 90.0,
          'messier': 42,
          'constellation': 'Ori',
          'aliases': ['M42', 'NGC 1976'],
          'distance_ly': null,
          'x': 0.5,
          'y': 0.5,
          'has_hires': m42Hires,
        },
        {
          'id': 'HIP26311',
          'name': 'Alnilam',
          'kind': 'star',
          'type': 'star',
          'type_label': 'Star',
          'ra': 84.05,
          'dec': -1.2,
          'magnitude': 1.69,
          'size_arcmin': null,
          'messier': null,
          'constellation': 'Ori',
          'aliases': ['HR 1903'],
          'distance_ly': null,
          'x': 0.25,
          'y': 0.2,
          'has_hires': false,
        },
      ],
      'total_in_field': 2,
      'pending': pending,
      'source': 'OpenNGC',
    };

const solveJson = {
  'ra': 83.82,
  'dec': -5.39,
  'rotation': 12.0,
  'fov': 52.0,
  'confidence': 0.0,
  'approximate': true,
  'source': 'sensors',
  'message': 'From the phone sensors.',
  'alt': 40.0,
  'az': 180.0,
};
