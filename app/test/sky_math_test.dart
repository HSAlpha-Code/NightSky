import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:night_sky/models.dart';
import 'package:night_sky/photo_utils.dart';
import 'package:night_sky/sky_math.dart';

List<double> axisAngle(double ax, double ay, double az, double deg) {
  final h = deg * math.pi / 360;
  final n = math.sqrt(ax * ax + ay * ay + az * az);
  return [ax / n * math.sin(h), ay / n * math.sin(h), az / n * math.sin(h), math.cos(h)];
}

void main() {
  group('quaternion averaging', () {
    test('average of +/- small rotations is the middle', () {
      final avg = averageQuaternion([axisAngle(0, 0, 1, 10), axisAngle(0, 0, 1, -10)]);
      expect(quaternionAngleDeg(avg, [0, 0, 0, 1]), closeTo(0, 1e-9));
    });

    test('q and -q are treated as the same rotation', () {
      final q = axisAngle(1, 2, 3, 40);
      final avg = averageQuaternion([q, q.map((v) => -v).toList()]);
      expect(quaternionAngleDeg(avg, q), closeTo(0, 1e-6));
    });

    test('spread measures hand shake', () {
      final s = [axisAngle(1, 0, 0, 0), axisAngle(1, 0, 0, 2), axisAngle(1, 0, 0, 4)];
      expect(maxSpreadDeg(s), closeTo(2, 1e-6));
      expect(maxSpreadDeg([s.first]), 0);
    });
  });

  test('FOV from optics: 26mm-equivalent phone camera', () {
    // 4.25 mm lens on a 5.6 x 4.2 mm sensor -> ~66.8° wide (landscape), ~52.6° portrait width.
    final args = (focal: 4.25, w: 5.6, h: 4.2);
    expect(
        fovFromOptics(
            focalLengthMm: args.focal, sensorWidthMm: args.w, sensorHeightMm: args.h,
            portrait: false),
        closeTo(66.8, 0.1));
    expect(
        fovFromOptics(
            focalLengthMm: args.focal, sensorWidthMm: args.w, sensorHeightMm: args.h,
            portrait: true),
        closeTo(52.6, 0.1));
  });

  test('RA/Dec formatting', () {
    expect(formatRa(83.82), '05h 35m 17s');
    expect(formatRa(-15), '23h 00m 00s');
    expect(formatDec(-5.391), '-05° 23′ 28″');
    expect(formatDec(41.269), '+41° 16′ 08″');
  });

  group('photo preparation', () {
    Uint8List jpeg(int w, int h, {int orientation = 1}) {
      final image = img.Image(width: w, height: h);
      image.exif.imageIfd.orientation = orientation;
      return Uint8List.fromList(img.encodeJpg(image));
    }

    test('downscales the long side to 1600', () {
      final p = preparePhoto(jpeg(4000, 3000));
      expect((p.width, p.height), (1600, 1200));
      expect(img.decodeJpg(p.jpeg)!.width, 1600);
    });

    test('applies EXIF rotation so the photo is upright', () {
      // Sensor-landscape frame tagged "rotate 90" -> portrait photo.
      final p = preparePhoto(jpeg(2000, 1000, orientation: 6));
      expect((p.width, p.height), (800, 1600));
    });

    test('small photos are not upscaled', () {
      final p = preparePhoto(jpeg(800, 600));
      expect((p.width, p.height), (800, 600));
    });

    test('garbage bytes throw a FormatException', () {
      expect(() => preparePhoto(Uint8List.fromList([1, 2, 3])), throwsFormatException);
    });

    test('sky image size keeps the aspect ratio', () {
      expect(skyImageSize(1200, 1600), (900, 1200));
      expect(skyImageSize(600, 800), (600, 800));
    });
  });

  test('capture metadata JSON matches the backend contract', () {
    final m = CaptureMetadata(
      timestampUtc: DateTime.utc(2026, 10, 29, 22),
      latitude: 51.5,
      longitude: -0.1,
      altitude: 20,
      quaternion: [0.1, 0.2, 0.3, 0.9],
      fovDeg: 52.6,
    ).toJson();
    expect(m['timestamp'], '2026-10-29T22:00:00.000Z');
    expect(m['orientation'], {
      'quaternion': {'x': 0.1, 'y': 0.2, 'z': 0.3, 'w': 0.9},
      'reference': 'magnetic_north',
    });
    expect(m['image_rotation_deg'], 0);
    expect(m['fov_deg'], 52.6);

    final bare = CaptureMetadata(timestampUtc: DateTime.utc(2026)).toJson();
    expect(bare.containsKey('latitude'), isFalse);
    expect(bare.containsKey('orientation'), isFalse);
  });
}
