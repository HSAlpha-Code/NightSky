import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'models.dart';

/// Thin client for the Django backend.
class ApiClient {
  ApiClient(String baseUrl, {Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: normaliseBaseUrl(baseUrl),
              connectTimeout: const Duration(seconds: 10),
              sendTimeout: const Duration(seconds: 60),
              // Plate solving plus provider fallbacks can take a while on the server.
              receiveTimeout: const Duration(seconds: 90),
            ));

  final Dio _dio;

  /// "http://host:8000", ".../", ".../api" and ".../api/" all become "http://host:8000/api".
  static String normaliseBaseUrl(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u.endsWith('/api') ? u : '$u/api';
  }

  Future<ProviderCatalog> getProviders() => _guard(() async {
        final resp = await _dio.get<Map<String, dynamic>>('/providers');
        return ProviderCatalog.fromJson(resp.data!);
      });

  Future<SolveResult> solve(Uint8List jpeg, CaptureMetadata meta) => _guard(() async {
        final form = FormData.fromMap({
          'image': MultipartFile.fromBytes(jpeg,
              filename: 'sky.jpg', contentType: DioMediaType('image', 'jpeg')),
          'metadata': jsonEncode(meta.toJson()),
        });
        final resp = await _dio.post<Map<String, dynamic>>('/solve', data: form);
        return SolveResult.fromJson(resp.data!);
      });

  Future<SkyImage> skyImage({
    required SolveResult pointing,
    required String? providerKey,
    required int width,
    required int height,
  }) =>
      _guard(() async {
        final resp = await _dio.post<List<int>>(
          '/sky-image',
          data: {
            'ra': pointing.ra,
            'dec': pointing.dec,
            'fov': pointing.fov,
            'rotation': pointing.rotation,
            'width': width,
            'height': height,
            if (providerKey != null) 'provider': providerKey,
          },
          options: Options(responseType: ResponseType.bytes),
        );
        final h = resp.headers;
        return SkyImage(
          bytes: Uint8List.fromList(resp.data!),
          providerKey: h.value('x-provider') ?? providerKey ?? '',
          providerName: h.value('x-provider-name') ?? '',
          credit: h.value('x-credit') ?? '',
          fallbackUsed: h.value('x-fallback-used') == 'true',
          fallbackReason: h.value('x-fallback-reason'),
          fallbackMessage: h.value('x-fallback-message'),
        );
      });

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }
}

/// Map a dio error to a user-facing [ApiException].
ApiException toApiException(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.connectionError:
      return const ApiException('NETWORK',
          'Cannot reach the server. Check your connection and the server address in Settings.');
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return const ApiException('TIMEOUT', 'The server took too long to answer. Please try again.');
    default:
      break;
  }
  final error = _errorBody(e.response?.data);
  if (error != null) {
    return ApiException(error['code']?.toString() ?? 'ERROR',
        error['message']?.toString() ?? 'Something went wrong.');
  }
  final status = e.response?.statusCode;
  return ApiException('HTTP_${status ?? 0}',
      status == null ? 'Network error. Please try again.' : 'Server error ($status).');
}

Map<String, dynamic>? _errorBody(Object? data) {
  try {
    Object? decoded = data;
    if (data is List<int>) decoded = jsonDecode(utf8.decode(data));
    if (data is String) decoded = jsonDecode(data);
    if (decoded is Map && decoded['error'] is Map) {
      return Map<String, dynamic>.from(decoded['error'] as Map);
    }
  } catch (_) {
    // Not a JSON error body.
  }
  return null;
}
