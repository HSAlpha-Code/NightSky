import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'panorama_packs.dart';

class PanoramaDownloads extends ConsumerWidget {
  const PanoramaDownloads({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(panoramaPacksProvider);
    final notifier = ref.read(panoramaPacksProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Panorama resolution',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        const Text(
          'NASA Deep Star Maps 2020. 8K is included; download 16K or 32K '
          'for more detail when zooming in. Installed maps work offline. '
          'Higher resolutions use more storage and memory. Wi-Fi recommended.',
        ),
        for (final r in PanoramaResolution.values)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              state.active == r
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
            ),
            title: Text(
              '${r.label}${r == PanoramaResolution.eightK ? ' (included)' : ''}',
            ),
            subtitle: Text(
              '${r.k * 1024} x ${r.k * 512} - lossless'
              '${r == PanoramaResolution.eightK ? '' : ' - ${(r.downloadBytes / (1024 * 1024)).toStringAsFixed(1)} MiB'}'
              '${state.installed.contains(r) ? ' - installed' : ''}',
            ),
            onTap: r == PanoramaResolution.eightK || state.installed.contains(r)
                ? () => notifier.select(r)
                : null,
            trailing: r == PanoramaResolution.eightK
                ? null
                : state.installed.contains(r)
                ? IconButton(
                    tooltip: 'Remove ${r.label} download',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: state.downloading == null
                        ? () => notifier.remove(r)
                        : null,
                  )
                : TextButton(
                    onPressed: state.downloading == null
                        ? () => notifier.install(r)
                        : null,
                    child: Text('Download ${r.label}'),
                  ),
          ),
        if (state.downloading != null) ...[
          LinearProgressIndicator(value: state.progress),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Downloading ${state.downloading!.label}: ${(state.progress * 100).round()}%',
                ),
              ),
              TextButton(
                onPressed: notifier.cancel,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
        if (state.error != null)
          Text(
            state.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}
