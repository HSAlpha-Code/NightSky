import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../curated.dart';
import '../models.dart';
import '../screens/landmark_detail_screen.dart';
import '../sensors.dart';
import '../settings.dart';
import '../sky_math.dart';
import '../widgets/camera_hints.dart';
import '../widgets/curated_viewer.dart';
import 'astro_math.dart';
import 'ephemeris.dart';
import 'sky_catalog.dart';
import 'sky_overlay_painter.dart';

// --- 1. Object Detail Bottom Sheet ------------------------------------------------------

class SkyObjectSheet extends ConsumerWidget {
  const SkyObjectSheet({
    super.key,
    required this.object,
    required this.latitudeDeg,
    required this.longitudeDeg,
    required this.when,
    required this.manualMode,
    required this.onGuide,
    required this.onCenterHere,
  });

  final SkyObject object;
  final double latitudeDeg;
  final double longitudeDeg;
  final DateTime when;
  final bool manualMode;
  final VoidCallback onGuide;
  final VoidCallback onCenterHere;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hor = raDecToAltAz(
      raDeg: object.raDeg,
      decDeg: object.decDeg,
      latitudeDeg: latitudeDeg,
      longitudeDeg: longitudeDeg,
      when: when,
    );
    final above = hor.altitudeDeg >= 0;
    final compass = PointingReadout.compassPoint(hor.azimuthDeg);
    final altSign = hor.altitudeDeg >= 0 ? '+' : '−';
    final altText = '$altSign${hor.altitudeDeg.abs().toStringAsFixed(1)}° · '
        '$compass ${hor.azimuthDeg.round() % 360}° '
        '(${above ? 'above horizon' : 'below horizon'})';

    final hasCurated = ref.watch(curatedIndexProvider.select((i) => i?.has(object.id) ?? false));
    final landmark = object.toLandmark();

    final facts = <(String, String)>[
      ('Type', object.typeLabel),
      ('Sky position', altText),
      if (object.magnitude != null)
        ('Brightness', 'magnitude ${object.magnitude!.toStringAsFixed(2)}'),
      if (object.phaseLabel != null)
        ('Phase', '${object.phaseLabel!} (${((object.phaseFraction ?? 0) * 100).round()}%)')
      else if (object.phaseFraction != null && object.kind == SkyBodyKind.planet)
        ('Illuminated', '${(object.phaseFraction! * 100).round()}%'),
      if (object.distanceAu != null)
        (
          'Distance',
          object.kind == SkyBodyKind.moon
              ? '${(object.distanceAu! * 149597870.7).round()} km'
              : '${object.distanceAu!.toStringAsFixed(3)} AU',
        ),
      if (object.distanceLy != null) ('Distance', formatDistance(object.distanceLy!)),
      if (object.sizeArcmin != null && object.kind != SkyBodyKind.star)
        (
          'Apparent size',
          '${object.sizeArcmin!.toStringAsFixed(object.sizeArcmin! < 10 ? 1 : 0)}′',
        ),
      if (object.constellation.isNotEmpty) ('Constellation', object.constellation),
      ('RA / Dec', '${formatRa(object.raDeg)} · ${formatDec(object.decDeg)}'),
      if (object.aliases.isNotEmpty) ('Also known as', object.aliases.join(', ')),
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(color: object.color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(object.name, style: Theme.of(context).textTheme.titleLarge),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            if (object.summary.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(object.summary, style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: 14),
            if (hasCurated) ...[
              Card(
                key: const Key('sky-curated-link'),
                color: Colors.amber.withValues(alpha: 0.14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.amber.withValues(alpha: 0.6)),
                ),
                child: ListTile(
                  leading: const Icon(Icons.auto_awesome_motion, color: Colors.amber),
                  title: const Text(curatedSourceLabel),
                  subtitle: const Text('View hand-picked NASA / ESA imagery & story'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).pop();
                    if (landmark != null) {
                      ref
                          .read(detailPreferenceProvider.notifier)
                          .choose(const DetailView('curated', null, curatedSourceLabel));
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => LandmarkDetailScreen(landmark: landmark),
                        ),
                      );
                    } else {
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => _StandaloneCuratedSheet(
                          bodyId: object.id,
                          title: object.name,
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 10),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('object-guide-button'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    onGuide();
                  },
                  icon: const Icon(Icons.my_location, size: 18),
                  label: const Text('Guide me there'),
                ),
                if (manualMode)
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onCenterHere();
                    },
                    icon: const Icon(Icons.center_focus_strong, size: 18),
                    label: const Text('Center in view'),
                  ),
                if (landmark != null)
                  OutlinedButton.icon(
                    key: const Key('object-closeup-button'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => LandmarkDetailScreen(landmark: landmark),
                        ),
                      );
                    },
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: Text(
                      object.kind == SkyBodyKind.star ? 'Survey close-up' : 'Webb / Hubble close-up',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            for (final (label, value) in facts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3.5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 112,
                      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
                    ),
                    Expanded(child: Text(value)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StandaloneCuratedSheet extends ConsumerWidget {
  const _StandaloneCuratedSheet({required this.bodyId, required this.title});

  final String bodyId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final body = ref.watch(curatedBodyProvider(bodyId));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            body.when(
              loading: () => const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load highlights: $e'),
              ),
              data: (b) => CuratedViewer(highlights: b.highlights),
            ),
          ],
        ),
      ),
    );
  }
}

// --- 2. Find / Search Celestial Object Sheet --------------------------------------------

enum _SearchCategory { visible, solarSystem, highlights, stars, constellations, deepSky }

class SkySearchSheet extends StatefulWidget {
  const SkySearchSheet({
    super.key,
    required this.catalog,
    required this.solarSystem,
    required this.curatedIds,
    required this.latitudeDeg,
    required this.longitudeDeg,
    required this.when,
    required this.onSelect,
  });

  final SkyCatalog? catalog;
  final SolarSystemSnapshot solarSystem;
  final Set<String> curatedIds;
  final double latitudeDeg;
  final double longitudeDeg;
  final DateTime when;
  final ValueChanged<SkyObject> onSelect;

  @override
  State<SkySearchSheet> createState() => _SkySearchSheetState();
}

class _SkySearchSheetState extends State<SkySearchSheet> {
  final _queryController = TextEditingController();
  _SearchCategory _category = _SearchCategory.visible;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  List<(SkyObject, double, double)> _buildResults() {
    final q = _queryController.text.trim().toLowerCase();
    final cat = widget.catalog;
    final candidates = <SkyObject>[
      ...widget.solarSystem.allBodies,
      if (cat != null) ...[
        for (final idx in cat.namedStarIndices) cat.starObjectAt(idx),
        ...cat.deepSkyObjects,
        for (final c in cat.constellations) cat.constellationObject(c),
      ],
    ];

    final m = icrsToEnuMatrix(
      latitudeDeg: widget.latitudeDeg,
      longitudeDeg: widget.longitudeDeg,
      when: widget.when,
    );

    final matched = <(SkyObject, double, double)>[];
    for (final obj in candidates) {
      if (q.isEmpty) {
        final keep = switch (_category) {
          _SearchCategory.visible => obj.kind == SkyBodyKind.planet ||
              obj.kind == SkyBodyKind.moon ||
              widget.curatedIds.contains(obj.id) ||
              (obj.kind == SkyBodyKind.star && (obj.magnitude ?? 9) < 1.6) ||
              (obj.messier != null && (obj.magnitude ?? 9) < 6.2),
          _SearchCategory.solarSystem =>
            obj.kind == SkyBodyKind.sun || obj.kind == SkyBodyKind.moon || obj.kind == SkyBodyKind.planet,
          _SearchCategory.highlights =>
            widget.curatedIds.contains(obj.id) || (obj.messier != null && (obj.magnitude ?? 9) < 6.5),
          _SearchCategory.stars => obj.kind == SkyBodyKind.star && (obj.magnitude ?? 9) < 3.0,
          _SearchCategory.constellations => obj.kind == SkyBodyKind.constellation,
          _SearchCategory.deepSky => obj.kind == SkyBodyKind.dso,
        };
        if (!keep) continue;
      } else {
        final hay = [
          obj.name.toLowerCase(),
          obj.id.toLowerCase(),
          obj.typeLabel.toLowerCase(),
          for (final a in obj.aliases) a.toLowerCase(),
        ];
        if (!hay.any((h) => h.contains(q))) continue;
      }

      final hor = enuToAltAz(m.transform(obj.icrs));
      if (q.isEmpty && _category == _SearchCategory.visible && hor.altitudeDeg < 2.0) {
        continue;
      }
      matched.add((obj, hor.altitudeDeg, hor.azimuthDeg));
    }

    matched.sort((a, b) {
      if (q.isNotEmpty) {
        final aExact = a.$1.name.toLowerCase() == q ||
            a.$1.aliases.any((al) => al.toLowerCase() == q);
        final bExact = b.$1.name.toLowerCase() == q ||
            b.$1.aliases.any((al) => al.toLowerCase() == q);
        if (aExact != bExact) return aExact ? -1 : 1;
        final aStarts = a.$1.name.toLowerCase().startsWith(q);
        final bStarts = b.$1.name.toLowerCase().startsWith(q);
        if (aStarts != bStarts) return aStarts ? -1 : 1;
      }
      final aUp = a.$2 >= 0;
      final bUp = b.$2 >= 0;
      if (aUp != bUp) return aUp ? -1 : 1;
      return (a.$1.magnitude ?? 5.0).compareTo(b.$1.magnitude ?? 5.0);
    });

    return matched.take(60).toList();
  }

  @override
  Widget build(BuildContext context) {
    final results = _buildResults();
    final labels = {
      _SearchCategory.visible: 'Up tonight',
      _SearchCategory.solarSystem: 'Solar System',
      _SearchCategory.highlights: 'Highlights',
      _SearchCategory.stars: 'Stars',
      _SearchCategory.constellations: 'Constellations',
      _SearchCategory.deepSky: 'Deep sky',
    };

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  key: const Key('sky-search-input'),
                  controller: _queryController,
                  autofocus: false,
                  decoration: InputDecoration(
                    hintText: 'Find planet, star, constellation, M31…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _queryController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(_queryController.clear),
                          ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (_queryController.text.trim().isEmpty)
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final c in _SearchCategory.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(labels[c]!),
                            selected: _category == c,
                            onSelected: (_) => setState(() => _category = c),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: results.isEmpty
                    ? const Center(child: Text('No matching sky objects.'))
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: results.length,
                        itemBuilder: (context, i) {
                          final (obj, alt, az) = results[i];
                          final up = alt >= 0;
                          final dir = PointingReadout.compassPoint(az);
                          final hasCurated = widget.curatedIds.contains(obj.id);
                          return ListTile(
                            leading: Icon(
                              switch (obj.kind) {
                                SkyBodyKind.sun => Icons.wb_sunny_outlined,
                                SkyBodyKind.moon => Icons.brightness_3,
                                SkyBodyKind.planet => Icons.public,
                                SkyBodyKind.star => Icons.star_rounded,
                                SkyBodyKind.dso => Icons.blur_circular,
                                SkyBodyKind.constellation => Icons.hub_outlined,
                              },
                              color: hasCurated ? Colors.amber : obj.color,
                            ),
                            title: Row(
                              children: [
                                Flexible(child: Text(obj.name, overflow: TextOverflow.ellipsis)),
                                if (hasCurated) ...[
                                  const SizedBox(width: 6),
                                  const Icon(Icons.auto_awesome_motion,
                                      size: 15, color: Colors.amber),
                                ],
                              ],
                            ),
                            subtitle: Text(
                              '${obj.typeLabel}'
                              '${obj.aliases.isNotEmpty ? ' · ${obj.aliases.first}' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(
                              up ? 'Alt +${alt.round()}° $dir' : 'Below horizon',
                              style: TextStyle(
                                fontSize: 12,
                                color: up ? Colors.greenAccent : Colors.white38,
                              ),
                            ),
                            onTap: () {
                              Navigator.of(context).pop();
                              widget.onSelect(obj);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// --- 3. Manual / GPS Location Picker Sheet ----------------------------------------------

class SkyLocationSheet extends ConsumerStatefulWidget {
  const SkyLocationSheet({
    super.key,
    required this.currentLat,
    required this.currentLon,
    required this.hasGpsFix,
    required this.onRequestGps,
  });

  final double currentLat;
  final double currentLon;
  final bool hasGpsFix;
  final VoidCallback onRequestGps;

  @override
  ConsumerState<SkyLocationSheet> createState() => _SkyLocationSheetState();
}

class _SkyLocationSheetState extends ConsumerState<SkyLocationSheet> {
  late final TextEditingController _latCtrl;
  late final TextEditingController _lonCtrl;
  late final TextEditingController _nameCtrl;
  String? _error;

  static const _presets = [
    ('Mauna Kea, Hawaii', 19.8207, -155.4681),
    ('Atacama (Paranal), Chile', -24.6272, -70.4042),
    ('Hanle Dark Sky Reserve, India', 32.7794, 78.9642),
    ('La Palma, Canary Islands', 28.7606, -17.8816),
    ('Greenwich, London', 51.4769, -0.0005),
    ('New York, USA', 40.7128, -74.0060),
    ('Tokyo, Japan', 35.6762, 139.6503),
    ('Sydney, Australia', -33.8688, 151.2093),
    ('Cape Town, South Africa', -33.9249, 18.4241),
  ];

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _latCtrl = TextEditingController(text: widget.currentLat.toStringAsFixed(4));
    _lonCtrl = TextEditingController(text: widget.currentLon.toStringAsFixed(4));
    _nameCtrl = TextEditingController(text: s.manualLocationName ?? '');
  }

  @override
  void dispose() {
    _latCtrl.dispose();
    _lonCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _saveManual({double? lat, double? lon, String? name}) {
    final parsedLat = lat ?? double.tryParse(_latCtrl.text.trim());
    final parsedLon = lon ?? double.tryParse(_lonCtrl.text.trim());
    if (parsedLat == null || parsedLat < -90 || parsedLat > 90) {
      setState(() => _error = 'Latitude must be between −90° and +90°.');
      return;
    }
    if (parsedLon == null || parsedLon < -180 || parsedLon > 180) {
      setState(() => _error = 'Longitude must be between −180° and +180°.');
      return;
    }
    final label = (name ?? _nameCtrl.text).trim();
    ref.read(settingsProvider.notifier).update(
          (s) => s.copyWith(
            useManualLocation: true,
            manualLatitude: parsedLat,
            manualLongitude: parsedLon,
            manualLocationName: label.isEmpty ? 'Custom location' : label,
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Observer location', style: Theme.of(context).textTheme.titleLarge),
                ),
                TextButton.icon(
                  key: const Key('use-gps-location'),
                  onPressed: () {
                    ref
                        .read(settingsProvider.notifier)
                        .update((st) => st.copyWith(useManualLocation: false));
                    widget.onRequestGps();
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.my_location, size: 18),
                  label: Text(widget.hasGpsFix ? 'Use GPS (ready)' : 'Use GPS'),
                ),
              ],
            ),
            Text(
              s.useManualLocation
                  ? 'Using manual coordinates (works completely offline).'
                  : 'Using phone GPS when available, or set coordinates manually below.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('manual-lat-input'),
                    controller: _latCtrl,
                    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Latitude (°N)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const Key('manual-lon-input'),
                    controller: _lonCtrl,
                    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Longitude (°E)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('manual-location-name'),
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Label (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.amber)),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('save-manual-location'),
                onPressed: _saveManual,
                child: const Text('Apply manual location'),
              ),
            ),
            const SizedBox(height: 16),
            Text('Offline presets', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final (name, lat, lon) in _presets)
                  ActionChip(
                    label: Text(name),
                    onPressed: () => _saveManual(lat: lat, lon: lon, name: name),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// --- 4. Sensor Status & Compass Calibration Help Sheet ----------------------------------

class SensorCalibrationSheet extends ConsumerWidget {
  const SensorCalibrationSheet({
    super.key,
    required this.sensors,
    required this.magnetometerAccuracy,
    required this.rotationAccuracy,
    required this.manualMode,
    required this.declinationDeg,
    required this.onSwitchManual,
    required this.onResumeSensors,
  });

  final SensorAvailability? sensors;
  final int? magnetometerAccuracy;
  final int? rotationAccuracy;
  final bool manualMode;
  final double declinationDeg;
  final VoidCallback onSwitchManual;
  final VoidCallback onResumeSensors;

  static String _accuracyLabel(int? level) => switch (level) {
        0 => 'Unreliable — needs figure-8 calibration',
        1 => 'Low — figure-8 calibration recommended',
        2 => 'Medium',
        3 => 'High (calibrated)',
        _ => 'Waiting for sensor readings…',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final avail = sensors;
    final activeAcc = s.useGyroscope ? rotationAccuracy : magnetometerAccuracy;
    final declSign = declinationDeg >= 0 ? 'E' : 'W';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sensors & compass calibration', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Calibration status: ${_accuracyLabel(activeAcc)}\n'
              'True-north WMM declination applied: ${declinationDeg.abs().toStringAsFixed(1)}° $declSign',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Card(
              color: Colors.white.withValues(alpha: 0.06),
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.all_inclusive, size: 32, color: Colors.amber),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'How to calibrate the compass:\n'
                        '1. Sweep your phone through the air 3–4 times in a smooth figure-8 (∞), '
                        'rotating your wrist along all three axes.\n'
                        '2. Remove magnetic cases/rings and step a few paces away from cars, '
                        'reinforced concrete, railings, or laptops.\n'
                        '3. If headings still jump, drag the sky with one finger anytime.',
                        style: TextStyle(height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (avail != null) ...[
              const SizedBox(height: 10),
              Text(
                'Hardware: '
                'Accelerometer ${avail.accelerometer ? "✓" : "✗"} · '
                'Compass ${avail.magnetometer ? "✓" : "✗"} · '
                'Gyroscope ${avail.gyroscope ? "✓" : "✗"}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            if (avail?.supports(SensorMode.gyro) ?? false)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use gyroscope fusion'),
                subtitle: const Text('Smoother motion; turn off if heading slowly drifts.'),
                value: s.useGyroscope,
                onChanged: (v) =>
                    ref.read(settingsProvider.notifier).update((st) => st.copyWith(useGyroscope: v)),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                if (manualMode)
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onResumeSensors();
                    },
                    icon: const Icon(Icons.explore),
                    label: const Text('Use live sensors'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onSwitchManual();
                    },
                    icon: const Icon(Icons.touch_app_outlined),
                    label: const Text('Switch to manual drag'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// --- 5. Sky Layers, Quality & Credits Sheet ---------------------------------------------

class SkyLayersSheet extends ConsumerWidget {
  const SkyLayersSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layers = ref.watch(skyLayersProvider);
    final layersNotifier = ref.read(skyLayersProvider.notifier);
    final s = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    Widget chip(String keyName, String label, bool on, ValueChanged<bool> toggle) => FilterChip(
          key: Key('layer-chip-$keyName'),
          label: Text(label),
          selected: on,
          showCheckmark: true,
          onSelected: toggle,
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Sky Layers & Display',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                chip('milky-way', 'Milky Way', layers.milkyWay,
                    (v) => layersNotifier.update((l) => l.copyWith(milkyWay: v))),
                chip('stars', 'Stars', layers.stars,
                    (v) => layersNotifier.update((l) => l.copyWith(stars: v))),
                chip('constellations', 'Constellations', layers.constellations,
                    (v) => layersNotifier.update((l) => l.copyWith(constellations: v))),
                chip('solar-system', 'Sun, Moon & Planets', layers.solarSystem,
                    (v) => layersNotifier.update((l) => l.copyWith(solarSystem: v))),
                chip('deep-sky', 'Deep-Sky Objects', layers.deepSky,
                    (v) => layersNotifier.update((l) => l.copyWith(deepSky: v))),
                chip('labels', 'Labels', layers.labels,
                    (v) => layersNotifier.update((l) => l.copyWith(labels: v))),
                chip('horizon', 'Horizon & Compass', layers.horizon,
                    (v) => layersNotifier.update((l) => l.copyWith(horizon: v))),
                chip('night-vision', 'Red Night Vision', s.nightVision,
                    (v) => settingsNotifier.update((st) => st.copyWith(nightVision: v))),
              ],
            ),
            const SizedBox(height: 16),
            Text('Graphics Quality', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            // Full-width SegmentedButton keeps constant width and height during selection
            // transitions, preventing chip-wrap reflows that made the panel jump.
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<SkyQuality>(
                key: const Key('sky-quality-segmented'),
                segments: [
                  for (final q in SkyQuality.values)
                    ButtonSegment<SkyQuality>(
                      value: q,
                      label: Text(q.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ],
                selected: {s.skyQuality},
                onSelectionChanged: (sel) =>
                    settingsNotifier.update((st) => st.copyWith(skyQuality: sel.first)),
              ),
            ),
            const SizedBox(height: 6),
            // Fixed 2-line height keeps the modal sheet stationary across short/long descriptions.
            SizedBox(
              height: 36,
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  s.skyQuality.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            const Divider(height: 20),
            Text(
              'Credits: All-sky Milky Way panorama © Axel Mellinger (PASP 121, 1180) via NASA '
              'SkyView. Stars & 88 IAU constellation figures from ESA Hipparcos / d3-celestial '
              '(Olaf Frohn, BSD-3-Clause) and the IAU Working Group on Star Names. Deep-sky '
              'catalog from OpenNGC (Mattia Verga, CC BY-SA 4.0). Offline geomagnetic declination '
              'from NOAA WMM-2025.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
