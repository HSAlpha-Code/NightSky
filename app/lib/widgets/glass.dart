import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Frosted-glass surface used for controls floating over the camera feed and images:
/// blurs what is behind it, with a dark tint and a faint light border.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.padding = EdgeInsets.zero,
    this.blur = 12,
    this.opacity = 0.25,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final double blur;

  /// Strength of the dark tint (0..1).
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: opacity),
            borderRadius: borderRadius,
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          // Transparent Material so InkWells inside show their splash on the glass.
          child: Material(
            type: MaterialType.transparency,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Round glass icon button (settings, tips, ...).
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Highlighted (e.g. a toggle that is on).
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Glass(
      borderRadius: const BorderRadius.all(Radius.circular(999)),
      opacity: selected ? 0.25 : 0.45,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        color: selected ? scheme.primary : Colors.white,
        icon: Icon(icon),
      ),
    );
  }
}

/// Segmented two-icon pill that switches between the 3D Sky View (globe) and Camera modes.
/// Keeping both icons visible with the active mode highlighted makes its purpose unmistakable
/// without needing a text label that could clip on narrow screens.
class ModeSwitchPill extends StatelessWidget {
  const ModeSwitchPill({
    super.key,
    required this.isSkyView,
    required this.tooltip,
    required this.onPressed,
    this.height = 34,
  });

  /// True when currently on Sky View (globe highlighted); false on Camera (camera highlighted).
  final bool isSkyView;
  final String tooltip;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final segmentSize = height - 8;
    final iconSize = (height * 0.45).clamp(14.0, 18.0);

    Widget segment({required IconData icon, required bool active}) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: segmentSize,
        height: segmentSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? scheme.primary : Colors.transparent,
        ),
        child: Icon(
          icon,
          size: iconSize,
          color: active ? scheme.onPrimary : Colors.white70,
        ),
      );
    }

    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Glass(
          borderRadius: const BorderRadius.all(Radius.circular(999)),
          opacity: 0.5,
          child: InkWell(
            borderRadius: const BorderRadius.all(Radius.circular(999)),
            onTap: onPressed,
            child: SizedBox(
              height: height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    segment(icon: Icons.public, active: isSkyView),
                    const SizedBox(width: 2),
                    segment(icon: Icons.camera_alt_outlined, active: !isSkyView),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
