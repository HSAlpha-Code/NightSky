import 'package:flutter/material.dart';

/// Compact pill + expandable Time Machine scrubber for exploring the sky earlier or later.
class TimeMachineBar extends StatelessWidget {
  const TimeMachineBar({
    super.key,
    required this.effectiveUtc,
    required this.isLive,
    required this.playing,
    required this.expanded,
    required this.sliderHours,
    required this.onToggleExpanded,
    required this.onSliderChanged,
    required this.onStep,
    required this.onTogglePlay,
    required this.onResetNow,
    required this.onPickDateTime,
  });

  final DateTime effectiveUtc;
  final bool isLive;
  final bool playing;
  final bool expanded;

  /// Offset in hours [-12..+12] relative to the current scrubber anchor time.
  final double sliderHours;

  final VoidCallback onToggleExpanded;
  final ValueChanged<double> onSliderChanged;
  final ValueChanged<Duration> onStep;
  final VoidCallback onTogglePlay;
  final VoidCallback onResetNow;
  final VoidCallback onPickDateTime;

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String formatLocalStamp(DateTime utc) {
    final local = utc.toLocal();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[local.month - 1]} ${local.day}, ${_two(local.hour)}:${_two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final stamp = formatLocalStamp(effectiveUtc);
    if (!expanded) {
      return ActionChip(
        key: const Key('time-machine-pill'),
        backgroundColor: Colors.black.withValues(alpha: 0.68),
        avatar: Icon(
          isLive ? Icons.schedule : Icons.history_toggle_off,
          size: 16,
          color: isLive ? Colors.greenAccent : Colors.amber,
        ),
        label: Text(
          isLive ? 'Live · $stamp' : '$stamp · Time travel',
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        ),
        onPressed: onToggleExpanded,
      );
    }

    final compact = MediaQuery.sizeOf(context).height < 440;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Card(
        key: const Key('time-machine-panel'),
        color: Colors.black.withValues(alpha: 0.84),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.white24),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, compact ? 4 : 8, 8, compact ? 4 : 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    isLive ? Icons.fiber_manual_record : Icons.history_toggle_off,
                    size: 14,
                    color: isLive ? Colors.greenAccent : Colors.amber,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$stamp${isLive ? ' (Now)' : ''}',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                  ),
                  if (!isLive)
                    TextButton(
                      key: const Key('time-reset-now'),
                      onPressed: onResetNow,
                      child: const Text('Now'),
                    ),
                  IconButton(
                    tooltip: 'Pick date & time',
                    visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
                    icon: const Icon(Icons.calendar_month_outlined, size: 19),
                    onPressed: onPickDateTime,
                  ),
                  IconButton(
                    tooltip: 'Close time controls',
                    visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
                    icon: const Icon(Icons.expand_more, size: 20),
                    onPressed: onToggleExpanded,
                  ),
                ],
              ),
              SizedBox(
                height: compact ? 32 : null,
                child: Row(
                  children: [
                    const Text('−12h', style: TextStyle(fontSize: 11, color: Colors.white60)),
                    Expanded(
                      child: Slider(
                        key: const Key('time-scrubber-slider'),
                        min: -12.0,
                        max: 12.0,
                        value: sliderHours.clamp(-12.0, 12.0),
                        onChanged: onSliderChanged,
                      ),
                    ),
                    const Text('+12h', style: TextStyle(fontSize: 11, color: Colors.white60)),
                  ],
                ),
              ),
              Wrap(
                spacing: 4,
                alignment: WrapAlignment.center,
                children: [
                  TextButton(
                    style: compact ? TextButton.styleFrom(visualDensity: VisualDensity.compact) : null,
                    onPressed: () => onStep(const Duration(days: -1)),
                    child: const Text('−1d'),
                  ),
                  TextButton(
                    style: compact ? TextButton.styleFrom(visualDensity: VisualDensity.compact) : null,
                    onPressed: () => onStep(const Duration(hours: -1)),
                    child: const Text('−1h'),
                  ),
                  FilledButton.tonalIcon(
                    key: const Key('time-play-toggle'),
                    style:
                        compact ? FilledButton.styleFrom(visualDensity: VisualDensity.compact) : null,
                    onPressed: onTogglePlay,
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow, size: 18),
                    label: Text(playing ? 'Pause' : 'Timelapse'),
                  ),
                  TextButton(
                    style: compact ? TextButton.styleFrom(visualDensity: VisualDensity.compact) : null,
                    onPressed: () => onStep(const Duration(hours: 1)),
                    child: const Text('+1h'),
                  ),
                  TextButton(
                    style: compact ? TextButton.styleFrom(visualDensity: VisualDensity.compact) : null,
                    onPressed: () => onStep(const Duration(days: 1)),
                    child: const Text('+1d'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
