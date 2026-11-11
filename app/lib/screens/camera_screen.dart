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
import '../widgets/glass.dart';
import '../widgets/provider_picker.dart';
import 'result_screen.dart';
import 'settings_screen.dart';
import 'sky_view_screen.dart';

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
    final ready = _cameraError == null && (_controller?.value.isInitialized ?? false);
    // Full screen: the camera feed runs edge to edge (under the status and navigation bars)
    // and every control floats on top of it.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(fit: StackFit.expand, children: [
          _preview(),
          // Soft shading at the top and bottom keeps the controls readable on bright scenes.
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x99000000), Color(0x00000000), Color(0x00000000), Color(0xB3000000)],
                  stops: [0, 0.2, 0.7, 1],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(children: [
              _topBar(),
              ..._banners().map((b) =>
                  Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 8), child: b)),
              if (_showTips && ready)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: CaptureTips(onClose: () => setState(() => _showTips = false)),
                ),
              const Spacer(),
              if (ready && _orientation.hasData) _readouts(),
              _controls(),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
      child: Row(children: [
        const Icon(Icons.auto_awesome, color: Colors.white, size: 22),
        const SizedBox(width: 8),
        Text(
          'NightSky',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white, fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
        const Spacer(),
        GlassIconButton(
          key: const Key('open-sky-view'),
          tooltip: 'Sky View',
          icon: Icons.public,
          onPressed: _openSkyView,
        ),
        const SizedBox(width: 8),
        GlassIconButton(
          tooltip: _showTips ? 'Hide tips' : 'Show tips',
          icon: Icons.lightbulb_outline,
          selected: _showTips,
          onPressed: () => setState(() => _showTips = !_showTips),
        ),
        const SizedBox(width: 8),
        GlassIconButton(
          tooltip: 'Settings',
          icon: Icons.settings_outlined,
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
        ),
      ]),
    );
  }

  Widget _readouts() {
    final settings = ref.watch(settingsProvider);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (settings.showPointingReadout && _pointing != null)
        PointingReadout(
          altitudeDeg: _pointing!.altitude,
          azimuthDeg: _pointing!.azimuth,
          usingGyroscope: _orientation.mode == SensorMode.gyro,
        ),
      const SizedBox(height: 8),
      SteadyIndicator(
        shakeDeg: _shake,
        maxShakeDeg: settings.steadiness.maxShakeDeg,
        autoCaptureProgress: _autoCaptureProgress,
      ),
    ]);
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

  Future<void> _openSkyView() async {
    final c = _controller;
    _controller = null;
    await c?.dispose();
    if (!mounted) return;
    setState(() {});
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SkyViewScreen(openedFromCamera: true)),
    );
    if (mounted && _controller == null) {
      unawaited(_initCamera());
    }
  }

  Widget _preview() {
    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.no_photography_outlined, size: 56, color: Colors.white70),
            const SizedBox(height: 16),
            Text(_cameraError!,
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.center, children: [
              FilledButton(
                onPressed: _cameraPermissionDenied ? Geolocator.openAppSettings : _initCamera,
                child: Text(_cameraPermissionDenied ? 'Open settings' : 'Try again'),
              ),
              OutlinedButton.icon(
                onPressed: _openSkyView,
                icon: const Icon(Icons.public, size: 18),
                label: const Text('Use Sky View instead'),
              ),
            ]),
          ]),
        ),
      );
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    // previewSize is reported in sensor (landscape) orientation; the app is portrait-only,
    // so swap it and scale the feed to cover the whole screen (cropping the overflow).
    final size = controller.value.previewSize;
    if (size == null) return Center(child: CameraPreview(controller));
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.shortestSide,
          height: size.longestSide,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  Widget _controls() {
    final selected = ref.watch(selectedProviderProvider);
    final catalog = ref.watch(providerCatalogProvider).value;
    final providerName = catalog?.providers
            .where((p) => p.key == (selected ?? catalog.defaultKey))
            .map((p) => p.name)
            .firstOrNull ??
        'Image source';
    final enabled = _controller != null && !_capturing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      child: Row(children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Glass(
              borderRadius: const BorderRadius.all(Radius.circular(999)),
              child: InkWell(
                onTap: () => showProviderPicker(context, ref),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.layers_outlined, size: 18, color: Colors.white),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(providerName,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(color: Colors.white)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Shutter: white ring around a solid disc, the familiar camera-app look.
        Container(
          width: 84,
          height: 84,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 4),
          ),
          child: FilledButton(
            key: const Key('shutter'),
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              disabledBackgroundColor: Colors.white38,
            ),
            onPressed: enabled ? _capture : null,
            child: _capturing
                ? const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 3, color: Colors.black))
                : const Icon(Icons.camera_alt, size: 30),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(child: SizedBox()),
      ]),
    );
  }
}
