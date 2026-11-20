import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings.dart';

const nasaEastAssetPath = 'assets/sky/nasa_2020_east.webp';
const nasaWestAssetPath = 'assets/sky/nasa_2020_west.webp';
const skySphereShaderAsset = 'shaders/sky_sphere.frag';

/// Dual-hemisphere GPU textures forming an all-sky 8K (`2*S x S`) Galactic CAR panorama,
/// keeping each individual texture `<= 4096 x 4096` for wide mobile GPU compatibility.
class SkyPanorama {
  const SkyPanorama({required this.east, required this.west});

  /// Left half (`u in [0, 0.5]`, Galactic longitude `l in [+180°, 0°]`).
  final ui.Image east;

  /// Right half (`u in [0.5, 1.0]`, Galactic longitude `l in [0°, -180°]`).
  final ui.Image west;

  int get hemisphereSize => east.width;

  void dispose() {
    east.dispose();
    west.dispose();
  }
}

Future<ui.Image?> _decodeSquare(String assetPath, int size, AssetBundle b) async {
  final data = await b.load(assetPath);
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: size,
    targetHeight: size,
  );
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

/// Decodes both hemispheres scaled to [SkyQuality.hemisphereSize] (`1600` Power saver,
/// `4096` full 8K Balanced default and Max detail).
Future<SkyPanorama?> decodeSkyPanorama(
  SkyQuality quality, {
  AssetBundle? bundle,
}) async {
  try {
    final b = bundle ?? rootBundle;
    final edge = quality.hemisphereSize;
    final results = await Future.wait([
      _decodeSquare(nasaEastAssetPath, edge, b),
      _decodeSquare(nasaWestAssetPath, edge, b),
    ]);
    final east = results[0];
    final west = results[1];
    if (east == null || west == null) {
      east?.dispose();
      west?.dispose();
      return null;
    }
    return SkyPanorama(east: east, west: west);
  } catch (_) {
    return null;
  }
}

Future<ui.FragmentProgram?> loadSkyShaderProgram() async {
  try {
    return await ui.FragmentProgram.fromAsset(skySphereShaderAsset);
  } catch (_) {
    return null;
  }
}

final skyShaderProgramProvider = FutureProvider<ui.FragmentProgram?>((ref) => loadSkyShaderProgram());

/// Manages the active [SkyPanorama] across [SkyQuality] changes without ever exposing a
/// disposed `ui.Image` while a new resolution is decoding in the background.
class SkyPanoramaNotifier extends Notifier<SkyPanorama?> {
  int _generation = 0;
  SkyPanorama? _current;
  bool _disposed = false;

  @override
  SkyPanorama? build() {
    ref.onDispose(() {
      _disposed = true;
      _generation++;
      final old = _current;
      _current = null;
      if (old != null) _retireSafely(old);
    });

    ref.listen<SkyQuality>(
      settingsProvider.select((s) => s.skyQuality),
      (prev, next) {
        if (prev != next) unawaited(_loadQuality(next));
      },
      fireImmediately: true,
    );

    return _current;
  }

  Future<void> _loadQuality(SkyQuality quality) async {
    final gen = ++_generation;
    final next = await decodeSkyPanorama(quality);
    if (_disposed || !ref.mounted || gen != _generation) {
      next?.dispose();
      return;
    }
    final previous = _current;
    _current = next;
    state = next;
    if (previous != null && !identical(previous, next)) {
      _retireSafely(previous);
    }
  }

  static void _retireSafely(SkyPanorama old) {
    try {
      SchedulerBinding.instance.addPostFrameCallback((_) => old.dispose());
    } catch (_) {
      old.dispose();
    }
  }
}

final skyPanoramaProvider =
    NotifierProvider<SkyPanoramaNotifier, SkyPanorama?>(SkyPanoramaNotifier.new);
