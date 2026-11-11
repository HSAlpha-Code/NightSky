import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart';

import '../sky_math.dart';

const double degToRad = math.pi / 180.0;
const double radToDeg = 180.0 / math.pi;

/// Lightweight immutable 3D vector used across coordinate transforms and 3D projection.
@immutable
class Vec3 {
  const Vec3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  static const zero = Vec3(0, 0, 0);
  static const east = Vec3(1, 0, 0);
  static const north = Vec3(0, 1, 0);
  static const up = Vec3(0, 0, 1);

  double get length => math.sqrt(x * x + y * y + z * z);

  Vec3 get normalized {
    final n = length;
    return n < 1e-12 ? zero : Vec3(x / n, y / n, z / n);
  }

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator -() => Vec3(-x, -y, -z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;

  Vec3 cross(Vec3 o) => Vec3(
        y * o.z - z * o.y,
        z * o.x - x * o.z,
        x * o.y - y * o.x,
      );
}

/// Row-major 3x3 rotation matrix.
@immutable
class Mat3 {
  const Mat3(
    this.m00, this.m01, this.m02,
    this.m10, this.m11, this.m12,
    this.m20, this.m21, this.m22,
  );

  final double m00, m01, m02;
  final double m10, m11, m12;
  final double m20, m21, m22;

  static const identity = Mat3(
    1, 0, 0,
    0, 1, 0,
    0, 0, 1,
  );

  factory Mat3.fromRows(Vec3 r0, Vec3 r1, Vec3 r2) => Mat3(
        r0.x, r0.y, r0.z,
        r1.x, r1.y, r1.z,
        r2.x, r2.y, r2.z,
      );

  factory Mat3.fromColumns(Vec3 c0, Vec3 c1, Vec3 c2) => Mat3(
        c0.x, c1.x, c2.x,
        c0.y, c1.y, c2.y,
        c0.z, c1.z, c2.z,
      );

  factory Mat3.fromList(List<double> r) => Mat3(
        r[0], r[1], r[2],
        r[3], r[4], r[5],
        r[6], r[7], r[8],
      );

  Mat3 get transposed => Mat3(
        m00, m10, m20,
        m01, m11, m21,
        m02, m12, m22,
      );

  Vec3 transform(Vec3 v) => Vec3(
        m00 * v.x + m01 * v.y + m02 * v.z,
        m10 * v.x + m11 * v.y + m12 * v.z,
        m20 * v.x + m21 * v.y + m22 * v.z,
      );

  Mat3 operator *(Mat3 b) => Mat3(
        m00 * b.m00 + m01 * b.m10 + m02 * b.m20,
        m00 * b.m01 + m01 * b.m11 + m02 * b.m21,
        m00 * b.m02 + m01 * b.m12 + m02 * b.m22,
        m10 * b.m00 + m11 * b.m10 + m12 * b.m20,
        m10 * b.m01 + m11 * b.m11 + m12 * b.m21,
        m10 * b.m02 + m11 * b.m12 + m12 * b.m22,
        m20 * b.m00 + m21 * b.m10 + m22 * b.m20,
        m20 * b.m01 + m21 * b.m11 + m22 * b.m21,
        m20 * b.m02 + m21 * b.m12 + m22 * b.m22,
      );
}

/// Exact IAU / Hipparcos ICRS (J2000) -> Galactic orthonormal transformation matrix
/// (Hipparcos Catalogue Vol. 1, Sec. 1.5.3, identical to Astropy's ICRS->Galactic matrix).
const Mat3 icrsToGalacticMatrix = Mat3(
  -0.0548755604162154, -0.8734370902348850, -0.4838350155487132,
   0.4941094278755837, -0.4448296299600112,  0.7469822444972189,
  -0.8676661490190047, -0.1980763734312015,  0.4559837761750669,
);

/// Julian Date from a UTC [DateTime].
double julianDate(DateTime when) {
  final utc = when.toUtc();
  return utc.microsecondsSinceEpoch / 86400000000.0 + 2440587.5;
}

/// Julian centuries since J2000.0 (2000-01-01 12:00 UTC).
double julianCenturiesJ2000(DateTime when) => (julianDate(when) - 2451545.0) / 36525.0;

/// Greenwich Mean Sidereal Time in degrees [0, 360) (Meeus Ch. 12 / IAU).
double gmstDeg(DateTime when) {
  final jd = julianDate(when);
  final d = jd - 2451545.0;
  final t = d / 36525.0;
  final theta = 280.46061837 +
      360.98564736629 * d +
      0.000387933 * t * t -
      (t * t * t) / 38710000.0;
  return _wrap360(theta);
}

/// Local Mean Sidereal Time in degrees [0, 360), east longitude positive.
double lstDeg(DateTime when, double longitudeDeg) => _wrap360(gmstDeg(when) + longitudeDeg);

/// Lieske (1979) / IAU precession matrix rotating J2000.0 equatorial unit vectors to the
/// mean equator and equinox of [when].
Mat3 precessionJ2000ToDate(DateTime when) {
  final t = julianCenturiesJ2000(when);
  final t2 = t * t;
  final t3 = t2 * t;
  final zeta = (2306.2181 * t + 0.30188 * t2 + 0.017998 * t3) / 3600.0 * degToRad;
  final z = (2306.2181 * t + 1.09468 * t2 + 0.018203 * t3) / 3600.0 * degToRad;
  final theta = (2004.3109 * t - 0.42665 * t2 - 0.041833 * t3) / 3600.0 * degToRad;

  final cz = math.cos(zeta), sz = math.sin(zeta);
  final cZ = math.cos(z), sZ = math.sin(z);
  final ct = math.cos(theta), st = math.sin(theta);

  return Mat3(
    cz * ct * cZ - sz * sZ, -sz * ct * cZ - cz * sZ, -st * cZ,
    cz * ct * sZ + sz * cZ, -sz * ct * sZ + cz * cZ, -st * sZ,
    cz * st,                -sz * st,                 ct,
  );
}

/// Matrix rotating ICRS J2000 unit vectors directly into the observer's local horizontal
/// East-North-Up (ENU) frame at ([latitudeDeg], [longitudeDeg], [when]).
Mat3 icrsToEnuMatrix({
  required double latitudeDeg,
  required double longitudeDeg,
  required DateTime when,
  bool applyPrecession = true,
}) {
  final lst = lstDeg(when, longitudeDeg) * degToRad;
  final lat = latitudeDeg * degToRad;
  final cl = math.cos(lst), sl = math.sin(lst);
  final sp = math.sin(lat), cp = math.cos(lat);

  // Basis vectors of ENU expressed in true-of-date equatorial coordinates:
  // Zenith (Up)  = (cos lat cos LST, cos lat sin LST, sin lat)
  // East         = (-sin LST, cos LST, 0)
  // North        = (-sin lat cos LST, -sin lat sin LST, cos lat)
  final dateToEnu = Mat3(
    -sl,       cl,       0,
    -sp * cl, -sp * sl,  cp,
     cp * cl,  cp * sl,  sp,
  );
  return applyPrecession ? dateToEnu * precessionJ2000ToDate(when) : dateToEnu;
}

/// Unit vector in equatorial coordinates from Right Ascension and Declination (degrees).
Vec3 raDecToVec(double raDeg, double decDeg) {
  final r = raDeg * degToRad;
  final d = decDeg * degToRad;
  final cd = math.cos(d);
  return Vec3(cd * math.cos(r), cd * math.sin(r), math.sin(d));
}

/// Right Ascension [0, 360) and Declination [-90, +90] in degrees from a unit vector.
({double raDeg, double decDeg}) vecToRaDec(Vec3 v) {
  final u = v.normalized;
  final dec = math.asin(u.z.clamp(-1.0, 1.0)) * radToDeg;
  final ra = _wrap360(math.atan2(u.y, u.x) * radToDeg);
  return (raDeg: ra, decDeg: dec);
}

/// Unit vector in ENU (East, North, Up) from altitude and azimuth (degrees, N=0, E=90).
Vec3 altAzToEnu(double altitudeDeg, double azimuthDeg) {
  final alt = altitudeDeg * degToRad;
  final az = azimuthDeg * degToRad;
  final ca = math.cos(alt);
  return Vec3(ca * math.sin(az), ca * math.cos(az), math.sin(alt));
}

/// Altitude [-90, +90] and true azimuth [0, 360) (N=0, E=90) from an ENU vector.
({double altitudeDeg, double azimuthDeg}) enuToAltAz(Vec3 enu) {
  final u = enu.normalized;
  final alt = math.asin(u.z.clamp(-1.0, 1.0)) * radToDeg;
  final az = _wrap360(math.atan2(u.x, u.y) * radToDeg);
  return (altitudeDeg: alt, azimuthDeg: az);
}

/// Convert J2000 (RA, Dec) to local (Altitude, Azimuth) for an observer.
({double altitudeDeg, double azimuthDeg}) raDecToAltAz({
  required double raDeg,
  required double decDeg,
  required double latitudeDeg,
  required double longitudeDeg,
  required DateTime when,
  bool applyPrecession = true,
}) {
  final m = icrsToEnuMatrix(
    latitudeDeg: latitudeDeg,
    longitudeDeg: longitudeDeg,
    when: when,
    applyPrecession: applyPrecession,
  );
  return enuToAltAz(m.transform(raDecToVec(raDeg, decDeg)));
}

/// Convert local (Altitude, Azimuth) to J2000 (RA, Dec) for an observer.
({double raDeg, double decDeg}) altAzToRaDec({
  required double altitudeDeg,
  required double azimuthDeg,
  required double latitudeDeg,
  required double longitudeDeg,
  required DateTime when,
  bool applyPrecession = true,
}) {
  final enuToIcrs = icrsToEnuMatrix(
    latitudeDeg: latitudeDeg,
    longitudeDeg: longitudeDeg,
    when: when,
    applyPrecession: applyPrecession,
  ).transposed;
  return vecToRaDec(enuToIcrs.transform(altAzToEnu(altitudeDeg, azimuthDeg)));
}

/// Convert an ICRS J2000 unit vector to Galactic (l in [0, 360), b in [-90, +90]) in degrees.
({double lDeg, double bDeg}) icrsVecToGalactic(Vec3 icrs) {
  final g = icrsToGalacticMatrix.transform(icrs).normalized;
  final l = _wrap360(math.atan2(g.y, g.x) * radToDeg);
  final b = math.asin(g.z.clamp(-1.0, 1.0)) * radToDeg;
  return (lDeg: l, bDeg: b);
}

/// Normalized UV coordinates (0..1, 0..1) in the Mellinger Galactic CAR panorama for an ICRS
/// J2000 unit vector. Matches NASA SkyView WCS (`CRVAL=(0,0), CDELT=(-0.1, +0.1)`):
/// - Centre (0.5, 0.5) is Galactic (l = 0, b = 0)
/// - Left edge (u = 0) is l = +180 deg, right edge (u = 1) is l = -180 deg
/// - Top edge (v = 0) is North Galactic Pole (b = +90 deg), bottom (v = 1) is b = -90 deg
({double u, double v}) icrsVecToPanoramaUv(Vec3 icrs) {
  final g = icrsToGalacticMatrix.transform(icrs).normalized;
  return galacticVecToPanoramaUv(g);
}

({double u, double v}) galacticVecToPanoramaUv(Vec3 galactic) {
  final lRad = math.atan2(galactic.y, galactic.x); // [-pi, +pi]
  final bRad = math.asin(galactic.z.clamp(-1.0, 1.0)); // [-pi/2, +pi/2]
  var u = 0.5 - lRad / (2 * math.pi);
  u = u - u.floorToDouble();
  final v = (0.5 - bRad / math.pi).clamp(0.0, 1.0);
  return (u: u, v: v);
}

/// Great-circle angular separation between two unit vectors, in degrees [0, 180].
double angularSeparationDeg(Vec3 a, Vec3 b) {
  final d = a.normalized.dot(b.normalized).clamp(-1.0, 1.0);
  return math.acos(d) * radToDeg;
}

/// Rotate an ENU vector clockwise (seen from above) by [deg] so magnetic north becomes true north.
/// Matches `_rotate_about_up` in `backend/solver/astro.py`.
Vec3 rotateEnuClockwiseAboutUp(Vec3 v, double deg) {
  final r = deg * degToRad;
  final c = math.cos(r), s = math.sin(r);
  return Vec3(v.x * c + v.y * s, -v.x * s + v.y * c, v.z);
}

// --- Offline World Magnetic Model (WMM-2025, NOAA NCEI, degree N=6) ---------------------

const List<(int, int, double, double, double, double)> _wmm2025 = [
  (1, 0, -29351.8, 12.0, 0.0, 0.0),
  (1, 1, -1410.8, 9.7, 4545.4, -21.5),
  (2, 0, -2556.6, -11.6, 0.0, 0.0),
  (2, 1, 2951.1, -5.2, -3133.6, -27.7),
  (2, 2, 1649.3, -8.0, -815.1, -12.1),
  (3, 0, 1361.0, -1.3, 0.0, 0.0),
  (3, 1, -2404.1, -4.2, -56.6, 4.0),
  (3, 2, 1243.8, 0.4, 237.5, -0.3),
  (3, 3, 453.6, -15.6, -549.5, -4.1),
  (4, 0, 895.0, -1.6, 0.0, 0.0),
  (4, 1, 799.5, -2.4, 278.6, -1.1),
  (4, 2, 55.7, -6.0, -133.9, 4.1),
  (4, 3, -281.1, 5.6, 212.0, 1.6),
  (4, 4, 12.1, -7.0, -375.6, -4.4),
  (5, 0, -233.2, 0.6, 0.0, 0.0),
  (5, 1, 368.9, 1.4, 45.4, -0.5),
  (5, 2, 187.2, 0.0, 220.2, 2.2),
  (5, 3, -138.7, 0.6, -122.9, 0.4),
  (5, 4, -142.0, 2.2, 43.0, 1.7),
  (5, 5, 20.9, 0.9, 106.1, 1.9),
  (6, 0, 64.4, -0.2, 0.0, 0.0),
  (6, 1, 63.8, -0.4, -18.4, 0.3),
  (6, 2, 76.9, 0.9, 16.8, -1.6),
  (6, 3, -115.7, 1.2, 48.8, -0.4),
  (6, 4, -40.9, -0.9, -59.8, 0.9),
  (6, 5, 14.9, 0.3, 10.9, 0.7),
  (6, 6, -60.7, 0.9, 72.7, 0.9),
  (7, 0, 79.5, 0.0, 0.0, 0.0),
  (7, 1, -77.0, -0.1, -48.9, 0.6),
  (7, 2, -8.8, -0.1, -14.4, 0.5),
  (7, 3, 59.3, 0.5, -1.0, -0.8),
  (7, 4, 15.8, -0.1, 23.4, 0.0),
  (7, 5, 2.5, -0.8, -7.4, -1.0),
  (7, 6, -11.1, -0.8, -25.1, 0.6),
  (7, 7, 14.2, 0.8, -2.3, -0.2),
  (8, 0, 23.2, -0.1, 0.0, 0.0),
  (8, 1, 10.8, 0.2, 7.1, -0.2),
  (8, 2, -17.5, 0.0, -12.6, 0.5),
  (8, 3, 2.0, 0.5, 11.4, -0.4),
  (8, 4, -21.7, -0.1, -9.7, 0.4),
  (8, 5, 16.9, 0.3, 12.7, -0.5),
  (8, 6, 15.0, 0.2, 0.7, -0.6),
  (8, 7, -16.8, 0.0, -5.2, 0.3),
  (8, 8, 0.9, 0.2, 3.9, 0.2),
];

/// Offline magnetic declination in degrees (east positive) from NOAA WMM-2025 (degree 8).
/// Converts magnetic-north phone compass headings to true astronomical north without network.
double magneticDeclinationDeg({
  required double latitudeDeg,
  required double longitudeDeg,
  required DateTime when,
}) {
  final utc = when.toUtc();
  final decimalYear = utc.year +
      utc.difference(DateTime.utc(utc.year)).inHours / (365.25 * 24.0);
  final dt = (decimalYear - 2025.0).clamp(-10.0, 15.0);

  const a = 6378.137;
  const f = 1.0 / 298.257223563;
  const e2 = f * (2.0 - f);
  const r0 = 6371.2;

  final phi = latitudeDeg.clamp(-89.5, 89.5) * degToRad;
  final lam = longitudeDeg * degToRad;
  final sp = math.sin(phi), cp = math.cos(phi);
  final rc = a / math.sqrt(1.0 - e2 * sp * sp);
  final xp = rc * cp;
  final zp = rc * (1.0 - e2) * sp;
  final r = math.sqrt(xp * xp + zp * zp);
  final spC = zp / r;
  final cpC = math.max(1e-8, xp / r);
  final phiC = math.asin(spC.clamp(-1.0, 1.0));

  final p = List.generate(9, (_) => List<double>.filled(9, 0));
  final dp = List.generate(9, (_) => List<double>.filled(9, 0));
  p[0][0] = 1.0;

  for (var n = 1; n <= 8; n++) {
    final fnn = n == 1 ? 1.0 : math.sqrt((2 * n - 1) / (2 * n));
    p[n][n] = fnn * cpC * p[n - 1][n - 1];
    dp[n][n] = fnn * (cpC * dp[n - 1][n - 1] - spC * p[n - 1][n - 1]);
    for (var m = 0; m < n; m++) {
      final denom = math.sqrt((n * n - m * m).toDouble());
      final k2 = n - 1 > m ? math.sqrt(((n - 1) * (n - 1) - m * m).toDouble()) : 0.0;
      final pPrev2 = n >= 2 ? p[n - 2][m] : 0.0;
      final dpPrev2 = n >= 2 ? dp[n - 2][m] : 0.0;
      p[n][m] = ((2 * n - 1) * spC * p[n - 1][m] - k2 * pPrev2) / denom;
      dp[n][m] =
          ((2 * n - 1) * (spC * dp[n - 1][m] + cpC * p[n - 1][m]) - k2 * dpPrev2) / denom;
    }
  }

  var xPrime = 0.0, yPrime = 0.0, zPrime = 0.0;
  for (final (n, m, g0, dg, h0, dh) in _wmm2025) {
    final g = g0 + dg * dt;
    final h = h0 + dh * dt;
    final ratio = math.pow(r0 / r, n + 2).toDouble();
    final cm = math.cos(m * lam), sm = math.sin(m * lam);
    final gh = g * cm + h * sm;
    xPrime += -ratio * gh * dp[n][m];
    yPrime += ratio * m * (g * sm - h * cm) * p[n][m] / cpC;
    zPrime += -(n + 1) * ratio * gh * p[n][m];
  }

  final psi = phiC - phi;
  final north = xPrime * math.cos(psi) - zPrime * math.sin(psi);
  final east = yPrime;
  return math.atan2(east, north) * radToDeg;
}

// --- 3D Sky Camera (perspective projection + sensor/manual pose) ------------------------

/// Complete 3D viewing state for one rendered Sky View frame.
@immutable
class SkyCamera {
  SkyCamera._({
    required this.forwardEnu,
    required this.rightEnu,
    required this.upEnu,
    required this.latitudeDeg,
    required this.longitudeDeg,
    required this.when,
    required this.fovDeg,
    required this.enuToIcrs,
  })  : forwardIcrs = enuToIcrs.transform(forwardEnu).normalized,
        rightIcrs = enuToIcrs.transform(rightEnu).normalized,
        upIcrs = enuToIcrs.transform(upEnu).normalized,
        zenithIcrs = enuToIcrs.transform(Vec3.up).normalized,
        tanHalfFov = math.tan((fovDeg.clamp(15.0, 110.0) * 0.5) * degToRad) {
    forwardGal = icrsToGalacticMatrix.transform(forwardIcrs).normalized;
    rightGal = icrsToGalacticMatrix.transform(rightIcrs).normalized;
    upGal = icrsToGalacticMatrix.transform(upIcrs).normalized;
    zenithGal = icrsToGalacticMatrix.transform(zenithIcrs).normalized;
  }

  /// Camera basis in true-north ENU coordinates.
  final Vec3 forwardEnu;
  final Vec3 rightEnu;
  final Vec3 upEnu;

  final double latitudeDeg;
  final double longitudeDeg;
  final DateTime when;

  /// Horizontal field of view in degrees.
  final double fovDeg;
  final double tanHalfFov;

  final Mat3 enuToIcrs;
  final Vec3 forwardIcrs;
  final Vec3 rightIcrs;
  final Vec3 upIcrs;
  final Vec3 zenithIcrs;

  late final Vec3 forwardGal;
  late final Vec3 rightGal;
  late final Vec3 upGal;
  late final Vec3 zenithGal;

  /// Build camera from a phone orientation quaternion `[x, y, z, w]` (device -> magnetic ENU),
  /// applying [declinationDeg] to align with true astronomical north.
  factory SkyCamera.fromSensorQuaternion({
    required List<double> quaternion,
    required double declinationDeg,
    required double latitudeDeg,
    required double longitudeDeg,
    required DateTime when,
    required double fovDeg,
  }) {
    final r = quaternionToMatrix(quaternion);
    // Device axes: +X right, +Y top of portrait screen, -Z rear viewing direction.
    final rawRight = Vec3(r[0], r[3], r[6]);
    final rawUp = Vec3(r[1], r[4], r[7]);
    final rawForward = Vec3(-r[2], -r[5], -r[8]);

    final forward = rotateEnuClockwiseAboutUp(rawForward, declinationDeg).normalized;
    final upTemp = rotateEnuClockwiseAboutUp(rawUp, declinationDeg).normalized;
    final right = forward.cross(upTemp).normalized.length > 1e-6
        ? forward.cross(upTemp).normalized
        : rotateEnuClockwiseAboutUp(rawRight, declinationDeg).normalized;
    final up = right.cross(forward).normalized;

    final enuToIcrs = icrsToEnuMatrix(
      latitudeDeg: latitudeDeg,
      longitudeDeg: longitudeDeg,
      when: when,
    ).transposed;

    return SkyCamera._(
      forwardEnu: forward,
      rightEnu: right,
      upEnu: up,
      latitudeDeg: latitudeDeg,
      longitudeDeg: longitudeDeg,
      when: when,
      fovDeg: fovDeg,
      enuToIcrs: enuToIcrs,
    );
  }

  /// Build an upright horizon-level camera looking towards ([altitudeDeg], [azimuthDeg]) for
  /// manual touch drag mode or tests.
  factory SkyCamera.fromAltAz({
    required double altitudeDeg,
    required double azimuthDeg,
    required double latitudeDeg,
    required double longitudeDeg,
    required DateTime when,
    double fovDeg = 60.0,
  }) {
    final clampedAlt = altitudeDeg.clamp(-89.8, 89.8);
    final forward = altAzToEnu(clampedAlt, azimuthDeg).normalized;
    // Right = forward x worldUp keeps the horizon horizontal across all azimuths.
    var right = forward.cross(Vec3.up);
    if (right.length < 1e-6) {
      final azRad = azimuthDeg * degToRad;
      right = Vec3(math.cos(azRad), -math.sin(azRad), 0);
    } else {
      right = right.normalized;
    }
    final up = right.cross(forward).normalized;

    final enuToIcrs = icrsToEnuMatrix(
      latitudeDeg: latitudeDeg,
      longitudeDeg: longitudeDeg,
      when: when,
    ).transposed;

    return SkyCamera._(
      forwardEnu: forward,
      rightEnu: right,
      upEnu: up,
      latitudeDeg: latitudeDeg,
      longitudeDeg: longitudeDeg,
      when: when,
      fovDeg: fovDeg,
      enuToIcrs: enuToIcrs,
    );
  }

  ({double altitudeDeg, double azimuthDeg}) get centerAltAz => enuToAltAz(forwardEnu);
  ({double raDeg, double decDeg}) get centerRaDec => vecToRaDec(forwardIcrs);

  /// Project an ICRS J2000 unit vector onto screen pixel coordinates for [size], or null if
  /// behind the camera (`z <= 0.02`).
  Offset? projectIcrs(Vec3 icrs, Size size) {
    final z = icrs.dot(forwardIcrs);
    if (z <= 0.02) return null;
    final x = icrs.dot(rightIcrs) / (z * tanHalfFov);
    final y = icrs.dot(upIcrs) / (z * tanHalfFov);
    final halfW = size.width * 0.5;
    return Offset(halfW * (1.0 + x), size.height * 0.5 - halfW * y);
  }

  /// Project a local ENU unit vector (e.g. horizon ring, cardinal points) onto [size].
  Offset? projectEnu(Vec3 enu, Size size) {
    final z = enu.dot(forwardEnu);
    if (z <= 0.02) return null;
    final x = enu.dot(rightEnu) / (z * tanHalfFov);
    final y = enu.dot(upEnu) / (z * tanHalfFov);
    final halfW = size.width * 0.5;
    return Offset(halfW * (1.0 + x), size.height * 0.5 - halfW * y);
  }

  /// Unproject a screen tap [point] in [size] back into a unit ICRS J2000 ray direction.
  Vec3 unprojectToIcrs(Offset point, Size size) {
    final halfW = size.width * 0.5;
    final nx = (point.dx - halfW) / halfW;
    final ny = (size.height * 0.5 - point.dy) / halfW;
    return (forwardIcrs + rightIcrs * (nx * tanHalfFov) + upIcrs * (ny * tanHalfFov)).normalized;
  }

  /// Direction in screen plane (`dx` right, `dy` down, unit vector) + angular distance in
  /// degrees from the centre of view towards [targetIcrs]. Works all the way to 180° behind
  /// the user, powering the "Find object" guide arrow.
  ({Offset screenDir, double angleDeg, Offset? onScreen}) guideTowards(Vec3 targetIcrs, Size size) {
    final u = targetIcrs.normalized;
    final angle = angularSeparationDeg(forwardIcrs, u);
    final projected = projectIcrs(u, size);
    final inBounds = projected != null &&
        projected.dx >= 24 &&
        projected.dx <= size.width - 24 &&
        projected.dy >= 24 &&
        projected.dy <= size.height - 24;

    var rx = u.dot(rightIcrs);
    var ry = -u.dot(upIcrs); // screen Y points down
    final norm = math.sqrt(rx * rx + ry * ry);
    final dir = norm < 1e-6 ? const Offset(1, 0) : Offset(rx / norm, ry / norm);
    return (screenDir: dir, angleDeg: angle, onScreen: inBounds ? projected : null);
  }
}

double _wrap360(double deg) {
  final r = deg % 360.0;
  return r < 0 ? r + 360.0 : r;
}
