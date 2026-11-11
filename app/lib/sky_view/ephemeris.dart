import 'dart:math' as math;
import 'dart:ui' show Color;

import 'astro_math.dart';
import 'sky_catalog.dart';

/// Mean J2000.0 obliquity of the ecliptic in degrees (IAU).
const double _obliquityJ2000Deg = 23.439291111;

/// Speed of light in AU per day (for planetary light-time aberration).
const double _lightSpeedAuPerDay = 173.144632674;

/// JPL Keplerian orbital elements and century rates referenced to the J2000.0 ecliptic and
/// equinox (Standish 1992, NASA JPL Solar System Dynamics Table 1, valid 1800–2050 AD).
/// Columns: (a0, aDot, e0, eDot, i0, iDot, L0, LDot, wBar0, wBarDot, node0, nodeDot).
class _PlanetElements {
  const _PlanetElements({
    required this.id,
    required this.name,
    required this.color,
    required this.hMag,
    required this.summary,
    required this.a0,
    required this.aDot,
    required this.e0,
    required this.eDot,
    required this.i0,
    required this.iDot,
    required this.l0,
    required this.lDot,
    required this.wBar0,
    required this.wBarDot,
    required this.node0,
    required this.nodeDot,
  });

  final String id;
  final String name;
  final Color color;
  final double hMag; // absolute magnitude V(1,0)
  final String summary;
  final double a0, aDot;
  final double e0, eDot;
  final double i0, iDot;
  final double l0, lDot;
  final double wBar0, wBarDot;
  final double node0, nodeDot;
}

const _earthElements = _PlanetElements(
  id: 'EARTH',
  name: 'Earth',
  color: Color(0xFFFFFFFF),
  hMag: 0,
  summary: '',
  a0: 1.00000261, aDot: 0.00000562,
  e0: 0.01671123, eDot: -0.00004392,
  i0: -0.00001531, iDot: -0.01294668,
  l0: 100.46457166, lDot: 35999.37244981,
  wBar0: 102.93768193, wBarDot: 0.32327364,
  node0: 0.0, nodeDot: 0.0,
);

const List<_PlanetElements> _planets = [
  _PlanetElements(
    id: 'SOL-MERCURY',
    name: 'Mercury',
    color: Color(0xFFD5D2CC),
    hMag: -0.60,
    summary: 'Innermost rocky planet; stays within 28° of the Sun in dawn or dusk twilight.',
    a0: 0.38709927, aDot: 0.00000037,
    e0: 0.20563593, eDot: 0.00001906,
    i0: 7.00497902, iDot: -0.00594749,
    l0: 252.25032350, lDot: 149472.67411175,
    wBar0: 77.45779628, wBarDot: 0.16047689,
    node0: 48.33076593, nodeDot: -0.12534081,
  ),
  _PlanetElements(
    id: 'SOL-VENUS',
    name: 'Venus',
    color: Color(0xFFFFF4D6),
    hMag: -4.47,
    summary: 'Cloud-shrouded terrestrial world and brightest planet ("Morning" or "Evening Star").',
    a0: 0.72333566, aDot: 0.00000390,
    e0: 0.00677672, eDot: -0.00004107,
    i0: 3.39467605, iDot: -0.00078890,
    l0: 181.97909950, lDot: 58517.81538729,
    wBar0: 131.60246718, wBarDot: 0.00268329,
    node0: 76.67984255, nodeDot: -0.27769418,
  ),
  _PlanetElements(
    id: 'SOL-MARS',
    name: 'Mars',
    color: Color(0xFFFF9E73),
    hMag: -1.52,
    summary: 'The Red Planet — iron-oxide deserts, polar ice caps, and canyon system Valles Marineris.',
    a0: 1.52371034, aDot: 0.00001847,
    e0: 0.09339410, eDot: 0.00007882,
    i0: 1.84969142, iDot: -0.00813131,
    l0: -4.55343205, lDot: 19140.30268499,
    wBar0: -23.94362959, wBarDot: 0.44441088,
    node0: 49.55953891, nodeDot: -0.29257343,
  ),
  _PlanetElements(
    id: 'SOL-JUPITER',
    name: 'Jupiter',
    color: Color(0xFFFFE3B3),
    hMag: -9.40,
    summary: 'Largest planet in the Solar System; binoculars reveal its four Galilean moons.',
    a0: 5.20288700, aDot: -0.00011607,
    e0: 0.04838624, eDot: -0.00013253,
    i0: 1.30439695, iDot: -0.00183714,
    l0: 34.39644051, lDot: 3034.74612775,
    wBar0: 14.72847983, wBarDot: 0.21252668,
    node0: 100.47390909, nodeDot: 0.20469106,
  ),
  _PlanetElements(
    id: 'SOL-SATURN',
    name: 'Saturn',
    color: Color(0xFFF7DFA0),
    hMag: -8.88,
    summary: 'Gas giant famous for its icy ring system and giant hazy moon Titan.',
    a0: 9.53667594, aDot: -0.00125060,
    e0: 0.05386179, eDot: -0.00050991,
    i0: 2.48599187, iDot: 0.00193609,
    l0: 49.95424423, lDot: 1222.49362201,
    wBar0: 92.59887831, wBarDot: -0.41897216,
    node0: 113.66242448, nodeDot: -0.28867794,
  ),
  _PlanetElements(
    id: 'SOL-URANUS',
    name: 'Uranus',
    color: Color(0xFFACEBF2),
    hMag: -7.19,
    summary: 'Ice giant orbiting on its side (~98° axial tilt), right at the naked-eye limit under dark skies.',
    a0: 19.18916464, aDot: -0.00196176,
    e0: 0.04725744, eDot: -0.00004397,
    i0: 0.77263783, iDot: -0.00242939,
    l0: 313.23810451, lDot: 428.48202785,
    wBar0: 170.95427630, wBarDot: 0.40805281,
    node0: 74.01692503, nodeDot: 0.04240589,
  ),
  _PlanetElements(
    id: 'SOL-NEPTUNE',
    name: 'Neptune',
    color: Color(0xFF7FA9FF),
    hMag: -6.87,
    summary: 'Outermost major planet (~30 AU), a deep-azure ice giant requiring binoculars or a telescope.',
    a0: 30.06992276, aDot: 0.00026291,
    e0: 0.00859048, eDot: 0.00005105,
    i0: 1.77004347, iDot: 0.00035372,
    l0: -55.12002969, lDot: 218.45945325,
    wBar0: 44.96476227, wBarDot: -0.32241464,
    node0: 131.78422574, nodeDot: -0.00508664,
  ),
];

/// Complete Solar System snapshot for a given time and observer location.
class SolarSystemSnapshot {
  const SolarSystemSnapshot({
    required this.sun,
    required this.moon,
    required this.planets,
    required this.sunAltitudeDeg,
    required this.waxingMoon,
  });

  final SkyObject sun;
  final SkyObject moon;
  final List<SkyObject> planets;
  final double sunAltitudeDeg;
  final bool waxingMoon;

  List<SkyObject> get allBodies => [sun, moon, ...planets];
}

/// Compute offline positions for the Sun, Moon (topocentric, with phase), and Mercury–Neptune.
SolarSystemSnapshot computeSolarSystem({
  required DateTime when,
  required double latitudeDeg,
  required double longitudeDeg,
}) {
  final tCent = julianCenturiesJ2000(when);
  final earthHelio = _heliocentricEclipticJ2000(_earthElements, tCent);

  // --- Sun (geocentric J2000 = -earthHelio) ---
  final sunGeoEcl = -earthHelio;
  final sunDistAu = sunGeoEcl.length;
  final sunIcrs = _eclipticJ2000ToIcrs(sunGeoEcl).normalized;
  final sunRaDec = vecToRaDec(sunIcrs);
  final sunHor = raDecToAltAz(
    raDeg: sunRaDec.raDeg,
    decDeg: sunRaDec.decDeg,
    latitudeDeg: latitudeDeg,
    longitudeDeg: longitudeDeg,
    when: when,
  );
  final sunObj = SkyObject(
    id: 'SOL-SUN',
    name: 'Sun',
    kind: SkyBodyKind.sun,
    typeLabel: 'Star (G2V)',
    icrs: sunIcrs,
    raDeg: sunRaDec.raDeg,
    decDeg: sunRaDec.decDeg,
    magnitude: -26.74,
    distanceAu: sunDistAu,
    sizeArcmin: 31.99 / sunDistAu,
    color: const Color(0xFFFFD97D),
    summary: 'Never point eyes, binoculars, or cameras directly at the Sun without certified solar filters.',
  );

  // --- Moon (Meeus Ch. 47 periodic terms + topocentric parallax) ---
  final (moonObj, waxing) = _computeMoon(
    when: when,
    tCent: tCent,
    latitudeDeg: latitudeDeg,
    longitudeDeg: longitudeDeg,
    sunIcrs: sunIcrs,
    sunDistAu: sunDistAu,
  );

  // --- Planets (Mercury .. Neptune, light-time corrected) ---
  final planetObjs = <SkyObject>[];
  for (final p in _planets) {
    var helio = _heliocentricEclipticJ2000(p, tCent);
    var geo = helio - earthHelio;
    final dist0 = geo.length;
    // One light-time iteration (~minutes for outer planets).
    final tRetarded = tCent - (dist0 / _lightSpeedAuPerDay) / 36525.0;
    helio = _heliocentricEclipticJ2000(p, tRetarded);
    geo = helio - earthHelio;

    final delta = geo.length;
    final rSun = helio.length;
    final icrs = _eclipticJ2000ToIcrs(geo).normalized;
    final rd = vecToRaDec(icrs);

    // Phase angle i between Sun-Planet and Earth-Planet vectors.
    final cosPhase = ((rSun * rSun + delta * delta - sunDistAu * sunDistAu) /
            (2.0 * rSun * delta))
        .clamp(-1.0, 1.0);
    final phaseDeg = math.acos(cosPhase) * radToDeg;
    final illum = 0.5 * (1.0 + cosPhase);
    final vMag = _planetMagnitude(p.id, p.hMag, rSun, delta, phaseDeg);

    planetObjs.add(
      SkyObject(
        id: p.id,
        name: p.name,
        kind: SkyBodyKind.planet,
        typeLabel: 'Planet',
        icrs: icrs,
        raDeg: rd.raDeg,
        decDeg: rd.decDeg,
        magnitude: vMag,
        distanceAu: delta,
        phaseFraction: illum,
        color: p.color,
        summary: p.summary,
      ),
    );
  }

  return SolarSystemSnapshot(
    sun: sunObj,
    moon: moonObj,
    planets: planetObjs,
    sunAltitudeDeg: sunHor.altitudeDeg,
    waxingMoon: waxing,
  );
}

Vec3 _heliocentricEclipticJ2000(_PlanetElements p, double t) {
  final a = p.a0 + p.aDot * t;
  final e = (p.e0 + p.eDot * t).clamp(0.0, 0.95);
  final inc = (p.i0 + p.iDot * t) * degToRad;
  final lMean = p.l0 + p.lDot * t;
  final wBar = p.wBar0 + p.wBarDot * t;
  final node = p.node0 + p.nodeDot * t;

  final argPeri = (wBar - node) * degToRad;
  final nodeRad = node * degToRad;
  var mRad = ((lMean - wBar) % 360.0) * degToRad;
  if (mRad > math.pi) mRad -= 2 * math.pi;
  if (mRad < -math.pi) mRad += 2 * math.pi;

  // Solve Kepler's equation M = E - e sin(E).
  var ecc = mRad + e * math.sin(mRad);
  for (var iter = 0; iter < 6; iter++) {
    final dM = mRad - (ecc - e * math.sin(ecc));
    ecc += dM / (1.0 - e * math.cos(ecc));
  }

  final xOrb = a * (math.cos(ecc) - e);
  final yOrb = a * math.sqrt(1.0 - e * e) * math.sin(ecc);

  final cw = math.cos(argPeri), sw = math.sin(argPeri);
  final cn = math.cos(nodeRad), sn = math.sin(nodeRad);
  final ci = math.cos(inc), si = math.sin(inc);

  final x = (cw * cn - sw * sn * ci) * xOrb + (-sw * cn - cw * sn * ci) * yOrb;
  final y = (cw * sn + sw * cn * ci) * xOrb + (-sw * sn + cw * cn * ci) * yOrb;
  final z = (sw * si) * xOrb + (cw * si) * yOrb;
  return Vec3(x, y, z);
}

Vec3 _eclipticJ2000ToIcrs(Vec3 ecl) {
  final eps = _obliquityJ2000Deg * degToRad;
  final ce = math.cos(eps), se = math.sin(eps);
  return Vec3(
    ecl.x,
    ecl.y * ce - ecl.z * se,
    ecl.y * se + ecl.z * ce,
  );
}

double _planetMagnitude(String id, double hMag, double r, double delta, double phaseDeg) {
  final base = hMag + 5.0 * (math.log(r * delta) / math.ln10);
  final p = phaseDeg / 100.0;
  final phaseTerm = switch (id) {
    'SOL-MERCURY' => 3.80 * p - 2.73 * p * p + 2.00 * p * p * p,
    'SOL-VENUS' => 0.09 * p + 2.39 * p * p - 0.65 * p * p * p,
    'SOL-MARS' => 1.60 * p,
    'SOL-JUPITER' => 0.50 * p,
    'SOL-SATURN' => 0.44 * p - 0.35, // average ring contribution
    _ => 0.0,
  };
  return double.parse((base + phaseTerm).toStringAsFixed(2));
}

(SkyObject, bool) _computeMoon({
  required DateTime when,
  required double tCent,
  required double latitudeDeg,
  required double longitudeDeg,
  required Vec3 sunIcrs,
  required double sunDistAu,
}) {
  final t = tCent;
  final t2 = t * t;
  final t3 = t2 * t;

  double rad(double deg) => (deg % 360.0) * degToRad;

  // Fundamental arguments (Meeus Ch. 47, degrees).
  final lPrime = 218.3164477 + 481267.88123421 * t - 0.0015786 * t2 + t3 / 538841.0;
  final d = 297.8501921 + 445267.1114034 * t - 0.0018819 * t2 + t3 / 545868.0;
  final mSun = 357.5291092 + 35999.0502909 * t - 0.0001536 * t2;
  final mMoon = 134.9633964 + 477198.8675055 * t + 0.0087414 * t2 + t3 / 69699.0;
  final f = 93.2720950 + 483202.0175233 * t - 0.0036539 * t2;

  final dR = rad(d), mSR = rad(mSun), mMR = rad(mMoon), fR = rad(f);

  // Dominant periodic longitude terms (degrees).
  final dLon = 6.288774 * math.sin(mMR) +
      1.274027 * math.sin(2 * dR - mMR) +
      0.658314 * math.sin(2 * dR) +
      0.213618 * math.sin(2 * mMR) -
      0.185116 * math.sin(mSR) -
      0.114332 * math.sin(2 * fR) +
      0.058793 * math.sin(2 * dR - 2 * mMR) +
      0.057066 * math.sin(2 * dR - mSR - mMR) +
      0.053322 * math.sin(2 * dR + mMR) +
      0.045758 * math.sin(2 * dR - mSR) -
      0.040923 * math.sin(mSR - mMR) -
      0.034720 * math.sin(dR) -
      0.030383 * math.sin(mSR + mMR);

  // Dominant periodic latitude terms (degrees).
  final dLat = 5.128122 * math.sin(fR) +
      0.280602 * math.sin(mMR + fR) +
      0.277693 * math.sin(mMR - fR) +
      0.173237 * math.sin(2 * dR - fR) +
      0.055413 * math.sin(2 * dR - mMR + fR) +
      0.046271 * math.sin(2 * dR - mMR - fR) +
      0.032573 * math.sin(2 * dR + fR);

  // Geocentric distance in km.
  final distKm = 385000.56 -
      20905.355 * math.cos(mMR) -
      3699.111 * math.cos(2 * dR - mMR) -
      2955.968 * math.cos(2 * dR) -
      569.925 * math.cos(2 * mMR);

  final lamRad = rad(lPrime + dLon);
  final betaRad = dLat * degToRad;
  final epsRad = (23.439291 - 0.0130042 * t) * degToRad;

  final cb = math.cos(betaRad), sb = math.sin(betaRad);
  final cl = math.cos(lamRad), sl = math.sin(lamRad);
  final ce = math.cos(epsRad), se = math.sin(epsRad);

  // Apparent geocentric equatorial unit vector of date, scaled to Earth radii for topocentric shift.
  const earthRadiusKm = 6378.14;
  final rhoEr = distKm / earthRadiusKm;
  final xDate = rhoEr * cb * cl;
  final yDate = rhoEr * (cb * sl * ce - sb * se);
  final zDate = rhoEr * (cb * sl * se + sb * ce);

  // Observer geocentric equatorial vector in Earth radii (date frame).
  final lst = lstDeg(when, longitudeDeg) * degToRad;
  final lat = latitudeDeg * degToRad;
  final obsX = math.cos(lat) * math.cos(lst);
  final obsY = math.cos(lat) * math.sin(lst);
  final obsZ = math.sin(lat);

  final topoDate = Vec3(xDate - obsX, yDate - obsY, zDate - obsZ);
  final topoDistKm = topoDate.length * earthRadiusKm;

  // Rotate from equator/equinox of date back to J2000 ICRS so SkyCamera projects everything in one frame.
  final dateToJ2000 = precessionJ2000ToDate(when).transposed;
  final moonIcrs = dateToJ2000.transform(topoDate.normalized).normalized;
  final rd = vecToRaDec(moonIcrs);

  // Elongation & lunar phase.
  final cosPsi = moonIcrs.dot(sunIcrs).clamp(-1.0, 1.0);
  final psiRad = math.acos(cosPsi);
  const auKm = 149597870.7;
  final sunDistKm = sunDistAu * auKm;
  final phaseAngle = math.atan2(
    sunDistKm * math.sin(psiRad),
    topoDistKm - sunDistKm * math.cos(psiRad),
  );
  final illum = 0.5 * (1.0 + math.cos(phaseAngle));
  var synodicDeg = (d % 360.0);
  if (synodicDeg < 0) synodicDeg += 360.0;
  final waxing = synodicDeg < 180.0;
  final phaseName = _lunarPhaseLabel(synodicDeg, illum);

  // Visual magnitude from phase angle (Allen / Meeus).
  final phaseDeg = phaseAngle * radToDeg;
  final vMag = -12.73 + 0.026 * phaseDeg + 4e-9 * math.pow(phaseDeg, 4);
  final sizeArcmin = (2.0 * math.asin(1737.4 / topoDistKm) * radToDeg) * 60.0;

  final moon = SkyObject(
    id: 'SOL-MOON',
    name: 'Moon',
    kind: SkyBodyKind.moon,
    typeLabel: 'Natural satellite',
    icrs: moonIcrs,
    raDeg: rd.raDeg,
    decDeg: rd.decDeg,
    magnitude: double.parse(vMag.toStringAsFixed(1)),
    distanceAu: topoDistKm / auKm,
    sizeArcmin: sizeArcmin,
    phaseFraction: illum,
    phaseLabel: phaseName,
    color: const Color(0xFFF2EFE4),
    summary: '$phaseName (${(illum * 100).round()}% illuminated) · '
        '${(topoDistKm / 1000).round()},000 km from Earth.',
  );
  return (moon, waxing);
}

String _lunarPhaseLabel(double synodicDeg, double illum) {
  if (illum < 0.03) return 'New Moon';
  if (illum > 0.97) return 'Full Moon';
  if ((synodicDeg - 90.0).abs() < 12.0) return 'First Quarter';
  if ((synodicDeg - 270.0).abs() < 12.0) return 'Last Quarter';
  if (synodicDeg < 90.0) return 'Waxing Crescent';
  if (synodicDeg < 180.0) return 'Waxing Gibbous';
  if (synodicDeg < 270.0) return 'Waning Gibbous';
  return 'Waning Crescent';
}
