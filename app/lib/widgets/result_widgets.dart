import 'package:flutter/material.dart';

import '../models.dart';
import '../sky_math.dart';
import 'glass.dart';

/// Coordinates, solve source and image credit shown inside the Details sheet.
class InfoBar extends StatelessWidget {
  const InfoBar({super.key, required this.solve, this.image});

  final SolveResult solve;
  final SkyImage? image;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final approx = solve.approximate;
    final statusColor = approx ? Colors.amber : Colors.greenAccent;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DetailTile(
            icon: Icons.explore_outlined,
            iconColor: scheme.primary,
            title: 'Sky coordinates',
            body: 'RA ${formatRa(solve.ra)}   Dec ${formatDec(solve.dec)}   '
                'FOV ${solve.fov.toStringAsFixed(1)}°',
            tabular: true,
          ),
          const SizedBox(height: 8),
          _DetailTile(
            icon: approx ? Icons.sensors : Icons.verified_outlined,
            iconColor: statusColor,
            title: approx ? 'Approximate alignment' : 'Plate-solved alignment',
            body: approx
                ? 'Position from phone sensors'
                : 'Matched stars · confidence ${(solve.confidence * 100).round()}%',
          ),
          if (image != null && image!.credit.isNotEmpty) ...[
            const SizedBox(height: 8),
            _DetailTile(
              icon: Icons.layers_outlined,
              iconColor: Colors.lightBlueAccent,
              title: image!.providerName.isNotEmpty ? image!.providerName : 'Survey image',
              body: 'Image: ${image!.credit}',
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    this.tabular = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final bool tabular;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: iconColor.withValues(alpha: 0.15),
              ),
              child: Icon(icon, size: 17, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: textTheme.labelMedium?.copyWith(color: Colors.white60),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rounded alert card for non-fatal image errors (with optional action such as "Retry").
class Notice extends StatelessWidget {
  const Notice({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
    this.action,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String text;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white),
              ),
            ),
            if (action != null) TextButton(onPressed: onTap, child: Text(action!)),
          ]),
        ),
      ),
    );
  }
}

/// Frosted pill drawn over the result image ("Approximate position", "Showing X").
/// Tapping it shows the full explanation in a snack bar.
class NoticeChip extends StatelessWidget {
  const NoticeChip({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.details,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String details;

  @override
  Widget build(BuildContext context) {
    return Glass(
      borderRadius: const BorderRadius.all(Radius.circular(999)),
      opacity: 0.58,
      blur: 10,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(999)),
          border: Border.all(color: color.withValues(alpha: 0.55)),
        ),
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(999)),
          onTap: () => ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text(details),
              ),
            ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.info_outline, size: 13, color: Colors.white54),
            ]),
          ),
        ),
      ),
    );
  }
}

class ProgressMessage extends StatelessWidget {
  const ProgressMessage({super.key, required this.text, this.onCancel});

  final String text;

  /// Shows a "Cancel" button when set.
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Glass(
            borderRadius: const BorderRadius.all(Radius.circular(24)),
            opacity: 0.65,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.square(
                      dimension: 48,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: scheme.primary,
                      ),
                    ),
                    Icon(Icons.auto_awesome, size: 20, color: scheme.primary),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                text,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                      height: 1.4,
                    ),
              ),
              if (onCancel != null) ...[
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Cancel'),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Full-screen error with "Retry" (network errors) and "Take another".
class ErrorMessage extends StatelessWidget {
  const ErrorMessage({super.key, required this.error, required this.onRetry, required this.onBack});

  final ApiException error;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final solveFailed = error.code == 'SOLVE_FAILED';
    final accent = solveFailed ? Colors.amber : Colors.redAccent;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF0E1320),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.14),
                    border: Border.all(color: accent.withValues(alpha: 0.35)),
                  ),
                  child: Icon(
                    solveFailed ? Icons.cloud_outlined : Icons.wifi_off_rounded,
                    size: 32,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  solveFailed ? "We couldn't place this photo" : 'Something went wrong',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  error.message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                        height: 1.4,
                      ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    if (!solveFailed)
                      OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
                    FilledButton(onPressed: onBack, child: const Text('Take another')),
                  ],
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
