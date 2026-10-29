import 'package:flutter/material.dart';

import '../models.dart';
import '../sky_math.dart';

/// Coordinates, solve source and image credit under the result image.
class InfoBar extends StatelessWidget {
  const InfoBar({super.key, required this.solve, this.image});

  final SolveResult solve;
  final SkyImage? image;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          'RA ${formatRa(solve.ra)}   Dec ${formatDec(solve.dec)}   '
          'FOV ${solve.fov.toStringAsFixed(1)}°',
          style: style?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        const SizedBox(height: 2),
        Text(
          solve.approximate
              ? 'Position from phone sensors'
              : 'Matched stars · confidence ${(solve.confidence * 100).round()}%',
          style: style,
        ),
        if (image != null && image!.credit.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text('Image: ${image!.credit}', style: style),
        ],
      ]),
    );
  }
}

/// Coloured strip for "approximate position", "fallback provider" and image errors.
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
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.15),
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
        if (action != null) TextButton(onPressed: onTap, child: Text(action!)),
      ]),
    );
  }
}

/// Small pill drawn over the result image ("Approximate position", "Showing X").
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
    return Material(
      color: Colors.black.withValues(alpha: 0.6),
      shape: StadiumBorder(side: BorderSide(color: color.withValues(alpha: 0.7))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(details))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white)),
            ),
          ]),
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
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(text, textAlign: TextAlign.center),
        if (onCancel != null) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.close),
            label: const Text('Cancel'),
          ),
        ],
      ]),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(solveFailed ? Icons.cloud_outlined : Icons.wifi_off, size: 56),
          const SizedBox(height: 16),
          Text(
            solveFailed ? "We couldn't place this photo" : 'Something went wrong',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(error.message, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          Wrap(spacing: 12, children: [
            if (!solveFailed) OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            FilledButton(onPressed: onBack, child: const Text('Take another')),
          ]),
        ]),
      ),
    );
  }
}
