import 'package:flutter/material.dart';

/// Sky image over the original photo with a draggable divider: left of the divider shows the
/// original, right shows the survey image. Both images are fitted to the same box so the
/// fields line up (they share the photo's aspect ratio).
class CompareView extends StatefulWidget {
  const CompareView({
    super.key,
    required this.original,
    required this.replacement,
    required this.aspectRatio,
    this.initialSplit = 0.0,
  });

  final ImageProvider original;
  final ImageProvider replacement;
  final double aspectRatio;

  /// 0 = only the replacement visible, 1 = only the original.
  final double initialSplit;

  @override
  State<CompareView> createState() => CompareViewState();
}

class CompareViewState extends State<CompareView> {
  late double split = widget.initialSplit;

  void setSplit(double v) => setState(() => split = v.clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: LayoutBuilder(builder: (context, box) {
          final x = box.maxWidth * split;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => setSplit(split + d.delta.dx / box.maxWidth),
            child: Stack(fit: StackFit.expand, children: [
              Image(image: widget.replacement, fit: BoxFit.fill, gaplessPlayback: true),
              ClipRect(
                clipper: _LeftClipper(x),
                child: Image(image: widget.original, fit: BoxFit.fill),
              ),
              if (split > 0 && split < 1)
                Positioned(
                  left: x - 1,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 2, color: Colors.white70),
                ),
              if (split > 0 && split < 1)
                Positioned(
                  left: x - 16,
                  top: box.maxHeight / 2 - 16,
                  child: const CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.compare_arrows, size: 18, color: Colors.black),
                  ),
                ),
            ]),
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
