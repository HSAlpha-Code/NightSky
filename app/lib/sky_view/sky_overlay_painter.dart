import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../settings.dart';
import 'astro_math.dart';
import 'ephemeris.dart';
import 'sky_catalog.dart';

/// User-toggleable visibility layers in Sky View.
@immutable
class SkyLayerVisibility {
  const SkyLayerVisibility({
    this.milkyWay = true,
    this.stars = true,
    this.constellations = true,
    this.solarSystem = true,
    this.deepSky = true,
    this.labels = true,
    this.horizon = true,
  });

  final bool milkyWay;
  final bool stars;
  final bool constellations;
  final bool solarSystem;
  final bool deepSky;
  final bool labels;
  final bool horizon;

  SkyLayerVisibility copyWith({
    bool? milkyWay,
    bool? stars,
    bool? constellations,
    bool? solarSystem,
    bool? deepSky,
    bool? labels,
    bool? horizon,
  }) =>
      SkyLayerVisibility(
        milkyWay: milkyWay ?? this.milkyWay,
        stars: stars ?? this.stars,
        constellations: constellations ?? this.constellations,
        solarSystem: solarSystem ?? this.solarSystem,
        deepSky: deepSky ?? this.deepSky,
        labels: labels ?? this.labels,
        horizon: horizon ?? this.horizon,
      );
}

class _LabelCandidate {
  const _LabelCandidate({
    required this.text,
    required this.anchor,
    required this.offsetY,
    required this.color,
    required this.fontSize,
    required this.priority,
    this.italic = false,
    this.bold = false,
  });

  final String text;
  final Offset anchor;
  final double offsetY;
  final Color color;
  final double fontSize;
  final int priority;
  final bool italic;
  final bool bold;
}

/// Renders constellations, spectral stars, deep-sky objects, Sun, Moon (with illuminated phase),
/// planets, non-overlapping labels, and the directional "Find object" guide onto the sky sphere.
class SkySceneRenderer {
  const SkySceneRenderer({
    required this.camera,
    required this.quality,
    required this.layers,
    required this.nightVision,
    this.catalog,
    this.solarSystem,
    this.curatedIds = const {},
    this.selectedObject,
    this.guideTarget,
  });

  final SkyCamera camera;
  final SkyQuality quality;
  final SkyLayerVisibility layers;
  final bool nightVision;
  final SkyCatalog? catalog;
  final SolarSystemSnapshot? solarSystem;
  final Set<String> curatedIds;
  final SkyObject? selectedObject;
  final SkyObject? guideTarget;

  Color _tint(Color c) {
    if (!nightVision) return c;
    final lum = (0.299 * c.r + 0.587 * c.g + 0.114 * c.b).clamp(0.0, 1.0);
    return Color.fromARGB(
      (c.a * 255).round(),
      (lum * 255).round().clamp(40, 255),
      (lum * 36).round(),
      (lum * 24).round(),
    );
  }

  /// Effective limiting magnitude adjusted for zoom FOV so pinching in reveals fainter stars.
  double get effectiveLimitingMag {
    final zoomBonus = ((60.0 - camera.fovDeg) / 35.0).clamp(-0.4, 0.7);
    return (quality.limitingMagnitude + zoomBonus).clamp(4.2, 6.5);
  }

  /// Constellation closest to the screen centre (within 24°), highlighted gently as the user
  /// sweeps across the sky ("Constellation Spotlight").
  ConstellationEntry? spotlitConstellation() {
    final cat = catalog;
    if (cat == null) return null;
    ConstellationEntry? best;
    var bestCos = math.cos(24.0 * degToRad);
    for (final c in cat.constellations) {
      final d = c.centerIcrs.dot(camera.forwardIcrs);
      if (d > bestCos) {
        bestCos = d;
        best = c;
      }
    }
    return best;
  }

  void paint(Canvas canvas, Size size) {
    final labels = <_LabelCandidate>[];
    final cat = catalog;
    final spotlit = spotlitConstellation();

    if (cat != null && layers.constellations) {
      _paintConstellations(canvas, size, cat, spotlit, labels);
    }
    if (cat != null && layers.deepSky) {
      _paintDeepSky(canvas, size, cat, labels);
    }
    if (cat != null && layers.stars) {
      _paintStars(canvas, size, cat, labels);
    }
    if (solarSystem != null && layers.solarSystem) {
      _paintSolarSystem(canvas, size, solarSystem!, labels);
    }
    if (selectedObject != null) {
      _paintSelectionRing(canvas, size, selectedObject!);
    }
    if (layers.labels && labels.isNotEmpty) {
      _paintLabels(canvas, size, labels);
    }
    if (guideTarget != null) {
      _paintGuideHud(canvas, size, guideTarget!);
    }
  }

  void _paintConstellations(
    Canvas canvas,
    Size size,
    SkyCatalog cat,
    ConstellationEntry? spotlit,
    List<_LabelCandidate> labels,
  ) {
    final basePath = Path();
    final highlightPath = Path();
    final margin = size.width * 0.4;

    for (final con in cat.constellations) {
      final isSpot = identical(con, spotlit);
      final targetPath = isSpot ? highlightPath : basePath;
      for (final poly in con.polylines) {
        Offset? prev;
        for (final v in poly) {
          final pt = camera.projectIcrs(v, size);
          if (pt != null &&
              pt.dx >= -margin &&
              pt.dx <= size.width + margin &&
              pt.dy >= -margin &&
              pt.dy <= size.height + margin) {
            if (prev != null && (pt - prev).distance < size.width * 0.75) {
              targetPath.moveTo(prev.dx, prev.dy);
              targetPath.lineTo(pt.dx, pt.dy);
            }
            prev = pt;
          } else {
            prev = null;
          }
        }
      }

      final centerPt = camera.projectIcrs(con.centerIcrs, size);
      if (centerPt != null && _inScreen(centerPt, size, 24)) {
        if (isSpot || con.rank == 1 || camera.fovDeg <= 55) {
          labels.add(
            _LabelCandidate(
              text: con.name.toUpperCase(),
              anchor: centerPt,
              offsetY: 0,
              color: _tint(isSpot ? const Color(0xCC9CC8FF) : const Color(0x807CA4D8)),
              fontSize: isSpot ? 11.5 : 9.8,
              priority: isSpot ? 18 : 60,
              bold: isSpot,
            ),
          );
        }
      }
    }

    canvas.drawPath(
      basePath,
      Paint()
        ..color = _tint(const Color(0x3D6BA4FF))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    canvas.drawPath(
      highlightPath,
      Paint()
        ..color = _tint(const Color(0x998FC4FF))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  void _paintStars(Canvas canvas, Size size, SkyCatalog cat, List<_LabelCandidate> labels) {
    final limitMag = effectiveLimitingMag;
    final minCos = math.cos((camera.fovDeg * 0.85).clamp(20.0, 88.0) * degToRad);
    final fwd = camera.forwardIcrs;
    final right = camera.rightIcrs;
    final up = camera.upIcrs;
    final halfW = size.width * 0.5;
    final halfH = size.height * 0.5;
    final invTan = 1.0 / camera.tanHalfFov;
    final allowGlow = quality != SkyQuality.powerSaver;

    final starPaint = Paint()..style = PaintingStyle.fill;
    final glowPaint = Paint()..style = PaintingStyle.fill;

    final n = cat.starCount;
    for (var i = 0; i < n; i++) {
      final mag = cat.starMag[i];
      if (mag > limitMag) break; // sorted brightest-first!

      final vx = cat.starIx[i], vy = cat.starIy[i], vz = cat.starIz[i];
      final z = vx * fwd.x + vy * fwd.y + vz * fwd.z;
      if (z <= minCos && z <= 0.1) continue;
      if (z <= 0.05) continue;

      final scale = invTan / z;
      final sx = halfW + halfW * (vx * right.x + vy * right.y + vz * right.z) * scale;
      if (sx < -12 || sx > size.width + 12) continue;
      final sy = halfH - halfW * (vx * up.x + vy * up.y + vz * up.z) * scale;
      if (sy < -12 || sy > size.height + 12) continue;

      final pt = Offset(sx, sy);
      final baseColor = _tint(Color(cat.starColorArgb[i]));
      final radius = _starRadius(mag);
      final alpha = ((limitMag + 0.6 - mag) / 2.2).clamp(0.28, 1.0);

      if (allowGlow && mag < 1.8) {
        final glowR = radius * (mag < 0.3 ? 3.6 : 2.6);
        glowPaint.color = baseColor.withValues(alpha: mag < 0.3 ? 0.24 : 0.14);
        canvas.drawCircle(pt, glowR, glowPaint);
      }

      starPaint.color = baseColor.withValues(alpha: alpha);
      canvas.drawCircle(pt, radius, starPaint);

      final hip = cat.starHip[i];
      final labelLimit = camera.fovDeg > 65 ? 2.1 : (camera.fovDeg > 40 ? 2.8 : 3.6);
      if (mag <= labelLimit || curatedIds.contains('HIP$hip')) {
        final meta = cat.namedStarsByHip[hip];
        if (meta != null && meta.name.isNotEmpty) {
          labels.add(
            _LabelCandidate(
              text: meta.name,
              anchor: pt,
              offsetY: radius + 4,
              color: _tint(const Color(0xDCEAF2FF)),
              fontSize: mag < 1.2 ? 12.0 : 10.8,
              priority: mag < 1.0 ? 22 : 35,
            ),
          );
        }
      }
    }
  }

  double _starRadius(double mag) {
    if (mag < -0.5) return 4.2;
    if (mag < 0.5) return 3.3;
    if (mag < 1.5) return 2.6;
    if (mag < 2.5) return 2.0;
    if (mag < 3.5) return 1.5;
    if (mag < 4.8) return 1.15;
    return 0.85;
  }

  void _paintDeepSky(Canvas canvas, Size size, SkyCatalog cat, List<_LabelCandidate> labels) {
    final dsoMagLimit = camera.fovDeg > 65 ? 6.2 : (camera.fovDeg > 38 ? 7.8 : 9.5);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25;

    for (final dso in cat.deepSkyObjects) {
      final hasCurated = curatedIds.contains(dso.id);
      final mag = dso.magnitude ?? 9.0;
      if (!hasCurated && mag > dsoMagLimit) continue;

      final pt = camera.projectIcrs(dso.icrs, size);
      if (pt == null || !_inScreen(pt, size, 16)) continue;

      if (hasCurated) {
        // Signature NightSky gold circle for bodies with Curated Cosmic Highlights.
        stroke
          ..color = _tint(Colors.amber)
          ..strokeWidth = 1.6;
        canvas.drawCircle(pt, 7.5, stroke);
      } else {
        stroke
          ..color = _tint(const Color(0x9980D8FF))
          ..strokeWidth = 1.1;
        final r = 5.0;
        final path = Path()
          ..moveTo(pt.dx, pt.dy - r)
          ..lineTo(pt.dx + r, pt.dy)
          ..lineTo(pt.dx, pt.dy + r)
          ..lineTo(pt.dx - r, pt.dy)
          ..close();
        canvas.drawPath(path, stroke);
      }

      if (hasCurated || mag <= (camera.fovDeg > 55 ? 5.2 : 6.8)) {
        labels.add(
          _LabelCandidate(
            text: dso.name,
            anchor: pt,
            offsetY: hasCurated ? 10 : 8,
            color: _tint(hasCurated ? const Color(0xFFFFD54F) : const Color(0xCC9AD8FF)),
            fontSize: 10.5,
            priority: hasCurated ? 14 : 45,
            italic: true,
          ),
        );
      }
    }
  }

  void _paintSolarSystem(
    Canvas canvas,
    Size size,
    SolarSystemSnapshot sys,
    List<_LabelCandidate> labels,
  ) {
    final sunScreen = camera.projectIcrs(sys.sun.icrs, size);

    // Sun
    if (sunScreen != null && _inScreen(sunScreen, size, 40)) {
      final sunCol = _tint(const Color(0xFFFFDF7A));
      canvas.drawCircle(
        sunScreen,
        22,
        Paint()
          ..shader = ui.Gradient.radial(
            sunScreen,
            22,
            [sunCol.withValues(alpha: 0.45), sunCol.withValues(alpha: 0.0)],
          ),
      );
      canvas.drawCircle(sunScreen, 8.5, Paint()..color = sunCol);
      labels.add(
        _LabelCandidate(
          text: 'Sun',
          anchor: sunScreen,
          offsetY: 12,
          color: sunCol,
          fontSize: 12.5,
          priority: 5,
          bold: true,
        ),
      );
    }

    // Moon with accurate illuminated phase limb rotated towards the Sun!
    final moonPt = camera.projectIcrs(sys.moon.icrs, size);
    if (moonPt != null && _inScreen(moonPt, size, 32)) {
      _paintMoonPhaseDisc(canvas, size, moonPt, sys);
      labels.add(
        _LabelCandidate(
          text: 'Moon',
          anchor: moonPt,
          offsetY: 12,
          color: _tint(const Color(0xFFF5F2E6)),
          fontSize: 12.5,
          priority: 6,
          bold: true,
        ),
      );
    }

    // Planets
    for (final p in sys.planets) {
      final isIceGiant = p.id == 'SOL-URANUS' || p.id == 'SOL-NEPTUNE';
      if (isIceGiant && camera.fovDeg > 42 && selectedObject?.id != p.id && guideTarget?.id != p.id) {
        continue; // Uranus & Neptune appear when zoomed in or searched, avoiding clutter.
      }
      final pt = camera.projectIcrs(p.icrs, size);
      if (pt == null || !_inScreen(pt, size, 20)) continue;

      final col = _tint(p.color);
      final mag = p.magnitude ?? 2.0;
      final r = (4.6 - mag * 0.45).clamp(2.6, 5.8);

      canvas.drawCircle(pt, r * 2.3, Paint()..color = col.withValues(alpha: 0.20));
      canvas.drawCircle(pt, r, Paint()..color = col);

      if (p.id == 'SOL-SATURN') {
        canvas.save();
        canvas.translate(pt.dx, pt.dy);
        canvas.rotate(-0.35);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: r * 3.4, height: r * 1.1),
          Paint()
            ..color = col.withValues(alpha: 0.85)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
        canvas.restore();
      }

      labels.add(
        _LabelCandidate(
          text: p.name,
          anchor: pt,
          offsetY: r + 5,
          color: col,
          fontSize: 11.8,
          priority: 10,
          bold: true,
        ),
      );
    }
  }

  void _paintMoonPhaseDisc(
    Canvas canvas,
    Size size,
    Offset center,
    SolarSystemSnapshot sys,
  ) {
    const r = 8.5;
    final lit = _tint(const Color(0xFFF5F2E6));
    final dark = _tint(const Color(0xFF232834));
    final illum = (sys.moon.phaseFraction ?? 0.5).clamp(0.0, 1.0);

    // Compute screen-space direction from Moon towards the Sun so the bright limb faces the Sun!
    final sunGuide = camera.guideTowards(sys.sun.icrs, size);
    final angleToSun = math.atan2(sunGuide.screenDir.dy, sunGuide.screenDir.dx);

    canvas.drawCircle(center, r * 2.0, Paint()..color = lit.withValues(alpha: 0.18));
    canvas.drawCircle(center, r, Paint()..color = dark);

    if (illum > 0.02) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angleToSun);
      // Right (+X) half is the Sun-facing hemisphere; terminator ellipse has semi-axis |2*illum - 1|*r.
      final path = Path()
        ..addArc(Rect.fromCircle(center: Offset.zero, radius: r), -math.pi / 2, math.pi);
      final k = (2.0 * illum - 1.0) * r;
      path.arcTo(
        Rect.fromCenter(center: Offset.zero, width: (k.abs() * 2).clamp(0.2, r * 2), height: r * 2),
        math.pi / 2,
        k >= 0 ? math.pi : -math.pi,
        false,
      );
      path.close();
      canvas.drawPath(path, Paint()..color = lit);
      canvas.restore();
    }
  }

  void _paintSelectionRing(Canvas canvas, Size size, SkyObject obj) {
    final pt = camera.projectIcrs(obj.icrs, size);
    if (pt == null || !_inScreen(pt, size, 30)) return;
    final paint = Paint()
      ..color = _tint(Colors.white)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawCircle(pt, 14, paint);
  }

  void _paintLabels(Canvas canvas, Size size, List<_LabelCandidate> candidates) {
    candidates.sort((a, b) => a.priority.compareTo(b.priority));
    final occupied = <Rect>[];
    var drawn = 0;

    for (final c in candidates) {
      if (drawn >= quality.maxLabels) break;
      final tp = TextPainter(
        text: TextSpan(
          text: c.text,
          style: TextStyle(
            color: c.color,
            fontSize: c.fontSize,
            fontWeight: c.bold ? FontWeight.w600 : FontWeight.w400,
            fontStyle: c.italic ? FontStyle.italic : FontStyle.normal,
            letterSpacing: c.italic ? 0.2 : 0.4,
            shadows: const [Shadow(blurRadius: 3.5, color: Colors.black)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final topLeft = Offset(c.anchor.dx - tp.width * 0.5, c.anchor.dy + c.offsetY);
      final box = (topLeft & tp.size).inflate(4);
      // Keep clear of top/bottom HUD strips and already-placed labels.
      if (box.left < 6 || box.right > size.width - 6 || box.top < 54 || box.bottom > size.height - 96) {
        continue;
      }
      if (occupied.any((r) => r.overlaps(box))) continue;

      occupied.add(box);
      tp.paint(canvas, topLeft);
      drawn++;
    }
  }

  void _paintGuideHud(Canvas canvas, Size size, SkyObject target) {
    final center = Offset(size.width * 0.5, size.height * 0.5);
    final g = camera.guideTowards(target.icrs, size);
    final accent = _tint(const Color(0xFF69F0AE));

    if (g.onScreen != null) {
      final pt = g.onScreen!;
      final locked = g.angleDeg <= 4.5;
      final ringPaint = Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = locked ? 2.4 : 1.8;
      canvas.drawCircle(pt, locked ? 19 : 16, ringPaint);

      if (!locked) {
        canvas.drawLine(
          center + g.screenDir * 14,
          pt - g.screenDir * 18,
          Paint()
            ..color = accent.withValues(alpha: 0.65)
            ..strokeWidth = 1.4,
        );
      }
      return;
    }

    // Off-screen: clamp guide indicator onto a rounded perimeter margin and draw a chevron arrow.
    final marginX = size.width * 0.5 - 36.0;
    final marginY = size.height * 0.5 - 118.0;
    final dx = g.screenDir.dx, dy = g.screenDir.dy;
    final tx = dx.abs() < 1e-5 ? 1e9 : marginX / dx.abs();
    final ty = dy.abs() < 1e-5 ? 1e9 : marginY / dy.abs();
    final t = math.min(tx, ty).clamp(24.0, 500.0);
    final edgePt = center + g.screenDir * t;

    final angle = math.atan2(dy, dx);
    canvas.save();
    canvas.translate(edgePt.dx, edgePt.dy);
    canvas.rotate(angle);
    final arrow = Path()
      ..moveTo(12, 0)
      ..lineTo(-8, -9)
      ..lineTo(-4, 0)
      ..lineTo(-8, 9)
      ..close();
    canvas.drawPath(arrow, Paint()..color = accent);
    canvas.restore();
  }

  /// Hit-test a user tap [tapPoint] in [size], returning the closest visible [SkyObject] within
  /// finger tolerance (34 px), weighted slightly towards bright/prominent objects.
  SkyObject? hitTest(Offset tapPoint, Size size) {
    const maxRadiusPx = 34.0;
    SkyObject? best;
    var bestScore = double.infinity;

    void consider(SkyObject obj, {double bonusPx = 0.0}) {
      final pt = camera.projectIcrs(obj.icrs, size);
      if (pt == null) return;
      final d = (pt - tapPoint).distance;
      if (d > maxRadiusPx) return;
      final score = d - bonusPx;
      if (score < bestScore) {
        bestScore = score;
        best = obj;
      }
    }

    if (solarSystem != null && layers.solarSystem) {
      consider(solarSystem!.sun, bonusPx: 8);
      consider(solarSystem!.moon, bonusPx: 8);
      for (final p in solarSystem!.planets) {
        consider(p, bonusPx: 6);
      }
    }

    final cat = catalog;
    if (cat != null && layers.deepSky) {
      final dsoLimit = camera.fovDeg > 65 ? 6.5 : 9.5;
      for (final dso in cat.deepSkyObjects) {
        final hasCurated = curatedIds.contains(dso.id);
        if (!hasCurated && (dso.magnitude ?? 9.0) > dsoLimit) continue;
        consider(dso, bonusPx: hasCurated ? 7 : 3);
      }
    }

    if (cat != null && layers.stars) {
      final limit = math.min(effectiveLimitingMag, 5.2);
      for (var i = 0; i < cat.starCount; i++) {
        final mag = cat.starMag[i];
        if (mag > limit) break;
        final pt = camera.projectIcrs(Vec3(cat.starIx[i], cat.starIy[i], cat.starIz[i]), size);
        if (pt == null) continue;
        final d = (pt - tapPoint).distance;
        if (d > maxRadiusPx) continue;
        final namedBonus = cat.namedStarsByHip.containsKey(cat.starHip[i]) ? 4.0 : 0.0;
        final score = d - namedBonus + mag * 1.2;
        if (score < bestScore) {
          bestScore = score;
          best = cat.starObjectAt(i);
        }
      }
    }

    if (best == null && cat != null && layers.constellations) {
      for (final c in cat.constellations) {
        consider(cat.constellationObject(c), bonusPx: -4);
      }
    }

    return best;
  }

  static bool _inScreen(Offset pt, Size size, double pad) =>
      pt.dx >= -pad && pt.dx <= size.width + pad && pt.dy >= -pad && pt.dy <= size.height + pad;
}
