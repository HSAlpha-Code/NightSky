import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:night_sky/sensors.dart';
import 'package:night_sky/sky_math.dart';

// Synthetic sensor readings for a phone in portrait whose rear camera points at (alt, az).
// World frame: East, North, Up. Earth's field (uT) points north and down (N. hemisphere).
const _field = [0.0, 22.0, -40.0];

List<double> _enu(double altDeg, double azDeg) {
  final a = altDeg * math.pi / 180, z = azDeg * math.pi / 180;
  return [math.cos(a) * math.sin(z), math.cos(a) * math.cos(z), math.sin(a)];
}

List<double> _cross(List<double> a, List<double> b) =>
    [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];

List<double> _unit(List<double> v) {
  final n = math.sqrt(v.fold<double>(0, (s, x) => s + x * x));
  return [for (final x in v) x / n];
}

/// Device -> world matrix (row-major): camera at (alt, az), top of the phone towards the
/// zenith (at the zenith itself: towards [topAzDeg]).
List<double> phone(double altDeg, double azDeg, {double topAzDeg = 0}) {
  final view = _enu(altDeg, azDeg);
  final upHint = altDeg.abs() > 89.9 ? _enu(0, topAzDeg) : [0.0, 0.0, 1.0];
  final dot = view[0] * upHint[0] + view[1] * upHint[1] + view[2] * upHint[2];
  final y = _unit([for (var i = 0; i < 3; i++) upHint[i] - dot * view[i]]);
  final z = [for (final v in view) -v];
  final x = _cross(y, z);
  return [x[0], y[0], z[0], x[1], y[1], z[1], x[2], y[2], z[2]];
}

/// World vector -> device frame (transpose of R).
List<double> _toDevice(List<double> r, List<double> w) => [
      r[0] * w[0] + r[3] * w[1] + r[6] * w[2],
      r[1] * w[0] + r[4] * w[1] + r[7] * w[2],
      r[2] * w[0] + r[5] * w[1] + r[8] * w[2],
    ];

/// What the accelerometer and the magnetometer read in that pose.
(List<double>, List<double>) readings(List<double> r) =>
    (_toDevice(r, [0, 0, 9.81]), _toDevice(r, _field));

double _altFromSensors(List<double> r) {
  final (g, m) = readings(r);
  return cameraAltAzDeg(matrixToQuaternion(rotationFromGravityAndMagnetic(g, m)!)).altitude;
}

void main() {
  group('accelerometer + compass orientation (no gyroscope)', () {
    test('recovers where the camera points', () {
      for (final (alt, az) in [(10.0, 0.0), (45.0, 120.0), (-20.0, 250.0), (75.0, 300.0)]) {
        final (g, m) = readings(phone(alt, az));
        final p = cameraAltAzDeg(matrixToQuaternion(rotationFromGravityAndMagnetic(g, m)!));
        expect(p.altitude, closeTo(alt, 1e-6), reason: 'alt $alt az $az');
        expect((p.azimuth - az + 540) % 360 - 180, closeTo(0, 1e-6), reason: 'az $az');
      }
    });

    test('tilting up to and past the zenith never reports "below the horizon"', () {
      // The reported bug: pointing up past a threshold flipped the reading. Here "up" comes
      // from gravity alone, so the altitude follows the tilt all the way.
      for (var alt = 0.0; alt <= 89.0; alt += 1) {
        expect(_altFromSensors(phone(alt, 30)), closeTo(alt, 1e-6));
      }
      for (final topAz in [0.0, 90.0, 200.0]) {
        expect(_altFromSensors(phone(90, 0, topAzDeg: topAz)), closeTo(90, 1e-4));
      }
      for (var alt = 89.0; alt >= 30; alt -= 1) {
        expect(_altFromSensors(phone(alt, 210)), closeTo(alt, 1e-6)); // leaned back past it
      }
    });

    test('free fall and a field parallel to gravity give no orientation', () {
      expect(rotationFromGravityAndMagnetic([0, 0, 0.1], [0, 20, -40]), isNull);
      expect(rotationFromGravityAndMagnetic([0, 0, 9.81], [0, 0, -40]), isNull);
    });
  });

  group('quaternion helpers', () {
    test('matrix <-> quaternion round trip, including the w ~ 0 branches', () {
      for (final r in [phone(10, 20), phone(-80, 200), phone(90, 0, topAzDeg: 180)]) {
        final back = quaternionToMatrix(matrixToQuaternion(r));
        for (var i = 0; i < 9; i++) {
          expect(back[i], closeTo(r[i], 1e-9));
        }
      }
    });

    test('rotation vector without w is completed', () {
      final q = quaternionFromRotationVector([0.6, 0, 0, double.nan]);
      expect(q, [closeTo(0.6, 1e-12), 0, 0, closeTo(0.8, 1e-12)]);
    });

    test('smoothing moves part of the way and takes the short path', () {
      const a = [0.0, 0.0, 0.0, 1.0];
      final b = matrixToQuaternion(phone(0, 0)); // a quarter turn from identity
      final half = smoothQuaternion(a, b, 0.5);
      expect(quaternionAngleDeg(half, a), inExclusiveRange(30, 60));
      final viaNegative = smoothQuaternion(a, [for (final v in b) -v], 0.5);
      expect(quaternionAngleDeg(viaNegative, half), closeTo(0, 1e-6)); // -b == b
      expect(smoothQuaternion(a, b, 1), b);
      expect(lowPass([0, 0], [10, 20], 0.25), [2.5, 5]);
    });
  });

  group('OrientationEngine', () {
    Duration ms(int v) => Duration(milliseconds: v);

    test('compass mode: averaged pose and shake from raw readings', () {
      final e = OrientationEngine(alpha: 1);
      final (g, m) = readings(phone(40, 90));
      for (var i = 0; i < 20; i++) {
        e.addAccelerometer(g, ms(i * 20));
        e.addMagnetometer(m, ms(i * 20 + 1));
      }
      expect(e.hasData, isTrue);
      expect(cameraAltAzDeg(e.averaged()!).altitude, closeTo(40, 1e-6));
      expect(e.shake(), closeTo(0, 1e-4)); // acos near 1 amplifies rounding a little
    });

    test('smoothing filters jitter; shake reflects movement', () {
      double spread(double alpha) {
        final e = OrientationEngine(alpha: alpha);
        final (_, m) = readings(phone(40, 90));
        for (var i = 0; i < 40; i++) {
          final (g, _) = readings(phone(40 + (i.isEven ? 3 : -3), 90)); // +/-3 deg jitter
          e.addMagnetometer(m, ms(i * 20));
          e.addAccelerometer(g, ms(i * 20 + 1));
        }
        return e.shake();
      }

      expect(spread(1), greaterThan(2.5));
      expect(spread(0.1), lessThan(spread(1) / 3));
    });

    test('only the last 0.6 s count', () {
      final e = OrientationEngine(alpha: 1);
      final (g1, m1) = readings(phone(10, 0));
      e.addAccelerometer(g1, ms(0));
      e.addMagnetometer(m1, ms(1));
      final (g2, m2) = readings(phone(50, 0));
      e.addAccelerometer(g2, ms(1000));
      e.addMagnetometer(m2, ms(1001));
      expect(cameraAltAzDeg(e.averaged()!).altitude, closeTo(50, 1e-6));
    });

    test('gyro mode uses the rotation vector', () {
      final e = OrientationEngine(mode: SensorMode.gyro, alpha: 1);
      e.addRotationVector(matrixToQuaternion(phone(60, 10)), ms(0));
      expect(cameraAltAzDeg(e.current!).altitude, closeTo(60, 1e-6));
    });
  });

  test('sensor availability per mode', () {
    const compassOnly = SensorAvailability(accelerometer: true, magnetometer: true);
    expect(compassOnly.supports(SensorMode.compass), isTrue);
    expect(compassOnly.supports(SensorMode.gyro), isFalse);
    const all = SensorAvailability(
        accelerometer: true, magnetometer: true, gyroscope: true, rotationVector: true);
    expect(all.supports(SensorMode.gyro), isTrue);
  });
}
