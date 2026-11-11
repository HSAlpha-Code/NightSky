import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'astro_math.dart';
import 'panorama_loader.dart';

/// Renders the 3D 8K Mellinger Milky Way sphere, horizon line, cardinal compass points, and
/// optional sky overlays onto a single hardware-accelerated [Canvas].
class SkySpherePainter extends CustomPainter {
  SkySpherePainter({
    required this.camera,
    this.panorama,
    this.shaderProgram,
    this.sunAltitudeDeg = -30.0,
    this.showMilkyWay = true,
    this.showHorizon = true,
    this.nightVision = false,
    this.exposure = 1.12,
    this.overlayPaint,
  });

  final SkyCamera camera;
  final MellingerPanorama? panorama;
  final ui.FragmentProgram? shaderProgram;
  final double sunAltitudeDeg;
  final bool showMilkyWay;
  final bool showHorizon;
  final bool nightVision;
  final double exposure;

  final void Function(Canvas canvas, Size size)? overlayPaint;

  static const _cardinals = [
    (0.0, 'N', true),
    (45.0, 'NE', false),
    (90.0, 'E', true),
    (135.0, 'SE', false),
    (180.0, 'S', true),
    (225.0, 'SW', false),
    (270.0, 'W', true),
    (315.0, 'NW', false),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = nightVision ? const Color(0xFF090101) : const Color(0xFF03050A),
    );

    final pano = panorama;
    if (showMilkyWay && pano != null) {
      if (shaderProgram != null) {
        _paintWithShader(canvas, size, pano, shaderProgram!);
      } else {
        _paintWithMeshFallback(canvas, size, pano);
      }
    } else {
      _paintProceduralGradient(canvas, size);
    }

    overlayPaint?.call(canvas, size);

    if (showHorizon) {
      _paintHorizonAndCardinals(canvas, size);
    }
    _paintCenterReticle(canvas, size);
  }

  void _paintWithShader(
    Canvas canvas,
    Size size,
    MellingerPanorama pano,
    ui.FragmentProgram program,
  ) {
    final shader = program.fragmentShader();
    var i = 0;
    shader.setFloat(i++, size.width);
    shader.setFloat(i++, size.height);
    shader.setFloat(i++, camera.tanHalfFov);

    shader.setFloat(i++, camera.forwardGal.x);
    shader.setFloat(i++, camera.forwardGal.y);
    shader.setFloat(i++, camera.forwardGal.z);

    shader.setFloat(i++, camera.rightGal.x);
    shader.setFloat(i++, camera.rightGal.y);
    shader.setFloat(i++, camera.rightGal.z);

    shader.setFloat(i++, camera.upGal.x);
    shader.setFloat(i++, camera.upGal.y);
    shader.setFloat(i++, camera.upGal.z);

    shader.setFloat(i++, camera.zenithGal.x);
    shader.setFloat(i++, camera.zenithGal.y);
    shader.setFloat(i++, camera.zenithGal.z);

    shader.setFloat(i++, sunAltitudeDeg);
    shader.setFloat(i++, exposure);
    shader.setFloat(i++, nightVision ? 1.0 : 0.0);
    shader.setFloat(i++, pano.hemisphereSize.toDouble());

    shader.setImageSampler(0, pano.east);
    shader.setImageSampler(1, pano.west);

    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
    shader.dispose();
  }

  /// Screen-space ray-grid `drawVertices` fallback splitting triangles cleanly between the East
  /// (`u < 0.5`) and West (`u >= 0.5`) hemisphere textures when custom shaders aren't available.
  void _paintWithMeshFallback(Canvas canvas, Size size, MellingerPanorama pano) {
    const cols = 24;
    const rows = 16;
    final edge = pano.hemisphereSize.toDouble();

    final gridU = Float32List((cols + 1) * (rows + 1));
    final gridV = Float32List((cols + 1) * (rows + 1));
    final gridX = Float32List((cols + 1) * (rows + 1));
    final gridY = Float32List((cols + 1) * (rows + 1));

    final aspect = size.height / size.width;
    for (var r = 0; r <= rows; r++) {
      final fy = r / rows;
      final ny = (0.5 - fy) * 2.0 * aspect;
      final sy = fy * size.height;
      for (var c = 0; c <= cols; c++) {
        final fx = c / cols;
        final nx = fx * 2.0 - 1.0;
        final sx = fx * size.width;
        final dir = (camera.forwardGal +
                camera.rightGal * (nx * camera.tanHalfFov) +
                camera.upGal * (ny * camera.tanHalfFov))
            .normalized;
        final uv = galacticVecToPanoramaUv(dir);
        final idx = r * (cols + 1) + c;
        gridX[idx] = sx;
        gridY[idx] = sy;
        gridU[idx] = uv.u;
        gridV[idx] = uv.v;
      }
    }

    final eastPos = <double>[];
    final eastUv = <double>[];
    final westPos = <double>[];
    final westUv = <double>[];

    void emitQuad(int i00, int i10, int i01, int i11) {
      var u00 = gridU[i00], u10 = gridU[i10], u01 = gridU[i01], u11 = gridU[i11];
      final maxU = [u00, u10, u01, u11].reduce((a, b) => a > b ? a : b);
      final minU = [u00, u10, u01, u11].reduce((a, b) => a < b ? a : b);
      if (maxU - minU > 0.5) {
        if (u00 < 0.5) u00 += 1.0;
        if (u10 < 0.5) u10 += 1.0;
        if (u01 < 0.5) u01 += 1.0;
        if (u11 < 0.5) u11 += 1.0;
      }
      final avgU = (u00 + u10 + u01 + u11) * 0.25;
      final useWest = avgU >= 0.5 && avgU < 1.0;
      final posOut = useWest ? westPos : eastPos;
      final uvOut = useWest ? westUv : eastUv;

      double localU(double gu) {
        final wrapped = gu >= 1.0 ? gu - 1.0 : gu;
        final lu = useWest ? (wrapped - 0.5) * 2.0 : wrapped * 2.0;
        return lu.clamp(0.0, 1.0) * edge;
      }

      for (final (idx, gu) in [
        (i00, u00), (i10, u10), (i01, u01),
        (i10, u10), (i11, u11), (i01, u01),
      ]) {
        posOut.add(gridX[idx]);
        posOut.add(gridY[idx]);
        uvOut.add(localU(gu));
        uvOut.add(gridV[idx] * edge);
      }
    }

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final i00 = r * (cols + 1) + c;
        emitQuad(i00, i00 + 1, i00 + cols + 1, i00 + cols + 2);
      }
    }

    void drawBatch(ui.Image tex, List<double> pos, List<double> uvs) {
      if (pos.isEmpty) return;
      final vertices = ui.Vertices.raw(
        ui.VertexMode.triangles,
        Float32List.fromList(pos),
        textureCoordinates: Float32List.fromList(uvs),
      );
      final paint = Paint()
        ..shader = ImageShader(
          tex,
          TileMode.clamp,
          TileMode.clamp,
          Matrix4.identity().storage,
          filterQuality: FilterQuality.medium,
        );
      if (nightVision) {
        paint.colorFilter = const ColorFilter.matrix(<double>[
          0.34, 0.66, 0.12, 0, 0,
          0.02, 0.04, 0.01, 0, 0,
          0.01, 0.02, 0.01, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      }
      canvas.drawVertices(vertices, BlendMode.srcOver, paint);
      vertices.dispose();
    }

    drawBatch(pano.east, eastPos, eastUv);
    drawBatch(pano.west, westPos, westUv);
  }

  void _paintProceduralGradient(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final top = nightVision ? const Color(0xFF1A0303) : const Color(0xFF060B19);
    final bottom = nightVision ? const Color(0xFF0A0101) : const Color(0xFF0E1A30);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, bottom],
        ).createShader(rect),
    );
  }

  void _paintHorizonAndCardinals(Canvas canvas, Size size) {
    final lineColor = nightVision ? const Color(0x99FF4040) : const Color(0x7770A8FF);
    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    const steps = 96;
    final path = Path();
    var penDown = false;
    Offset? prev;
    for (var i = 0; i <= steps; i++) {
      final az = (i / steps) * 360.0;
      final pt = camera.projectEnu(altAzToEnu(0.0, az), size);
      if (pt != null &&
          pt.dx >= -size.width * 0.5 &&
          pt.dx <= size.width * 1.5 &&
          pt.dy >= -size.height * 0.5 &&
          pt.dy <= size.height * 1.5) {
        if (!penDown || (prev != null && (pt - prev).distance > size.width * 0.6)) {
          path.moveTo(pt.dx, pt.dy);
          penDown = true;
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
        prev = pt;
      } else {
        penDown = false;
        prev = null;
      }
    }
    canvas.drawPath(path, linePaint);

    for (final (az, label, major) in _cardinals) {
      final pt = camera.projectEnu(altAzToEnu(0.0, az), size);
      if (pt == null ||
          pt.dx < -20 ||
          pt.dx > size.width + 20 ||
          pt.dy < -20 ||
          pt.dy > size.height + 20) {
        continue;
      }
      final tickPaint = Paint()
        ..color = major
            ? (nightVision ? const Color(0xFFFF5252) : const Color(0xFFD6E6FF))
            : lineColor
        ..strokeWidth = major ? 1.8 : 1.1;
      canvas.drawLine(pt.translate(0, -4), pt.translate(0, 4), tickPaint);

      final accent = label == 'N'
          ? (nightVision ? const Color(0xFFFF6E6E) : const Color(0xFFFF8A65))
          : (major
              ? (nightVision ? const Color(0xFFFF5252) : const Color(0xFFE3EEFF))
              : (nightVision ? const Color(0xAAFF4444) : const Color(0xAA9BB8E8)));

      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: accent,
            fontSize: major ? 13 : 10.5,
            fontWeight: major ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: 0.6,
            shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(pt.dx - tp.width * 0.5, pt.dy - tp.height - 6));
    }
  }

  void _paintCenterReticle(Canvas canvas, Size size) {
    final c = Offset(size.width * 0.5, size.height * 0.5);
    final paint = Paint()
      ..color = (nightVision ? const Color(0x55FF4444) : const Color(0x44FFFFFF))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(c, 8, paint);
  }

  @override
  bool shouldRepaint(covariant SkySpherePainter old) =>
      old.camera != camera ||
      old.panorama != panorama ||
      old.shaderProgram != shaderProgram ||
      old.sunAltitudeDeg != sunAltitudeDeg ||
      old.showMilkyWay != showMilkyWay ||
      old.showHorizon != showHorizon ||
      old.nightVision != nightVision ||
      old.exposure != exposure ||
      old.overlayPaint != overlayPaint;
}
