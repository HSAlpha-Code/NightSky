import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'astro_math.dart';
import 'panorama_packs.dart';

/// Only visible tiles are decoded. A bounded working set avoids a full-sphere
/// allocation (~2 GiB for a 32K RGBA image). The bundled 8K fills cache misses.
class PanoramaTileCache extends ChangeNotifier {
  PanoramaTileCache(this.directory);
  final Future<Directory> Function(PanoramaResolution) directory;
  static const maxTiles = 24;
  final images = <String, ui.Image>{};
  final clips = <String, Rect>{};
  final _failed = <String>{};
  final _pending = <String>{};
  PanoramaResolution resolution = PanoramaResolution.eightK;
  Set<String> _wanted = {};
  int _generation = 0;
  int _loading = 0;
  bool _closed = false;

  void updateView(
    PanoramaResolution next,
    SkyCamera camera,
    Size size,
    bool enabled,
  ) {
    if (resolution != next) {
      resolution = next;
      _generation++;
      for (final image in images.values) {
        _retire(image);
      }
      images.clear();
      _failed.clear();
      _pending.clear();
    }
    clips.clear();
    if (!enabled || next == PanoramaResolution.eightK || size.isEmpty) {
      _wanted = {};
      if (images.isNotEmpty) {
        _generation++;
        for (final image in images.values) {
          _retire(image);
        }
        images.clear();
        _pending.clear();
        _failed.clear();
      }
      return;
    }
    // Dense screen-space samples identify visible tiles, including wrapped seams.
    // Clip each shader pass to the screen cells that can contain that tile.
    const cols = 32, rows = 24;
    final cellW = size.width / cols, cellH = size.height / rows;
    final tan = camera.horizontalTanHalfFov(size);
    final aspect = size.height / size.width;
    for (var y = 0; y <= rows; y++) {
      for (var x = 0; x <= cols; x++) {
        final dir =
            (camera.forwardGal +
                    camera.rightGal * ((2 * x / cols - 1) * tan) +
                    camera.upGal * ((1 - 2 * y / rows) * aspect * tan))
                .normalized;
        final uv = galacticVecToPanoramaUv(dir);
        final tx = (uv.u * next.columns).floor() % next.columns;
        final ty = (uv.v * next.rows).floor().clamp(0, next.rows - 1);
        final rect = Rect.fromLTRB(
          (x - 1) * cellW,
          (y - 1) * cellH,
          (x + 1) * cellW,
          (y + 1) * cellH,
        ).intersect(Offset.zero & size);
        final key = '${tx}_$ty';
        clips[key] = clips[key]?.expandToInclude(rect) ?? rect;
      }
    }
    // Prefer the center of the display when a broad view exceeds the budget.
    final keys = clips.keys.toList()
      ..sort(
        (a, b) => (clips[a]!.center - size.center(Offset.zero)).distanceSquared
            .compareTo(
              (clips[b]!.center - size.center(Offset.zero)).distanceSquared,
            ),
      );
    _wanted = keys.take(maxTiles).toSet();
    for (final key in images.keys.toList()) {
      if (!_wanted.contains(key)) _retire(images.remove(key)!);
    }
    _pump();
  }

  void _pump() {
    if (_closed) return;
    while (_loading < 2) {
      final key = _wanted
          .where(
            (k) =>
                !images.containsKey(k) &&
                !_failed.contains(k) &&
                !_pending.contains(k),
          )
          .firstOrNull;
      if (key == null) return;
      _pending.add(key);
      _loading++;
      unawaited(_load(key, _generation, resolution));
    }
  }

  Future<void> _load(
    String key,
    int generation,
    PanoramaResolution requested,
  ) async {
    ui.Image? decoded;
    try {
      final folder = await directory(requested);
      if (_closed || generation != _generation) return;
      final bytes = await File('${folder.path}/$key.webp').readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        if (descriptor.width != 2050 || descriptor.height != 2050) {
          throw const FormatException('Unexpected tile dimensions');
        }
        final codec = await descriptor.instantiateCodec();
        try {
          decoded = (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
        buffer.dispose();
      }
      if (_closed || generation != _generation || !_wanted.contains(key)) {
        return;
      }
      images[key] = decoded;
      decoded = null;
      notifyListeners();
    } catch (_) {
      if (!_closed && generation == _generation) _failed.add(key);
      // Retain the 8K fallback if a tile cannot be decoded on this device.
    } finally {
      decoded?.dispose();
      if (generation == _generation) _pending.remove(key);
      _loading--;
      _pump();
    }
  }

  static void _retire(ui.Image image) =>
      SchedulerBinding.instance.addPostFrameCallback((_) => image.dispose());

  @override
  void dispose() {
    _closed = true;
    _generation++;
    for (final image in images.values) {
      _retire(image);
    }
    images.clear();
    super.dispose();
  }
}

final panoramaTileCacheProvider = Provider.autoDispose<PanoramaTileCache>((
  ref,
) {
  final packs = ref.read(panoramaPacksProvider.notifier);
  final cache = PanoramaTileCache(packs.folder);
  ref.onDispose(cache.dispose);
  return cache;
});
