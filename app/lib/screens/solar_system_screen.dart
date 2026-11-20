import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings.dart';
import '../sky_view/ephemeris.dart';
import 'sky_view_screen.dart';

class SolarSystemScreen extends ConsumerStatefulWidget {
  const SolarSystemScreen({super.key, this.initialUtc});
  final DateTime? initialUtc;

  @override
  ConsumerState<SolarSystemScreen> createState() => _SolarSystemScreenState();
}

class _SolarSystemScreenState extends ConsumerState<SolarSystemScreen> {
  late DateTime _utc = (widget.initialUtc ?? DateTime.now()).toUtc();
  String _selected = 'EARTH';
  bool _inner = true;

  bool _supported(DateTime date) => date.year >= 1950 && date.year <= 2050;

  Future<void> _pickDate() async {
    final initial = _supported(_utc) ? _utc : DateTime.utc(2000);
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(1950),
      lastDate: DateTime(2050, 12, 31),
      helpText: 'Choose a date in UTC',
    );
    if (date != null && mounted) {
      setState(
        () => _utc = DateTime.utc(
          date.year,
          date.month,
          date.day,
          _utc.hour,
          _utc.minute,
        ),
      );
    }
  }

  void _select(OrbitalBody body) => setState(() {
    _selected = body.id;
    if (body.position.length > 2) _inner = false;
  });

  @override
  Widget build(BuildContext context) {
    final bodies = _supported(_utc)
        ? heliocentricBodies(_utc)
        : <OrbitalBody>[];
    final body = bodies.where((b) => b.id == _selected).firstOrNull;
    final night = ref.watch(settingsProvider.select((s) => s.nightVision));
    final stamp = _utc
        .toIso8601String()
        .substring(0, 16)
        .replaceFirst('T', ' ');
    final screen = Scaffold(
      appBar: AppBar(title: const Text('Solar system')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Previous day',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _supported(_utc.subtract(const Duration(days: 1)))
                      ? () => setState(
                          () => _utc = _utc.subtract(const Duration(days: 1)),
                        )
                      : null,
                ),
                TextButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text('$stamp UTC'),
                ),
                IconButton(
                  tooltip: 'Next day',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _supported(_utc.add(const Duration(days: 1)))
                      ? () => setState(
                          () => _utc = _utc.add(const Duration(days: 1)),
                        )
                      : null,
                ),
              ],
            ),
            if (body == null)
              const Text(
                'Choose a date from 1950 through 2050 to see the planets.',
              )
            else ...[
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: _OrbitMap(
                      bodies: bodies,
                      selected: body,
                      radiusAu: _inner ? 2 : 32,
                      onSelected: _select,
                    ),
                  ),
                ),
              ),
              Center(
                child: Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Inner planets'),
                      selected: _inner,
                      onSelected: (_) {
                        setState(() {
                          _inner = true;
                          if (body.position.length > 2) _selected = 'EARTH';
                        });
                      },
                    ),
                    ChoiceChip(
                      label: const Text('All planets'),
                      selected: !_inner,
                      onSelected: (_) => setState(() => _inner = false),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Seen from above the north ecliptic pole. Rings are spaced ${_inner ? "0.5" : "8"} AU apart on a linear scale. Body markers are enlarged.',
              ),
              const Divider(height: 32),
              DropdownButton<String>(
                value: body.id,
                isExpanded: true,
                items: [
                  for (final b in bodies)
                    DropdownMenuItem(value: b.id, child: Text(b.name)),
                ],
                onChanged: (id) {
                  if (id != null) _select(bodies.firstWhere((b) => b.id == id));
                },
              ),
              Text(
                body.id == 'SOL-SUN'
                    ? 'The Sun is at the center of this map.'
                    : '${body.position.length.toStringAsFixed(3)} AU from the Sun',
              ),
              if (body.id == 'EARTH')
                const Text('Earth marks the Earth–Moon center of mass.'),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SkyViewScreen(
                        initialUtc: _utc,
                        initialManualMode: true,
                        initialBodyId: body.id == 'EARTH' ? null : body.id,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.explore_outlined),
                  label: Text(
                    body.id == 'EARTH'
                        ? 'Open sky from Earth'
                        : 'Find ${body.name} in Sky View',
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Approximate positions from JPL orbital elements, projected onto the J2000 ecliptic. Explorer dates cover 1950–2050.',
              ),
            ],
          ],
        ),
      ),
    );
    if (!night) return screen;
    return ColorFiltered(
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
      child: screen,
    );
  }
}

class _OrbitMap extends StatelessWidget {
  const _OrbitMap({
    required this.bodies,
    required this.selected,
    required this.radiusAu,
    required this.onSelected,
  });

  final List<OrbitalBody> bodies;
  final OrbitalBody selected;
  final double radiusAu;
  final ValueChanged<OrbitalBody> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth;
        final scale = math.max(0.0, side / 2 - 14) / radiusAu;
        final center = Offset(side / 2, side / 2);
        final points = {
          for (final b in bodies)
            if (b.position.length <= radiusAu)
              b: center + Offset(b.position.x, -b.position.y) * scale,
        };
        return Semantics(
          image: true,
          label:
              'Sun-centered map. ${selected.name} selected. Use the planet selector below the map.',
          child: GestureDetector(
            excludeFromSemantics: true,
            onTapUp: (tap) {
              OrbitalBody? nearest;
              var best = 24.0;
              for (final entry in points.entries) {
                final d = (entry.value - tap.localPosition).distance;
                if (d < best) {
                  nearest = entry.key;
                  best = d;
                }
              }
              if (nearest != null) onSelected(nearest);
            },
            child: CustomPaint(
              painter: _OrbitPainter(points, selected.id, scale * radiusAu),
            ),
          ),
        );
      },
    );
  }
}

class _OrbitPainter extends CustomPainter {
  const _OrbitPainter(this.points, this.selectedId, this.radius);
  final Map<OrbitalBody, Offset> points;
  final String selectedId;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final ring = Paint()
      ..color = const Color(0xFF434A5E)
      ..style = PaintingStyle.stroke;
    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(center, radius * i / 4, ring);
    }
    for (final entry in points.entries) {
      final paint = Paint()..color = entry.key.color;
      canvas.drawCircle(entry.value, entry.key.id == 'SOL-SUN' ? 6 : 4, paint);
      if (entry.key.id == selectedId) {
        paint.style = PaintingStyle.stroke;
        paint.strokeWidth = 2;
        canvas.drawCircle(entry.value, 9, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_OrbitPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.selectedId != selectedId ||
      oldDelegate.radius != radius;
}
