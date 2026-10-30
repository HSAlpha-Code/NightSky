import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Smoothing applied to the orientation readings (exponential low-pass filter).
enum SensorSmoothing {
  off('Off', 'Raw readings, most responsive', 1.0),
  low('Low', 'Slight smoothing', 0.5),
  medium('Medium', 'Balanced (recommended)', 0.2),
  high('High', 'Very smooth, slower to follow', 0.08);

  const SensorSmoothing(this.label, this.description, this.alpha);

  final String label;
  final String description;

  /// Low-pass factor per reading (1 = no smoothing).
  final double alpha;
}

/// How still the phone has to be to count as "steady" (and before auto-capture fires):
/// the largest allowed movement, in degrees, over the last 0.6 s.
enum Steadiness {
  relaxed('Relaxed', 3.0),
  normal('Normal', 1.5),
  strict('Strict', 0.7);

  const Steadiness(this.label, this.maxShakeDeg);

  final String label;
  final double maxShakeDeg;
}

/// Text size, applied app-wide on top of the phone's own font size.
enum FontSize {
  small('Small', 0.85),
  normal('Normal', 1.0),
  large('Large', 1.15),
  extraLarge('Extra large', 1.3);

  const FontSize(this.label, this.scale);

  final String label;
  final double scale;
}

@immutable
class AppSettings {
  const AppSettings({
    this.useGyroscope = false,
    this.smoothing = SensorSmoothing.medium,
    this.steadiness = Steadiness.normal,
    this.autoCapture = false,
    this.showPointingReadout = true,
    this.fontSize = FontSize.normal,
  });

  /// Off (default): orientation from accelerometer + compass only, like Sky Map's
  /// "legacy sensors". On: Android's gyroscope-fused rotation vector.
  final bool useGyroscope;
  final SensorSmoothing smoothing;
  final Steadiness steadiness;

  /// Take the photo automatically once the phone has been steady for a moment.
  final bool autoCapture;

  /// Show where the camera points (altitude/heading) over the camera preview.
  final bool showPointingReadout;
  final FontSize fontSize;

  AppSettings copyWith({
    bool? useGyroscope,
    SensorSmoothing? smoothing,
    Steadiness? steadiness,
    bool? autoCapture,
    bool? showPointingReadout,
    FontSize? fontSize,
  }) =>
      AppSettings(
        useGyroscope: useGyroscope ?? this.useGyroscope,
        smoothing: smoothing ?? this.smoothing,
        steadiness: steadiness ?? this.steadiness,
        autoCapture: autoCapture ?? this.autoCapture,
        showPointingReadout: showPointingReadout ?? this.showPointingReadout,
        fontSize: fontSize ?? this.fontSize,
      );

  Map<String, dynamic> toJson() => {
        'useGyroscope': useGyroscope,
        'smoothing': smoothing.name,
        'steadiness': steadiness.name,
        'autoCapture': autoCapture,
        'showPointingReadout': showPointingReadout,
        'fontSize': fontSize.name,
      };

  /// Unknown or missing values fall back to the defaults (settings from older versions).
  factory AppSettings.fromJson(Map<String, dynamic> j) {
    const d = AppSettings();
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.where((v) => v.name == name).firstOrNull ?? fallback;
    bool flag(String key, bool fallback) => j[key] is bool ? j[key] as bool : fallback;
    return AppSettings(
      useGyroscope: flag('useGyroscope', d.useGyroscope),
      smoothing: pick(SensorSmoothing.values, j['smoothing'], d.smoothing),
      steadiness: pick(Steadiness.values, j['steadiness'], d.steadiness),
      autoCapture: flag('autoCapture', d.autoCapture),
      showPointingReadout: flag('showPointingReadout', d.showPointingReadout),
      fontSize: pick(FontSize.values, j['fontSize'], d.fontSize),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings && jsonEncode(toJson()) == jsonEncode(other.toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}


/// Where settings are kept. The default stores them in Android SharedPreferences through
/// the `night_sky/settings` channel (MainActivity.kt); tests use [MemorySettingsStore].
abstract class SettingsStore {
  Future<String?> load();
  Future<void> save(String json);
}

class ChannelSettingsStore implements SettingsStore {
  static const _channel = MethodChannel('night_sky/settings');

  @override
  Future<String?> load() async {
    try {
      return await _channel.invokeMethod<String>('load');
    } on MissingPluginException {
      return null; // not on Android (e.g. tests): defaults
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> save(String json) async {
    try {
      await _channel.invokeMethod<void>('save', json);
    } on MissingPluginException {
      // Settings still apply for this session, they just aren't kept.
    } on PlatformException {
      // Same.
    }
  }
}

class MemorySettingsStore implements SettingsStore {
  MemorySettingsStore([this.value]);

  String? value;

  @override
  Future<String?> load() async => value;

  @override
  Future<void> save(String json) async => value = json;
}

final settingsStoreProvider = Provider<SettingsStore>((ref) => ChannelSettingsStore());

class SettingsNotifier extends Notifier<AppSettings> {
  bool _changed = false;

  @override
  AppSettings build() {
    unawaited(_restore());
    return const AppSettings();
  }

  Future<void> _restore() async {
    final raw = await ref.read(settingsStoreProvider).load();
    if (raw == null || _changed) return; // don't overwrite a change made meanwhile
    try {
      state = AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      // Corrupt settings: keep the defaults.
    } on TypeError {
      // Same.
    }
  }

  void update(AppSettings Function(AppSettings) change) {
    _changed = true;
    state = change(state);
    unawaited(ref.read(settingsStoreProvider).save(jsonEncode(state.toJson())));
  }

  void reset() => update((_) => const AppSettings());
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
