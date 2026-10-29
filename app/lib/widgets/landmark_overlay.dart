import 'package:flutter/material.dart';

import '../models.dart';

/// Small tappable markers drawn over the survey image. Positions are fractions of the image
/// (0..1), so this must be laid out in the same box as the image.
///
/// Styles: filled ring + glow = Hubble/JWST image available; hollow dashed-looking ring =
/// basic info only; small white star dot = named star; faint pulsing = still checking.
class LandmarkOverlay extends StatelessWidget {
  const LandmarkOverlay({super.key, required this.landmarks, required this.onTap});

  final List<Landmark> landmarks;
  final ValueChanged<Landmark> onTap;

  static const double hitSize = 36;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      return Stack(clipBehavior: Clip.none, children: [
        for (final lm in landmarks)
          Positioned(
            left: lm.x * box.maxWidth - hitSize / 2,
            top: lm.y * box.maxHeight - hitSize / 2,
            child: LandmarkMarker(landmark: lm, onTap: () => onTap(lm)),
          ),
      ]);
    });
  }
}

class LandmarkMarker extends StatelessWidget {
  const LandmarkMarker({super.key, required this.landmark, required this.onTap});

  final Landmark landmark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lm = landmark;
    final hires = lm.hasHires == true;
    final Widget dot;
    if (lm.isStar) {
      dot = Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white70, width: 1.5),
        ),
      );
    } else if (hires) {
      dot = Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.amber.withValues(alpha: 0.35),
          border: Border.all(color: Colors.amber, width: 2),
          boxShadow: [BoxShadow(color: Colors.amber.withValues(alpha: 0.6), blurRadius: 8)],
        ),
        child: const Icon(Icons.auto_awesome, size: 9, color: Colors.white),
      );
    } else {
      dot = Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: lm.hasHires == null ? Colors.white38 : Colors.lightBlueAccent, width: 1.5),
        ),
      );
    }
    return Semantics(
      button: true,
      label: '${lm.name}, ${lm.typeLabel}${hires ? ', high-resolution image available' : ''}',
      child: Tooltip(
        message: lm.name,
        child: InkResponse(
          onTap: onTap,
          radius: LandmarkOverlay.hitSize / 2,
          child: SizedBox.square(
            dimension: LandmarkOverlay.hitSize,
            child: Center(child: dot),
          ),
        ),
      ),
    );
  }
}
