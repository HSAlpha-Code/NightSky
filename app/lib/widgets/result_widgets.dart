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

class ProgressMessage extends StatelessWidget {
  const ProgressMessage({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(text, textAlign: TextAlign.center),
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
