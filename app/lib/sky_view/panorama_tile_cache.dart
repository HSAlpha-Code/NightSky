import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'astro_math.dart';
import 'panorama_packs.dart';

/// Loads a complete view before revealing it, retains an LRU working set and
/// prefetches adjacent tiles. Wide views use smaller decoded textures within the
/// same memory budget; zoomed views decode the original native-resolution pixels.
class PanoramaTileCache extends ChangeNotifier {
  PanoramaTileCache(
    this.directory, {
    this.fadeDuration = const Duration(milliseconds: 240),
    Future<ui.Image> Function(String key, int edge)? decodeTile,
  }) : _decodeOverride = decodeTile {
    _fade = Ticker(_tickFade);
  }

  final Future<Directory> Function(PanoramaResolution) directory;
  final Duration fadeDuration;
  final Future<ui.Image> Function(String key, int edge)? _decodeOverride;
  static const maxTiles = 16; // ~256 MiB in full 2050x2050 RGBA textures.
  final images = <String, ui.Image>{};
  final clips = <String, Rect>{};
  final _failed = <String>{};
  final _pending = <String>{};
  PanoramaResolution resolution = PanoramaResolution.eightK;
  Set<String> _visible = {};
  Set<String> _wanted = {};
  int _scale = 1;
  int _generation = 0;
  int _loading = 0;
  bool _closed = false;
  bool _ready = false;
  double _opacity = 0;
  late final Ticker _fade;
  SkyCamera? _lastCamera;
  Size? _lastSize;

  double get opacity => _ready ? _opacity : 0;
  bool get ready => _ready;
  int get decodedTileEdge => (2050 / _scale).round();
  int get capacity => maxTiles * _scale * _scale;

  void _tickFade(Duration elapsed) {
    final t = (elapsed.inMicroseconds / fadeDuration.inMicroseconds).clamp(
      0.0,
      1.0,
    );
    _opacity = t * t * (3 - 2 * t);
    if (t >= 1) _fade.stop();
    notifyListeners();
  }

  void _updateReadiness() {
    final next = _visible.isNotEmpty && _visible.every(images.containsKey);
    if (next == _ready) return;
    _ready = next;
    _fade.stop();
    _opacity = 0;
    if (next) {
      if (fadeDuration == Duration.zero) {
        _opacity = 1;
      } else {
        _fade.start();
      }
    }
  }

  void _clear() {
    _lastCamera = null;
    _generation++;
    _fade.stop();
    _ready = false;
    _opacity = 0;
    for (final image in images.values) {
      _retire(image);
    }
    images.clear();
    _failed.clear();
    _pending.clear();
  }

  void updateView(
    PanoramaResolution next,
    SkyCamera camera,
    Size size,
    bool enabled,
  ) {
    final previous = _lastCamera;
    if (enabled &&
        next == resolution &&
        previous != null &&
        size == _lastSize &&
        size.shortestSide > 0) {
      final tolerance = camera.tanHalfFov / size.shortestSide * .25;
      final forward = camera.forwardGal - previous.forwardGal;
      final up = camera.upGal - previous.upGal;
      if (forward.dot(forward) < tolerance * tolerance &&
          up.dot(up) < tolerance * tolerance &&
          (camera.tanHalfFov - previous.tanHalfFov).abs() < tolerance) {
        return;
      }
    }
    if (resolution != next) {
      resolution = next;
      _scale = 1;
      _clear();
    }
    clips.clear();
    if (!enabled || next == PanoramaResolution.eightK || size.isEmpty) {
      _lastCamera = null;
      _visible = {};
      _wanted = {};
      if (images.isNotEmpty ||
          _pending.isNotEmpty ||
          _ready ||
          _failed.isNotEmpty) {
        _clear();
      }
      return;
    }
    _lastCamera = camera;
    _lastSize = size;
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
    final visible = clips.keys.toList()
      ..sort(
        (a, b) => (clips[a]!.center - size.center(Offset.zero)).distanceSquared
            .compareTo(
              (clips[b]!.center - size.center(Offset.zero)).distanceSquared,
            ),
      );
    // Hysteresis prevents repeated redecodes around a memory/LOD boundary.
    var scale = _scale;
    while (visible.length > maxTiles * scale * scale) {
      scale *= 2;
    }
    while (scale > 1 &&
        visible.length <= maxTiles * (scale ~/ 2) * (scale ~/ 2) * .65) {
      scale ~/= 2;
    }
    if (scale != _scale) {
      _scale = scale;
      _clear();
    }
    _visible = visible.toSet();
    final adjacent = <String>{};
    for (final key in visible) {
      final xy = key.split('_').map(int.parse).toList();
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          adjacent.add(
            '${(xy[0] + dx) % next.columns}_${(xy[1] + dy).clamp(0, next.rows - 1)}',
          );
        }
      }
    }
    _wanted = [
      ...visible,
      ...adjacent.where((key) => !_visible.contains(key)),
    ].take(capacity).toSet();
    // Touch used textures without discarding tiles just outside the viewport.
    for (final key in _wanted) {
      final image = images.remove(key);
      if (image != null) images[key] = image;
    }
    _updateReadiness();
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
      unawaited(_load(key, _generation, resolution, decodedTileEdge));
    }
  }

  Future<ui.Image> _decode(
    String key,
    PanoramaResolution requested,
    int edge,
  ) async {
    if (_decodeOverride != null) return _decodeOverride(key, edge);
    final folder = await directory(requested);
    final bytes = await File('${folder.path}/$key.webp').readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        if (descriptor.width != 2050 || descriptor.height != 2050) {
          throw const FormatException('Unexpected tile dimensions');
        }
        final codec = await descriptor.instantiateCodec(
          targetWidth: edge,
          targetHeight: edge,
        );
        try {
          return (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }

  Future<void> _load(
    String key,
    int generation,
    PanoramaResolution requested,
    int edge,
  ) async {
    ui.Image? decoded;
    try {
      decoded = await _decode(key, requested, edge);
      if (_closed || generation != _generation || !_wanted.contains(key)) {
        return;
      }
      while (images.length >= capacity) {
        final victim = images.keys
            .where((k) => !_wanted.contains(k))
            .firstOrNull;
        if (victim == null) break;
        _retire(images.remove(victim)!);
      }
      images[key] = decoded;
      decoded = null;
      _updateReadiness();
      notifyListeners();
    } catch (_) {
      if (!_closed && generation == _generation) _failed.add(key);
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
    _fade.dispose();
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
