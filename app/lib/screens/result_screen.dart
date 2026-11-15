import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../state.dart';
import '../widgets/compare_view.dart';
import '../widgets/landmark_overlay.dart';
import '../widgets/magic_reveal.dart';
import '../widgets/provider_picker.dart';
import '../widgets/result_widgets.dart';
import 'landmark_detail_screen.dart';

class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({super.key});

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  final _compareKey = GlobalKey<CompareViewState>();
  double _split = 0; // 0 = survey image, 1 = original photo
  bool _showMarkers = true;

  void _openLandmark(Landmark lm, String? providerKey) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LandmarkDetailScreen(landmark: lm, providerKey: providerKey),
    ));
  }

  void _setSplit(double v) {
    setState(() => _split = v);
    _compareKey.currentState?.setSplit(v);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider);
    final session = ref.read(sessionProvider.notifier);
    final landmarkCount = s.landmarks?.landmarks.length ?? 0;
    final hasLandmarks = s.skyImage != null && landmarkCount > 0;

    final shortLandscape = MediaQuery.sizeOf(context).height < 460;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) session.reset();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: const Color(0xFF05070D),
          appBar: AppBar(
            toolbarHeight: shortLandscape ? 46 : kToolbarHeight,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            titleSpacing: 4,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Your sky',
                  style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.2),
                ),
                if (hasLandmarks && !s.busy)
                  Text(
                    '$landmarkCount ${landmarkCount == 1 ? 'object' : 'objects'} in field',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white60,
                        ),
                  ),
              ],
            ),
            actions: [
              if (hasLandmarks)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _HeaderActionButton(
                    tooltip: _showMarkers ? 'Hide landmarks' : 'Show landmarks',
                    icon: _showMarkers ? Icons.location_on : Icons.location_off_outlined,
                    selected: _showMarkers,
                    onPressed: () => setState(() => _showMarkers = !_showMarkers),
                  ),
                ),
              if (s.solve != null)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _HeaderActionButton(
                    tooltip: 'Details',
                    icon: Icons.info_outline,
                    onPressed: () => _showDetails(s),
                  ),
                ),
              if (s.solve != null)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _HeaderActionButton(
                    tooltip: 'Image source',
                    icon: Icons.layers_outlined,
                    onPressed: s.busy
                        ? null
                        : () =>
                            showProviderPicker(context, ref, onSelected: session.changeProvider),
                  ),
                ),
            ],
          ),
          body: SafeArea(top: false, child: _body(s, session)),
        ),
      ),
    );
  }

  Widget _body(SessionState s, SessionNotifier session) {
    if (s.stage == Stage.error) {
      return ErrorMessage(
          error: s.error!, onRetry: session.retry, onBack: () => Navigator.of(context).pop());
    }
    final photo = s.photo;
    if (photo == null) return const ProgressMessage(text: 'Preparing photo…');
    final aspect = photo.width / photo.height;
    final original = MemoryImage(photo.jpeg);

    final chips = [
      if (s.solve?.approximate ?? false)
        NoticeChip(
          icon: Icons.gps_not_fixed,
          color: Colors.amber,
          label: 'Approximate position',
          details: 'Approximate position. ${s.solve!.message}',
        ),
      if (s.skyImage?.fallbackUsed ?? false)
        NoticeChip(
          icon: Icons.swap_horiz,
          color: Colors.lightBlueAccent,
          label: s.skyImage!.providerName.isNotEmpty
              ? 'Showing ${s.skyImage!.providerName}'
              : 'Different image source',
          details: s.skyImage!.fallbackMessage ?? 'Showing a different image source.',
        ),
    ];

    return Column(children: [
      if (s.imageError != null)
        Notice(
          icon: Icons.cloud_off,
          color: Colors.redAccent,
          text: '${s.imageError!.message} Showing your original photo.',
          action: 'Retry',
          onTap: session.retry,
        ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
              boxShadow: const [
                BoxShadow(color: Colors.black87, blurRadius: 20, offset: Offset(0, 8)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(19),
              child: Stack(fit: StackFit.expand, children: [
                if (s.skyImage != null)
                  // Each newly fetched survey image ripples in with a burst of shifting colours.
                  MagicReveal(
                    trigger: s.skyImage,
                    child: CompareView(
                      key: _compareKey,
                      original: original,
                      replacement: MemoryImage(s.skyImage!.bytes),
                      aspectRatio: aspect,
                      initialSplit: _split,
                      onSplitChanged: (v) => setState(() => _split = v),
                      overlayBuilder: _showMarkers && s.landmarks != null && !s.busy
                          ? (scale) => LandmarkOverlay(
                                landmarks: s.landmarks!.landmarks,
                                scale: scale,
                                onTap: (lm) => _openLandmark(lm, s.skyImage!.providerKey),
                              )
                          : null,
                    ),
                  )
                else
                  Center(
                    child: AspectRatio(
                      aspectRatio: aspect,
                      child: Image(image: original, fit: BoxFit.fill),
                    ),
                  ),
                if (s.busy)
                  ColoredBox(
                    color: Colors.black.withValues(alpha: 0.45),
                    child: ProgressMessage(
                      text: switch (s.stage) {
                        Stage.solving => 'Finding your stars…\nThis can take up to a minute.',
                        Stage.fetchingImage => 'Fetching the survey image…',
                        _ => 'Preparing photo…',
                      },
                      onCancel: s.stage == Stage.fetchingImage ? session.cancelImage : null,
                    ),
                  ),
                if (chips.isNotEmpty && !s.busy)
                  Positioned(
                    top: 10,
                    left: 10,
                    right: 10,
                    child: Wrap(spacing: 6, runSpacing: 6, children: chips),
                  ),
              ]),
            ),
          ),
        ),
      ),
      if (s.skyImage != null) _compareSlider(),
    ]);
  }

  /// Coordinates, solve source and image credit, opened from the ⓘ button.
  void _showDetails(SessionState s) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF10131C),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome_outlined, size: 20, color: Colors.white70),
                    const SizedBox(width: 8),
                    Text(
                      'Details',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
              InfoBar(solve: s.solve!, image: s.skyImage),
            ],
          ),
        ),
      ),
    );
  }

  Widget _compareSlider() {
    final scheme = Theme.of(context).colorScheme;
    final surveyActive = _split <= 0.08;
    final photoActive = _split >= 0.92;
    final compact = MediaQuery.sizeOf(context).height < 460;

    return Padding(
      padding: compact
          ? const EdgeInsets.fromLTRB(10, 2, 10, 6)
          : const EdgeInsets.fromLTRB(10, 4, 10, 10),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF0E1320),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: compact ? 2 : 4),
              child: Row(children: [
                _CompareEndpointButton(
                  icon: Icons.auto_awesome_outlined,
                  label: 'Survey',
                  active: surveyActive,
                  onPressed: () => _setSplit(0),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      activeTrackColor: scheme.primary,
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.16),
                      thumbColor: Colors.white,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    ),
                    child: Slider(
                      key: const Key('compare-slider'),
                      value: _split,
                      onChanged: _setSplit,
                      semanticFormatterCallback: (v) => '${(v * 100).round()}% original photo',
                    ),
                  ),
                ),
                _CompareEndpointButton(
                  icon: Icons.photo_camera_outlined,
                  label: 'My photo',
                  active: photoActive,
                  onPressed: () => _setSplit(1),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderActionButton extends StatelessWidget {
  const _HeaderActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = selected
        ? scheme.primary.withValues(alpha: 0.22)
        : Colors.white.withValues(alpha: 0.07);
    final border = selected
        ? scheme.primary.withValues(alpha: 0.55)
        : Colors.white.withValues(alpha: 0.12);
    final fg = onPressed == null
        ? Colors.white30
        : (selected ? scheme.primary : Colors.white);

    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: bg,
          shape: CircleBorder(side: BorderSide(color: border)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox.square(
              dimension: 38,
              child: Icon(icon, size: 19, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompareEndpointButton extends StatelessWidget {
  const _CompareEndpointButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: active ? scheme.primary.withValues(alpha: 0.22) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: active ? scheme.primary : Colors.white60,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: active ? Colors.white : Colors.white70,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
