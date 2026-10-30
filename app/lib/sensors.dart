import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import 'sky_math.dart';

/// Which sensors produce the orientation.
enum SensorMode {
  /// Accelerometer + magnetometer only (no gyroscope). "Up" comes straight from gravity,
  /// so above/below the horizon is never flipped. Default.
  compass,

  /// Android's rotation vector: gyroscope fused with accelerometer and magnetometer.
  /// Smoother, but on some phones the fusion can flip or drift.
  gyro,
}

/// Turns raw sensor readings into a smoothed device -> world orientation and keeps a short
/// rolling buffer for averaging and the steadiness check. No platform code, so it is unit
/// tested with synthetic readings.
///
/// Frame: world X = East, Y = magnetic North, Z = Up; device axes as on Android (the
/// rear camera looks along device -Z). Matches the backend.
class OrientationEngine {
  OrientationEngine({this.mode = SensorMode.compass, this.alpha = 0.2});

  static const window = Duration(milliseconds: 600);

  SensorMode mode;

  /// Low-pass factor per reading (1 = no smoothing). See SensorSmoothing.
  double alpha;

  List<double>? _gravity;
  List<double>? _magnetic;
  List<double>? _smoothed;
  final _samples = <(Duration, List<double>)>[];

  bool get hasData => _samples.isNotEmpty;

  /// Latest smoothed orientation [x, y, z, w], or null before the first reading.
  List<double>? get current => _smoothed;

  void reset() {
    _gravity = _magnetic = _smoothed = null;
    _samples.clear();
  }

  void addAccelerometer(List<double> v, Duration t) {
    _gravity = lowPass(_gravity, v, alpha);
    _update(t);
  }

  void addMagnetometer(List<double> v, Duration t) {
    _magnetic = lowPass(_magnetic, v, alpha);
    _update(t);
  }

  void addRotationVector(List<double> v, Duration t) {
    _push(smoothQuaternion(_smoothed, quaternionFromRotationVector(v), alpha), t);
  }

  void _update(Duration t) {
    final g = _gravity, m = _magnetic;
    if (g == null || m == null) return;
    final r = rotationFromGravityAndMagnetic(g, m);
    if (r == null) return;
    // The vectors are already low-passed, so the orientation itself is not filtered again.
    _push(matrixToQuaternion(r), t);
  }

  void _push(List<double> q, Duration t) {
    _smoothed = q;
    _samples.add((t, q));
    _samples.removeWhere((s) => t - s.$1 > window * 2);
  }

  /// Samples from the last [window] before [now] (default: the newest sample).
  List<List<double>> recent([Duration? now]) {
    if (_samples.isEmpty) return const [];
    final cutoff = (now ?? _samples.last.$1) - window;
    return [for (final s in _samples) if (s.$1 > cutoff) s.$2];
  }

  /// Averaged orientation over the last [window], or null if there is no data.
  List<double>? averaged([Duration? now]) {
    final r = recent(now);
    return r.isEmpty ? null : averageQuaternion(r);
  }

  /// How much the phone moved during the last [window], degrees.
  double shake([Duration? now]) => maxSpreadDeg(recent(now));
}

/// Which motion sensors the phone has.
@immutable
class SensorAvailability {
  const SensorAvailability({
    this.accelerometer = false,
    this.magnetometer = false,
    this.gyroscope = false,
    this.rotationVector = false,
  });

  final bool accelerometer;
  final bool magnetometer;
  final bool gyroscope;
  final bool rotationVector;

  bool supports(SensorMode mode) => switch (mode) {
        SensorMode.compass => accelerometer && magnetometer,
        SensorMode.gyro => rotationVector && gyroscope,
      };

  static const _channel = MethodChannel('night_sky/sensors');

  static Future<SensorAvailability> query() async {
    try {
      final r = await _channel.invokeMapMethod<String, bool>('available') ?? const {};
      return SensorAvailability(
        accelerometer: r['accelerometer'] ?? false,
        magnetometer: r['magnetometer'] ?? false,
        gyroscope: r['gyroscope'] ?? false,
        rotationVector: r['rotationVector'] ?? false,
      );
    } on MissingPluginException {
      return const SensorAvailability();
    } on PlatformException {
      return const SensorAvailability();
    }
  }
}

/// Connects [OrientationEngine] to the phone's sensors (MainActivity.kt, `night_sky/sensor_events`).
class OrientationTracker {
  OrientationTracker({SensorMode mode = SensorMode.compass, double alpha = 0.2})
      : engine = OrientationEngine(mode: mode, alpha: alpha);

  static const _events = EventChannel('night_sky/sensor_events');

  final OrientationEngine engine;
  StreamSubscription<dynamic>? _sub;
  Object? lastError;

  SensorMode get mode => engine.mode;
  bool get hasData => engine.hasData;

  /// Start (or restart, e.g. after the sensor mode changed in Settings).
  void start({SensorMode? mode, double? alpha}) {
    if (alpha != null) engine.alpha = alpha;
    if (mode != null && mode != engine.mode) {
      engine.mode = mode;
      stop();
    }
    if (_sub != null) return;
    lastError = null;
    engine.reset();
    _sub = _events.receiveBroadcastStream({'mode': engine.mode.name}).listen(_onEvent,
        onError: (Object err) => lastError = err);
  }

  void _onEvent(dynamic event) {
    final d = [for (final v in event as List<dynamic>) (v as num).toDouble()];
    final t = Duration(microseconds: d[6] ~/ 1000);
    switch (d[0].round()) {
      case 0:
        engine.addAccelerometer(d.sublist(1, 4), t);
      case 1:
        engine.addMagnetometer(d.sublist(1, 4), t);
      case 2:
        engine.addRotationVector(d.sublist(1, 5), t);
    }
  }

  /// Averaged orientation over the last 0.6 s, or null if there is no recent data.
  List<double>? averaged() => engine.averaged();

  /// How much the phone moved during the last 0.6 s, degrees.
  double shake() => engine.shake();

  void stop() {
    _sub?.cancel();
    _sub = null;
    engine.reset();
  }
}

enum LocationStatus { granted, denied, deniedForever, serviceDisabled }

class LocationService {
  Position? _last;

  Future<LocationStatus> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return LocationStatus.serviceDisabled;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    return switch (perm) {
      LocationPermission.deniedForever => LocationStatus.deniedForever,
      LocationPermission.denied || LocationPermission.unableToDetermine => LocationStatus.denied,
      _ => LocationStatus.granted,
    };
  }

  /// Start fetching a fix in the background so it's ready when the shutter is pressed.
  Future<void> warmUp() async {
    try {
      _last = await Geolocator.getLastKnownPosition() ?? _last;
      _last = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 20)),
      );
    } catch (_) {
      // Keep whatever we had; position is optional.
    }
  }

  /// Best available position: a fresh fix if quick, else the last known one.
  Future<Position?> current() async {
    try {
      final fresh = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 4)),
      );
      return _last = fresh;
    } catch (_) {
      return _last ?? await Geolocator.getLastKnownPosition();
    }
  }
}

/// Horizontal FOV of a portrait photo from the camera's optics (Android camera2), or null.
class CameraOptics {
  static const _channel = MethodChannel('night_sky/camera');

  static Future<double?> portraitFovDeg(CameraDescription camera) async {
    try {
      final r = await _channel
          .invokeMapMethod<String, double>('getCameraOptics', {'cameraId': camera.name});
      if (r == null) return null;
      return fovFromOptics(
        focalLengthMm: r['focalLength']!,
        sensorWidthMm: r['sensorWidth']!,
        sensorHeightMm: r['sensorHeight']!,
        portrait: true,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
