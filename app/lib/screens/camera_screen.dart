import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../models.dart';
import 'events_screen.dart';
import 'solar_system_screen.dart';
import '../sensors.dart';
import '../settings.dart';
import '../sky_math.dart';
import '../state.dart';
import '../upload_consent.dart';
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
  ({double portraitDeg, double landscapeDeg})? _cameraFov;
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
      await controller.setFlashMode(FlashMode.off);
      _cameraFov ??= await CameraOptics.fieldOfViewDeg(_camera!);
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
    } on MissingPluginException {
      if (mounted) {
        setState(() => _cameraError = 'Camera is not available on this device.');
      }
    }
  }

  Future<void> _initLocation() async {
    try {
      final status = await _location.ensurePermission();
      if (!mounted) return;
      setState(() => _locationStatus = status);
      if (status == LocationStatus.granted) unawaited(_location.warmUp());
    } on MissingPluginException {
      // Desktop / unit test environments without geolocator plugin.
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _capturing || controller.value.isTakingPicture) return;
    setState(() => _capturing = true);
    try {
      final server = ref.read(serverUrlProvider);
      final consent = ref.read(uploadConsentProvider);
      if (!consent.covers(server)) {
        final accepted = await requestUploadConsent(context, server);
        if (!mounted) return;
        if (!accepted) {
          // A declined automatic capture must not reopen the dialog every two seconds.
          ref.read(settingsProvider.notifier).update((s) => s.copyWith(autoCapture: false));
          return;
        }
        // The receiving server must still be the one named in the disclosure.
        if (ref.read(serverUrlProvider) != server) return;
        consent.accept(server);
      }
      // Orientation is the average of the moment just before the shutter.
      final quaternion = _orientation.averaged();
      final timestamp = DateTime.now().toUtc();
      final positionFuture = _locationStatus == LocationStatus.granted
          ? _location.current()
          : Future<Position?>.value(null);
      final file = await controller.takePicture();
      final position = await positionFuture;
      final raw = await file.readAsBytes();
      // The camera plugin writes a temporary capture; keep only the in-memory session.
      try {
        await File(file.path).delete();
      } on FileSystemException {
        // Android may already have removed the temporary capture.
      }
      final meta = CaptureMetadata(
        timestampUtc: timestamp,
        latitude: position?.latitude,
        longitude: position?.longitude,
        altitude: position?.altitude,
        quaternion: quaternion,
        // Both sensor modes are referenced to magnetic north; the backend applies the
        // World Magnetic Model declination.
        reference: 'magnetic_north',
        fovDeg: _cameraFov?.portraitDeg,
        landscapeFovDeg: _cameraFov?.landscapeDeg,
        displayRotationDeg: _orientation.displayRotationDeg,
      );
      ref.read(sessionProvider.notifier).start(raw, meta);
      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const ResultScreen()));
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not take the photo (${e.description ?? e.code}).')),
        );
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isLandscape = constraints.maxWidth > constraints.maxHeight;
                final bannerCards = [
                  for (final b in _banners())
                    Padding(padding: const EdgeInsets.only(bottom: 8), child: b),
                  if (_showTips && ready)
                    CaptureTips(onClose: () => setState(() => _showTips = false)),
                ];

                if (isLandscape) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _topBar(compact: true),
                            Expanded(
                              child: bannerCards.isEmpty
                                  ? const SizedBox.shrink()
                                  : Align(
                                      alignment: Alignment.topLeft,
                                      child: SingleChildScrollView(
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(maxWidth: 460),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: bannerCards,
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 4, 8, 10),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  _providerPill(),
                                  if (ready && _orientation.hasData) ..._readoutPills(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
                        child: Center(child: _shutterButton()),
                      ),
                    ],
                  );
                }

                return Column(children: [
                  _topBar(),
                  Expanded(
                    child: bannerCards.isEmpty
                        ? const SizedBox.shrink()
                        : Align(
                            alignment: Alignment.topCenter,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: bannerCards,
                              ),
                            ),
                          ),
                  ),
                  if (ready && _orientation.hasData) _readouts(),
                  _controls(),
                ]);
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _topBar({bool compact = false}) {
    return Padding(
      padding: compact
          ? const EdgeInsets.fromLTRB(16, 4, 8, 6)
          : const EdgeInsets.fromLTRB(20, 8, 12, 12),
      child: Row(children: [
        Flexible(
          child: PopupMenuButton<String>(
            tooltip: 'Observing events and solar system',
            onSelected: (page) => _openObservingPage(page == 'events'
                ? const EventsScreen() : const SolarSystemScreen()),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'events', child: Text('Observing events')),
              PopupMenuItem(value: 'solar', child: Text('Solar system')),
            ],
            child: const Padding(padding: EdgeInsets.symmetric(vertical:12),
              child: Text('NightSky ▾', overflow: TextOverflow.ellipsis)),
          ),
        ),
        const Spacer(),
        ModeSwitchPill(
          key: const Key('open-sky-view'),
          isSkyView: false,
          tooltip: 'Switch to Sky View',
          height: compact ? 38 : 44,
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

  List<Widget> _readoutPills() {
    final settings = ref.watch(settingsProvider);
    return [
      if (settings.showPointingReadout && _pointing != null)
        PointingReadout(
          altitudeDeg: _pointing!.altitude,
          azimuthDeg: _pointing!.azimuth,
          usingGyroscope: _orientation.mode == SensorMode.gyro,
        ),
      SteadyIndicator(
        shakeDeg: _shake,
        maxShakeDeg: settings.steadiness.maxShakeDeg,
        autoCaptureProgress: _autoCaptureProgress,
      ),
    ];
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

  Future<void> _openSkyView() => _openObservingPage(const SkyViewScreen(openedFromCamera: true));

  Future<void> _openObservingPage(Widget page) async {
    final c = _controller;
    _controller = null;
    await c?.dispose();
    if (!mounted) return;
    setState(() {});
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
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
    // previewSize is reported in sensor (landscape) orientation; swap in portrait and scale
    // the feed to cover the whole screen (cropping the overflow).
    final size = controller.value.previewSize;
    if (size == null) return Center(child: CameraPreview(controller));
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: isLandscape ? size.longestSide : size.shortestSide,
          height: isLandscape ? size.shortestSide : size.longestSide,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  Widget _providerPill() {
    final selected = ref.watch(selectedProviderProvider);
    final catalog = ref.watch(providerCatalogProvider).value;
    final providerName = catalog?.providers
            .where((p) => p.key == (selected ?? catalog.defaultKey))
            .map((p) => p.name)
            .firstOrNull ??
        'Image source';
    return Glass(
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
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.white)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _shutterButton() {
    final enabled = _controller != null && !_capturing;
    // Shutter: white ring around a solid disc, the familiar camera-app look.
    return Container(
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
    );
  }

  Widget _controls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      child: Row(children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: _providerPill(),
          ),
        ),
        const SizedBox(width: 12),
        _shutterButton(),
        const SizedBox(width: 12),
        const Expanded(child: SizedBox()),
      ]),
    );
  }
}
