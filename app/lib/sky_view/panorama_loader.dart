import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings.dart';

const mellingerAssetPath = 'assets/sky/mellinger_galactic.webp';
const skySphereShaderAsset = 'shaders/sky_sphere.frag';

/// Bundled Mellinger GPU resources for the active [SkyQuality] tier.
class SkyResources {
  const SkyResources({this.panorama, this.shaderProgram});

  final ui.Image? panorama;
  final ui.FragmentProgram? shaderProgram;
}

/// Decodes the Mellinger panorama scaled to [SkyQuality.panoramaWidth] so older/low-end
/// phones keep GPU texture memory tiny (~2 MB on Power saver, ~8 MB on Balanced).
Future<ui.Image?> decodeMellingerPanorama(SkyQuality quality, {AssetBundle? bundle}) async {
  try {
    final data = await (bundle ?? rootBundle).load(mellingerAssetPath);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: quality.panoramaWidth,
      targetHeight: quality.panoramaWidth ~/ 2,
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  } catch (_) {
    return null;
  }
}

Future<ui.FragmentProgram?> loadSkyShaderProgram() async {
  try {
    return await ui.FragmentProgram.fromAsset(skySphereShaderAsset);
  } catch (_) {
    // Fallback mesh renderer in SkySpherePainter handles environments without shader support.
    return null;
  }
}

final skyShaderProgramProvider = FutureProvider<ui.FragmentProgram?>((ref) => loadSkyShaderProgram());

final mellingerImageProvider = FutureProvider<ui.Image?>((ref) async {
  final quality = ref.watch(settingsProvider.select((s) => s.skyQuality));
  final image = await decodeMellingerPanorama(quality);
  if (image != null) {
    ref.onDispose(image.dispose);
  }
  return image;
});
