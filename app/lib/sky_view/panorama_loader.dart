import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings.dart';

const mellingerEastAssetPath = 'assets/sky/mellinger_east.webp';
const mellingerWestAssetPath = 'assets/sky/mellinger_west.webp';
const skySphereShaderAsset = 'shaders/sky_sphere.frag';

/// Dual-hemisphere GPU textures forming an all-sky 8K (`2*S x S`) Galactic CAR panorama,
/// keeping each individual texture `<= 4096 x 4096` for wide mobile GPU compatibility.
class MellingerPanorama {
  const MellingerPanorama({required this.east, required this.west});

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
/// `3200` Balanced Retina default, `4096` full 8K Max detail).
Future<MellingerPanorama?> decodeMellingerPanorama(
  SkyQuality quality, {
  AssetBundle? bundle,
}) async {
  try {
    final b = bundle ?? rootBundle;
    final edge = quality.hemisphereSize;
    final results = await Future.wait([
      _decodeSquare(mellingerEastAssetPath, edge, b),
      _decodeSquare(mellingerWestAssetPath, edge, b),
    ]);
    final east = results[0];
    final west = results[1];
    if (east == null || west == null) {
      east?.dispose();
      west?.dispose();
      return null;
    }
    return MellingerPanorama(east: east, west: west);
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

/// Manages the active [MellingerPanorama] across [SkyQuality] changes without ever exposing a
/// disposed `ui.Image` while a new resolution is decoding in the background.
class MellingerPanoramaNotifier extends Notifier<MellingerPanorama?> {
  int _generation = 0;
  MellingerPanorama? _current;
  bool _disposed = false;

  @override
  MellingerPanorama? build() {
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
    final next = await decodeMellingerPanorama(quality);
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

  static void _retireSafely(MellingerPanorama old) {
    try {
      SchedulerBinding.instance.addPostFrameCallback((_) => old.dispose());
    } catch (_) {
      old.dispose();
    }
  }
}

final mellingerImageProvider =
    NotifierProvider<MellingerPanoramaNotifier, MellingerPanorama?>(MellingerPanoramaNotifier.new);
