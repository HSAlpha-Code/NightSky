import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// Disposable device storage, shared by survey details and curated image downloads.
/// Successful reads refresh LRU order; writes are atomic and evict the oldest files.
class ImageDiskCache {
  ImageDiskCache({Future<Directory?> Function()? directory, this.maxBytes = 100 * 1024 * 1024})
      : _directory = directory ?? _platformDirectory;

  static final shared = ImageDiskCache();
  final Future<Directory?> Function() _directory;
  final int maxBytes;
  Future<void> _pending = Future.value();

  static Future<Directory?> _platformDirectory() async {
    if (!Platform.isAndroid) return null;
    final path = await const MethodChannel('night_sky/image_cache').invokeMethod<String>('directory');
    return path == null ? null : Directory(path);
  }

  // Serialize file operations so reads, replacements and eviction cannot race.
  Future<T> _run<T>(T fallback, Future<T> Function(Directory) operation) async {
    final Directory? directory;
    try {
      directory = await _directory();
    } catch (_) {
      return fallback;
    }
    final folder = directory;
    if (folder == null) return fallback;
    final result = _pending.then((_) async {
      try {
        await folder.create(recursive: true);
        return await operation(folder);
      } catch (_) {
        // Disk full, cache cleared by the OS, unavailable platform: use the network.
        return fallback;
      }
    });
    _pending = result.then((_) {});
    return result;
  }

  File _file(Directory directory, String key) =>
      File('${directory.path}/${sha256.convert(utf8.encode(key))}.cache');

  Future<Uint8List?> read(String key) => _run<Uint8List?>(null, (directory) async {
        final file = _file(directory, key);
        if (!await file.exists()) return null;
        final bytes = await file.readAsBytes();
        await file.setLastModified(DateTime.now());
        return bytes;
      });

  Future<void> remove(String key) => _run<void>(null, (directory) async {
        final file = _file(directory, key);
        if (await file.exists()) await file.delete();
      });

  Future<void> write(String key, List<int> bytes) => _run<void>(null, (directory) async {
        if (bytes.isEmpty || bytes.length > maxBytes) return;
        final file = _file(directory, key);
        final temp = File('${file.path}.tmp');
        await temp.writeAsBytes(bytes, flush: true);
        if (await file.exists()) await file.delete();
        await temp.rename(file.path);
        final entries = <(File, FileStat)>[];
        var total = 0;
        await for (final entry in directory.list()) {
          if (entry is! File || !entry.path.endsWith('.cache')) continue;
          final stat = await entry.stat();
          entries.add((entry, stat));
          total += stat.size;
        }
        entries.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
        for (final entry in entries) {
          if (total <= maxBytes) break;
          await entry.$1.delete();
          total -= entry.$2.size;
        }
      });
}
