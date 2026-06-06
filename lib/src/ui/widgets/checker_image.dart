import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Shows image bytes over a transparency checkerboard, so alpha is obvious — the
/// standard sprite-editing backdrop. [bytes] of null renders just the checker.
///
/// Performance: the checker is drawn as **one** GPU-tiled rect (a cached 2×2
/// tile image repeated via an [ui.ImageShader]) instead of a `drawRect` per
/// cell — so a big zoom/pan canvas no longer issues thousands of draw calls per
/// frame. Wrapped in a [RepaintBoundary] so panning/moving it just re-composites
/// the cached layer instead of repainting.
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
    return RepaintBoundary(
      child: CustomPaint(
        painter: _CheckerPainter(cell: cell),
        child: image ?? const SizedBox.expand(),
      ),
    );
  }
}

class _CheckerPainter extends CustomPainter {
  _CheckerPainter({required this.cell});
  final double cell;

  static const Color _a = Color(0xFF2A2A33);
  static const Color _b = Color(0xFF22222A);

  /// One small 2×2-cell tile per cell size, drawn once and repeated by the GPU.
  static final Map<int, ui.Image> _tileCache = <int, ui.Image>{};

  static ui.Image _tile(double cell) {
    final int key = (cell * 100).round();
    final ui.Image? cached = _tileCache[key];
    if (cached != null) return cached;
    final double s = cell * 2;
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final Canvas c = Canvas(rec);
    c.drawRect(Rect.fromLTWH(0, 0, s, s), Paint()..color = _b);
    c.drawRect(Rect.fromLTWH(0, 0, cell, cell), Paint()..color = _a);
    c.drawRect(Rect.fromLTWH(cell, cell, cell, cell), Paint()..color = _a);
    final ui.Image img = rec.endRecording().toImageSync(s.ceil(), s.ceil());
    _tileCache[key] = img;
    return img;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..shader = ui.ImageShader(_tile(cell), TileMode.repeated,
          TileMode.repeated, Matrix4.identity().storage);
    canvas.drawRect(Offset.zero & size, p);
  }

  @override
  bool shouldRepaint(covariant _CheckerPainter oldDelegate) =>
      oldDelegate.cell != cell;
}
