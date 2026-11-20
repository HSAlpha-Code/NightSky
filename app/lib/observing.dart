import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const observingChannel = MethodChannel('night_sky/observing');
bool get androidObserving =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

class ObservingEvent {
  const ObservingEvent(this.id, this.title, this.utc, this.kind);
  final String id, title, kind;
  final DateTime utc;
  bool get shower => kind == 'shower';
  DateTime get reminderUtc => utc.subtract(const Duration(hours: 1));
}

List<ObservingEvent> parseCalendar(String csv) {
  return csv
      .trim()
      .split('\n')
      .skip(1)
      .map((line) {
        final [id, title, millis, kind] = line.trim().split(',');
        return ObservingEvent(
          id,
          title,
          DateTime.fromMillisecondsSinceEpoch(int.parse(millis), isUtc: true),
          kind,
        );
      })
      .toList(growable: false);
}

final observingCalendarProvider = FutureProvider<List<ObservingEvent>>(
  (ref) async =>
      parseCalendar(await rootBundle.loadString('assets/observing/events.csv')),
);
