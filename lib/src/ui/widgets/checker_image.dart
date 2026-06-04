import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Shows image bytes over a transparency checkerboard, so alpha is obvious — the
/// standard sprite-editing backdrop. [bytes] of null renders just the checker.
class CheckerImage extends StatelessWidget {
  const CheckerImage({
    super.key,
    required this.bytes,
    this.fit = BoxFit.contain,
    this.cell = 10,
    this.colorFilter,
  });

  final Uint8List? bytes;
  final BoxFit fit;
  final double cell;

  /// Optional GPU [ColorFilter] applied to the **image only** (never the
  /// checker backdrop). Powers the Colour Lab's live, compositor-side preview of
  /// matrix-representable adjustments — see `imaging/color_matrix.dart`.
  final ColorFilter? colorFilter;

  @override
  Widget build(BuildContext context) {
    Widget? image = bytes == null
        ? null
        : Image.memory(
            bytes!,
            fit: fit,
            gaplessPlayback: true,
            // Smooth scaling so previews don't look pixelated (this is just
            // how the preview is displayed; the sprite data is untouched).
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) =>
                const Center(child: Icon(Icons.broken_image_outlined)),
          );
    if (image != null && colorFilter != null) {
      image = ColorFiltered(colorFilter: colorFilter!, child: image);
    }
    return CustomPaint(
      painter: _CheckerPainter(cell: cell),
      child: image ?? const SizedBox.expand(),
    );
  }
}

class _CheckerPainter extends CustomPainter {
  _CheckerPainter({required this.cell});
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint a = Paint()..color = const Color(0xFF2A2A33);
    final Paint b = Paint()..color = const Color(0xFF22222A);
    canvas.drawRect(Offset.zero & size, b);
    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        final bool even = ((x ~/ cell) + (y ~/ cell)).isEven;
        if (even) {
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), a);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerPainter oldDelegate) =>
      oldDelegate.cell != cell;
}
