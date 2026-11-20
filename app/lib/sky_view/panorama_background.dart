import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class PanoramaBackgroundDownloader {
  Future<void> start(int resolution, String directory);
  Future<Map<String, dynamic>?> status();
  Future<void> cancel();
}

class ChannelPanoramaBackgroundDownloader
    implements PanoramaBackgroundDownloader {
  static const _channel = MethodChannel('night_sky/panorama_downloads');

  @override
  Future<void> start(int resolution, String directory) async {
    // A denied notification permission does not prevent Android foreground work.
    await _channel.invokeMethod<bool>('permission');
    await _channel.invokeMethod<void>('start', {
      'resolution': resolution,
      'directory': directory,
    });
  }

  @override
  Future<Map<String, dynamic>?> status() =>
      _channel.invokeMapMethod<String, dynamic>('status');

  @override
  Future<void> cancel() => _channel.invokeMethod<void>('cancel');
}

final panoramaBackgroundDownloaderProvider =
    Provider<PanoramaBackgroundDownloader?>((ref) {
      return !kIsWeb && Platform.isAndroid
          ? ChannelPanoramaBackgroundDownloader()
          : null;
    });
