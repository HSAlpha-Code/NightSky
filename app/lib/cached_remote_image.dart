import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'image_disk_cache.dart';

/// Uses Flutter's decoded-image cache first, then the device cache before downloading.
class CachedRemoteImage extends ImageProvider<CachedRemoteImage> {
  const CachedRemoteImage(this.url);

  final String url;

  @override
  Future<CachedRemoteImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(CachedRemoteImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1, debugLabel: url);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final cache = ImageDiskCache.shared;
    final key = 'remote-v1:$url';
    final cached = await cache.read(key);
    if (cached != null) {
      try {
        return await decode(await ui.ImmutableBuffer.fromUint8List(cached));
      } catch (_) {
        await cache.remove(key);
      }
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final uri = Uri.parse(url);
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != HttpStatus.ok) {
        throw NetworkImageLoadException(statusCode: response.statusCode, uri: uri);
      }
      final bytes = await consolidateHttpClientResponseBytes(response)
          .timeout(const Duration(seconds: 30));
      final codec = await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
      // Cache only decodable images, never error pages or partial downloads.
      unawaited(cache.write(key, bytes));
      return codec;
    } catch (_) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(this));
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  @override
  bool operator ==(Object other) => other is CachedRemoteImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
