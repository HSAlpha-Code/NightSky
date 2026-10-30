import 'package:flutter/material.dart';

/// Default max orientation spread (degrees) over the last 0.6 s that still counts as
/// "steady". The user can change it in Settings (Steadiness).
const defaultMaxShakeDeg = 1.5;

class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.icon, required this.text, this.action, this.onTap});

  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      leading: Icon(icon),
      content: Text(text),
      actions: [
        if (action != null)
          TextButton(onPressed: onTap, child: Text(action!))
        else
          const SizedBox.shrink(),
      ],
    );
  }
}

class CaptureTips extends StatelessWidget {
  const CaptureTips({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.black.withValues(alpha: 0.7),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Expanded(
            child: Text(
              'For best results:\n'
              '• Hold the phone steady (rest it on something if you can)\n'
              '• Turn on Night mode if your camera has it\n'
              '• Avoid city lights, the Moon and buildings in the frame',
              style: TextStyle(height: 1.4),
            ),
          ),
          IconButton(
              tooltip: 'Hide tips', icon: const Icon(Icons.close, size: 18), onPressed: onClose),
        ]),
      ),
    );
  }
}

class SteadyIndicator extends StatelessWidget {
  const SteadyIndicator({
    super.key,
    required this.shakeDeg,
    this.maxShakeDeg = defaultMaxShakeDeg,
    this.autoCaptureProgress,
  });

  final double shakeDeg;
  final double maxShakeDeg;

  /// Auto-capture countdown (0..1) while the phone is steady; null when auto-capture is off.
  final double? autoCaptureProgress;

  @override
  Widget build(BuildContext context) {
    final steady = shakeDeg <= maxShakeDeg;
    final progress = autoCaptureProgress;
    return Center(
      child: Chip(
        avatar: steady && progress != null
            ? SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                    value: progress, strokeWidth: 2.5, color: Colors.greenAccent),
              )
            : Icon(steady ? Icons.check_circle : Icons.pan_tool_alt_outlined,
                color: steady ? Colors.greenAccent : Colors.amber, size: 18),
        label: Text(steady
            ? (progress != null ? 'Steady, taking photo…' : 'Steady')
            : 'Hold steady…'),
        backgroundColor: Colors.black.withValues(alpha: 0.6),
      ),
    );
  }
}

/// Where the camera points, from the motion sensors: altitude above the horizon and
/// compass heading (magnetic). Lets the user check the sensors before taking a photo.
class PointingReadout extends StatelessWidget {
  const PointingReadout({
    super.key,
    required this.altitudeDeg,
    required this.azimuthDeg,
    required this.usingGyroscope,
  });

  final double altitudeDeg;
  final double azimuthDeg;
  final bool usingGyroscope;

  static const _directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

  static String compassPoint(double azimuthDeg) =>
      _directions[((azimuthDeg % 360) / 45).round() % 8];

  @override
  Widget build(BuildContext context) {
    final below = altitudeDeg < 0;
    final alt = '${altitudeDeg >= 0 ? '+' : '−'}${altitudeDeg.abs().round()}°';
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          'Alt $alt${below ? ' (below horizon)' : ''} · '
          '${compassPoint(azimuthDeg)} ${azimuthDeg.round() % 360}° · '
          '${usingGyroscope ? 'gyro' : 'compass'}',
          key: const Key('pointing-readout'),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: below ? Colors.amber : Colors.white,
              fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ),
    );
  }
}
