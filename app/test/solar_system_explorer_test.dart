import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sky/screens/sky_view_screen.dart';
import 'package:night_sky/screens/solar_system_screen.dart';
import 'package:night_sky/sky_view/astro_math.dart';
import 'package:night_sky/sky_view/ephemeris.dart';

class _RouteCapture extends NavigatorObserver {
  Route<dynamic>? latest;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    latest = route;
  }
}

void main() {
  test('geometric vectors agree with independent JPL Horizons ephemerides', () {
    // JPL Horizons vectors, AU, ecliptic J2000, Sun center (500@10).
    // Numeric targets 3, 4, 8 at JD 2451545 TDB, target 5 at JD 2464328.5.
    // UTC is an adequate proxy for TDB at these approximate-model tolerances.
    final epoch = DateTime.utc(2000, 1, 1, 12);
    final cases = [
      (epoch, 'EARTH', const Vec3(-0.177159, 0.967219, -0.000001), 0.0002),
      (epoch, 'SOL-MARS', const Vec3(1.390716, -0.013416, -0.034468), 0.001),
      (epoch, 'SOL-NEPTUNE', const Vec3(16.812047, -24.991763, 0.127223), 0.01),
      (
        DateTime.utc(2035),
        'SOL-JUPITER',
        const Vec3(4.741156, 1.428259, -0.112005),
        0.02,
      ),
    ];
    for (final (time, id, reference, tolerance) in cases) {
      final planet = heliocentricBodies(time).singleWhere((b) => b.id == id);
      expect(
        (planet.position - reference).length,
        lessThan(tolerance),
        reason: id,
      );
    }
  });

  testWidgets(
    'map uses a linear scale and opens selected planet at the chosen time',
    (tester) async {
      final observer = _RouteCapture();
      final time = DateTime.utc(2000, 1, 1, 12);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            navigatorObservers: [observer],
            home: SolarSystemScreen(initialUtc: time),
          ),
        ),
      );
      final map = tester.getRect(find.byType(AspectRatio));
      final pixelsPerAu = (map.width / 2 - 14) / 2;
      // Project the independent J2000 Mars vector above onto the screen.
      await tester.tapAt(map.center + Offset(1.390716, 0.013416) * pixelsPerAu);
      await tester.pump();
      await tester.tap(find.byTooltip('Next day'));
      await tester.pump();
      final target = find.text('Find Mars in Sky View');
      await tester.scrollUntilVisible(target, 180, maxScrolls: 8);
      await tester.tap(target);
      final page = observer.latest! as MaterialPageRoute<void>;
      final sky = page.builder(tester.element(target)) as SkyViewScreen;
      expect(sky.initialUtc, time.add(const Duration(days: 1)));
      expect(sky.initialBodyId, 'SOL-MARS');
    },
  );
}

