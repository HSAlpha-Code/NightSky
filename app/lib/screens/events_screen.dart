import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../observing.dart';
import '../settings.dart';
import '../sky_view/astro_math.dart';
import '../sky_view/ephemeris.dart';
import 'sky_view_screen.dart';

String _stamp(BuildContext context, DateTime utc) {
  final local = utc.toLocal();
  final format = MaterialLocalizations.of(context);
  return '${format.formatMediumDate(local)} ${local.year} · ${format.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))} ${local.timeZoneName}';
}

class EventsScreen extends ConsumerStatefulWidget {
  const EventsScreen({super.key, this.moonOnly = false});
  final bool moonOnly;
  @override
  ConsumerState<EventsScreen> createState() => _EventsState();
}

class _EventsState extends ConsumerState<EventsScreen> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final calendar = ref.watch(observingCalendarProvider);
    return _NightPage(
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.moonOnly ? 'Moon phases' : 'Observing events'),
        ),
        body: calendar.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: TextButton(
              onPressed: () => ref.invalidate(observingCalendarProvider),
              child: const Text('Calendar unavailable · Retry'),
            ),
          ),
          data: (all) {
            final now = DateTime.now().toUtc();
            final events = all
                .where(
                  (e) => e.utc.isAfter(now) && (!widget.moonOnly || !e.shower),
                )
                .toList();
            return ListView.builder(
              itemCount: events.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  final empty = events.isEmpty
                      ? '\nNo upcoming events in the bundled calendar.'
                      : '';
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Global events in your device time zone. Moon phases cover 2025–2030. Four major meteor showers cover 2026–2027.$empty',
                    ),
                  );
                }
                final e = events[i - 1];
                return ListTile(
                  leading: Icon(
                    e.shower ? Icons.auto_awesome : Icons.brightness_2_outlined,
                  ),
                  title: Text(e.title),
                  subtitle: Text(
                    '${e.shower ? "Approx. " : ""}${_stamp(context, e.utc)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => EventDetail(event: e),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class EventDetail extends ConsumerStatefulWidget {
  const EventDetail({super.key, required this.event});
  final ObservingEvent event;
  @override
  ConsumerState<EventDetail> createState() => _EventDetailState();
}

class _EventDetailState extends ConsumerState<EventDetail>
    with WidgetsBindingObserver {
  String status = 'loading';
  bool busy = false;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    timer = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !busy) _refresh();
  }

  Future<void> _refresh() async {
    var next = 'unsupported';
    if (androidObserving) {
      try {
        next =
            await observingChannel.invokeMethod<String>(
              'status',
              widget.event.id,
            ) ??
            'error';
      } on PlatformException {
        next = 'error';
      } on MissingPluginException {
        next = 'unsupported';
      }
    }
    if (mounted) setState(() => status = next);
  }

  Future<void> _change() async {
    setState(() => busy = true);
    try {
      if (status == 'scheduled' || status == 'paused') {
        await observingChannel.invokeMethod<void>('cancel', widget.event.id);
      } else if (await observingChannel.invokeMethod<bool>('permission') ==
          true) {
        await observingChannel.invokeMethod<bool>('schedule', widget.event.id);
      }
      await _refresh();
    } on PlatformException {
      if (mounted) setState(() => status = 'error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final settings = ref.watch(settingsProvider);
    final lat = settings.manualLatitude, lon = settings.manualLongitude;
    var guidance = 'Choose a location in Sky View to estimate sky conditions.';
    if (lat != null && lon != null) {
      final sky = computeSolarSystem(
        when: event.utc,
        latitudeDeg: lat,
        longitudeDeg: lon,
      );
      final moon = raDecToAltAz(
        raDeg: sky.moon.raDeg,
        decDeg: sky.moon.decDeg,
        latitudeDeg: lat,
        longitudeDeg: lon,
        when: event.utc,
      );
      guidance =
          '${settings.useManualLocation ? "Selected location" : "Last saved location"} (${lat.toStringAsFixed(2)}°, ${lon.toStringAsFixed(2)}°) at the listed instant\nSun altitude ≈ ${sky.sunAltitudeDeg.round()}°. Moon altitude ≈ ${moon.altitudeDeg.round()}°. Negative values are below the geometric horizon.';
    }
    final active = status == 'scheduled' || status == 'paused';
    final tooLate = !event.reminderUtc.isAfter(DateTime.now().toUtc());
    final message = switch (status) {
      'scheduled' =>
        'Reminder scheduled for about one hour before the event. Android may delay delivery.',
      'paused' =>
        'Reminder saved. Enable notifications in Android settings to receive it.',
      'blocked' =>
        'Notifications are disabled. Allow notifications when prompted or enable them in Android settings.',
      'unsupported' => 'Event reminders are available on Android.',
      'loading' => 'Checking reminder…',
      'error' => 'Reminder status unavailable.',
      _ =>
        tooLate
            ? 'The reminder time has passed.'
            : 'Android can remind you about one hour beforehand.',
    };
    return _NightPage(
      child: Scaffold(
        appBar: AppBar(title: Text(event.title)),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              _stamp(context, event.utc),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              event.shower
                  ? 'Approximate global maximum from the International Meteor Organization annual calendar. Activity can peak hours earlier or later. Look for a dark sky while the radiant is above your horizon.'
                  : 'Global lunar phase from the U.S. Naval Observatory, tabulated to the minute.',
            ),
            const SizedBox(height: 20),
            Text(guidance),
            const SizedBox(height: 8),
            const Text(
              'Terrain, cloud and light pollution can affect local observing.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.explore_outlined),
              label: const Text('Open Sky View at event time'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => SkyViewScreen(
                    initialUtc: event.utc,
                    initialBodyId: event.shower ? null : 'SOL-MOON',
                    initialManualMode: true,
                  ),
                ),
              ),
            ),
            const Divider(height: 36),
            Text(message),
            const SizedBox(height: 8),
            if (!['unsupported', 'loading'].contains(status))
              FilledButton(
                onPressed: busy || (!active && tooLate)
                    ? null
                    : (status == 'error' ? _refresh : _change),
                child: Text(
                  active
                      ? 'Cancel reminder'
                      : status == 'error'
                      ? 'Retry'
                      : 'Remind me',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NightPage extends ConsumerWidget {
  const _NightPage({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(settingsProvider.select((s) => s.nightVision))
      ? ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            0.3,
            0.59,
            0.11,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
          ]),
          child: child,
        )
      : child;
}
