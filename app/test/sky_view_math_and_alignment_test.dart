import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:night_sky/sky_view/astro_math.dart';
import 'package:night_sky/sky_view/ephemeris.dart';
import 'package:night_sky/sky_view/sky_catalog.dart';

void main() {
  late SkyCatalog catalog;

  setUpAll(() {
    final starsBytes = File('assets/sky/stars.bin').readAsBytesSync();
    final catalogJson = File('assets/sky/sky_catalog.json').readAsStringSync();
    catalog = SkyCatalog.parse(
      starsBin: ByteData.sublistView(starsBytes),
      catalogJson: catalogJson,
    );
  });

  group('Astronomical coordinate transforms', () {
    test('exact North Celestial Pole altitude equals observer latitude at all times', () {
      for (final lat in [0.0, 19.07, 28.61, 51.51, 69.65, -33.87]) {
        for (var hour = 0; hour < 24; hour += 5) {
          final p = raDecToAltAz(
            raDeg: 0.0,
            decDeg: 90.0,
            latitudeDeg: lat,
            longitudeDeg: -0.12,
            when: DateTime.utc(2026, 11, 11, hour),
            applyPrecession: false,
          );
          expect(p.altitudeDeg, closeTo(lat, 1e-6), reason: 'lat=$lat hour=$hour');
        }
      }
    });

    test('Polaris (HIP 11767) from bundled catalog stays within <0.8° of latitude all night', () {
      final idx = catalog.indexOfHip(11767);
      expect(idx, greaterThanOrEqualTo(0));
      final polaris = catalog.starObjectAt(idx);
      expect(polaris.name, 'Polaris');

      for (final lat in [28.6139, 40.7128, 51.5074, 64.1466]) {
        for (var hour = 0; hour < 24; hour += 3) {
          final p = raDecToAltAz(
            raDeg: polaris.raDeg,
            decDeg: polaris.decDeg,
            latitudeDeg: lat,
            longitudeDeg: 15.0,
            when: DateTime.utc(2026, 11, 11, hour),
          );
          expect(p.altitudeDeg, closeTo(lat, 0.78), reason: 'Polaris alt at lat=$lat h=$hour');
          final northDiff = ((p.azimuthDeg + 180.0) % 360.0) - 180.0;
          expect(northDiff.abs(), lessThan(1.6), reason: 'Polaris az at lat=$lat h=$hour');
        }
      }
    });

    test('South Celestial Pole is at +latitude altitude due South in Southern Hemisphere', () {
      final sydney = raDecToAltAz(
        raDeg: 120.0,
        decDeg: -90.0,
        latitudeDeg: -33.8688,
        longitudeDeg: 151.2093,
        when: DateTime.utc(2026, 6, 21, 12),
        applyPrecession: false,
      );
      expect(sydney.altitudeDeg, closeTo(33.8688, 1e-6));
      expect(sydney.azimuthDeg, closeTo(180.0, 1e-4));
    });

    test('equatorial star transits zenith on Earth equator and rises due East / sets due West', () {
      final when = DateTime.utc(2026, 3, 20, 21, 0);
      final lst = lstDeg(when, 0.0);

      // On the meridian (RA = LST, Dec = 0) at lat = 0 -> straight overhead (Alt = +90°).
      final zenith = raDecToAltAz(
        raDeg: lst,
        decDeg: 0.0,
        latitudeDeg: 0.0,
        longitudeDeg: 0.0,
        when: when,
        applyPrecession: false,
      );
      expect(zenith.altitudeDeg, closeTo(90.0, 1e-6));

      // 6 hours East of meridian (RA = LST + 90°) -> rising due East (Alt = 0°, Az = 90°).
      final rising = raDecToAltAz(
        raDeg: (lst + 90.0) % 360.0,
        decDeg: 0.0,
        latitudeDeg: 35.0,
        longitudeDeg: 0.0,
        when: when,
        applyPrecession: false,
      );
      expect(rising.altitudeDeg, closeTo(0.0, 1e-6));
      expect(rising.azimuthDeg, closeTo(90.0, 1e-6));

      // 6 hours West of meridian (RA = LST - 90°) -> setting due West (Alt = 0°, Az = 270°).
      final setting = raDecToAltAz(
        raDeg: (lst - 90.0) % 360.0,
        decDeg: 0.0,
        latitudeDeg: 35.0,
        longitudeDeg: 0.0,
        when: when,
        applyPrecession: false,
      );
      expect(setting.altitudeDeg, closeTo(0.0, 1e-6));
      expect(setting.azimuthDeg, closeTo(270.0, 1e-6));
    });

    test('RA/Dec <-> Alt/Az round-trips accurately with precession', () {
      final when = DateTime.utc(2026, 11, 11, 22, 30);
      for (final (ra, dec) in [(83.822, -5.391), (279.235, 38.784), (10.685, 41.269), (310.358, 45.280)]) {
        final hor = raDecToAltAz(
          raDeg: ra,
          decDeg: dec,
          latitudeDeg: 28.6139,
          longitudeDeg: 77.2090,
          when: when,
        );
        final back = altAzToRaDec(
          altitudeDeg: hor.altitudeDeg,
          azimuthDeg: hor.azimuthDeg,
          latitudeDeg: 28.6139,
          longitudeDeg: 77.2090,
          when: when,
        );
        expect(back.raDeg, closeTo(ra, 1e-6));
        expect(back.decDeg, closeTo(dec, 1e-6));
      }
    });

    test('ICRS -> Galactic places Sgr A* at (0, 0) and NGP at b = +90°', () {
      final sgrA = icrsVecToGalactic(raDecToVec(266.4050, -28.9362));
      final lDiff = ((sgrA.lDeg + 180.0) % 360.0) - 180.0;
      expect(lDiff.abs(), lessThan(0.08));
      expect(sgrA.bDeg.abs(), lessThan(0.08));

      final ngp = icrsVecToGalactic(raDecToVec(192.85948, 27.12825));
      expect(ngp.bDeg, closeTo(90.0, 0.01));
    });

    test('offline WMM-2025 magnetic declination matches reference cities within 0.5°', () {
      final when = DateTime.utc(2026, 11, 11);
      final cases = [
        ('London', 51.5, -0.1, 1.23),
        ('New York', 40.7, -74.0, -12.46),
        ('San Francisco', 37.8, -122.4, 12.83),
        ('Tokyo', 35.7, 139.7, -7.94),
        ('Sydney', -33.9, 151.2, 12.84),
        ('Cape Town', -33.9, 18.4, -26.79),
      ];
      for (final (city, lat, lon, expected) in cases) {
        final d = magneticDeclinationDeg(latitudeDeg: lat, longitudeDeg: lon, when: when);
        expect(d, closeTo(expected, 0.5), reason: city);
      }
    });

    test('SkyCamera project/unproject round-trip and directional guide arrow', () {
      const size = Size(400, 800);
      final cam = SkyCamera.fromAltAz(
        altitudeDeg: 35.0,
        azimuthDeg: 180.0,
        latitudeDeg: 40.0,
        longitudeDeg: -74.0,
        when: DateTime.utc(2026, 11, 11, 2, 0),
        fovDeg: 60.0,
      );
      const samplePt = Offset(260, 310);
      final ray = cam.unprojectToIcrs(samplePt, size);
      final reprojected = cam.projectIcrs(ray, size)!;
      expect(reprojected.dx, closeTo(samplePt.dx, 1e-5));
      expect(reprojected.dy, closeTo(samplePt.dy, 1e-5));

      // Facing South (az 180°): an object due East (az 90°, to the left when facing South!)
      // should yield a negative screen dx (turn left).
      final eastIcrs = cam.enuToIcrs.transform(altAzToEnu(35.0, 90.0));
      final guide = cam.guideTowards(eastIcrs, size);
      expect(guide.screenDir.dx, lessThan(-0.8));
      expect(guide.onScreen, isNull);
    });
  });

  group('Mellinger Milky Way panorama <-> catalog alignment', () {
    test('bundled stars and Andromeda align with bright features in mellinger_galactic.webp', () async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final rawWebp = await File('assets/sky/mellinger_galactic.webp').readAsBytes();
      final decoded = img.decodeWebP(rawWebp);
      expect(decoded, isNotNull);
      final pano = decoded!;
      expect((pano.width, pano.height), (3600, 1800));

      double lumAt(int x, int y) {
        final px = pano.getPixel(x.clamp(0, pano.width - 1), y.clamp(0, pano.height - 1));
        return (px.r + px.g + px.b) / 3.0;
      }

      // Check 5 bright isolated stars across all quadrants + M31 Andromeda Galaxy from the
      // actual shipped catalog against the actual shipped Mellinger panorama pixels.
      final targets = <SkyObject>[
        catalog.starObjectAt(catalog.indexOfHip(32349)), // Sirius
        catalog.starObjectAt(catalog.indexOfHip(91262)), // Vega
        catalog.starObjectAt(catalog.indexOfHip(69673)), // Arcturus
        catalog.starObjectAt(catalog.indexOfHip(113368)), // Fomalhaut
        catalog.starObjectAt(catalog.indexOfHip(7588)), // Achernar
        catalog.deepSkyObjects.firstWhere((d) => d.id == 'NGC0224'), // Andromeda Galaxy
      ];

      for (final obj in targets) {
        final uv = icrsVecToPanoramaUv(obj.icrs);
        final cx = (uv.u * pano.width - 0.5).round();
        final cy = (uv.v * pano.height - 0.5).round();

        var bestLum = -1.0;
        var bestDx = 0, bestDy = 0;
        final samples = <double>[];
        for (var dy = -6; dy <= 6; dy++) {
          for (var dx = -6; dx <= 6; dx++) {
            final l = lumAt((cx + dx) % pano.width, cy + dy);
            samples.add(l);
            if (l > bestLum) {
              bestLum = l;
              bestDx = dx;
              bestDy = dy;
            }
          }
        }
        samples.sort();
        final medianBg = samples[samples.length ~/ 2];
        final offsetDeg = math.sqrt(bestDx * bestDx + bestDy * bestDy) * (360.0 / pano.width);

        expect(offsetDeg, lessThanOrEqualTo(0.25),
            reason: '${obj.name} peak offset ${offsetDeg.toStringAsFixed(2)}°');
        expect(bestLum, greaterThan(medianBg + 70.0),
            reason: '${obj.name} should sit on a bright star/galaxy core in Mellinger');
      }

      // Verify global orientation (no N/S or E/W flip): Galactic Centre and Large Magellanic
      // Cloud are much brighter than the North Galactic Pole.
      double patchMean(double lDeg, double bDeg) {
        final normL = lDeg > 180.0 ? lDeg - 360.0 : lDeg;
        final u = (0.5 - normL / 360.0) % 1.0;
        final v = 0.5 - bDeg / 180.0;
        final cx = (u * pano.width).round();
        final cy = (v * pano.height).round();
        var sum = 0.0;
        var n = 0;
        for (var dy = -8; dy <= 8; dy++) {
          for (var dx = -8; dx <= 8; dx++) {
            sum += lumAt((cx + dx) % pano.width, cy + dy);
            n++;
          }
        }
        return sum / n;
      }

      final gcMean = patchMean(0.0, 0.0);
      final lmcMean = patchMean(280.47, -32.89);
      final lmcMirrored = patchMean(280.47, 32.89);
      final ngpMean = patchMean(0.0, 88.0);

      expect(gcMean, greaterThan(ngpMean * 5.0));
      expect(lmcMean, greaterThan(lmcMirrored * 1.8));
      expect(catalog.constellations.length, 88);
      expect(catalog.starCount, greaterThan(8000));
    });
  });

  group('Offline Solar System ephemeris', () {
    test('Sun is at RA ~0°, Dec ~0° at March equinox and RA ~90°, Dec ~+23.4° at June solstice', () {
      final equinox = computeSolarSystem(
        when: DateTime.utc(2026, 3, 20, 14, 46),
        latitudeDeg: 0,
        longitudeDeg: 0,
      );
      final eqRaDiff = ((equinox.sun.raDeg + 180.0) % 360.0) - 180.0;
      expect(eqRaDiff.abs(), lessThan(0.5));
      expect(equinox.sun.decDeg.abs(), lessThan(0.3));

      final solstice = computeSolarSystem(
        when: DateTime.utc(2026, 6, 21, 8, 24),
        latitudeDeg: 0,
        longitudeDeg: 0,
      );
      expect(solstice.sun.raDeg, closeTo(90.0, 0.5));
      expect(solstice.sun.decDeg, closeTo(23.44, 0.2));
    });

    test('Mercury and Venus remain within physical maximum solar elongation, and Moon phases match', () {
      // Sample across a full year (every 15 days) to verify inner planet elongations and Moon illumination.
      var sawFullMoon = false;
      var sawNewMoon = false;
      for (var day = 0; day < 365; day += 3) {
        final sys = computeSolarSystem(
          when: DateTime.utc(2026, 1, 1).add(Duration(days: day)),
          latitudeDeg: 28.6,
          longitudeDeg: 77.2,
        );
        final mercury = sys.planets.firstWhere((p) => p.id == 'SOL-MERCURY');
        final venus = sys.planets.firstWhere((p) => p.id == 'SOL-VENUS');
        expect(angularSeparationDeg(mercury.icrs, sys.sun.icrs), lessThan(29.0));
        expect(angularSeparationDeg(venus.icrs, sys.sun.icrs), lessThan(48.5));

        final illum = sys.moon.phaseFraction!;
        if (illum > 0.96) sawFullMoon = true;
        if (illum < 0.04) sawNewMoon = true;
      }
      expect(sawFullMoon, isTrue);
      expect(sawNewMoon, isTrue);
    });
  });
}
