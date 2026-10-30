import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/camera_screen.dart';
import 'settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Portrait only: the orientation maths assumes the top of the phone is "up" in the photo.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ProviderScope(child: NightSkyApp()));
}

class NightSkyApp extends StatelessWidget {
  const NightSkyApp({super.key});

  @override
  Widget build(BuildContext context) => const NightSkyAppShell(home: CameraScreen());
}

/// Theme and app-wide settings (font size) around [home]; separate so tests can use it
/// without the camera.
class NightSkyAppShell extends ConsumerWidget {
  const NightSkyAppShell({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fontScale = ref.watch(settingsProvider.select((s) => s.fontSize.scale));
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
      home: home,
    );
  }
}
