import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Sky image over the original photo with a draggable divider: left of the divider shows the
/// original, right shows the survey image. Both images are fitted to the same box so the
/// fields line up (they share the photo's aspect ratio).
///
/// Pinch to zoom in on any spot and drag to pan; both images zoom together so they stay
/// aligned. The divider stays on screen: drag it by its handle (or a strip around it).
class CompareView extends StatefulWidget {
  const CompareView({
    super.key,
    required this.original,
    required this.replacement,
    required this.aspectRatio,
    this.initialSplit = 0.0,
    this.overlayBuilder,
  });

  final ImageProvider original;
  final ImageProvider replacement;
  final double aspectRatio;

  /// Drawn over the survey image only (clipped to the right of the divider), e.g. markers.
  /// It zooms with the image; `scale` is the current zoom (1 = not zoomed), so the overlay
  /// can keep its symbols at a constant on-screen size.
  final Widget Function(double scale)? overlayBuilder;

  /// 0 = only the replacement visible, 1 = only the original.
  final double initialSplit;

  static const double maxZoom = 8;

  /// Width of the touch strip around the divider that moves it (the rest pans the image).
  static const double dividerHitWidth = 48;

  @override
  State<CompareView> createState() => CompareViewState();
}

class CompareViewState extends State<CompareView> {
  late double split = widget.initialSplit;
  final zoom = TransformationController();

  /// Current zoom factor (1 = whole image visible).
  double get scale => zoom.value.getMaxScaleOnAxis();

  void setSplit(double v) => setState(() => split = v.clamp(0.0, 1.0));

  void resetZoom() => zoom.value = Matrix4.identity();

  @override
  void dispose() {
    zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: LayoutBuilder(builder: (context, box) {
          final x = box.maxWidth * split;
          return ClipRect(
            child: ListenableBuilder(
              listenable: zoom,
              builder: (context, _) {
                final s = scale;
                // The divider is in screen space; inside the zoomed content it sits here:
                final contentX = zoom.toScene(Offset(x, 0)).dx;
                return Stack(fit: StackFit.expand, children: [
                  InteractiveViewer(
                    key: const Key('sky-zoom'),
                    transformationController: zoom,
                    maxScale: CompareView.maxZoom,
                    child: Stack(fit: StackFit.expand, children: [
                      Image(image: widget.replacement, fit: BoxFit.fill, gaplessPlayback: true),
                      if (widget.overlayBuilder != null && split < 1)
                        ClipRect(
                          clipper: _RightClipper(contentX),
                          child: widget.overlayBuilder!(s),
                        ),
                    ]),
                  ),
                  // The original photo, zoomed exactly like the survey image underneath.
                  IgnorePointer(
                    child: ClipRect(
                      clipper: _LeftClipper(x),
                      child: Transform(
                        transform: zoom.value,
                        child: Image(image: widget.original, fit: BoxFit.fill),
                      ),
                    ),
                  ),
                  if (split > 0 && split < 1)
                    Positioned(
                      left: x - 1,
                      top: 0,
                      bottom: 0,
                      child: const IgnorePointer(
                          child: SizedBox(width: 2, child: ColoredBox(color: Colors.white70))),
                    ),
                  if (split > 0 && split < 1)
                    Positioned(
                      left: x - 16,
                      top: box.maxHeight / 2 - 16,
                      child: const IgnorePointer(
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.white,
                          child: Icon(Icons.compare_arrows, size: 18, color: Colors.black),
                        ),
                      ),
                    ),
                  // Dragging near the divider moves it; anywhere else pans/zooms the image.
                  Positioned(
                    key: const Key('compare-divider'),
                    left: (x - CompareView.dividerHitWidth / 2).clamp(
                        0.0, math.max(0.0, box.maxWidth - CompareView.dividerHitWidth)),
                    top: 0,
                    bottom: 0,
                    width: math.min(CompareView.dividerHitWidth, box.maxWidth),
                    child: GestureDetector(
                      // Opaque: a drag here moves the divider and never also pans the image.
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: (d) => setSplit(split + d.delta.dx / box.maxWidth),
                    ),
                  ),
                  if (s > 1.01)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: IconButton.filledTonal(
                        tooltip: 'Reset zoom',
                        icon: const Icon(Icons.zoom_out_map),
                        onPressed: resetZoom,
                      ),
                    ),
                ]);
              },
            ),
          );
        }),
      ),
    );
  }
}

class _LeftClipper extends CustomClipper<Rect> {
  _LeftClipper(this.width);

  final double width;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, width, size.height);

  @override
  bool shouldReclip(_LeftClipper old) => old.width != width;
}

class _RightClipper extends CustomClipper<Rect> {
  _RightClipper(this.left);

  final double left;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(left, 0, size.width, size.height);

  @override
  bool shouldReclip(_RightClipper old) => old.left != left;
}
