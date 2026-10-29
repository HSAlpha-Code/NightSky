import 'dart:typed_data';

/// Image provider metadata from `GET /api/providers`.
class SkyProviderInfo {
  const SkyProviderInfo({
    required this.key,
    required this.name,
    required this.description,
    required this.wavelength,
    required this.coverage,
    required this.allSky,
    required this.credit,
  });

  final String key;
  final String name;
  final String description;
  final String wavelength;
  final String coverage;
  final bool allSky;
  final String credit;

  factory SkyProviderInfo.fromJson(Map<String, dynamic> j) => SkyProviderInfo(
        key: j['key'] as String,
        name: j['name'] as String,
        description: (j['description'] ?? '') as String,
        wavelength: (j['wavelength'] ?? '') as String,
        coverage: (j['coverage'] ?? '') as String,
        allSky: (j['all_sky'] ?? true) as bool,
        credit: (j['credit'] ?? '') as String,
      );
}

class ProviderCatalog {
  const ProviderCatalog(this.defaultKey, this.providers);

  final String defaultKey;
  final List<SkyProviderInfo> providers;

  factory ProviderCatalog.fromJson(Map<String, dynamic> j) => ProviderCatalog(
        j['default'] as String,
        (j['providers'] as List)
            .map((p) => SkyProviderInfo.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}

/// Result of `POST /api/solve`.
class SolveResult {
  const SolveResult({
    required this.ra,
    required this.dec,
    required this.rotation,
    required this.fov,
    required this.confidence,
    required this.approximate,
    this.source = '',
    this.message = '',
  });

  final double ra;
  final double dec;
  final double rotation;
  final double fov;
  final double confidence;
  final bool approximate;
  final String source;
  final String message;

  factory SolveResult.fromJson(Map<String, dynamic> j) => SolveResult(
        ra: (j['ra'] as num).toDouble(),
        dec: (j['dec'] as num).toDouble(),
        rotation: (j['rotation'] as num).toDouble(),
        fov: (j['fov'] as num).toDouble(),
        confidence: (j['confidence'] as num).toDouble(),
        approximate: j['approximate'] as bool,
        source: (j['source'] ?? '') as String,
        message: (j['message'] ?? '') as String,
      );
}

/// Image bytes plus the metadata headers from `POST /api/sky-image`.
class SkyImage {
  const SkyImage({
    required this.bytes,
    required this.providerKey,
    required this.providerName,
    required this.credit,
    this.fallbackUsed = false,
    this.fallbackReason,
    this.fallbackMessage,
  });

  final Uint8List bytes;
  final String providerKey;
  final String providerName;
  final String credit;
  final bool fallbackUsed;
  final String? fallbackReason;
  final String? fallbackMessage;
}

/// A notable object in the field, from `GET /api/landmarks`.
class Landmark {
  const Landmark({
    required this.id,
    required this.name,
    required this.kind,
    required this.typeLabel,
    required this.x,
    required this.y,
    this.hasHires,
    this.magnitude,
    this.sizeArcmin,
    this.messier,
    this.constellation = '',
    this.aliases = const [],
    this.distanceLy,
  });

  final String id;
  final String name;
  final String kind; // "dso" | "star"
  final String typeLabel;

  /// Position in the survey image, 0..1 from the left / top edge.
  final double x;
  final double y;

  /// true / false, or null while the backend is still asking MAST.
  final bool? hasHires;
  final double? magnitude;
  final double? sizeArcmin;
  final int? messier;
  final String constellation;
  final List<String> aliases;
  final double? distanceLy;

  bool get isStar => kind == 'star';

  factory Landmark.fromJson(Map<String, dynamic> j) => Landmark(
        id: j['id'] as String,
        name: j['name'] as String,
        kind: (j['kind'] ?? 'dso') as String,
        typeLabel: (j['type_label'] ?? '') as String,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        hasHires: j['has_hires'] as bool?,
        magnitude: (j['magnitude'] as num?)?.toDouble(),
        sizeArcmin: (j['size_arcmin'] as num?)?.toDouble(),
        messier: j['messier'] as int?,
        constellation: (j['constellation'] ?? '') as String,
        aliases: [for (final a in (j['aliases'] as List? ?? const [])) a as String],
        distanceLy: (j['distance_ly'] as num?)?.toDouble(),
      );
}

class LandmarkField {
  const LandmarkField({required this.landmarks, required this.pending, this.source = ''});

  final List<Landmark> landmarks;

  /// Some Hubble/JWST checks are still running; ask again shortly.
  final bool pending;
  final String source;

  factory LandmarkField.fromJson(Map<String, dynamic> j) => LandmarkField(
        landmarks: [
          for (final l in j['landmarks'] as List) Landmark.fromJson(l as Map<String, dynamic>)
        ],
        pending: (j['pending'] ?? false) as bool,
        source: (j['source'] ?? '') as String,
      );
}

/// Second-level view from `GET /api/landmark-detail`.
class LandmarkDetail {
  const LandmarkDetail({
    required this.image,
    required this.imageSource,
    required this.credit,
    this.caption = '',
    this.fovDeg,
  });

  final Uint8List image;
  final String imageSource; // "jwst" | "hst" | "survey"
  final String credit;
  final String caption;
  final double? fovDeg;

  bool get fromSpaceTelescope => imageSource == 'jwst' || imageSource == 'hst';
}

/// Point of view for the landmark detail image.
class DetailView {
  const DetailView(this.view, this.providerKey, this.label);

  /// "auto" | "jwst" | "hst" | "survey"
  final String view;

  /// Survey used for the close-up (and for colour under Hubble/Webb mosaics).
  final String? providerKey;
  final String label;

  static const auto = DetailView('auto', null, 'Best');

  @override
  bool operator ==(Object other) =>
      other is DetailView && other.view == view && other.providerKey == providerKey;

  @override
  int get hashCode => Object.hash(view, providerKey);
}

/// Downscaled, upright JPEG ready for upload.
class PreparedPhoto {
  const PreparedPhoto(this.jpeg, this.width, this.height);

  final Uint8List jpeg;
  final int width;
  final int height;
}

/// Sensor/GPS/time data recorded at the moment of capture (sent as `/solve` metadata).
class CaptureMetadata {
  const CaptureMetadata({
    required this.timestampUtc,
    this.latitude,
    this.longitude,
    this.altitude,
    this.quaternion,
    this.reference = 'magnetic_north',
    this.fovDeg,
  });

  final DateTime timestampUtc;
  final double? latitude;
  final double? longitude;
  final double? altitude;

  /// Device -> world (East/North/Up) rotation, [x, y, z, w].
  final List<double>? quaternion;
  final String reference;
  final double? fovDeg;

  CaptureMetadata copyWith({double? fovDeg}) => CaptureMetadata(
        timestampUtc: timestampUtc,
        latitude: latitude,
        longitude: longitude,
        altitude: altitude,
        quaternion: quaternion,
        reference: reference,
        fovDeg: fovDeg ?? this.fovDeg,
      );

  Map<String, dynamic> toJson() => {
        'timestamp': timestampUtc.toUtc().toIso8601String(),
        if (latitude != null && longitude != null) ...{
          'latitude': latitude,
          'longitude': longitude,
          'altitude': altitude ?? 0.0,
        },
        if (quaternion != null)
          'orientation': {
            'quaternion': {
              'x': quaternion![0],
              'y': quaternion![1],
              'z': quaternion![2],
              'w': quaternion![3],
            },
            'reference': reference,
          },
        // The app is locked to portrait and the capture orientation is locked too, so the
        // top of the phone is always "up" in the photo.
        'image_rotation_deg': 0,
        if (fovDeg != null) 'fov_deg': fovDeg,
      };
}

/// Error returned by the backend (`{"error": {"code", "message"}}`) or a network failure.
class ApiException implements Exception {
  const ApiException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}
