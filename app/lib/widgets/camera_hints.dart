import 'package:flutter/material.dart';

import 'glass.dart';

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
    return Glass(
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
      child: Row(children: [
        Icon(icon, size: 20, color: Colors.amberAccent),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white)),
          ),
        ),
        if (action != null) TextButton(onPressed: onTap, child: Text(action!)),
      ]),
    );
  }
}

class CaptureTips extends StatelessWidget {
  const CaptureTips({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Glass(
      padding: const EdgeInsets.fromLTRB(16, 10, 4, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(top: 2, right: 12),
          child: Icon(Icons.tips_and_updates_outlined, size: 20, color: Colors.amberAccent),
        ),
        const Expanded(
          child: Text(
            'For best results:\n'
            '• Hold the phone steady (rest it on something if you can)\n'
            '• Turn on Night mode if your camera has it\n'
            '• Avoid city lights, the Moon and buildings in the frame',
            style: TextStyle(height: 1.4, color: Colors.white),
          ),
        ),
        IconButton(
            tooltip: 'Hide tips',
            icon: const Icon(Icons.close, size: 18, color: Colors.white70),
            onPressed: onClose),
      ]),
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
      child: Glass(
        borderRadius: const BorderRadius.all(Radius.circular(999)),
        padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (steady && progress != null)
            SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                  value: progress, strokeWidth: 2.5, color: Colors.greenAccent),
            )
          else
            Icon(steady ? Icons.check_circle : Icons.pan_tool_alt_outlined,
                color: steady ? Colors.greenAccent : Colors.amber, size: 18),
          const SizedBox(width: 8),
          Text(
            steady ? (progress != null ? 'Steady, taking photo…' : 'Steady') : 'Hold steady…',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.white),
          ),
        ]),
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
      child: Glass(
        borderRadius: const BorderRadius.all(Radius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
