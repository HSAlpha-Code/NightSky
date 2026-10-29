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
