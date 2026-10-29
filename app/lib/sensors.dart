import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rotation_sensor/flutter_rotation_sensor.dart';
import 'package:geolocator/geolocator.dart';

import 'sky_math.dart';

/// Keeps a short rolling buffer of fused orientation samples (Android rotation vector:
/// gyro + accelerometer + magnetometer, so it doesn't drift like raw gyroscope data).
///
/// Frame: device -> world, world X = East, Y = North (magnetic), Z = Up. The device
/// coordinate system is used (not the display one) so the axes match the backend.
class OrientationTracker {
  static const window = Duration(milliseconds: 600);

  final _samples = <(DateTime, List<double>)>[];
  StreamSubscription<OrientationEvent>? _sub;
  Object? lastError;

  bool get isSupported => RotationSensor.isPlatformSupported;
  bool get hasData => _samples.isNotEmpty;

  void start() {
    if (_sub != null || !isSupported) return;
    RotationSensor.coordinateSystem = CoordinateSystem.device();
    RotationSensor.samplingPeriod = SensorInterval.gameInterval;
    _sub = RotationSensor.orientationStream.listen((e) {
      final q = e.quaternion;
      final now = DateTime.now();
      _samples.add((now, [q.x, q.y, q.z, q.w]));
      _samples.removeWhere((s) => now.difference(s.$1) > window * 2);
    }, onError: (Object err) => lastError = err);
  }

  /// Samples from the last [window].
  List<List<double>> recent() {
    final cutoff = DateTime.now().subtract(window);
    return [for (final s in _samples) if (s.$1.isAfter(cutoff)) s.$2];
  }

  /// Averaged orientation over the last [window], or null if there is no recent data.
  List<double>? averaged() {
    final r = recent();
    return r.isEmpty ? null : averageQuaternion(r);
  }

  /// How much the phone moved during the last [window], degrees.
  double shake() => maxSpreadDeg(recent());

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _samples.clear();
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
