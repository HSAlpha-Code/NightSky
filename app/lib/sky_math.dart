import 'dart:math' as math;

/// Average of orientation quaternions [x, y, z, w]. Signs are aligned first because q and -q
/// are the same rotation. Fine for the small spread of a hand-held phone.
List<double> averageQuaternion(List<List<double>> samples) {
  if (samples.isEmpty) throw ArgumentError('No samples');
  final ref = samples.first;
  final sum = [0.0, 0.0, 0.0, 0.0];
  for (final q in samples) {
    final dot = q[0] * ref[0] + q[1] * ref[1] + q[2] * ref[2] + q[3] * ref[3];
    final s = dot < 0 ? -1.0 : 1.0;
    for (var i = 0; i < 4; i++) {
      sum[i] += s * q[i];
    }
  }
  final n = math.sqrt(sum.fold<double>(0, (a, v) => a + v * v));
  return sum.map((v) => v / n).toList();
}

/// Rotation angle between two unit quaternions, degrees.
double quaternionAngleDeg(List<double> a, List<double> b) {
  final dot = (a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3]).abs().clamp(0.0, 1.0);
  return 2 * math.acos(dot) * 180 / math.pi;
}

/// Largest deviation of any sample from the average, degrees (how much the phone moved).
double maxSpreadDeg(List<List<double>> samples) {
  if (samples.length < 2) return 0;
  final avg = averageQuaternion(samples);
  return samples.map((q) => quaternionAngleDeg(q, avg)).reduce(math.max);
}

// --- Orientation from raw sensors -------------------------------------------------------
//
// Frames (Android convention, same as the backend): world X = East, Y = magnetic North,
// Z = Up; device X = right, Y = top of the screen, Z = out of the screen. A rotation matrix
// R (row-major, 3x3 as a flat list of 9) maps device vectors to world vectors: w = R · d.

/// Device -> world rotation from an accelerometer and a magnetometer reading (both in the
/// device frame), like Android's SensorManager.getRotationMatrix. No gyroscope involved.
///
/// The "up" axis comes from gravity alone, so whether the camera points above or below the
/// horizon is always right; only the compass heading depends on the (noisier) magnetometer.
/// Returns null in free fall or when the magnetic field is parallel to gravity.
List<double>? rotationFromGravityAndMagnetic(List<double> gravity, List<double> magnetic) {
  final g = gravity, m = magnetic;
  final gNorm = _norm(g);
  if (gNorm < 0.1 * 9.81) return null; // free fall: no "down" to measure
  var h = _cross(m, g); // east
  final hNorm = _norm(h);
  if (hNorm < 1e-6 || hNorm / (gNorm * _norm(m)) < 0.1) return null;
  h = [for (final v in h) v / hNorm];
  final a = [for (final v in g) v / gNorm]; // up (the accelerometer measures the push up)
  final n = _cross(a, h); // north
  return [...h, ...n, ...a];
}

/// Unit quaternion [x, y, z, w] of a rotation matrix (row-major, 9 values).
List<double> matrixToQuaternion(List<double> r) {
  final m00 = r[0], m01 = r[1], m02 = r[2];
  final m10 = r[3], m11 = r[4], m12 = r[5];
  final m20 = r[6], m21 = r[7], m22 = r[8];
  final trace = m00 + m11 + m22;
  double x, y, z, w;
  if (trace > 0) {
    final s = math.sqrt(trace + 1) * 2;
    w = 0.25 * s;
    x = (m21 - m12) / s;
    y = (m02 - m20) / s;
    z = (m10 - m01) / s;
  } else if (m00 > m11 && m00 > m22) {
    final s = math.sqrt(1 + m00 - m11 - m22) * 2;
    w = (m21 - m12) / s;
    x = 0.25 * s;
    y = (m01 + m10) / s;
    z = (m02 + m20) / s;
  } else if (m11 > m22) {
    final s = math.sqrt(1 + m11 - m00 - m22) * 2;
    w = (m02 - m20) / s;
    x = (m01 + m10) / s;
    y = 0.25 * s;
    z = (m12 + m21) / s;
  } else {
    final s = math.sqrt(1 + m22 - m00 - m11) * 2;
    w = (m10 - m01) / s;
    x = (m02 + m20) / s;
    y = (m12 + m21) / s;
    z = 0.25 * s;
  }
  return _normalise([x, y, z, w]);
}

/// Rotation matrix (row-major) of a unit quaternion [x, y, z, w].
List<double> quaternionToMatrix(List<double> q) {
  final [x, y, z, w] = _normalise(q);
  return [
    1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w),
    2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w),
    2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y),
  ];
}

/// Quaternion [x, y, z, w] from Android's rotation-vector values (x, y, z[, w]). Older
/// devices omit w; it is then derived from the unit norm.
List<double> quaternionFromRotationVector(List<double> v) {
  final x = v[0], y = v[1], z = v[2];
  final w = v.length > 3 && v[3].isFinite
      ? v[3]
      : math.sqrt(math.max(0.0, 1 - x * x - y * y - z * z));
  return _normalise([x, y, z, w]);
}

/// Exponential low-pass filter: moves [previous] a fraction [alpha] (0..1] towards [next].
/// alpha = 1 means no smoothing.
List<double> lowPass(List<double>? previous, List<double> next, double alpha) {
  if (previous == null || alpha >= 1) return List.of(next);
  return [for (var i = 0; i < next.length; i++) previous[i] + alpha * (next[i] - previous[i])];
}

/// Low-pass filter for orientations: normalised linear interpolation between quaternions,
/// taking the short way round (q and -q are the same rotation).
List<double> smoothQuaternion(List<double>? previous, List<double> next, double alpha) {
  if (previous == null || alpha >= 1) return List.of(next);
  final dot = next[0] * previous[0] + next[1] * previous[1] + next[2] * previous[2] +
      next[3] * previous[3];
  final s = dot < 0 ? -1.0 : 1.0;
  return _normalise([
    for (var i = 0; i < 4; i++) previous[i] + alpha * (s * next[i] - previous[i]),
  ]);
}

/// Where the rear camera points: altitude above the horizon and azimuth from (magnetic)
/// north through east, both in degrees. The rear camera looks along device -Z.
({double altitude, double azimuth}) cameraAltAzDeg(List<double> quaternion) {
  final r = quaternionToMatrix(quaternion);
  final east = -r[2], north = -r[5], up = -r[8];
  final altitude = math.asin(up.clamp(-1.0, 1.0)) * 180 / math.pi;
  final azimuth = (math.atan2(east, north) * 180 / math.pi) % 360;
  return (altitude: altitude, azimuth: azimuth);
}

double _norm(List<double> v) => math.sqrt(v.fold<double>(0, (a, x) => a + x * x));

List<double> _cross(List<double> a, List<double> b) => [
      a[1] * b[2] - a[2] * b[1],
      a[2] * b[0] - a[0] * b[2],
      a[0] * b[1] - a[1] * b[0],
    ];

List<double> _normalise(List<double> q) {
  final n = _norm(q);
  return [for (final v in q) v / n];
}

/// Horizontal (image-width) field of view in degrees from the lens focal length and the
/// physical sensor size (mm). Sensors are landscape; a portrait photo's width is the short side.
double fovFromOptics({
  required double focalLengthMm,
  required double sensorWidthMm,
  required double sensorHeightMm,
  required bool portrait,
}) {
  final side = portrait
      ? math.min(sensorWidthMm, sensorHeightMm)
      : math.max(sensorWidthMm, sensorHeightMm);
  return 2 * math.atan(side / (2 * focalLengthMm)) * 180 / math.pi;
}

/// Right ascension in degrees -> "05h 35m 17s".
String formatRa(double raDeg) {
  final totalSeconds = ((raDeg % 360) / 15 * 3600).round() % (24 * 3600);
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  return '${_two(h)}h ${_two(m)}m ${_two(s)}s';
}

/// Declination in degrees -> "-05° 23′ 28″".
String formatDec(double decDeg) {
  final sign = decDeg < 0 ? '-' : '+';
  final totalSeconds = (decDeg.abs() * 3600).round();
  final d = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  return '$sign${_two(d)}° ${_two(m)}′ ${_two(s)}″';
}

String _two(int v) => v.toString().padLeft(2, '0');
