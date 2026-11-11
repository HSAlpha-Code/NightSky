import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import 'astro_math.dart';

const starsAssetPath = 'assets/sky/stars.bin';
const skyCatalogAssetPath = 'assets/sky/sky_catalog.json';

/// Kind of celestial body selectable or searchable in Sky View.
enum SkyBodyKind {
  star('Star'),
  planet('Planet'),
  sun('Star (Sun)'),
  moon('Natural satellite'),
  dso('Deep-sky object'),
  constellation('Constellation');

  const SkyBodyKind(this.defaultTypeLabel);
  final String defaultTypeLabel;
}

/// Unified celestial object model for tapping, searching, guiding, and detail sheets.
@immutable
class SkyObject {
  const SkyObject({
    required this.id,
    required this.name,
    required this.kind,
    required this.typeLabel,
    required this.icrs,
    required this.raDeg,
    required this.decDeg,
    this.magnitude,
    this.constellation = '',
    this.aliases = const [],
    this.distanceLy,
    this.distanceAu,
    this.sizeArcmin,
    this.messier,
    this.phaseFraction,
    this.phaseLabel,
    this.summary = '',
    this.color = const Color(0xFFFFFFFF),
  });

  /// Matches backend `Landmark.id` (`HIP...`, `NGC...`, `IC...`, `Mel...`, `C...`) where
  /// applicable so `CuratedIndex.has(id)` and `LandmarkDetailScreen` work seamlessly.
  final String id;
  final String name;
  final SkyBodyKind kind;
  final String typeLabel;

  /// Unit direction vector in J2000 ICRS coordinates (geocentric/topocentric of date for
  /// solar-system bodies converted to J2000 so one camera projects everything consistently).
  final Vec3 icrs;
  final double raDeg;
  final double decDeg;

  final double? magnitude;
  final String constellation;
  final List<String> aliases;
  final double? distanceLy;
  final double? distanceAu;
  final double? sizeArcmin;
  final int? messier;

  /// Illuminated fraction [0..1] and descriptive phase name (for Moon / planets).
  final double? phaseFraction;
  final String? phaseLabel;
  final String summary;
  final Color color;

  /// Convert to a [Landmark] when opening NightSky's online Hubble/Webb/Survey/Curated screen.
  Landmark? toLandmark() {
    if (kind != SkyBodyKind.dso && kind != SkyBodyKind.star) return null;
    return Landmark(
      id: id,
      name: name,
      kind: kind == SkyBodyKind.star ? 'star' : 'dso',
      typeLabel: typeLabel,
      x: 0.5,
      y: 0.5,
      magnitude: magnitude,
      sizeArcmin: sizeArcmin,
      messier: messier,
      constellation: constellation,
      aliases: aliases,
      distanceLy: distanceLy,
    );
  }
}

/// Metadata for a proper-named naked-eye star.
@immutable
class NamedStarMeta {
  const NamedStarMeta({
    required this.hip,
    required this.name,
    required this.bayer,
    required this.constellation,
    this.distanceLy,
  });

  final int hip;
  final String name;
  final String bayer;
  final String constellation;
  final double? distanceLy;
}

/// One of the 88 IAU constellations, with precomputed J2000 3D unit vectors for every stick
/// segment so frame rendering requires zero trig.
@immutable
class ConstellationEntry {
  const ConstellationEntry({
    required this.id,
    required this.name,
    required this.latin,
    required this.rank,
    required this.raDeg,
    required this.decDeg,
    required this.centerIcrs,
    required this.polylines,
  });

  final String id;
  final String name;
  final String latin;
  final int rank;
  final double raDeg;
  final double decDeg;
  final Vec3 centerIcrs;
  final List<List<Vec3>> polylines;
}

/// Packed, cache-friendly offline catalog of stars (sorted brightest-first), constellations,
/// and deep-sky objects.
class SkyCatalog {
  SkyCatalog._({
    required this.starCount,
    required this.starHip,
    required this.starRaDeg,
    required this.starDecDeg,
    required this.starIx,
    required this.starIy,
    required this.starIz,
    required this.starMag,
    required this.starColorArgb,
    required this.namedStarsByHip,
    required this.namedStarIndices,
    required this.constellations,
    required this.constellationByCode,
    required this.deepSkyObjects,
  });

  final int starCount;
  final Int32List starHip;
  final Float32List starRaDeg;
  final Float32List starDecDeg;
  final Float32List starIx;
  final Float32List starIy;
  final Float32List starIz;
  final Float32List starMag;
  final Uint32List starColorArgb;

  final Map<int, NamedStarMeta> namedStarsByHip;
  final Int32List namedStarIndices;

  final List<ConstellationEntry> constellations;
  final Map<String, ConstellationEntry> constellationByCode;
  final List<SkyObject> deepSkyObjects;

  static SkyCatalog parse({required ByteData starsBin, required String catalogJson}) {
    // Validate 'NSKY' v1 header.
    if (starsBin.lengthInBytes < 8 ||
        starsBin.getUint8(0) != 0x4E ||
        starsBin.getUint8(1) != 0x53 ||
        starsBin.getUint8(2) != 0x4B ||
        starsBin.getUint8(3) != 0x59) {
      throw const FormatException('Invalid stars.bin header');
    }
    final count = starsBin.getUint16(6, Endian.little);
    if (starsBin.lengthInBytes < 8 + count * 12) {
      throw const FormatException('Truncated stars.bin payload');
    }

    final decoded = jsonDecode(catalogJson) as Map<String, dynamic>;
    final namedByHip = <int, NamedStarMeta>{};
    for (final row in (decoded['named_stars'] as List? ?? const [])) {
      final list = row as List;
      final hip = (list[0] as num).toInt();
      namedByHip[hip] = NamedStarMeta(
        hip: hip,
        name: list[1] as String,
        bayer: list[2] as String,
        constellation: list[3] as String,
        distanceLy: (list[4] as num?)?.toDouble(),
      );
    }

    final hips = Int32List(count);
    final ras = Float32List(count);
    final decs = Float32List(count);
    final ix = Float32List(count);
    final iy = Float32List(count);
    final iz = Float32List(count);
    final mags = Float32List(count);
    final colors = Uint32List(count);
    final namedIdx = <int>[];

    for (var i = 0; i < count; i++) {
      final base = 8 + i * 12;
      final hip = starsBin.getUint32(base, Endian.little);
      final raQ = starsBin.getUint16(base + 4, Endian.little);
      final decQ = starsBin.getInt16(base + 6, Endian.little);
      final magMmag = starsBin.getInt16(base + 8, Endian.little);
      final bvCent = starsBin.getInt8(base + 10);

      final raDeg = (raQ / 65535.0) * 360.0;
      final decDeg = (decQ / 32767.0) * 90.0;
      final mag = magMmag / 1000.0;
      final bv = bvCent / 50.0;
      final v = raDecToVec(raDeg, decDeg);

      hips[i] = hip;
      ras[i] = raDeg;
      decs[i] = decDeg;
      ix[i] = v.x;
      iy[i] = v.y;
      iz[i] = v.z;
      mags[i] = mag;
      colors[i] = bvToStarColor(bv).toARGB32();
      if (namedByHip.containsKey(hip)) {
        namedIdx.add(i);
      }
    }

    final constellations = <ConstellationEntry>[];
    final conByCode = <String, ConstellationEntry>{};
    for (final raw in (decoded['constellations'] as List? ?? const [])) {
      final m = raw as Map<String, dynamic>;
      final ra = (m['ra'] as num).toDouble();
      final dec = (m['dec'] as num).toDouble();
      final polylines = <List<Vec3>>[];
      for (final line in (m['lines'] as List? ?? const [])) {
        final coords = line as List;
        final pts = <Vec3>[];
        for (var j = 0; j + 1 < coords.length; j += 2) {
          pts.add(raDecToVec((coords[j] as num).toDouble(), (coords[j + 1] as num).toDouble()));
        }
        if (pts.length >= 2) polylines.add(pts);
      }
      final entry = ConstellationEntry(
        id: m['id'] as String,
        name: m['name'] as String,
        latin: (m['latin'] ?? m['name']) as String,
        rank: (m['rank'] as num? ?? 2).toInt(),
        raDeg: ra,
        decDeg: dec,
        centerIcrs: raDecToVec(ra, dec),
        polylines: polylines,
      );
      constellations.add(entry);
      conByCode[entry.id] = entry;
    }

    final dsos = <SkyObject>[];
    for (final raw in (decoded['dso'] as List? ?? const [])) {
      final m = raw as Map<String, dynamic>;
      final ra = (m['ra'] as num).toDouble();
      final dec = (m['dec'] as num).toDouble();
      final conCode = (m['con'] ?? '') as String;
      final conName = conByCode[conCode]?.name ?? conCode;
      final typeLabel = (m['type'] ?? 'Deep-sky object') as String;
      final messier = (m['m'] as num?)?.toInt();
      final aliases = [for (final a in (m['aliases'] as List? ?? const [])) a as String];
      dsos.add(
        SkyObject(
          id: m['id'] as String,
          name: m['name'] as String,
          kind: SkyBodyKind.dso,
          typeLabel: typeLabel,
          icrs: raDecToVec(ra, dec),
          raDeg: ra,
          decDeg: dec,
          magnitude: (m['mag'] as num?)?.toDouble(),
          sizeArcmin: (m['size'] as num?)?.toDouble(),
          messier: messier,
          constellation: conName,
          aliases: aliases,
          distanceLy: (m['dist'] as num?)?.toDouble(),
          color: const Color(0xFF9AD0FF),
          summary: _dsoSummary(typeLabel, conName, messier),
        ),
      );
    }

    return SkyCatalog._(
      starCount: count,
      starHip: hips,
      starRaDeg: ras,
      starDecDeg: decs,
      starIx: ix,
      starIy: iy,
      starIz: iz,
      starMag: mags,
      starColorArgb: colors,
      namedStarsByHip: namedByHip,
      namedStarIndices: Int32List.fromList(namedIdx),
      constellations: constellations,
      constellationByCode: conByCode,
      deepSkyObjects: dsos,
    );
  }

  static Future<SkyCatalog> load({AssetBundle? bundle}) async {
    final b = bundle ?? rootBundle;
    final results = await Future.wait([
      b.load(starsAssetPath),
      b.loadString(skyCatalogAssetPath),
    ]);
    return parse(starsBin: results[0] as ByteData, catalogJson: results[1] as String);
  }

  /// Build a rich [SkyObject] for star index [i] (`0 <= i < starCount`).
  SkyObject starObjectAt(int i) {
    final hip = starHip[i];
    final meta = namedStarsByHip[hip];
    final conCode = meta?.constellation ?? '';
    final conName = constellationByCode[conCode]?.name ?? conCode;
    final name = meta?.name.isNotEmpty == true ? meta!.name : 'HIP $hip';
    final aliases = <String>[
      if (meta != null && meta.bayer.isNotEmpty && meta.bayer != name)
        '$conCode ${meta.bayer}'.trim(),
      'HIP $hip',
    ];
    final mag = starMag[i];
    return SkyObject(
      id: 'HIP$hip',
      name: name,
      kind: SkyBodyKind.star,
      typeLabel: 'Star',
      icrs: Vec3(starIx[i], starIy[i], starIz[i]),
      raDeg: starRaDeg[i],
      decDeg: starDecDeg[i],
      magnitude: mag,
      constellation: conName,
      aliases: aliases,
      distanceLy: meta?.distanceLy,
      color: Color(starColorArgb[i]),
      summary: conName.isNotEmpty
          ? 'Naked-eye star in $conName (apparent magnitude ${mag.toStringAsFixed(2)}).'
          : 'Naked-eye star (apparent magnitude ${mag.toStringAsFixed(2)}).',
    );
  }

  SkyObject constellationObject(ConstellationEntry c) => SkyObject(
        id: 'CON-${c.id}',
        name: c.name,
        kind: SkyBodyKind.constellation,
        typeLabel: 'Constellation (${c.id})',
        icrs: c.centerIcrs,
        raDeg: c.raDeg,
        decDeg: c.decDeg,
        constellation: c.name,
        aliases: [if (c.latin != c.name) c.latin, c.id],
        color: const Color(0xFF7FB3FF),
        summary: 'One of the 88 modern IAU constellations (${c.latin}).',
      );

  /// Look up a star index by Hipparcos number, or -1 if absent.
  int indexOfHip(int hip) {
    for (var i = 0; i < starCount; i++) {
      if (starHip[i] == hip) return i;
    }
    return -1;
  }
}

String _dsoSummary(String typeLabel, String constellation, int? messier) {
  final where = constellation.isNotEmpty ? ' in $constellation' : '';
  final mNote = messier != null ? ' (Messier $messier)' : '';
  return '$typeLabel$where$mNote.';
}

/// Convert stellar B-V colour index (-0.4 blue O/B star .. +2.0 deep orange-red M star) to a
/// natural visual tint via Ballesteros' (2012) blackbody approximation.
Color bvToStarColor(double bv) {
  final clamped = bv.clamp(-0.4, 2.0);
  final t = 4600.0 * (1.0 / (0.92 * clamped + 1.7) + 1.0 / (0.92 * clamped + 0.62));
  // Planckian locus -> sRGB (Charity / Tanner Helland approximation, softened for dark-sky display).
  final tk = t / 100.0;
  double r, g, b;
  if (tk <= 66.0) {
    r = 255.0;
    g = 99.4708025861 * math.log(tk) - 161.1195681661;
    b = tk <= 19.0 ? 0.0 : 138.5177312231 * math.log(tk - 10.0) - 305.0447927307;
  } else {
    r = 329.698727446 * math.pow(tk - 60.0, -0.1332047592);
    g = 288.1221695283 * math.pow(tk - 60.0, -0.0755148492);
    b = 255.0;
  }
  // Blend 70% chromaticity + 30% pure white so star cores remain luminous and legible.
  int ch(double v) => ((v.clamp(0.0, 255.0) * 0.72) + 255.0 * 0.28).round().clamp(0, 255);
  return Color.fromARGB(255, ch(r), ch(g), ch(b));
}

final skyCatalogProvider = FutureProvider<SkyCatalog>((ref) => SkyCatalog.load());
