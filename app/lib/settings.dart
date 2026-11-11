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

/// Rendering detail for Sky View, trading visual fidelity against GPU/memory load.
/// Panorama uses two square hemisphere textures (each `hemisphereSize` x `hemisphereSize`,
/// forming a `2 * hemisphereSize` x `hemisphereSize` all-sky mosaic).
enum SkyQuality {
  powerSaver(
    'Power saver',
    'For older or low-memory phones (3.2K panorama, stars to mag 5.2)',
    hemisphereSize: 1600,
    limitingMagnitude: 5.2,
    maxLabels: 18,
  ),
  balanced(
    'Balanced',
    'Crisp Retina sky (6.4K panorama, stars to mag 6.2)',
    hemisphereSize: 3200,
    limitingMagnitude: 6.2,
    maxLabels: 34,
  ),
  maxDetail(
    'Max detail',
    'Full 8192×4096 8K Mellinger mosaic and all naked-eye stars (mag 6.5)',
    hemisphereSize: 4096,
    limitingMagnitude: 6.5,
    maxLabels: 50,
  );

  const SkyQuality(
    this.label,
    this.description, {
    required this.hemisphereSize,
    required this.limitingMagnitude,
    required this.maxLabels,
  });

  final String label;
  final String description;
  final int hemisphereSize;
  int get panoramaWidth => hemisphereSize * 2;
  final double limitingMagnitude;
  final int maxLabels;
}

/// Backend used when the user never entered an address. Override at build time with
/// `--dart-define=SERVER_URL=...`.
const defaultServerUrl =
    String.fromEnvironment('SERVER_URL', defaultValue: 'https://nightsky-backend.vercel.app');

/// The default before the hosted backend existed (Android emulator -> host machine). It was
/// never meant to be a user choice: a stored value equal to it is dropped on load so the
/// user moves to [defaultServerUrl]. Also used as the example in the Settings help text.
const legacyDefaultServerUrl = 'http://10.0.2.2:8000';

/// Whether [a] and [b] are the same address, ignoring case and a trailing "/" or "/api".
bool sameServerUrl(String a, String b) {
  String norm(String u) {
    var x = u.trim().toLowerCase();
    while (x.endsWith('/')) {
      x = x.substring(0, x.length - 1);
    }
    return x.endsWith('/api') ? x.substring(0, x.length - 4) : x;
  }

  return norm(a) == norm(b);
}

// Letters, digits, dots and dashes (hostnames, IPv4), or an IPv6 literal (contains ':').
final _validHost = RegExp(r'^([A-Za-z0-9._-]+|[0-9A-Fa-f:.]*:[0-9A-Fa-f:.]*)$');

/// Null if [url] is a well-formed http(s) address, otherwise a message for the user.
String? validateServerUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null ||
      !(uri.scheme == 'http' || uri.scheme == 'https') ||
      !_validHost.hasMatch(uri.host) ||
      uri.hasQuery ||
      uri.hasFragment) {
    return 'Enter a full address starting with https:// (or http://), e.g. $defaultServerUrl';
  }
  return null;
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
    this.skyQuality = SkyQuality.balanced,
    this.startInSkyView = false,
    this.nightVision = false,
    this.useManualLocation = false,
    this.manualLatitude,
    this.manualLongitude,
    this.manualLocationName,
    this.serverUrl,
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

  /// Rendering quality for Sky View (Balanced by default).
  final SkyQuality skyQuality;

  /// Open straight into Sky View on launch (avoids touching the camera on phones without one).
  final bool startInSkyView;

  /// Red night-vision filter in Sky View to preserve dark adaptation.
  final bool nightVision;

  /// When true, Sky View uses [manualLatitude] and [manualLongitude] instead of GPS.
  /// When false, [manualLatitude]/[manualLongitude] may still hold the last known GPS fix
  /// as an offline fallback.
  final bool useManualLocation;
  final double? manualLatitude;
  final double? manualLongitude;
  final String? manualLocationName;

  /// Address the user saved in Settings; null = never changed, use [defaultServerUrl].
  final String? serverUrl;

  AppSettings copyWith({
    bool? useGyroscope,
    SensorSmoothing? smoothing,
    Steadiness? steadiness,
    bool? autoCapture,
    bool? showPointingReadout,
    FontSize? fontSize,
    SkyQuality? skyQuality,
    bool? startInSkyView,
    bool? nightVision,
    bool? useManualLocation,
    double? manualLatitude,
    double? manualLongitude,
    String? manualLocationName,
    bool clearManualLocation = false,
    String? serverUrl,
    bool clearServerUrl = false,
  }) =>
      AppSettings(
        useGyroscope: useGyroscope ?? this.useGyroscope,
        smoothing: smoothing ?? this.smoothing,
        steadiness: steadiness ?? this.steadiness,
        autoCapture: autoCapture ?? this.autoCapture,
        showPointingReadout: showPointingReadout ?? this.showPointingReadout,
        fontSize: fontSize ?? this.fontSize,
        skyQuality: skyQuality ?? this.skyQuality,
        startInSkyView: startInSkyView ?? this.startInSkyView,
        nightVision: nightVision ?? this.nightVision,
        useManualLocation:
            clearManualLocation ? false : (useManualLocation ?? this.useManualLocation),
        manualLatitude: clearManualLocation ? null : (manualLatitude ?? this.manualLatitude),
        manualLongitude: clearManualLocation ? null : (manualLongitude ?? this.manualLongitude),
        manualLocationName:
            clearManualLocation ? null : (manualLocationName ?? this.manualLocationName),
        serverUrl: clearServerUrl ? null : serverUrl ?? this.serverUrl,
      );

  Map<String, dynamic> toJson() => {
        'useGyroscope': useGyroscope,
        'smoothing': smoothing.name,
        'steadiness': steadiness.name,
        'autoCapture': autoCapture,
        'showPointingReadout': showPointingReadout,
        'fontSize': fontSize.name,
        'skyQuality': skyQuality.name,
        'startInSkyView': startInSkyView,
        'nightVision': nightVision,
        'useManualLocation': useManualLocation,
        if (manualLatitude != null) 'manualLatitude': manualLatitude,
        if (manualLongitude != null) 'manualLongitude': manualLongitude,
        if (manualLocationName != null) 'manualLocationName': manualLocationName,
        if (serverUrl != null) 'serverUrl': serverUrl,
      };

  /// Unknown or missing values fall back to the defaults (settings from older versions).
  factory AppSettings.fromJson(Map<String, dynamic> j) {
    const d = AppSettings();
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.where((v) => v.name == name).firstOrNull ?? fallback;
    bool flag(String key, bool fallback) => j[key] is bool ? j[key] as bool : fallback;
    double? coord(String key, double min, double max) {
      final v = j[key];
      if (v is! num) return null;
      final d = v.toDouble();
      return d.isFinite && d >= min && d <= max ? d : null;
    }

    final lat = coord('manualLatitude', -90, 90);
    final lon = coord('manualLongitude', -180, 180);
    final hasCoords = lat != null && lon != null;
    final locName = j['manualLocationName'];
    return AppSettings(
      useGyroscope: flag('useGyroscope', d.useGyroscope),
      smoothing: pick(SensorSmoothing.values, j['smoothing'], d.smoothing),
      steadiness: pick(Steadiness.values, j['steadiness'], d.steadiness),
      autoCapture: flag('autoCapture', d.autoCapture),
      showPointingReadout: flag('showPointingReadout', d.showPointingReadout),
      fontSize: pick(FontSize.values, j['fontSize'], d.fontSize),
      skyQuality: pick(SkyQuality.values, j['skyQuality'], d.skyQuality),
      startInSkyView: flag('startInSkyView', d.startInSkyView),
      nightVision: flag('nightVision', d.nightVision),
      useManualLocation: hasCoords && flag('useManualLocation', d.useManualLocation),
      manualLatitude: hasCoords ? lat : null,
      manualLongitude: hasCoords ? lon : null,
      manualLocationName:
          hasCoords && locName is String && locName.trim().isNotEmpty ? locName.trim() : null,
      serverUrl: _storedServerUrl(j['serverUrl']),
    );
  }

  /// Migration: only a valid, custom address is kept. A stored legacy default (or the
  /// current default) becomes null, so those users follow the app's default.
  static String? _storedServerUrl(Object? raw) {
    if (raw is! String) return null;
    final url = raw.trim();
    if (url.isEmpty || validateServerUrl(url) != null) return null;
    if (sameServerUrl(url, legacyDefaultServerUrl) || sameServerUrl(url, defaultServerUrl)) {
      return null;
    }
    return url;
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

  /// Back to defaults; the server address is kept (it has its own control).
  void reset() => update((s) => AppSettings(serverUrl: s.serverUrl));

  /// Saves the server address; the default (or empty) clears it.
  void setServerUrl(String? url) => update((s) {
        final isDefault = url == null || url.trim().isEmpty || sameServerUrl(url, defaultServerUrl);
        return isDefault ? s.copyWith(clearServerUrl: true) : s.copyWith(serverUrl: url.trim());
      });
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
