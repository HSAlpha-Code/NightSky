import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state.dart';
import '../widgets/compare_view.dart';
import '../widgets/provider_picker.dart';
import '../widgets/result_widgets.dart';

class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({super.key});

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  final _compareKey = GlobalKey<CompareViewState>();
  double _split = 0; // 0 = survey image, 1 = original photo

  void _setSplit(double v) {
    setState(() => _split = v);
    _compareKey.currentState?.setSplit(v);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider);
    final session = ref.read(sessionProvider.notifier);
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) session.reset();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text('Your sky'),
          actions: [
            if (s.solve != null)
              IconButton(
                tooltip: 'Image source',
                icon: const Icon(Icons.layers_outlined),
                onPressed: s.busy
                    ? null
                    : () => showProviderPicker(context, ref, onSelected: session.changeProvider),
              ),
          ],
        ),
        body: SafeArea(child: _body(s, session)),
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

    return Column(children: [
      if (s.solve?.approximate ?? false)
        Notice(
          icon: Icons.gps_not_fixed,
          color: Colors.amber,
          text: 'Approximate position. ${s.solve!.message}',
        ),
      if (s.skyImage?.fallbackUsed ?? false)
        Notice(
          icon: Icons.swap_horiz,
          color: Colors.lightBlueAccent,
          text: s.skyImage!.fallbackMessage ?? 'Showing a different image source.',
        ),
      if (s.imageError != null)
        Notice(
          icon: Icons.cloud_off,
          color: Colors.redAccent,
          text: '${s.imageError!.message} Showing your original photo.',
          action: 'Retry',
          onTap: session.retry,
        ),
      Expanded(
        child: Stack(fit: StackFit.expand, children: [
          if (s.skyImage != null)
            CompareView(
              key: _compareKey,
              original: original,
              replacement: MemoryImage(s.skyImage!.bytes),
              aspectRatio: aspect,
              initialSplit: _split,
            )
          else
            Center(
              child: AspectRatio(
                  aspectRatio: aspect, child: Image(image: original, fit: BoxFit.fill)),
            ),
          if (s.busy)
            ColoredBox(
              color: Colors.black54,
              child: ProgressMessage(
                text: switch (s.stage) {
                  Stage.solving => 'Finding your stars…\nThis can take up to a minute.',
                  Stage.fetchingImage => 'Fetching the survey image…',
                  _ => 'Preparing photo…',
                },
              ),
            ),
        ]),
      ),
      if (s.skyImage != null) _compareSlider(),
      if (s.solve != null) InfoBar(solve: s.solve!, image: s.skyImage),
    ]);
  }

  Widget _compareSlider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        TextButton(onPressed: () => _setSplit(0), child: const Text('Survey')),
        Expanded(
          child: Slider(
            key: const Key('compare-slider'),
            value: _split,
            onChanged: _setSplit,
            semanticFormatterCallback: (v) => '${(v * 100).round()}% original photo',
          ),
        ),
        TextButton(onPressed: () => _setSplit(1), child: const Text('My photo')),
      ]),
    );
  }
}
