import 'dart:async';

import 'package:dio/dio.dart';
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
    this.landmarks,
  });

  final Stage stage;
  final PreparedPhoto? photo;
  final SolveResult? solve;
  final SkyImage? skyImage;

  /// Markers for the field (null until loaded; empty if the lookup failed).
  final LandmarkField? landmarks;

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
    LandmarkField? landmarks,
    bool clearImage = false,
  }) =>
      SessionState(
        stage: stage ?? this.stage,
        photo: photo ?? this.photo,
        solve: solve ?? this.solve,
        skyImage: clearImage ? null : (skyImage ?? this.skyImage),
        error: error,
        imageError: imageError,
        landmarks: landmarks ?? this.landmarks,
      );
}

/// One capture -> solve -> sky-image run.
class SessionNotifier extends Notifier<SessionState> {
  /// How often to re-ask for markers while Hubble/JWST checks are pending, and how many times.
  static Duration landmarkPollInterval = const Duration(seconds: 6);
  static const landmarkMaxPolls = 6;

  CaptureMetadata? _meta;
  Uint8List? _raw;
  int _run = 0; // ignore results from superseded runs
  CancelToken? _imageCancel;
  CancelToken? _landmarkCancel;
  Timer? _landmarkTimer;
  bool _disposed = false;

  @override
  SessionState build() {
    ref.onDispose(() {
      _disposed = true;
      _imageCancel?.cancel();
      _landmarkCancel?.cancel();
      _landmarkTimer?.cancel();
    });
    return const SessionState();
  }

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
      unawaited(_loadLandmarks(run));
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
    _imageCancel?.cancel();
    final cancel = _imageCancel = CancelToken();
    try {
      final image = await _api.skyImage(
        pointing: state.solve!,
        providerKey: ref.read(selectedProviderProvider),
        width: w,
        height: h,
        cancelToken: cancel,
      );
      if (run == _run) state = state.copyWith(stage: Stage.done, skyImage: image);
    } on ApiException catch (e) {
      if (run == _run && e.code != 'CANCELLED') {
        state = state.copyWith(stage: Stage.done, imageError: e);
      }
    }
  }

  /// Stop waiting for the survey image. The original photo (or the previous survey image)
  /// stays on screen; "Retry" or the image-source picker can fetch it again.
  void cancelImage() {
    if (state.stage != Stage.fetchingImage) return;
    _run++;
    _imageCancel?.cancel();
    final keepPrevious = state.skyImage != null;
    state = state.copyWith(
      stage: Stage.done,
      imageError: keepPrevious
          ? null
          : const ApiException('CANCELLED', 'Survey image cancelled.'),
    );
  }

  /// Markers for the field. If some Hubble/JWST checks are still running on the server,
  /// ask again a few times so the "has high-res image" style fills in.
  Future<void> _loadLandmarks(int run, [int attempt = 0]) async {
    if (_disposed) return;
    final solve = state.solve;
    final photo = state.photo;
    if (solve == null || photo == null) return;
    _landmarkCancel?.cancel();
    final cancel = _landmarkCancel = CancelToken();
    try {
      final field = await _api.landmarks(solve,
          aspect: photo.height / photo.width, cancelToken: cancel);
      if (_landmarkRunStale(run, solve)) return;
      state = state.copyWith(landmarks: field, error: state.error, imageError: state.imageError);
      if (field.pending && attempt < landmarkMaxPolls) {
        _landmarkTimer?.cancel();
        _landmarkTimer =
            Timer(landmarkPollInterval, () => _loadLandmarks(run, attempt + 1));
      }
    } on ApiException {
      // Markers are optional; keep the result screen working without them.
      if (!_landmarkRunStale(run, solve) && state.landmarks == null) {
        state = state.copyWith(
            landmarks: const LandmarkField(landmarks: [], pending: false),
            error: state.error,
            imageError: state.imageError);
      }
    }
  }

  /// Image runs bump [_run] (cancel, provider change), so markers check the pointing instead.
  bool _landmarkRunStale(int run, SolveResult solve) =>
      _disposed || !identical(state.solve, solve) || state.stage == Stage.idle;

  void reset() {
    _run++;
    _imageCancel?.cancel();
    _landmarkCancel?.cancel();
    _landmarkTimer?.cancel();
    _raw = null;
    _meta = null;
    state = const SessionState();
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);
