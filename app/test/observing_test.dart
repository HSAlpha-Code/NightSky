import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_sky/observing.dart';
import 'package:night_sky/screens/events_screen.dart';
import 'package:night_sky/screens/sky_view_screen.dart';

class _Navigation extends NavigatorObserver {
  Route<dynamic>? latest;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      latest = route;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'bundled events have unique stable IDs, UTC instants and checked reference times',
    () async {
      final events = parseCalendar(
        await rootBundle.loadString('assets/observing/events.csv'),
      );
      expect(events.map((e) => e.id).toSet().length, events.length);
      for (var i = 1; i < events.length; i++) {
        expect(events[i].utc.isAfter(events[i - 1].utc), isTrue);
        expect(events[i].utc.isUtc, isTrue);
      }
      final moon = events.singleWhere((e) => e.id == 'moon-full-20261124');
      expect(moon.utc, DateTime.utc(2026, 11, 24, 14, 53));
      expect(moon.reminderUtc, DateTime.utc(2026, 11, 24, 13, 53));
      expect(
        events.singleWhere((e) => e.id == 'geminids-2026').utc,
        DateTime.utc(2026, 12, 14, 14),
      );
    },
  );

  testWidgets(
    'denial, scheduling, cancellation and chart handoff use the selected event',
    (tester) async {
      var allow = false;
      final saved = <String>{};
      final event = ObservingEvent(
        'phase-test',
        'Full Moon',
        DateTime.now().toUtc().add(const Duration(days: 3)),
        'full',
      );
      final observer = _Navigation();
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(observingChannel, (call) async {
        switch (call.method) {
          case 'permission':
            return allow;
          case 'status':
            return saved.contains(call.arguments)
                ? 'scheduled'
                : allow
                ? 'off'
                : 'blocked';
          case 'schedule':
            saved.add(call.arguments as String);
            return true;
          case 'cancel':
            saved.remove(call.arguments);
            return null;
          default:
            throw MissingPluginException();
        }
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(observingChannel, null),
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            navigatorObservers: [observer],
            home: EventDetail(event: event),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Choose a location'), findsOneWidget);
      await tester.tap(find.text('Remind me'));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
      expect(find.textContaining('Notifications are disabled'), findsOneWidget);
      allow = true;
      await tester.tap(find.text('Remind me'));
      await tester.pumpAndSettle();
      expect(saved, {event.id});
      await tester.tap(find.text('Cancel reminder'));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
      final target = find.text('Open Sky View at event time');
      await tester.tap(target);
      final page = observer.latest! as MaterialPageRoute<void>;
      final sky = page.builder(tester.element(target)) as SkyViewScreen;
      expect(sky.initialUtc, event.utc);
      expect(sky.initialBodyId, 'SOL-MOON');
    },
  );
}
