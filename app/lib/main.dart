import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'curated.dart';
import 'screens/camera_screen.dart';
import 'settings.dart';
import 'legal_notices.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerDataLicences();
  await SystemChrome.setPreferredOrientations(ScreenOrientationMode.auto.orientations);
  runApp(const ProviderScope(child: NightSkyApp()));
}

class NightSkyApp extends ConsumerWidget {
  const NightSkyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restored = ref.watch(settingsRestoredProvider);
    return NightSkyAppShell(
      home: restored.isLoading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : const CameraScreen(),
    );
  }
}

/// Theme and app-wide settings (font size, screen orientation) around [home]; separate so
/// tests can use it without the camera.
class NightSkyAppShell extends ConsumerStatefulWidget {
  const NightSkyAppShell({super.key, required this.home});

  final Widget home;

  @override
  ConsumerState<NightSkyAppShell> createState() => _NightSkyAppShellState();
}

class _NightSkyAppShellState extends ConsumerState<NightSkyAppShell> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(ref.read(settingsProvider).orientationMode.orientations);
  }

  @override
  Widget build(BuildContext context) {
    final fontScale = ref.watch(settingsProvider.select((s) => s.fontSize.scale));
    ref.listen<ScreenOrientationMode>(
      settingsProvider.select((s) => s.orientationMode),
      (prev, next) {
        if (prev != next) {
          SystemChrome.setPreferredOrientations(next.orientations);
        }
      },
    );
    // Download the curated-highlights index in the background (app start and whenever the
    // server address changes). Never blocks anything; failures are silent.
    ref.listen(curatedIndexProvider, (_, _) {});
    return MaterialApp(
      title: 'NightSky',
      debugShowCheckedModeBanner: false,
      // The app's font size setting multiplies the phone's own text size.
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final phone = media.textScaler.scale(1);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(phone * fontScale)),
          child: child!,
        );
      },
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF3F51B5), brightness: Brightness.dark),
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
      home: widget.home,
    );
  }
}
