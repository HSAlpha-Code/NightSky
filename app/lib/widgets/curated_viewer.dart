import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../curated.dart';

/// More images than this: show a "3 / 12" counter instead of one dot per image.
const maxCuratedDots = 8;

Future<void> openExternalLink(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Horizontally swipeable curated images with page dots, and the caption, credit and source
/// link of the image currently shown. A single image has no dots and cannot be swiped.
class CuratedViewer extends StatefulWidget {
  const CuratedViewer({
    super.key,
    required this.highlights,
    this.initialPage = 0,
    this.onPageChanged,
    this.onOpenLink,
  });

  final List<CuratedHighlight> highlights;
  final int initialPage;
  final ValueChanged<int>? onPageChanged;

  /// Defaults to opening the link in the browser.
  final ValueChanged<String>? onOpenLink;

  @override
  State<CuratedViewer> createState() => _CuratedViewerState();
}

class _CuratedViewerState extends State<CuratedViewer> {
  late final PageController _controller;
  late int _page;

  int get _count => widget.highlights.length;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage.clamp(0, math.max(0, _count - 1));
    _controller = PageController(initialPage: _page);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheAround(_page);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Warm the shared image cache for the neighbours so swiping feels instant.
  void _precacheAround(int page) {
    for (final i in [page - 1, page + 1]) {
      if (i < 0 || i >= _count) continue;
      precacheImage(NetworkImage(widget.highlights[i].imageUrl), context, onError: (_, _) {});
    }
  }

  void _changed(int page) {
    setState(() => _page = page);
    _precacheAround(page);
    widget.onPageChanged?.call(page);
  }

  void _goTo(int page) => _controller.animateToPage(page,
      duration: const Duration(milliseconds: 250), curve: Curves.easeOut);

  @override
  Widget build(BuildContext context) {
    final items = widget.highlights;
    if (items.isEmpty) return const SizedBox.shrink();
    final current = items[_page.clamp(0, items.length - 1)];
    final multiple = items.length > 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AspectRatio(
        aspectRatio: 4 / 3,
        child: PageView.builder(
          key: const Key('curated-pages'),
          controller: _controller,
          // One image: nothing to swipe to.
          physics: multiple ? const PageScrollPhysics() : const NeverScrollableScrollPhysics(),
          allowImplicitScrolling: true,
          itemCount: items.length,
          onPageChanged: _changed,
          itemBuilder: (context, i) => _CuratedImage(
            key: ValueKey('curated-image-$i'),
            url: items[i].imageUrl,
            label: items[i].title.isNotEmpty ? items[i].title : 'Image ${i + 1} of ${items.length}',
          ),
        ),
      ),
      if (multiple)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: PageIndicator(
            controller: _controller,
            count: items.length,
            initialPage: _page,
            onTap: _goTo,
          ),
        ),
      _Attribution(item: current, onOpenLink: widget.onOpenLink ?? openExternalLink),
    ]);
  }
}

class _CuratedImage extends StatelessWidget {
  const _CuratedImage({super.key, required this.url, required this.label});

  final String url;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Semantics(
        image: true,
        label: label,
        // Image.network uses the app-wide ImageCache (same as the precaching above).
        child: Image.network(
          url,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            final total = progress.expectedTotalBytes;
            return Center(
              child: CircularProgressIndicator(
                value: total == null ? null : progress.cumulativeBytesLoaded / total,
              ),
            );
          },
          errorBuilder: (context, error, _) => const Center(
            child: Icon(Icons.image_not_supported_outlined, size: 48, color: Colors.white54),
          ),
        ),
      ),
    );
  }
}

/// Dots that follow the finger: each dot's size and colour are interpolated from the
/// controller's fractional page value, so the highlight moves while swiping (and animates
/// when a dot is tapped). Above [maxCuratedDots] images it shows a "3 / 12" counter.
class PageIndicator extends StatelessWidget {
  const PageIndicator({
    super.key,
    required this.controller,
    required this.count,
    required this.onTap,
    this.initialPage = 0,
  });

  final PageController controller;
  final int count;
  final int initialPage;
  final ValueChanged<int> onTap;

  double _page() {
    if (controller.hasClients && controller.position.haveDimensions) {
      return controller.page ?? initialPage.toDouble();
    }
    return initialPage.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final page = _page();
        if (count > maxCuratedDots) {
          final n = page.round().clamp(0, count - 1) + 1;
          return Semantics(
            label: 'Image $n of $count',
            excludeSemantics: true,
            child: Center(child: Text('$n / $count', key: const Key('curated-counter'))),
          );
        }
        return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < count; i++)
            Semantics(
              button: true,
              selected: page.round() == i,
              label: 'Image ${i + 1} of $count',
              excludeSemantics: true,
              child: GestureDetector(
                key: Key('curated-dot-tap-$i'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
                  child: _Dot(
                    key: Key('curated-dot-$i'),
                    // 1 on the current page, fading to 0 one page away.
                    t: (1 - (page - i).abs()).clamp(0.0, 1.0),
                    active: scheme.primary,
                    inactive: scheme.onSurface.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
        ]);
      },
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({super.key, required this.t, required this.active, required this.inactive});

  final double t;
  final Color active;
  final Color inactive;

  @override
  Widget build(BuildContext context) => Container(
        width: 8 + 10 * t,
        height: 8,
        decoration: BoxDecoration(
          color: Color.lerp(inactive, active, t),
          borderRadius: BorderRadius.circular(4),
        ),
      );
}

class _Attribution extends StatelessWidget {
  const _Attribution({required this.item, required this.onOpenLink});

  final CuratedHighlight item;
  final ValueChanged<String> onOpenLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final link = Uri.tryParse(item.sourceUrl);
    final hasLink = link != null && (link.scheme == 'https' || link.scheme == 'http');
    final outlet = item.sourceOutlet.isNotEmpty ? item.sourceOutlet : 'source';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        key: const Key('curated-attribution'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.title.isNotEmpty)
            Text(item.title, key: const Key('curated-title'), style: theme.textTheme.titleSmall),
          if (item.caption.isNotEmpty)
            Text(item.caption, key: const Key('curated-caption'), style: small),
          if (item.credit.isNotEmpty)
            Text('Credit: ${item.credit}', key: const Key('curated-credit'), style: small),
          if (item.sourceOutlet.isNotEmpty || hasLink)
            Row(children: [
              Text('Source: ', style: small),
              if (hasLink)
                InkWell(
                  key: const Key('curated-source-link'),
                  onTap: () => onOpenLink(item.sourceUrl),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(outlet,
                        style: small?.copyWith(
                            color: theme.colorScheme.primary,
                            decoration: TextDecoration.underline)),
                  ),
                )
              else
                Text(outlet, style: small),
            ]),
        ],
      ),
    );
  }
}
