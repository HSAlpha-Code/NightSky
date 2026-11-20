import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'panorama_background.dart';

/// Versioned public release assets; independent of the user's API server.
const panoramaReleaseUrl =
    'https://github.com/HSAlpha-Code/NightSky/releases/download/panorama-nasa2020-v1';

String panoramaAssetUrl(PanoramaResolution resolution, String filename) =>
    '$panoramaReleaseUrl/nasa2020-${resolution.k}k-$filename';

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
    this.downloadMessage,
  });
  final PanoramaResolution active;
  final Set<PanoramaResolution> installed;
  final PanoramaResolution? downloading;
  final double progress;
  final String? error;
  final String? downloadMessage;
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
  Timer? _backgroundPoll;
  bool _polling = false;
  bool _startingBackground = false;
  String? _handledJob;
  late final PanoramaBackgroundDownloader? _background;

  @override
  PanoramaPackState build() {
    _background = ref.read(panoramaBackgroundDownloaderProvider);
    ref.onDispose(() {
      _cancel?.cancel();
      _backgroundPoll?.cancel();
    });
    unawaited(_initialize());
    return const PanoramaPackState();
  }

  Future<void> _initialize() async {
    await _restore();
    if (ref.mounted && _background != null) await _syncBackground();
  }

  void _watchBackground() {
    _backgroundPoll ??= Timer.periodic(const Duration(milliseconds: 750), (_) {
      if (ref.mounted) unawaited(_syncBackground());
    });
  }

  Future<void> _syncBackground() async {
    if (_polling || _startingBackground || _background == null) return;
    _polling = true;
    final generation = _choiceGeneration;
    try {
      final job = await _background.status();
      if (!ref.mounted ||
          generation != _choiceGeneration ||
          job == null ||
          job['id'] == _handledJob) {
        return;
      }
      final resolution = PanoramaResolution.values
          .where((r) => r.k == job['resolution'])
          .firstOrNull;
      if (resolution == null || resolution == PanoramaResolution.eightK) return;
      final status = job['status'];
      if (status == 'RUNNING' || status == 'ENQUEUED' || status == 'BLOCKED') {
        state = PanoramaPackState(
          active: state.active,
          installed: state.installed,
          downloading: resolution,
          progress: ((job['progress'] as num?)?.toDouble() ?? 0).clamp(0, 1),
          downloadMessage: status == 'RUNNING'
              ? 'Downloading in background'
              : 'Download queued — waiting for network or Android',
        );
        _watchBackground();
      } else {
        _handledJob = job['id'] as String?;
        _backgroundPoll?.cancel();
        _backgroundPoll = null;
        if (status == 'SUCCEEDED') {
          state = PanoramaPackState(
            active: state.active,
            installed: state.installed,
          );
          await _restore();
        } else {
          state = PanoramaPackState(
            active: state.active,
            installed: state.installed,
            error: status == 'CANCELLED'
                ? 'Download cancelled. Tap Download to resume.'
                : (job['error'] as String? ??
                      'Download failed. Check your connection and storage, then retry.'),
          );
        }
      }
    } catch (_) {
      // Keep watching OS-owned work through a temporary activity/channel interruption.
    } finally {
      _polling = false;
    }
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
      downloadMessage: state.downloadMessage,
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

  void cancel() {
    _cancel?.cancel('Cancelled');
    if (_background != null) unawaited(_cancelBackground());
  }

  Future<void> _cancelBackground() async {
    try {
      await _background!.cancel();
      await _syncBackground();
    } catch (_) {
      /* The next poll reconnects if the activity is recreating. */
    }
  }

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
      if (_background != null) {
        _startingBackground = true;
        try {
          final root = await ref.read(panoramaDirectoryProvider);
          await _background.start(resolution.k, root.path);
        } finally {
          _startingBackground = false;
        }
        if (!ref.mounted) return;
        _handledJob = null;
        _watchBackground();
        await _syncBackground();
        return;
      }
      final dir = await folder(resolution);
      await dir.create(recursive: true);
      final dio = ref.read(panoramaDioProvider);
      final response = await dio.get<String>(
        panoramaAssetUrl(resolution, 'manifest.json'),
        cancelToken: token,
        options: Options(responseType: ResponseType.plain),
      );
      final json = jsonDecode(response.data!) as Map<String, dynamic>;
      final pack = PanoramaPack(resolution, json);
      var completed = 0;
      var nextTile = 0;
      Object? failure;
      StackTrace? failureStack;
      final tiles = pack.tiles.values.toList();
      final receivedByTile = <String, int>{};
      void updateProgress() {
        if (!ref.mounted) return;
        final received = receivedByTile.values.fold(
          0,
          (sum, bytes) => sum + bytes,
        );
        state = PanoramaPackState(
          active: state.active,
          installed: state.installed,
          downloading: resolution,
          progress: ((completed + received) / pack.bytes).clamp(0, 1),
        );
      }

      Future<void> downloadTile(Map<String, dynamic> tile) async {
        if (token.isCancelled) throw token.cancelError!;
        final file = File('${dir.path}/${tile['file']}');
        if (!await _matches(file, tile)) {
          final temporary = File('${file.path}.part');
          try {
            await dio.download(
              panoramaAssetUrl(resolution, tile['file'] as String),
              temporary.path,
              cancelToken: token,
              onReceiveProgress: (received, total) {
                receivedByTile[tile['file'] as String] = received.clamp(
                  0,
                  tile['bytes'] as int,
                );
                updateProgress();
              },
            );
            if (!await _matches(temporary, tile)) {
              throw const FormatException('Download checksum mismatch');
            }
            if (token.isCancelled) throw token.cancelError!;
            if (await file.exists()) await file.delete();
            await temporary.rename(file.path);
          } finally {
            if (await temporary.exists()) await temporary.delete();
          }
        }
        completed += tile['bytes'] as int;
        receivedByTile.remove(tile['file']);
        updateProgress();
      }

      Future<void> worker() async {
        while (failure == null && nextTile < tiles.length) {
          final tile = tiles[nextTile++];
          try {
            await downloadTile(tile);
          } catch (error, stack) {
            failure ??= error;
            failureStack ??= stack;
            token.cancel('Download worker stopped');
          }
        }
      }

      await Future.wait(List.generate(4, (_) => worker()));
      if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
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
