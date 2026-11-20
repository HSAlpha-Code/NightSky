import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sky/sky_view/astro_math.dart';
import 'package:night_sky/sky_view/panorama_loader.dart';
import 'package:night_sky/sky_view/panorama_packs.dart';
import 'package:night_sky/sky_view/panorama_tile_cache.dart';
import 'package:night_sky/sky_view/sky_sphere_painter.dart';

Future<ui.Image> solid(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(16, 16);
  picture.dispose();
  return image;
}

void main() {
  test('download sizes shown in the app match the prepared lossless packs', () {
    for (final resolution in [
      PanoramaResolution.sixteenK,
      PanoramaResolution.thirtyTwoK,
    ]) {
      final manifest =
          jsonDecode(
                File(
                  '../backend/panorama_packs/${resolution.k}k/manifest.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final pack = PanoramaPack(resolution, manifest);
      expect(pack.bytes, resolution.downloadBytes);
      expect(manifest['encoding'], contains('lossless'));
    }
  });
  testWidgets(
    'native installed tiles decode offline and reload after resolution changes',
    (tester) async {
      final cache = PanoramaTileCache(
        (resolution) async =>
            Directory('../backend/panorama_packs/${resolution.k}k'),
      );
      final camera = SkyCamera.fromAltAz(
        altitudeDeg: 40,
        azimuthDeg: 130,
        latitudeDeg: 20,
        longitudeDeg: 77,
        when: DateTime.utc(2026, 11, 20),
        fovDeg: 15,
      );
      await tester.runAsync(() async {
        for (var cycle = 0; cycle < 2; cycle++) {
          cache.updateView(
            PanoramaResolution.sixteenK,
            camera,
            const Size(80, 80),
            true,
          );
          for (var i = 0; i < 200 && cache.images.isEmpty; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          expect(cache.images, isNotEmpty);
          expect(
            cache.images.length,
            lessThanOrEqualTo(PanoramaTileCache.maxTiles),
          );
          for (final image in cache.images.values) {
            expect((image.width, image.height), (2050, 2050));
          }
          cache.updateView(
            PanoramaResolution.eightK,
            camera,
            const Size(80, 80),
            true,
          );
          expect(cache.images, isEmpty);
        }
        cache.dispose();
      });
      await tester.pump();
    },
  );

  testWidgets(
    'installed 16K and 32K tiles replace the 8K fallback in the shader',
    (tester) async {
      await tester.runAsync(() async {
        final program = await ui.FragmentProgram.fromAsset(
          skySphereShaderAsset,
        );
        final panorama = SkyPanorama(
          east: await solid(Colors.blue),
          west: await solid(Colors.blue),
        );
        final camera = SkyCamera.fromAltAz(
          altitudeDeg: 40,
          azimuthDeg: 130,
          latitudeDeg: 20,
          longitudeDeg: 77,
          when: DateTime.utc(2026, 11, 20),
          fovDeg: 15,
        );
        const size = Size(80, 80);
        // Sample away from the center reticle. Select the tile actually seen by this pixel.
        const x = 28, y = 28;

        Future<ByteData> render(
          PanoramaTileCache? cache, {
          bool red = false,
        }) async {
          final recorder = ui.PictureRecorder();
          SkySpherePainter(
            camera: camera,
            panorama: panorama,
            shaderProgram: program,
            tileCache: cache,
            showHorizon: false,
            horizonShading: false,
            nightVision: red,
          ).paint(Canvas(recorder), size);
          final picture = recorder.endRecording();
          final image = await picture.toImage(80, 80);
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          image.dispose();
          picture.dispose();
          return bytes;
        }

        final offset = (y * 80 + x) * 4;
        final base = await render(null);
        expect(base.getUint8(offset + 2), greaterThan(200));
        for (final resolution in [
          PanoramaResolution.sixteenK,
          PanoramaResolution.thirtyTwoK,
        ]) {
          final cache = PanoramaTileCache(
            (_) async => Directory.systemTemp,
            fadeDuration: Duration.zero,
            decodeTile: (_, _) => solid(const Color(0xff00ff00)),
          );
          cache.updateView(resolution, camera, size, true);
          for (var i = 0; i < 200 && !cache.ready; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          expect(cache.ready, isTrue);
          final high = await render(cache);
          expect(
            high.getUint8(offset + 1),
            greaterThan(100),
            reason: resolution.label,
          );
          expect(
            high.getUint8(offset + 2),
            lessThan(10),
            reason: resolution.label,
          );
          final red = await render(cache, red: true);
          expect(
            red.getUint8(offset),
            greaterThan(red.getUint8(offset + 1) * 5),
          );
          cache.dispose();
        }
        panorama.dispose();
      });
      await tester.pump();
    },
  );

  testWidgets(
    'partial tiles remain hidden, complete view fades together and offscreen tiles stay cached',
    (tester) async {
      final pending = <String, Completer<ui.Image>>{};
      final calls = <String, int>{};
      final cache = PanoramaTileCache(
        (_) async => Directory.systemTemp,
        decodeTile: (key, edge) {
          calls[key] = (calls[key] ?? 0) + 1;
          return (pending[key] = Completer<ui.Image>()).future;
        },
      );
      final camera = SkyCamera.fromAltAz(
        altitudeDeg: 40,
        azimuthDeg: 130,
        latitudeDeg: 20,
        longitudeDeg: 77,
        when: DateTime.utc(2026, 11, 20),
        fovDeg: 25,
      );
      const size = Size(80, 80);
      await tester.runAsync(() async {
        cache.updateView(PanoramaResolution.thirtyTwoK, camera, size, true);
        expect(cache.clips.length, greaterThan(1));
        final first = pending.keys.first;
        pending[first]!.complete(await solid(Colors.green));
        for (var i = 0; i < 100 && cache.images.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        expect(cache.images, isNotEmpty);
        expect(cache.ready, isFalse);
        expect(cache.opacity, 0);
        for (var i = 0; i < 100 && !cache.ready; i++) {
          for (final request in pending.values.toList()) {
            if (!request.isCompleted) {
              request.complete(await solid(Colors.green));
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        expect(cache.ready, isTrue);
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(cache.opacity, greaterThan(0));
      expect(cache.opacity, lessThan(1));
      await tester.pump(const Duration(milliseconds: 160));
      expect(cache.opacity, 1);
      final retained = cache.images.keys.toSet();
      final away = SkyCamera.fromAltAz(
        altitudeDeg: 40,
        azimuthDeg: 250,
        latitudeDeg: 20,
        longitudeDeg: 77,
        when: DateTime.utc(2026, 11, 20),
        fovDeg: 25,
      );
      cache.updateView(PanoramaResolution.thirtyTwoK, away, size, true);
      expect(cache.images.keys.toSet().containsAll(retained), isTrue);
      cache.updateView(PanoramaResolution.thirtyTwoK, camera, size, true);
      expect(cache.ready, isTrue);
      for (final key in retained) {
        expect(calls[key], 1);
      }
      cache.dispose();
      await tester.runAsync(() async {
        for (final request in pending.values.toList()) {
          if (!request.isCompleted) request.complete(await solid(Colors.green));
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
    },
  );

  testWidgets(
    'wide views fit the texture budget and deep zoom restores native 32K tiles',
    (tester) async {
      final edges = <int>[];
      final cache = PanoramaTileCache(
        (_) async => Directory.systemTemp,
        fadeDuration: Duration.zero,
        decodeTile: (_, edge) {
          edges.add(edge);
          return solid(Colors.green);
        },
      );
      SkyCamera camera(double fov) => SkyCamera.fromAltAz(
        altitudeDeg: 40,
        azimuthDeg: 130,
        latitudeDeg: 20,
        longitudeDeg: 77,
        when: DateTime.utc(2026, 11, 20),
        fovDeg: fov,
      );
      await tester.runAsync(() async {
        cache.updateView(
          PanoramaResolution.thirtyTwoK,
          camera(90),
          const Size(360, 800),
          true,
        );
        expect(cache.decodedTileEdge, lessThan(2050));
        for (var i = 0; i < 300 && !cache.ready; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(cache.ready, isTrue);
        expect(cache.clips.keys.every(cache.images.containsKey), isTrue);
        expect(cache.images.length, lessThanOrEqualTo(cache.capacity));
        cache.updateView(
          PanoramaResolution.thirtyTwoK,
          camera(2),
          const Size(360, 800),
          true,
        );
        expect(cache.decodedTileEdge, 2050);
        for (var i = 0; i < 300 && !cache.ready; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(cache.ready, isTrue);
        expect(edges, contains(2050));
        expect(
          cache.images.length,
          lessThanOrEqualTo(PanoramaTileCache.maxTiles),
        );
        cache.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
    },
  );
}
