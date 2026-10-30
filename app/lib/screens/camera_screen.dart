import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../models.dart';
import '../sensors.dart';
import '../settings.dart';
import '../sky_math.dart';
import '../state.dart';
import '../widgets/camera_hints.dart';
import '../widgets/provider_picker.dart';
import 'result_screen.dart';
import 'settings_screen.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen> with WidgetsBindingObserver {
  /// How long the phone must stay steady before auto-capture fires.
  static const autoCaptureHold = Duration(seconds: 2);

  final _orientation = OrientationTracker();
  final _location = LocationService();
  CameraController? _controller;
  CameraDescription? _camera;
  double? _fovDeg;
  String? _cameraError;
  bool _cameraPermissionDenied = false;
  LocationStatus? _locationStatus;
  SensorAvailability? _sensors;
  bool _capturing = false;
  bool _showTips = true;
  Timer? _shakeTimer;
  double _shake = 0;
  ({double altitude, double azimuth})? _pointing;
  DateTime? _steadySince;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SensorAvailability.query().then((s) {
      if (mounted) setState(() => _sensors = s);
    });
    _startSensors(ref.read(settingsProvider));
    // Camera first, then location, so the two permission dialogs don't overlap.
    _initCamera().then((_) => _initLocation());
    _shakeTimer = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shakeTimer?.cancel();
    _orientation.stop();
    _controller?.dispose();
    super.dispose();
  }

  void _startSensors(AppSettings s) => _orientation.start(
      mode: s.useGyroscope ? SensorMode.gyro : SensorMode.compass, alpha: s.smoothing.alpha);

  /// 4x a second: steadiness, the altitude/heading readout and auto-capture.
  void _tick() {
    if (!mounted) return;
    final settings = ref.read(settingsProvider);
    final q = _orientation.engine.current;
    final shake = _orientation.shake();
    final steady = _orientation.hasData && shake <= settings.steadiness.maxShakeDeg;
    final now = DateTime.now();
    _steadySince = steady ? (_steadySince ?? now) : null;
    setState(() {
      _shake = shake;
      _pointing = q == null ? null : cameraAltAzDeg(q);
    });
    if (settings.autoCapture &&
        _steadySince != null &&
        now.difference(_steadySince!) >= autoCaptureHold &&
        !_capturing &&
        ModalRoute.of(context)?.isCurrent == true) {
      _steadySince = null;
      _capture();
    }
  }

  /// Fraction of the auto-capture hold already done (0..1), or null when not counting.
  double? get _autoCaptureProgress {
    if (!ref.read(settingsProvider).autoCapture || _steadySince == null) return null;
    final held = DateTime.now().difference(_steadySince!);
    return (held.inMilliseconds / autoCaptureHold.inMilliseconds).clamp(0.0, 1.0);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      final c = _controller;
      _controller = null;
      c?.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null) _initCamera();
      if (_locationStatus != null && _locationStatus != LocationStatus.granted) {
        _initLocation();
      }
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.where((c) => c.lensDirection == CameraLensDirection.back);
      if (back.isEmpty) {
        if (mounted) setState(() => _cameraError = 'No rear camera found on this device.');
        return;
      }
      _camera = back.first;
      final controller =
          CameraController(_camera!, ResolutionPreset.veryHigh, enableAudio: false);
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      await controller.setFlashMode(FlashMode.off);
      _fovDeg ??= await CameraOptics.portraitFovDeg(_camera!);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _cameraError = null;
        _cameraPermissionDenied = false;
      });
    } on CameraException catch (e) {
      final denied = e.code.startsWith('CameraAccess') || e.code == 'cameraPermission';
      if (mounted) {
        setState(() {
          _cameraPermissionDenied = denied;
          _cameraError = denied
              ? 'Camera access is needed to photograph the sky.'
              : 'Could not start the camera (${e.description ?? e.code}).';
        });
      }
    }
  }

  Future<void> _initLocation() async {
    final status = await _location.ensurePermission();
    if (!mounted) return;
    setState(() => _locationStatus = status);
    if (status == LocationStatus.granted) unawaited(_location.warmUp());
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _capturing || controller.value.isTakingPicture) return;
    setState(() => _capturing = true);
    try {
      // Orientation is the average of the moment just before the shutter.
      final quaternion = _orientation.averaged();
      final timestamp = DateTime.now().toUtc();
      final positionFuture = _locationStatus == LocationStatus.granted
          ? _location.current()
          : Future<Position?>.value(null);
      final file = await controller.takePicture();
      final position = await positionFuture;
      final raw = await file.readAsBytes();
      final meta = CaptureMetadata(
        timestampUtc: timestamp,
        latitude: position?.latitude,
        longitude: position?.longitude,
        altitude: position?.altitude,
        quaternion: quaternion,
        // Both sensor modes are referenced to magnetic north; the backend applies the
        // World Magnetic Model declination.
        reference: 'magnetic_north',
        fovDeg: _fovDeg,
      );
      ref.read(sessionProvider.notifier).start(raw, meta);
      if (!mounted) return;
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const ResultScreen()));
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not take the photo (${e.description ?? e.code}).')));
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    // Settings changes (sensor mode, smoothing) apply immediately.
    ref.listen<AppSettings>(settingsProvider, (prev, next) {
      if (prev?.useGyroscope != next.useGyroscope || prev?.smoothing != next.smoothing) {
        _startSensors(next);
      }
    });
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('NightSky'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          ..._banners(),
          Expanded(child: _preview()),
          _controls(),
        ]),
      ),
    );
  }

  List<Widget> _banners() {
    final banners = <Widget>[];
    switch (_locationStatus) {
      case LocationStatus.serviceDisabled:
        banners.add(InfoBanner(
          icon: Icons.location_off_outlined,
          text: 'Location is off, so positions rely on star matching only.',
          action: 'Turn on',
          onTap: Geolocator.openLocationSettings,
        ));
      case LocationStatus.deniedForever:
        banners.add(InfoBanner(
          icon: Icons.location_off_outlined,
          text: 'Location permission is blocked, so positions rely on star matching only.',
          action: 'Settings',
          onTap: Geolocator.openAppSettings,
        ));
      case LocationStatus.denied:
        banners.add(InfoBanner(
          icon: Icons.location_off_outlined,
          text: 'Location helps find where you pointed the camera.',
          action: 'Allow',
          onTap: _initLocation,
        ));
      case LocationStatus.granted || null:
        break;
    }
    final settings = ref.watch(settingsProvider);
    final mode = settings.useGyroscope ? SensorMode.gyro : SensorMode.compass;
    final unsupported = _sensors != null && !_sensors!.supports(mode);
    if (unsupported || _orientation.lastError != null) {
      final canSwitch = mode == SensorMode.gyro && (_sensors?.supports(SensorMode.compass) ?? false);
      banners.add(InfoBanner(
        icon: Icons.explore_off_outlined,
        text: canSwitch
            ? 'This phone has no usable gyroscope. Turn it off in Settings to use the compass.'
            : 'Motion sensors are unavailable, so positions rely on star matching only.',
        action: canSwitch ? 'Use compass' : null,
        onTap: canSwitch
            ? () => ref
                .read(settingsProvider.notifier)
                .update((s) => s.copyWith(useGyroscope: false))
            : null,
      ));
    }
    return banners;
  }

  Widget _preview() {
    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.no_photography_outlined, size: 56),
            const SizedBox(height: 16),
            Text(_cameraError!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _cameraPermissionDenied ? Geolocator.openAppSettings : _initCamera,
              child: Text(_cameraPermissionDenied ? 'Open settings' : 'Try again'),
            ),
          ]),
        ),
      );
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(fit: StackFit.expand, children: [
      Center(child: CameraPreview(controller)),
      if (_showTips)
        Positioned(
          left: 12,
          right: 12,
          top: 12,
          child: CaptureTips(onClose: () => setState(() => _showTips = false)),
        ),
      if (_orientation.hasData)
        Positioned(
          left: 0,
          right: 0,
          bottom: 12,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (ref.watch(settingsProvider).showPointingReadout && _pointing != null)
              PointingReadout(
                altitudeDeg: _pointing!.altitude,
                azimuthDeg: _pointing!.azimuth,
                usingGyroscope: _orientation.mode == SensorMode.gyro,
              ),
            const SizedBox(height: 6),
            SteadyIndicator(
              shakeDeg: _shake,
              maxShakeDeg: ref.watch(settingsProvider).steadiness.maxShakeDeg,
              autoCaptureProgress: _autoCaptureProgress,
            ),
          ]),
        ),
    ]);
  }

  Widget _controls() {
    final selected = ref.watch(selectedProviderProvider);
    final catalog = ref.watch(providerCatalogProvider).value;
    final providerName = catalog?.providers
            .where((p) => p.key == (selected ?? catalog.defaultKey))
            .map((p) => p.name)
            .firstOrNull ??
        'Image source';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      child: Row(children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => showProviderPicker(context, ref),
              icon: const Icon(Icons.layers_outlined, size: 18),
              label: Text(providerName, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
        SizedBox(
          width: 76,
          height: 76,
          child: FilledButton(
            key: const Key('shutter'),
            style: FilledButton.styleFrom(shape: const CircleBorder(), padding: EdgeInsets.zero),
            onPressed: _controller == null || _capturing ? null : _capture,
            child: _capturing
                ? const SizedBox(
                    width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3))
                : const Icon(Icons.camera_alt, size: 34),
          ),
        ),
        const Expanded(child: SizedBox()),
      ]),
    );
  }
}
