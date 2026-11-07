import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sky/main.dart';
import 'package:night_sky/screens/settings_screen.dart';
import 'package:night_sky/settings.dart';
import 'package:night_sky/state.dart';
import 'package:night_sky/widgets/camera_hints.dart';

ProviderContainer _container(MemorySettingsStore store) {
  final c = ProviderContainer(overrides: [settingsStoreProvider.overrideWithValue(store)]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('AppSettings', () {
    test('defaults: gyroscope off', () {
      const s = AppSettings();
      expect(s.useGyroscope, isFalse);
      expect(s.smoothing, SensorSmoothing.medium);
      expect(s.steadiness, Steadiness.normal);
      expect(s.fontSize, FontSize.normal);
      expect(s.autoCapture, isFalse);
    });

    test('JSON round trip; unknown or missing values fall back to defaults', () {
      const s = AppSettings(
          useGyroscope: true,
          smoothing: SensorSmoothing.high,
          steadiness: Steadiness.strict,
          autoCapture: true,
          showPointingReadout: false,
          fontSize: FontSize.extraLarge);
      expect(AppSettings.fromJson(jsonDecode(jsonEncode(s.toJson()))), s);
      expect(AppSettings.fromJson({'smoothing': 'turbo', 'useGyroscope': 'yes'}),
          const AppSettings());
    });
  });

  group('SettingsNotifier', () {
    test('restores saved settings and saves changes', () async {
      final store = MemorySettingsStore(jsonEncode(
          const AppSettings(fontSize: FontSize.large, useGyroscope: true).toJson()));
      final c = _container(store);
      expect(c.read(settingsProvider), const AppSettings()); // before the load finishes
      await Future<void>.delayed(Duration.zero);
      expect(c.read(settingsProvider).fontSize, FontSize.large);
      expect(c.read(settingsProvider).useGyroscope, isTrue);

      c.read(settingsProvider.notifier).update((s) => s.copyWith(useGyroscope: false));
      await Future<void>.delayed(Duration.zero);
      expect(AppSettings.fromJson(jsonDecode(store.value!)).useGyroscope, isFalse);

      c.read(settingsProvider.notifier).reset();
      expect(c.read(settingsProvider), const AppSettings());
    });

    test('corrupt stored settings are ignored', () async {
      final c = _container(MemorySettingsStore('{oops'));
      c.read(settingsProvider);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(settingsProvider), const AppSettings());
    });
  });

  testWidgets('settings screen: sensors and display sections update the settings',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemorySettingsStore();
    final c = _container(store);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c, child: const MaterialApp(home: SettingsScreen())));
    await tester.pump();

    expect(find.text('Sensors'), findsOneWidget);
    expect(find.text('Display'), findsOneWidget);
    final gyro = find.byKey(const Key('setting-gyro'));
    expect(tester.widget<SwitchListTile>(gyro).value, isFalse); // off by default
    await tester.tap(gyro);
    await tester.pump();
    expect(c.read(settingsProvider).useGyroscope, isTrue);

    await tester.tap(find.widgetWithText(ChoiceChip, 'High'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Strict'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Large'));
    await tester.tap(find.byKey(const Key('setting-auto-capture')));
    await tester.pump();
    final s = c.read(settingsProvider);
    expect((s.smoothing, s.steadiness, s.fontSize, s.autoCapture),
        (SensorSmoothing.high, Steadiness.strict, FontSize.large, true));
    expect(find.textContaining('0.7°'), findsOneWidget); // strict threshold explained
    expect(AppSettings.fromJson(jsonDecode(store.value!)), s); // saved

    await tester.tap(find.text('Reset to defaults'));
    await tester.pump();
    expect(c.read(settingsProvider), const AppSettings());
  });

  testWidgets('font size setting scales text app-wide', (tester) async {
    final c = _container(MemorySettingsStore());
    double? scale;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: NightSkyAppShell(home: Builder(builder: (context) {
        scale = MediaQuery.textScalerOf(context).scale(10) / 10;
        return const SizedBox();
      })),
    ));
    expect(scale, closeTo(1.0, 1e-9));
    c.read(settingsProvider.notifier).update((s) => s.copyWith(fontSize: FontSize.extraLarge));
    await tester.pump();
    expect(scale, closeTo(1.3, 1e-9));
  });

  testWidgets('steadiness threshold, auto-capture countdown and pointing readout',
      (tester) async {
    Future<void> show(Widget w) =>
        tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: w))));

    await show(const SteadyIndicator(shakeDeg: 1.0, maxShakeDeg: 0.7));
    expect(find.text('Hold steady…'), findsOneWidget); // strict: 1° is too much
    await show(const SteadyIndicator(shakeDeg: 1.0, maxShakeDeg: 3.0));
    expect(find.text('Steady'), findsOneWidget);
    await show(const SteadyIndicator(shakeDeg: 0.2, autoCaptureProgress: 0.5));
    expect(find.text('Steady, taking photo…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await show(const PointingReadout(altitudeDeg: 62.4, azimuthDeg: 359.6, usingGyroscope: false));
    expect(find.text('Alt +62° · N 0° · compass'), findsOneWidget);
    await show(const PointingReadout(altitudeDeg: -12, azimuthDeg: 225, usingGyroscope: true));
    expect(find.text('Alt −12° (below horizon) · SW 225° · gyro'), findsOneWidget);
  });

  group('server address', () {
    test('the default is the hosted backend', () {
      expect(defaultServerUrl, 'https://nightsky-backend.vercel.app');
      final c = _container(MemorySettingsStore());
      expect(c.read(serverUrlProvider), defaultServerUrl);
    });

    test('a fresh install, or one that never changed it, gets the new default', () async {
      final c = _container(MemorySettingsStore(jsonEncode(const AppSettings().toJson())));
      await Future<void>.delayed(Duration.zero);
      expect(c.read(serverUrlProvider), defaultServerUrl);
    });

    test('a saved custom address is kept', () async {
      final c = _container(MemorySettingsStore(
          jsonEncode({'serverUrl': 'http://192.168.1.20:8000', 'fontSize': 'large'})));
      c.listen(serverUrlProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      expect(c.read(serverUrlProvider), 'http://192.168.1.20:8000');
      expect(c.read(settingsProvider).fontSize, FontSize.large);
    });

    test('migration: the old default stored explicitly moves to the new default', () {
      for (final old in [legacyDefaultServerUrl, '$legacyDefaultServerUrl/', 'HTTP://10.0.2.2:8000/api']) {
        expect(AppSettings.fromJson({'serverUrl': old}).serverUrl, isNull, reason: old);
      }
      // ...but only that one: any other address stays.
      expect(AppSettings.fromJson({'serverUrl': 'http://10.0.2.2:9000'}).serverUrl,
          'http://10.0.2.2:9000');
      expect(AppSettings.fromJson({'serverUrl': 'https://my.example.org'}).serverUrl,
          'https://my.example.org');
    });

    test('malformed stored addresses are dropped', () {
      for (final bad in ['', 'nonsense', 'ftp://host', 'http://', 42]) {
        expect(AppSettings.fromJson({'serverUrl': bad}).serverUrl, isNull, reason: '$bad');
      }
    });

    test('saving persists; saving the default clears it; reset keeps the address', () async {
      final store = MemorySettingsStore();
      final c = _container(store);
      c.listen(serverUrlProvider, (_, _) {});
      c.read(serverUrlProvider.notifier).set(' https://my.example.org ');
      expect(c.read(serverUrlProvider), 'https://my.example.org');
      expect(jsonDecode(store.value!)['serverUrl'], 'https://my.example.org');

      c.read(settingsProvider.notifier).reset();
      expect(c.read(serverUrlProvider), 'https://my.example.org');

      c.read(serverUrlProvider.notifier).set(defaultServerUrl);
      expect(jsonDecode(store.value!).containsKey('serverUrl'), isFalse);
      expect(c.read(serverUrlProvider), defaultServerUrl);
    });

    test('validation', () {
      expect(validateServerUrl('https://nightsky-backend.vercel.app'), isNull);
      expect(validateServerUrl(' http://192.168.1.20:8000 '), isNull);
      for (final bad in ['', 'localhost:8000', 'nightsky', 'ftp://x.org', 'https://', 'http://a b']) {
        expect(validateServerUrl(bad), isNotNull, reason: bad);
      }
    });
  });
}
