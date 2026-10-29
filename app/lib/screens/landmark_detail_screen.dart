import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../state.dart';

/// Second-level view: one landmark seen from several points of view (Webb, Hubble, surveys),
/// plus basic facts and credit.
final landmarkDetailProvider = FutureProvider.autoDispose
    .family<LandmarkDetail, (String, DetailView)>((ref, args) {
  final (id, view) = args;
  final cancel = CancelToken();
  ref.onDispose(cancel.cancel); // switching view or leaving stops the download
  return ref
      .watch(apiClientProvider)
      .landmarkDetail(id, providerKey: view.providerKey, view: view.view, cancelToken: cancel);
});

/// Views offered for a landmark: best, Webb, Hubble (not for stars), then every survey.
List<DetailView> detailViews(Landmark lm, ProviderCatalog? catalog, String? surveyKey) => [
      DetailView('auto', surveyKey, 'Best'),
      if (!lm.isStar) ...[
        DetailView('jwst', surveyKey, 'Webb'),
        DetailView('hst', surveyKey, 'Hubble'),
      ],
      for (final p in catalog?.providers ?? const <SkyProviderInfo>[])
        DetailView('survey', p.key, p.name),
    ];

class LandmarkDetailScreen extends ConsumerStatefulWidget {
  const LandmarkDetailScreen({super.key, required this.landmark, this.providerKey});

  final Landmark landmark;

  /// Survey the user picked on the result screen (default for close-ups and colour).
  final String? providerKey;

  @override
  ConsumerState<LandmarkDetailScreen> createState() => _LandmarkDetailScreenState();
}

class _LandmarkDetailScreenState extends ConsumerState<LandmarkDetailScreen> {
  late DetailView _view = DetailView('auto', widget.providerKey, 'Best');

  @override
  Widget build(BuildContext context) {
    final lm = widget.landmark;
    final catalog = ref.watch(providerCatalogProvider).value;
    final views = detailViews(lm, catalog, widget.providerKey);
    final args = (lm.id, _view);
    final detail = ref.watch(landmarkDetailProvider(args));
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.black, title: Text(lm.name)),
      body: SafeArea(
        child: ListView(children: [
          _ViewPicker(
            views: views,
            selected: _view,
            onSelected: (v) => setState(() => _view = v),
          ),
          AspectRatio(
            aspectRatio: 1,
            child: detail.when(
              skipLoadingOnReload: false,
              data: (d) => InteractiveViewer(
                key: ValueKey(_view),
                maxScale: 8,
                child: Image.memory(d.image, fit: BoxFit.contain, gaplessPlayback: true),
              ),
              loading: () => _Loading(view: _view),
              error: (e, _) => _Error(
                message: e is ApiException ? e.message : 'Could not load the image.',
                onRetry: () => ref.invalidate(landmarkDetailProvider(args)),
              ),
            ),
          ),
          if (detail.value case final d? when !detail.isLoading) _ImageCredit(detail: d),
          LandmarkFacts(landmark: lm),
        ]),
      ),
    );
  }
}

class _ViewPicker extends StatelessWidget {
  const _ViewPicker({required this.views, required this.selected, required this.onSelected});

  final List<DetailView> views;
  final DetailView selected;
  final ValueChanged<DetailView> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          for (final v in views)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: ValueKey('view-${v.view}-${v.providerKey}'),
                avatar: Icon(
                  switch (v.view) {
                    'jwst' || 'hst' => Icons.auto_awesome,
                    'auto' => Icons.star_outline,
                    _ => Icons.public,
                  },
                  size: 16,
                ),
                label: Text(v.label),
                selected: v == selected,
                onSelected: (_) => onSelected(v),
              ),
            ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.view});

  final DetailView view;

  @override
  Widget build(BuildContext context) {
    final text = switch (view.view) {
      'jwst' => 'Stitching Webb images…\nThe first time can take up to a minute.',
      'hst' => 'Stitching Hubble images…\nThe first time can take up to a minute.',
      'auto' => 'Looking for Webb and Hubble images…\nThe first time can take up to a minute.',
      _ => 'Loading ${view.label}…',
    };
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(text, textAlign: TextAlign.center),
      ]),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.image_not_supported_outlined, size: 48),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ]),
      ),
    );
  }
}

class _ImageCredit extends StatelessWidget {
  const _ImageCredit({required this.detail});

  final LandmarkDetail detail;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(detail.fromSpaceTelescope ? Icons.auto_awesome : Icons.public,
              size: 16, color: detail.fromSpaceTelescope ? Colors.amber : null),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              switch (detail.imageSource) {
                'jwst' => 'James Webb Space Telescope mosaic',
                'hst' => 'Hubble Space Telescope mosaic',
                _ => 'Survey close-up',
              },
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ]),
        if (detail.caption.isNotEmpty) Text(detail.caption, style: small),
        Text('Credit: ${detail.credit}', style: small),
      ]),
    );
  }
}

/// Name, type, magnitude, distance, catalogue names.
class LandmarkFacts extends StatelessWidget {
  const LandmarkFacts({super.key, required this.landmark});

  final Landmark landmark;

  @override
  Widget build(BuildContext context) {
    final lm = landmark;
    final rows = <(String, String)>[
      ('Type', lm.typeLabel),
      if (lm.magnitude != null) ('Brightness', 'magnitude ${lm.magnitude!.toStringAsFixed(1)}'),
      if (lm.distanceLy != null) ('Distance', formatDistance(lm.distanceLy!)),
      if (lm.sizeArcmin != null && !lm.isStar)
        ('Apparent size', '${lm.sizeArcmin!.toStringAsFixed(lm.sizeArcmin! < 10 ? 1 : 0)}′'),
      if (lm.constellation.isNotEmpty) ('Constellation', lm.constellation),
      if (lm.aliases.isNotEmpty) ('Also known as', lm.aliases.join(', ')),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 120,
                child: Text(label, style: Theme.of(context).textTheme.bodySmall),
              ),
              Expanded(child: Text(value)),
            ]),
          ),
        const SizedBox(height: 8),
        Text('Object data: OpenNGC (CC BY-SA 4.0) and IAU Catalog of Star Names.',
            style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}

String formatDistance(double ly) {
  if (ly >= 1e6) return '${(ly / 1e6).toStringAsFixed(ly >= 1e7 ? 0 : 1)} million light-years';
  if (ly >= 1e4) return '${(ly / 1000).round()} thousand light-years';
  return '${ly.round()} light-years';
}
