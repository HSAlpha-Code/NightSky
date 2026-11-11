import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../curated.dart';
import '../sensors.dart';
import '../settings.dart';
import '../sky_math.dart';
import '../sky_view/astro_math.dart';
import '../sky_view/ephemeris.dart';
import '../sky_view/panorama_loader.dart';
import '../sky_view/sky_catalog.dart';
import '../sky_view/sky_overlay_painter.dart';
import '../sky_view/sky_sheets.dart';
import '../sky_view/sky_sphere_painter.dart';
import '../sky_view/time_machine_bar.dart';
import '../widgets/camera_hints.dart';
import 'camera_screen.dart';
import 'settings_screen.dart';

/// 3D virtual night sky driven by orientation sensors (with manual touch drag fallback),
/// backed offline by Axel Mellinger's Milky Way panorama, 8,874 stars, 88 constellations,
/// deep-sky highlights, and real-time Solar System ephemeris.
class SkyViewScreen extends ConsumerStatefulWidget {
  const SkyViewScreen({
    super.key,
    this.openedFromCamera = false,
    this.initialManualMode = false,
    this.initialAltDeg = 35.0,
    this.initialAzDeg = 180.0,
    this.initialUtc,
  });

  final bool openedFromCamera;
  final bool initialManualMode;
  final double initialAltDeg;
  final double initialAzDeg;
  final DateTime? initialUtc;

  @override
  ConsumerState<SkyViewScreen> createState() => _SkyViewScreenState();
}

class _SkyViewScreenState extends ConsumerState<SkyViewScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// Timelapse speed when "Timelapse" play is active (300x = 5 minutes of sky per second).
  static const double _timelapseRate = 300.0;

  final _orientation = OrientationTracker();
  final _location = LocationService();
  late final Ticker _ticker;

  SensorAvailability? _sensors;
  late bool _manualMode = widget.initialManualMode;
  late double _manualAltDeg = widget.initialAltDeg;
  late double _manualAzDeg = widget.initialAzDeg;
  double _fovDeg = 60.0;
  double _pinchBaseFov = 60.0;
  Offset? _lastFocalPoint;

  double _gpsLatDeg = 28.6139;
  double _gpsLonDeg = 77.2090;
  bool _hasGpsFix = false;

  List<double>? _displayQuaternion;
  Duration _lastTick = Duration.zero;

  // Time Machine state: null offset + !_timelapsePlaying + initialUtc == null => live real-time clock.
  DateTime? _anchorUtc;
  double _sliderHours = 0.0;
  bool _timeExpanded = false;
  bool _timelapsePlaying = false;

  // Sky layers, selection, and directional "Find object" guide.
  SkyLayerVisibility _layers = const SkyLayerVisibility();
  SkyObject? _selectedObject;
  SkyObject? _guideTarget;

  // Ephemeris memoization so we only recompute planets/Moon when time moves >5s or location shifts.
  SolarSystemSnapshot? _cachedSolar;
  DateTime? _cachedSolarTime;
  double? _cachedSolarLat;
  double? _cachedSolarLon;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _anchorUtc = widget.initialUtc?.toUtc();
    final s = ref.read(settingsProvider);
    if (s.manualLatitude != null && s.manualLongitude != null) {
      _gpsLatDeg = s.manualLatitude!;
      _gpsLonDeg = s.manualLongitude!;
    }
    if (!_manualMode) {
      _startSensors(s);
    }
    _querySensors();
    _initLocation();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _orientation.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _orientation.stop();
    } else if (state == AppLifecycleState.resumed && !_manualMode) {
      _startSensors(ref.read(settingsProvider));
    }
  }

  Future<void> _querySensors() async {
    final avail = await SensorAvailability.query();
    if (!mounted) return;
    final useGyro = ref.read(settingsProvider).useGyroscope;
    final mode = useGyro ? SensorMode.gyro : SensorMode.compass;
    setState(() {
      _sensors = avail;
      if (!avail.supports(mode)) {
        if (mode == SensorMode.gyro && avail.supports(SensorMode.compass)) {
          _orientation.start(mode: SensorMode.compass);
        } else {
          _manualMode = true;
        }
      }
    });
  }

  void _startSensors(AppSettings s) {
    _orientation.start(
      mode: s.useGyroscope ? SensorMode.gyro : SensorMode.compass,
      alpha: s.smoothing.alpha,
    );
  }

  Future<void> _initLocation() async {
    try {
      final status = await _location.ensurePermission();
      if (!mounted || status != LocationStatus.granted) return;
      final pos = await _location.current();
      if (!mounted || pos == null) return;
      setState(() {
        _gpsLatDeg = pos.latitude;
        _gpsLonDeg = pos.longitude;
        _hasGpsFix = true;
      });
      final cur = ref.read(settingsProvider);
      if (!cur.useManualLocation) {
        ref.read(settingsProvider.notifier).update(
              (s) => s.copyWith(
                manualLatitude: pos.latitude,
                manualLongitude: pos.longitude,
              ),
            );
      }
    } catch (_) {
      // Offline / desktop / denied: manual or cached coordinates keep Sky View working.
    }
  }

  bool get _isLiveTime => _anchorUtc == null && _sliderHours == 0.0 && !_timelapsePlaying;

  DateTime _effectiveUtc() {
    final base = _anchorUtc ?? DateTime.now().toUtc();
    if (_sliderHours == 0.0) return base;
    return base.add(Duration(seconds: (_sliderHours * 3600.0).round()));
  }

  void _onTick(Duration elapsed) {
    final dtSec = _lastTick == Duration.zero
        ? 1 / 60.0
        : ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.001, 0.1);
    _lastTick = elapsed;

    var dirty = false;

    if (_timelapsePlaying) {
      _anchorUtc ??= DateTime.now().toUtc();
      _anchorUtc = _anchorUtc!.add(
        Duration(milliseconds: (dtSec * _timelapseRate * 1000.0).round()),
      );
      dirty = true;
    }

    if (!_manualMode) {
      if (_orientation.lastError != null && !_orientation.hasData) {
        _manualMode = true;
        dirty = true;
      } else {
        final target = _orientation.engine.current;
        if (target != null) {
          final prev = _displayQuaternion;
          final deltaDeg = prev == null ? 90.0 : quaternionAngleDeg(prev, target);
          final rate = deltaDeg > 4.0 ? 18.0 : 8.5;
          final blend = (1.0 - (1.0 / (1.0 + rate * dtSec))).clamp(0.08, 1.0);
          _displayQuaternion = smoothQuaternion(prev, target, blend);
          dirty = true;
        }
      }
    }

    if (dirty && mounted) {
      setState(() {});
    }
  }

  (double, double) _observerLatLon(AppSettings s) {
    if (s.useManualLocation && s.manualLatitude != null && s.manualLongitude != null) {
      return (s.manualLatitude!, s.manualLongitude!);
    }
    if (_hasGpsFix) return (_gpsLatDeg, _gpsLonDeg);
    if (s.manualLatitude != null && s.manualLongitude != null) {
      return (s.manualLatitude!, s.manualLongitude!);
    }
    return (_gpsLatDeg, _gpsLonDeg);
  }

  String _locationBadgeLabel(AppSettings s, double lat, double lon) {
    if (s.useManualLocation) {
      final name = s.manualLocationName;
      if (name != null && name.isNotEmpty && name != 'Custom location') return name;
    } else if (_hasGpsFix) {
      return 'GPS ${lat.toStringAsFixed(1)}°, ${lon.toStringAsFixed(1)}°';
    }
    final ns = lat >= 0 ? 'N' : 'S';
    final ew = lon >= 0 ? 'E' : 'W';
    return '${lat.abs().toStringAsFixed(1)}°$ns ${lon.abs().toStringAsFixed(1)}°$ew';
  }

  SolarSystemSnapshot _solarSystemFor(DateTime utc, double lat, double lon) {
    if (_cachedSolar != null &&
        _cachedSolarTime != null &&
        (utc.difference(_cachedSolarTime!).inSeconds).abs() < 5 &&
        _cachedSolarLat == lat &&
        _cachedSolarLon == lon) {
      return _cachedSolar!;
    }
    final snap = computeSolarSystem(when: utc, latitudeDeg: lat, longitudeDeg: lon);
    _cachedSolar = snap;
    _cachedSolarTime = utc;
    _cachedSolarLat = lat;
    _cachedSolarLon = lon;
    // Keep guide/selected Solar System body synced when scrubbing through time!
    if (_guideTarget != null && _guideTarget!.id.startsWith('SOL-')) {
      _guideTarget = snap.allBodies.where((b) => b.id == _guideTarget!.id).firstOrNull ?? _guideTarget;
    }
    if (_selectedObject != null && _selectedObject!.id.startsWith('SOL-')) {
      _selectedObject =
          snap.allBodies.where((b) => b.id == _selectedObject!.id).firstOrNull ?? _selectedObject;
    }
    return snap;
  }

  SkyCamera _buildCamera(double lat, double lon, DateTime utc, double declDeg) {
    final q = _displayQuaternion;
    if (!_manualMode && q != null) {
      return SkyCamera.fromSensorQuaternion(
        quaternion: q,
        declinationDeg: declDeg,
        latitudeDeg: lat,
        longitudeDeg: lon,
        when: utc,
        fovDeg: _fovDeg,
      );
    }
    return SkyCamera.fromAltAz(
      altitudeDeg: _manualAltDeg,
      azimuthDeg: _manualAzDeg,
      latitudeDeg: lat,
      longitudeDeg: lon,
      when: utc,
      fovDeg: _fovDeg,
    );
  }

  void _enterManualFromCurrent(SkyCamera cam) {
    if (_manualMode) return;
    final p = cam.centerAltAz;
    _manualAltDeg = p.altitudeDeg;
    _manualAzDeg = p.azimuthDeg;
    _manualMode = true;
  }

  void _resumeLiveSensors() {
    final s = ref.read(settingsProvider);
    final mode = s.useGyroscope ? SensorMode.gyro : SensorMode.compass;
    final supported = _sensors == null ||
        _sensors!.supports(mode) ||
        _sensors!.supports(SensorMode.compass);
    if (!supported) {
      _showCalibrationSheet(0.0);
      return;
    }
    setState(() => _manualMode = false);
    _startSensors(s);
  }

  void _centerOnObject(SkyObject obj, double lat, double lon, DateTime utc) {
    final hor = raDecToAltAz(
      raDeg: obj.raDeg,
      decDeg: obj.decDeg,
      latitudeDeg: lat,
      longitudeDeg: lon,
      when: utc,
    );
    setState(() {
      _manualMode = true;
      _manualAltDeg = hor.altitudeDeg.clamp(-89.5, 89.5);
      _manualAzDeg = hor.azimuthDeg;
      _selectedObject = obj;
    });
  }

  void _openCameraMode() {
    if (widget.openedFromCamera && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const CameraScreen()),
      );
    }
  }

  Future<void> _pickDateTime() async {
    final currentLocal = _effectiveUtc().toLocal();
    final date = await showDatePicker(
      context: context,
      initialDate: currentLocal,
      firstDate: DateTime(1950),
      lastDate: DateTime(2050, 12, 31),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(currentLocal),
    );
    if (time == null || !mounted) return;
    final chosenLocal = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      _anchorUtc = chosenLocal.toUtc();
      _sliderHours = 0.0;
      _timelapsePlaying = false;
    });
  }

  void _openObjectSheet(SkyObject obj, double lat, double lon, DateTime utc) {
    setState(() => _selectedObject = obj);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF10131C),
      builder: (_) => SkyObjectSheet(
        object: obj,
        latitudeDeg: lat,
        longitudeDeg: lon,
        when: utc,
        manualMode: _manualMode,
        onGuide: () => setState(() => _guideTarget = obj),
        onCenterHere: () => _centerOnObject(obj, lat, lon, utc),
      ),
    );
  }

  void _openSearchSheet(
    SkyCatalog? catalog,
    SolarSystemSnapshot solar,
    Set<String> curatedIds,
    double lat,
    double lon,
    DateTime utc,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF10131C),
      builder: (_) => SkySearchSheet(
        catalog: catalog,
        solarSystem: solar,
        curatedIds: curatedIds,
        latitudeDeg: lat,
        longitudeDeg: lon,
        when: utc,
        onSelect: (obj) {
          setState(() {
            _guideTarget = obj;
            _selectedObject = obj;
          });
        },
      ),
    );
  }

  void _openLocationSheet(double lat, double lon) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF10131C),
      builder: (_) => SkyLocationSheet(
        currentLat: lat,
        currentLon: lon,
        hasGpsFix: _hasGpsFix,
        onRequestGps: _initLocation,
      ),
    );
  }

  void _showCalibrationSheet(double declDeg) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF10131C),
      builder: (_) => SensorCalibrationSheet(
        sensors: _sensors,
        magnetometerAccuracy: _orientation.magnetometerAccuracy,
        rotationAccuracy: _orientation.rotationAccuracy,
        manualMode: _manualMode,
        declinationDeg: declDeg,
        onSwitchManual: () => setState(() => _manualMode = true),
        onResumeSensors: _resumeLiveSensors,
      ),
    );
  }

  void _openLayersSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF10131C),
      builder: (_) => SkyLayersSheet(
        layers: _layers,
        onChanged: (next) => setState(() => _layers = next),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppSettings>(settingsProvider, (prev, next) {
      if ((prev?.useGyroscope != next.useGyroscope || prev?.smoothing != next.smoothing) &&
          !_manualMode) {
        _startSensors(next);
      }
    });

    final settings = ref.watch(settingsProvider);
    final panorama = ref.watch(mellingerImageProvider).value;
    final shaderProgram = ref.watch(skyShaderProgramProvider).value;
    final catalog = ref.watch(skyCatalogProvider).value;
    final curatedIndex = ref.watch(curatedIndexProvider);
    final curatedIds = curatedIndex?.counts.keys.toSet() ?? const <String>{};

    final (lat, lon) = _observerLatLon(settings);
    final skyUtc = _effectiveUtc();
    final declDeg = magneticDeclinationDeg(latitudeDeg: lat, longitudeDeg: lon, when: skyUtc);
    final solar = _solarSystemFor(skyUtc, lat, lon);
    final camera = _buildCamera(lat, lon, skyUtc, declDeg);
    final center = camera.centerAltAz;

    final sceneRenderer = SkySceneRenderer(
      camera: camera,
      quality: settings.skyQuality,
      layers: _layers,
      nightVision: settings.nightVision,
      catalog: catalog,
      solarSystem: solar,
      curatedIds: curatedIds,
      selectedObject: _selectedObject,
      guideTarget: _guideTarget,
    );
    final spotlit = sceneRenderer.spotlitConstellation();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewSize = Size(
              constraints.maxWidth > 0 ? constraints.maxWidth : 360.0,
              constraints.maxHeight > 0 ? constraints.maxHeight : 640.0,
            );
            final guideInfo = _guideTarget == null
                ? null
                : camera.guideTowards(_guideTarget!.icrs, viewSize);

            return GestureDetector(
              key: const Key('sky-view-canvas'),
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                final hit = sceneRenderer.hitTest(details.localPosition, viewSize);
                if (hit != null) {
                  _openObjectSheet(hit, lat, lon, skyUtc);
                } else if (_selectedObject != null) {
                  setState(() => _selectedObject = null);
                }
              },
              onScaleStart: (details) {
                _pinchBaseFov = _fovDeg;
                _lastFocalPoint = details.localFocalPoint;
              },
              onScaleUpdate: (details) {
                setState(() {
                  if (details.pointerCount >= 2) {
                    _fovDeg = (_pinchBaseFov / details.scale).clamp(20.0, 95.0);
                  } else if (_lastFocalPoint != null) {
                    final delta = details.localFocalPoint - _lastFocalPoint!;
                    if (delta.distance > 0.5) {
                      _enterManualFromCurrent(camera);
                      final degPerPx = _fovDeg / viewSize.width;
                      _manualAzDeg = (_manualAzDeg - delta.dx * degPerPx) % 360.0;
                      if (_manualAzDeg < 0) _manualAzDeg += 360.0;
                      _manualAltDeg = (_manualAltDeg + delta.dy * degPerPx).clamp(-89.5, 89.5);
                    }
                  }
                  _lastFocalPoint = details.localFocalPoint;
                });
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: SkySpherePainter(
                        camera: camera,
                        panorama: panorama,
                        shaderProgram: shaderProgram,
                        sunAltitudeDeg: solar.sunAltitudeDeg,
                        showMilkyWay: _layers.milkyWay,
                        showHorizon: _layers.horizon,
                        nightVision: settings.nightVision,
                        overlayPaint: sceneRenderer.paint,
                      ),
                    ),
                  ),

                  // Top toolbar: Search/Find, Layers, Camera switch, Sensor calibration, Settings.
                  Positioned(
                    top: 6,
                    left: 8,
                    right: 6,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              key: const Key('sky-find-button'),
                              tooltip: 'Find object',
                              icon: const Icon(Icons.search),
                              onPressed: () => _openSearchSheet(
                                catalog,
                                solar,
                                curatedIds,
                                lat,
                                lon,
                                skyUtc,
                              ),
                            ),
                            ActionChip(
                              key: const Key('sky-location-pill'),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: Colors.black.withValues(alpha: 0.6),
                              avatar: Icon(
                                settings.useManualLocation
                                    ? Icons.edit_location_alt_outlined
                                    : Icons.location_on_outlined,
                                size: 15,
                              ),
                              label: Text(
                                _locationBadgeLabel(settings, lat, lon),
                                overflow: TextOverflow.ellipsis,
                              ),
                              onPressed: () => _openLocationSheet(lat, lon),
                            ),
                            const Spacer(),
                            IconButton(
                              key: const Key('sky-layers-button'),
                              tooltip: 'Layers & credits',
                              icon: const Icon(Icons.tune),
                              onPressed: _openLayersSheet,
                            ),
                            IconButton(
                              key: const Key('sky-calibrate-button'),
                              tooltip: 'Sensors & calibration',
                              icon: Icon(
                                _manualMode ? Icons.touch_app_outlined : Icons.explore_outlined,
                                color: _orientation.needsCalibration ? Colors.amber : null,
                              ),
                              onPressed: () => _showCalibrationSheet(declDeg),
                            ),
                            TextButton.icon(
                              key: const Key('switch-to-camera'),
                              onPressed: _openCameraMode,
                              icon: const Icon(Icons.camera_alt_outlined, size: 18),
                              label: const Text('Camera'),
                            ),
                            IconButton(
                              tooltip: 'Settings',
                              icon: const Icon(Icons.settings_outlined),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
                              ),
                            ),
                          ],
                        ),

                        // Active "Find object" directional guide banner.
                        if (_guideTarget != null && guideInfo != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                            child: _GuideBanner(
                              target: _guideTarget!,
                              angleDeg: guideInfo.angleDeg,
                              manualMode: _manualMode,
                              onCenter: () => _centerOnObject(_guideTarget!, lat, lon, skyUtc),
                              onDetails: () => _openObjectSheet(_guideTarget!, lat, lon, skyUtc),
                              onClear: () => setState(() => _guideTarget = null),
                            ),
                          )
                        else if (!_manualMode && _orientation.needsCalibration)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: ActionChip(
                              key: const Key('compass-calibration-warning'),
                              backgroundColor: Colors.black.withValues(alpha: 0.72),
                              avatar: const Icon(Icons.warning_amber_rounded,
                                  size: 17, color: Colors.amber),
                              label: const Text('Compass accuracy low · Tap to calibrate'),
                              onPressed: () => _showCalibrationSheet(declDeg),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Bottom HUD: Manual/Live pill, Time Machine scrubber, Pointing readout, credit.
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 8,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_manualMode)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: ActionChip(
                              key: const Key('resume-live-compass'),
                              backgroundColor: Colors.black.withValues(alpha: 0.7),
                              avatar: const Icon(Icons.explore, size: 17),
                              label: Text(
                                _sensors != null &&
                                        !_sensors!.supports(SensorMode.compass) &&
                                        !_sensors!.supports(SensorMode.gyro)
                                    ? 'Manual drag (no compass sensor)'
                                    : 'Manual drag · Tap for live compass',
                              ),
                              onPressed: _resumeLiveSensors,
                            ),
                          ),
                        TimeMachineBar(
                          effectiveUtc: skyUtc,
                          isLive: _isLiveTime,
                          playing: _timelapsePlaying,
                          expanded: _timeExpanded,
                          sliderHours: _sliderHours,
                          onToggleExpanded: () => setState(() => _timeExpanded = !_timeExpanded),
                          onSliderChanged: (h) => setState(() {
                            _anchorUtc ??= DateTime.now().toUtc();
                            _sliderHours = h;
                          }),
                          onStep: (delta) => setState(() {
                            final cur = _effectiveUtc();
                            _anchorUtc = cur.add(delta);
                            _sliderHours = 0.0;
                          }),
                          onTogglePlay: () => setState(() {
                            _anchorUtc = _effectiveUtc();
                            _sliderHours = 0.0;
                            _timelapsePlaying = !_timelapsePlaying;
                          }),
                          onResetNow: () => setState(() {
                            _anchorUtc = null;
                            _sliderHours = 0.0;
                            _timelapsePlaying = false;
                          }),
                          onPickDateTime: _pickDateTime,
                        ),
                        const SizedBox(height: 6),
                        if (settings.showPointingReadout)
                          PointingReadout(
                            altitudeDeg: center.altitudeDeg,
                            azimuthDeg: center.azimuthDeg,
                            usingGyroscope: _orientation.mode == SensorMode.gyro,
                          ),
                        const SizedBox(height: 3),
                        Text(
                          '${spotlit != null ? '${spotlit.name} · ' : ''}'
                          'FOV ${_fovDeg.round()}° · Milky Way © Axel Mellinger',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: Colors.white54),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _GuideBanner extends StatelessWidget {
  const _GuideBanner({
    required this.target,
    required this.angleDeg,
    required this.manualMode,
    required this.onCenter,
    required this.onDetails,
    required this.onClear,
  });

  final SkyObject target;
  final double angleDeg;
  final bool manualMode;
  final VoidCallback onCenter;
  final VoidCallback onDetails;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final locked = angleDeg <= 4.5;
    return Card(
      key: const Key('sky-guide-banner'),
      color: Colors.black.withValues(alpha: 0.82),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: locked ? Colors.greenAccent : Colors.white24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(
              locked ? Icons.check_circle : Icons.assistant_navigation,
              color: Colors.greenAccent,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: onDetails,
                child: Text(
                  locked
                      ? 'Centered on ${target.name} · Tap for details'
                      : 'Turn ${angleDeg.round()}° toward ${target.name}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ),
            if (!locked && manualMode)
              TextButton(
                key: const Key('guide-pan-button'),
                onPressed: onCenter,
                child: const Text('Point'),
              ),
            IconButton(
              key: const Key('guide-clear-button'),
              tooltip: 'Stop guiding',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 18),
              onPressed: onClear,
            ),
          ],
        ),
      ),
    );
  }
}
