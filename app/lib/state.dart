import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'models.dart';
import 'photo_utils.dart';

/// Default backend: the Android emulator's alias for the host machine. Change it in Settings
/// (e.g. http://192.168.1.20:8000) when running on a real phone.
const defaultServerUrl = String.fromEnvironment('SERVER_URL', defaultValue: 'http://10.0.2.2:8000');

class ServerUrlNotifier extends Notifier<String> {
  @override
  String build() => defaultServerUrl;

  void set(String url) => state = url.trim();
}

final serverUrlProvider = NotifierProvider<ServerUrlNotifier, String>(ServerUrlNotifier.new);

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(ref.watch(serverUrlProvider)));

final providerCatalogProvider = FutureProvider<ProviderCatalog>(
  (ref) => ref.watch(apiClientProvider).getProviders(),
  retry: (count, error) => count < 2 ? const Duration(seconds: 2) : null,
);

/// The provider key the user picked (null = server default).
class SelectedProviderNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? key) => state = key;
}

final selectedProviderProvider =
    NotifierProvider<SelectedProviderNotifier, String?>(SelectedProviderNotifier.new);

enum Stage { idle, preparing, solving, fetchingImage, done, error }

@immutable
class SessionState {
  const SessionState({
    this.stage = Stage.idle,
    this.photo,
    this.solve,
    this.skyImage,
    this.error,
    this.imageError,
  });

  final Stage stage;
  final PreparedPhoto? photo;
  final SolveResult? solve;
  final SkyImage? skyImage;

  /// Fatal error (solve failed / network); shown full-screen with a retry.
  final ApiException? error;

  /// Sky image failed but the solve succeeded; the original photo is still shown.
  final ApiException? imageError;

  bool get busy => stage == Stage.preparing || stage == Stage.solving || stage == Stage.fetchingImage;

  SessionState copyWith({
    Stage? stage,
    PreparedPhoto? photo,
    SolveResult? solve,
    SkyImage? skyImage,
    ApiException? error,
    ApiException? imageError,
    bool clearImage = false,
  }) =>
      SessionState(
        stage: stage ?? this.stage,
        photo: photo ?? this.photo,
        solve: solve ?? this.solve,
        skyImage: clearImage ? null : (skyImage ?? this.skyImage),
        error: error,
        imageError: imageError,
      );
}

/// One capture -> solve -> sky-image run.
class SessionNotifier extends Notifier<SessionState> {
  CaptureMetadata? _meta;
  Uint8List? _raw;
  int _run = 0; // ignore results from superseded runs

  @override
  SessionState build() => const SessionState();

  ApiClient get _api => ref.read(apiClientProvider);

  Future<void> start(Uint8List rawPhoto, CaptureMetadata meta) async {
    _raw = rawPhoto;
    _meta = meta;
    final run = ++_run;
    state = const SessionState(stage: Stage.preparing);
    try {
      final photo = await compute(preparePhotoIsolate, rawPhoto);
      if (run != _run) return;
      state = state.copyWith(stage: Stage.solving, photo: photo);
      final solve = await _api.solve(photo.jpeg, meta);
      if (run != _run) return;
      state = state.copyWith(stage: Stage.fetchingImage, solve: solve);
      await _fetchImage(run);
    } on ApiException catch (e) {
      if (run == _run) state = state.copyWith(stage: Stage.error, error: e);
    } on FormatException catch (e) {
      if (run == _run) {
        state = state.copyWith(stage: Stage.error, error: ApiException('BAD_PHOTO', e.message));
      }
    }
  }

  /// Re-run after an error, reusing the captured photo and metadata.
  Future<void> retry() async {
    if (state.solve != null && state.photo != null) {
      final run = ++_run;
      state = state.copyWith(stage: Stage.fetchingImage);
      await _fetchImage(run);
    } else if (_raw != null && _meta != null) {
      await start(_raw!, _meta!);
    }
  }

  /// Fetch the sky image again with a different provider.
  Future<void> changeProvider(String key) async {
    ref.read(selectedProviderProvider.notifier).select(key);
    if (state.solve == null || state.photo == null) return;
    final run = ++_run;
    state = state.copyWith(stage: Stage.fetchingImage);
    await _fetchImage(run);
  }

  Future<void> _fetchImage(int run) async {
    final photo = state.photo!;
    final (w, h) = skyImageSize(photo.width, photo.height);
    try {
      final image = await _api.skyImage(
        pointing: state.solve!,
        providerKey: ref.read(selectedProviderProvider),
        width: w,
        height: h,
      );
      if (run == _run) state = state.copyWith(stage: Stage.done, skyImage: image);
    } on ApiException catch (e) {
      if (run == _run) state = state.copyWith(stage: Stage.done, imageError: e);
    }
  }

  void reset() {
    _run++;
    _raw = null;
    _meta = null;
    state = const SessionState();
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);
