import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'models.dart';
import 'state.dart';

/// Curated Cosmic Highlights: hand-picked images for some celestial bodies, served by
/// `/api/curated/...`. The index (which bodies have highlights) is downloaded when the app
/// connects and cached; details and images are loaded lazily when a body's source is opened.

/// Name of the extra image source in the detail view's selector.
const curatedSourceLabel = 'Curated Cosmic Highlights';

@immutable
class CuratedIndex {
  const CuratedIndex({required this.version, required this.counts});

  final String version;

  /// body_id -> number of enabled highlights.
  final Map<String, int> counts;

  bool has(String bodyId) => (counts[bodyId] ?? 0) > 0;

  factory CuratedIndex.fromJson(Map<String, dynamic> j) {
    final counts = <String, int>{};
    for (final b in (j['bodies'] as List? ?? const [])) {
      if (b is Map && b['body_id'] is String && b['count'] is num) {
        counts[b['body_id'] as String] = (b['count'] as num).toInt();
      }
    }
    return CuratedIndex(version: (j['version'] ?? '') as String, counts: counts);
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'bodies': [
          for (final e in counts.entries) {'body_id': e.key, 'body_name': '', 'count': e.value}
        ],
      };
}

@immutable
class CuratedHighlight {
  const CuratedHighlight({
    required this.id,
    required this.imageUrl,
    this.thumbnailUrl = '',
    this.title = '',
    this.caption = '',
    this.credit = '',
    this.sourceOutlet = '',
    this.sourceUrl = '',
  });

  final int id;
  final String imageUrl;
  final String thumbnailUrl;
  final String title;
  final String caption;
  final String credit;
  final String sourceOutlet;
  final String sourceUrl;

  factory CuratedHighlight.fromJson(Map<String, dynamic> j) {
    String s(String k) => (j[k] ?? '') as String;
    return CuratedHighlight(
      id: (j['id'] as num).toInt(),
      imageUrl: s('image_url'),
      thumbnailUrl: s('thumbnail_url'),
      title: s('title'),
      caption: s('caption'),
      credit: s('credit'),
      sourceOutlet: s('source_outlet'),
      sourceUrl: s('source_url'),
    );
  }
}

@immutable
class CuratedBody {
  const CuratedBody({required this.bodyId, required this.bodyName, required this.highlights});

  final String bodyId;
  final String bodyName;
  final List<CuratedHighlight> highlights;

  factory CuratedBody.fromJson(Map<String, dynamic> j) => CuratedBody(
        bodyId: (j['body_id'] ?? '') as String,
        bodyName: (j['body_name'] ?? '') as String,
        highlights: [
          for (final h in (j['highlights'] as List? ?? const []))
            if (h is Map<String, dynamic> && (h['image_url'] ?? '') != '')
              CuratedHighlight.fromJson(h)
        ],
      );
}

/// Small persistent string cache (Android SharedPreferences via the `night_sky/settings`
/// channel); tests use [MemoryCacheStore].
abstract class CacheStore {
  Future<String?> load(String key);
  Future<void> save(String key, String value);
}

class ChannelCacheStore implements CacheStore {
  static const _channel = MethodChannel('night_sky/settings');

  @override
  Future<String?> load(String key) async {
    try {
      return await _channel.invokeMethod<String>('loadKey', key);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> save(String key, String value) async {
    try {
      await _channel.invokeMethod<void>('saveKey', {'key': key, 'value': value});
    } on MissingPluginException {
      // Not persisted; still works this session.
    } on PlatformException {
      // Same.
    }
  }
}

class MemoryCacheStore implements CacheStore {
  final values = <String, String>{};

  @override
  Future<String?> load(String key) async => values[key];

  @override
  Future<void> save(String key, String value) async => values[key] = value;
}

final cacheStoreProvider = Provider<CacheStore>((ref) => ChannelCacheStore());

/// A cached server answer: only valid for the server it came from.
class _Cached {
  _Cached(this.etag, this.json);

  final String? etag;
  final Map<String, dynamic> json;
}

Future<_Cached?> _readCache(CacheStore store, String key, String server) async {
  try {
    final raw = await store.load(key);
    if (raw == null) return null;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    if (!sameServer(m['server'] as String?, server)) return null;
    return _Cached(m['etag'] as String?, m['data'] as Map<String, dynamic>);
  } catch (_) {
    return null; // corrupt cache: ignore
  }
}

Future<void> _writeCache(
    CacheStore store, String key, String server, String? etag, Map<String, dynamic> data) {
  return store.save(key, jsonEncode({'server': server, 'etag': etag, 'data': data}));
}

bool sameServer(String? a, String? b) =>
    a != null && b != null && ApiClient.normaliseBaseUrl(a) == ApiClient.normaliseBaseUrl(b);

const _indexKey = 'curated_index';

/// The downloaded index, or null (nothing cached yet, or no server). Refreshed whenever the
/// server address changes (and at app start, because the app shell listens to it). Failures
/// are silent: the cached copy is used, and without one the source simply stays hidden.
class CuratedIndexNotifier extends Notifier<CuratedIndex?> {
  int _generation = 0;

  @override
  CuratedIndex? build() {
    final api = ref.watch(apiClientProvider);
    final server = ref.watch(serverUrlProvider);
    final generation = ++_generation;
    unawaited(_sync(api, server, generation));
    return null;
  }

  Future<void> _sync(ApiClient api, String server, int generation) async {
    try {
      final store = ref.read(cacheStoreProvider);
      final cached = await _readCache(store, _indexKey, server);
      if (!ref.mounted || generation != _generation) return;
      if (cached != null) state = CuratedIndex.fromJson(cached.json);
      final fresh = await api.curatedIndex(etag: cached?.etag);
      if (!ref.mounted || generation != _generation) return;
      if (fresh.json == null) return; // 304: cached copy is current
      state = CuratedIndex.fromJson(fresh.json!);
      await _writeCache(store, _indexKey, server, fresh.etag, fresh.json!);
    } catch (_) {
      // Quiet by design: never disturb the camera or the core flow.
    }
  }
}

final curatedIndexProvider =
    NotifierProvider<CuratedIndexNotifier, CuratedIndex?>(CuratedIndexNotifier.new);

/// Highlights of one body, loaded when its source is opened. Cached (with ETag) so reopening
/// is cheap and works offline once seen.
final curatedBodyProvider =
    FutureProvider.autoDispose.family<CuratedBody, String>((ref, bodyId) async {
  final api = ref.watch(apiClientProvider);
  final server = ref.watch(serverUrlProvider);
  final store = ref.read(cacheStoreProvider);
  final key = 'curated_body_$bodyId';
  final cached = await _readCache(store, key, server);
  try {
    final fresh = await api.curatedBody(bodyId, etag: cached?.etag);
    if (fresh.json == null && cached != null) return CuratedBody.fromJson(cached.json);
    if (fresh.json == null) throw const ApiException('ERROR', 'Empty answer from the server.');
    unawaited(_writeCache(store, key, server, fresh.etag, fresh.json!));
    return CuratedBody.fromJson(fresh.json!);
  } on ApiException {
    if (cached != null) return CuratedBody.fromJson(cached.json);
    rethrow;
  }
}, retry: (count, error) => null);

/// Which image the swipe viewer shows: remembered across rotation and returning from other
/// screens, reset to the first image when another body is opened.
class CuratedPageNotifier extends Notifier<({String bodyId, int page})> {
  @override
  ({String bodyId, int page}) build() => (bodyId: '', page: 0);

  int pageFor(String bodyId) => state.bodyId == bodyId ? state.page : 0;

  void set(String bodyId, int page) => state = (bodyId: bodyId, page: page);
}

final curatedPageProvider =
    NotifierProvider<CuratedPageNotifier, ({String bodyId, int page})>(CuratedPageNotifier.new);
