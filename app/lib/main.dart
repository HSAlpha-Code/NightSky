import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/camera_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Portrait only: the orientation maths assumes the top of the phone is "up" in the photo.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ProviderScope(child: NightSkyApp()));
}

class NightSkyApp extends StatelessWidget {
  const NightSkyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Night Sky',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF3F51B5), brightness: Brightness.dark),
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
      home: const CameraScreen(),
    );
  }
}
