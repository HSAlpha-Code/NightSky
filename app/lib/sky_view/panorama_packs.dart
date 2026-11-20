import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../settings.dart';

enum PanoramaResolution {
  eightK(8),
  sixteenK(16),
  thirtyTwoK(32);

  const PanoramaResolution(this.k);
  final int k;
  String get label => '${k}K';
  int get columns => k ~/ 2;
  int get rows => k ~/ 4;
  // Payload sizes of the versioned, lossless packs (manifests add a few KiB).
  int get downloadBytes => switch (this) {
    eightK => 34837846,
    sixteenK => 107421670,
    thirtyTwoK => 366526918,
  };
}

class PanoramaPack {
  PanoramaPack(this.resolution, Map<String, dynamic> json) {
    final width = resolution.k * 1024;
    if (json['version'] != 1 ||
        json['width'] != width ||
        json['height'] != width ~/ 2 ||
        json['tileSize'] != 2048 ||
        json['gutter'] != 1) {
      throw const FormatException('Unsupported panorama pack');
    }
    for (final value in json['tiles'] as List) {
      final tile = Map<String, dynamic>.from(value as Map);
      final name = tile['file'] as String;
      if (!RegExp(r'^\d{1,2}_\d{1,2}\.webp$').hasMatch(name) ||
          tile['bytes'] is! int ||
          (tile['bytes'] as int) <= 0 ||
          (tile['bytes'] as int) > 32 * 1024 * 1024 ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(tile['sha256'] as String) ||
          tiles.containsKey(name)) {
        throw const FormatException('Invalid panorama tile');
      }
      tiles[name] = tile;
    }
    if (tiles.length != resolution.columns * resolution.rows) {
      throw const FormatException('Incomplete panorama pack');
    }
    for (var y = 0; y < resolution.rows; y++) {
      for (var x = 0; x < resolution.columns; x++) {
        if (!tiles.containsKey('${x}_$y.webp')) {
          throw const FormatException('Missing panorama tile');
        }
      }
    }
  }
  final PanoramaResolution resolution;
  final Map<String, Map<String, dynamic>> tiles = {};
  int get bytes =>
      tiles.values.fold(0, (sum, tile) => sum + (tile['bytes'] as int));
}

class PanoramaPackState {
  const PanoramaPackState({
    this.active = PanoramaResolution.eightK,
    this.installed = const {},
    this.downloading,
    this.progress = 0,
    this.error,
  });
  final PanoramaResolution active;
  final Set<PanoramaResolution> installed;
  final PanoramaResolution? downloading;
  final double progress;
  final String? error;
}

final panoramaDirectoryProvider = Provider<Future<Directory>>((ref) async {
  final root = await getApplicationSupportDirectory();
  return Directory('${root.path}/nasa2020-v1')..createSync(recursive: true);
});
final panoramaDioProvider = Provider<Dio>(
  (ref) => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 2),
    ),
  ),
);

class PanoramaPacksNotifier extends Notifier<PanoramaPackState> {
  CancelToken? _cancel;
  int _choiceGeneration = 0;

  @override
  PanoramaPackState build() {
    ref.onDispose(() => _cancel?.cancel());
    unawaited(_restore());
    return const PanoramaPackState();
  }

  Future<Directory> folder(PanoramaResolution r) async {
    final root = await ref.read(panoramaDirectoryProvider);
    return Directory('${root.path}/${r.k}k');
  }

  Future<void> _restore() async {
    final generation = _choiceGeneration;
    try {
      final root = await ref.read(panoramaDirectoryProvider);
      final installed = <PanoramaResolution>{};
      for (final r in PanoramaResolution.values.skip(1)) {
        final dir = Directory('${root.path}/${r.k}k');
        final manifest = File('${dir.path}/manifest.json');
        if (!await manifest.exists()) continue;
        try {
          final pack = PanoramaPack(
            r,
            jsonDecode(await manifest.readAsString()) as Map<String, dynamic>,
          );
          var valid = true;
          for (final tile in pack.tiles.values) {
            final file = File('${dir.path}/${tile['file']}');
            if (!await file.exists() || await file.length() != tile['bytes']) {
              valid = false;
              break;
            }
          }
          if (valid) installed.add(r);
        } catch (_) {
          /* An interrupted or damaged pack is never activated. */
        }
      }
      var active = PanoramaResolution.eightK;
      final selection = File('${root.path}/active.txt');
      if (await selection.exists()) {
        final saved = await selection.readAsString();
        active = installed.where((r) => r.name == saved).firstOrNull ?? active;
      }
      if (ref.mounted &&
          generation == _choiceGeneration &&
          state.downloading == null) {
        state = PanoramaPackState(active: active, installed: installed);
      }
    } catch (_) {
      /* Bundled 8K works even if storage is unavailable. */
    }
  }

  Future<void> select(PanoramaResolution resolution) async {
    if (resolution != PanoramaResolution.eightK &&
        !state.installed.contains(resolution)) {
      return;
    }
    _choiceGeneration++;
    state = PanoramaPackState(
      active: resolution,
      installed: state.installed,
      downloading: state.downloading,
      progress: state.progress,
    );
    try {
      final root = await ref.read(panoramaDirectoryProvider);
      await File(
        '${root.path}/active.txt',
      ).writeAsString(resolution.name, flush: true);
    } catch (_) {
      /* Selection still applies for this session. */
    }
  }

  void cancel() => _cancel?.cancel('Cancelled');

  Future<bool> _matches(File file, Map<String, dynamic> tile) async {
    return await file.exists() &&
        await file.length() == tile['bytes'] &&
        (await sha256.bind(file.openRead()).first).toString() == tile['sha256'];
  }

  Future<void> install(PanoramaResolution resolution) async {
    if (state.downloading != null || resolution == PanoramaResolution.eightK) {
      return;
    }
    _choiceGeneration++;
    final token = _cancel = CancelToken();
    state = PanoramaPackState(
      active: state.active,
      installed: state.installed,
      downloading: resolution,
    );
    try {
      final dir = await folder(resolution);
      await dir.create(recursive: true);
      final base = ref.read(settingsProvider).serverUrl ?? defaultServerUrl;
      final origin = base.replaceFirst(RegExp(r'/(?:api)?/?$'), '');
      final url = '$origin/api/panorama/nasa2020-v1/${resolution.k}k';
      final dio = ref.read(panoramaDioProvider);
      final response = await dio.get<String>(
        '$url/manifest.json',
        cancelToken: token,
        options: Options(responseType: ResponseType.plain),
      );
      final json = jsonDecode(response.data!) as Map<String, dynamic>;
      final pack = PanoramaPack(resolution, json);
      var completed = 0;
      for (final tile in pack.tiles.values) {
        if (token.isCancelled) throw token.cancelError!;
        final file = File('${dir.path}/${tile['file']}');
        if (!await _matches(file, tile)) {
          final temporary = File('${file.path}.part');
          try {
            await dio.download(
              '$url/${tile['file']}',
              temporary.path,
              cancelToken: token,
              onReceiveProgress: (received, total) {
                if (ref.mounted) {
                  state = PanoramaPackState(
                    active: state.active,
                    installed: state.installed,
                    downloading: resolution,
                    progress: ((completed + received) / pack.bytes).clamp(0, 1),
                  );
                }
              },
            );
            if (!await _matches(temporary, tile)) {
              throw const FormatException('Download checksum mismatch');
            }
            if (await file.exists()) await file.delete();
            await temporary.rename(file.path);
          } finally {
            if (await temporary.exists()) await temporary.delete();
          }
        }
        completed += tile['bytes'] as int;
      }
      if (token.isCancelled) throw token.cancelError!;
      final manifest = File('${dir.path}/manifest.json.part');
      await manifest.writeAsString(jsonEncode(json), flush: true);
      final installedManifest = File('${dir.path}/manifest.json');
      if (await installedManifest.exists()) await installedManifest.delete();
      await manifest.rename(installedManifest.path);
      if (!ref.mounted) return;
      state = PanoramaPackState(
        active: state.active,
        installed: {...state.installed, resolution},
      );
      await select(resolution);
    } catch (error) {
      if (!ref.mounted) return;
      final cancelled = error is DioException && CancelToken.isCancel(error);
      state = PanoramaPackState(
        active: state.active,
        installed: state.installed,
        error: cancelled
            ? 'Download cancelled. Tap Download to resume.'
            : 'Download failed. Check your connection and free storage, then retry.',
      );
    } finally {
      _cancel = null;
    }
  }

  Future<void> remove(PanoramaResolution resolution) async {
    if (state.downloading != null || resolution == PanoramaResolution.eightK) {
      return;
    }
    if (state.active == resolution) await select(PanoramaResolution.eightK);
    try {
      final dir = await folder(resolution);
      if (await dir.exists()) await dir.delete(recursive: true);
      if (ref.mounted) {
        state = PanoramaPackState(
          active: state.active,
          installed: {...state.installed}..remove(resolution),
        );
      }
    } catch (_) {
      if (ref.mounted) {
        state = PanoramaPackState(
          active: state.active,
          installed: state.installed,
          error: 'Could not remove the panorama. Please try again.',
        );
      }
    }
  }
}

final panoramaPacksProvider =
    NotifierProvider<PanoramaPacksNotifier, PanoramaPackState>(
      PanoramaPacksNotifier.new,
    );
