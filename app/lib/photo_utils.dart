import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'models.dart';

const int maxUploadSide = 1600;

/// Decode, apply EXIF orientation, downscale to [maxSide] on the long side and re-encode.
/// Top-level so it can run in a background isolate via `compute`.
PreparedPhoto preparePhoto(Uint8List raw, {int maxSide = maxUploadSide}) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) {
    throw const FormatException('Could not read the captured photo.');
  }
  var image = img.bakeOrientation(decoded);
  if (math.max(image.width, image.height) > maxSide) {
    final landscape = image.width >= image.height;
    image = img.copyResize(
      image,
      width: landscape ? maxSide : null,
      height: landscape ? null : maxSide,
      interpolation: img.Interpolation.average,
    );
  }
  return PreparedPhoto(Uint8List.fromList(img.encodeJpg(image, quality: 90)), image.width,
      image.height);
}

PreparedPhoto preparePhotoIsolate(Uint8List raw) => preparePhoto(raw);

/// Sky-image size with the same aspect ratio as the photo, capped at [maxSide].
(int, int) skyImageSize(int photoWidth, int photoHeight, {int maxSide = 1200}) {
  final scale = maxSide / math.max(photoWidth, photoHeight);
  if (scale >= 1) return (photoWidth, photoHeight);
  return ((photoWidth * scale).round(), (photoHeight * scale).round());
}
