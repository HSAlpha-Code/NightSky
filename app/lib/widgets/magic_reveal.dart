import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Subtle sparkle for a freshly fetched image: whenever [trigger] changes to a new non-null
/// value, a few small white stars twinkle faintly over the image and fade away. Nothing covers
/// the image.
///
/// Decorative only: the overlay never takes touches, and with reduced motion (system
/// setting) the child is simply shown.
class MagicReveal extends StatefulWidget {
  const MagicReveal({
    super.key,
    required this.child,
    required this.trigger,
    this.origin = Alignment.center,
    this.duration = defaultDuration,
  });

  static const defaultDuration = Duration(milliseconds: 1800);

  final Widget child;

  /// Play the reveal each time this changes to a new non-null value (e.g. new image bytes).
  final Object? trigger;
  final Alignment origin;
  final Duration duration;

  @override
  State<MagicReveal> createState() => _MagicRevealState();
}

class _MagicRevealState extends State<MagicReveal> with SingleTickerProviderStateMixin {
  // Starts finished (child fully shown) until there is something to reveal.
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration, value: 1);
  bool _first = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_first) {
      _first = false;
      if (widget.trigger != null) _play();
    }
  }

  @override
  void didUpdateWidget(MagicReveal old) {
    super.didUpdateWidget(old);
    if (widget.trigger != null && !identical(widget.trigger, old.trigger)) _play();
  }

  void _play() {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        if (t >= 1) return child!;
        // The child stays fully visible and interactive; the stars are only painted over it.
        return Stack(fit: StackFit.passthrough, children: [
          child!,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                key: const Key('magic-reveal'),
                painter: _SparklePainter(t),
              ),
            ),
          ),
        ]);
      },
    );
  }
}

/// A fixed set of sparkles: position (0..1 of the field), size, phase, speed.
final List<(double, double, double, double, double)> _sparkles = () {
  final random = math.Random(42);
  return [
    for (var i = 0; i < 35; i++)
      (
        random.nextDouble(),
        random.nextDouble(),
        2 + random.nextDouble() * 4,
        random.nextDouble() * 2 * math.pi,
        2 + random.nextDouble() * 3,
      ),
  ];
}();

class _SparklePainter extends CustomPainter {
  _SparklePainter(this.t);

  final double t;

  /// A tiny four-pointed star with a faint glow.
  static void _star(Canvas canvas, Offset c, double r, double alpha) {
    if (alpha <= 0.01) return;
    final a = alpha.clamp(0.0, 1.0);
    canvas.drawCircle(
      c,
      r * 0.7,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.25 * a)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.6),
    );
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white.withValues(alpha: a));
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Fade in and out so the stars come and go gently.
    final envelope = math.sin(t * math.pi);
    if (envelope <= 0) return;
    for (final (fx, fy, starSize, phase, speed) in _sparkles) {
      final twinkle = math.pow(0.5 + 0.5 * math.sin(phase + t * speed * math.pi * 2), 3);
      _star(canvas, Offset(fx * size.width, fy * size.height), starSize * (0.5 + 0.5 * twinkle),
          0.55 * twinkle * envelope);
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.t != t;
}
