import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../core/ao_constants.dart';
import 'button_maker.dart' show IntRect, ButtonMaker;
import 'sprite_edit.dart';

/// A **normalized camera** over a sprite: where to look ([focusX]/[focusY], the
/// 0..1 point that lands in the centre of the output) and how close
/// ([zoom] — `>1` zooms in / crops to the focus and scales up, `<1` zooms out /
/// shrinks the character and shows transparent margin).
///
/// Why this lives in the imaging layer (pure Dart): the same [SpriteZoomSpec]
/// applied to **every** sprite of a character produces an identical transform,
/// so the cast stays aligned in-game — exactly what AO needs (it anchors and
/// rescales sprites; mismatched framing makes poses visibly jump). The maths is
/// just [SpriteEdit.cropTo] (frame-aware, transparent-fills out-of-bounds) →
/// [SpriteEdit.resize] (frame-aware, crisp), so a zoom round-trips every frame
/// + its duration the same way a crop does.
class SpriteZoomSpec {
  const SpriteZoomSpec({
    this.zoom = ZoomLimits.defaultZoom,
    this.focusX = ZoomLimits.defaultFocus,
    this.focusY = ZoomLimits.defaultFocus,
    this.outputScale = 1.0,
  });

  /// Camera zoom. `1` = whole sprite; `>1` = zoom in; `<1` = zoom out.
  final double zoom;

  /// The point of the sprite (0..1) that sits in the centre of the result.
  final double focusX;
  final double focusY;

  /// Multiply the **output** pixel dimensions (1.0 = keep the sprite's size,
  /// which is what AO wants). 2.0 bakes the zoom at twice the resolution for a
  /// crisper result on big themes. Uniform, so the aspect (and alignment across
  /// the cast) is unchanged.
  final double outputScale;

  /// Nothing to do — the camera shows the whole sprite at its native size.
  bool get isNoop =>
      zoom == 1.0 && outputScale == 1.0;

  SpriteZoomSpec copyWith({
    double? zoom,
    double? focusX,
    double? focusY,
    double? outputScale,
  }) =>
      SpriteZoomSpec(
        zoom: (zoom ?? this.zoom).clamp(ZoomLimits.minZoom, ZoomLimits.maxZoom),
        focusX: (focusX ?? this.focusX).clamp(0.0, 1.0),
        focusY: (focusY ?? this.focusY).clamp(0.0, 1.0),
        outputScale: (outputScale ?? this.outputScale).clamp(0.1, 8.0),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'zoom': zoom,
        'focusX': focusX,
        'focusY': focusY,
        'outputScale': outputScale,
      };

  factory SpriteZoomSpec.fromJson(Map<String, dynamic> j) => SpriteZoomSpec(
        zoom: (j['zoom'] as num?)?.toDouble() ?? ZoomLimits.defaultZoom,
        focusX: (j['focusX'] as num?)?.toDouble() ?? ZoomLimits.defaultFocus,
        focusY: (j['focusY'] as num?)?.toDouble() ?? ZoomLimits.defaultFocus,
        outputScale: (j['outputScale'] as num?)?.toDouble() ?? 1.0,
      );
}

class SpriteZoom {
  const SpriteZoom._();

  /// The integer source rectangle the camera sees for an image of [w]×[h]. May
  /// have a negative origin / exceed the image when zoomed out (the camera sees
  /// past the edge); [SpriteEdit.cropTo] fills that with transparency.
  static IntRect cameraRect(int w, int h, SpriteZoomSpec spec) {
    final double z = spec.zoom.clamp(ZoomLimits.minZoom, ZoomLimits.maxZoom);
    final double rw = w / z; // region the camera shows, in source pixels
    final double rh = h / z;
    final double cx = spec.focusX.clamp(0.0, 1.0) * w;
    final double cy = spec.focusY.clamp(0.0, 1.0) * h;
    final int rectW = math.max(1, rw.round());
    final int rectH = math.max(1, rh.round());
    final int rx = (cx - rw / 2).round();
    final int ry = (cy - rh / 2).round();
    return IntRect(rx, ry, rectW, rectH);
  }

  /// Apply the camera to [image] (frame-aware; preserves frame count +
  /// durations). The output is the camera's region scaled to the sprite's
  /// original size × [SpriteZoomSpec.outputScale]. Lossless-friendly: a crop
  /// then a single high-quality resize.
  static img.Image apply(img.Image image, SpriteZoomSpec spec) {
    if (spec.isNoop) return image;
    final int w = image.width, h = image.height;
    final IntRect rect = cameraRect(w, h, spec);
    final img.Image cropped = SpriteEdit.cropTo(image, rect);
    final int outW = math.max(1, (w * spec.outputScale).round());
    final int outH = math.max(1, (h * spec.outputScale).round());
    return SpriteEdit.resize(cropped, outW / rect.w, outH / rect.h);
  }

  /// Compute a single camera that frames the **union** of the non-transparent
  /// content across [images] (every frame of each), leaving
  /// [ZoomLimits.autoFrameCoverage] of the canvas filled. Because it's *one*
  /// transform derived from *all* the targeted sprites, applying it to the whole
  /// cast keeps them aligned (unlike framing each sprite to its own content,
  /// which would desync poses). Returns the identity camera when nothing is
  /// found / everything is transparent.
  static SpriteZoomSpec fitToContent(
    List<img.Image> images, {
    double coverage = ZoomLimits.autoFrameCoverage,
  }) {
    double minNX = 1, minNY = 1, maxNX = 0, maxNY = 0;
    bool any = false;
    for (final img.Image im in images) {
      final List<img.Image> frames =
          im.frames.isEmpty ? <img.Image>[im] : im.frames;
      for (final img.Image f in frames) {
        final IntRect b = ButtonMaker.autoTrimBounds(f);
        if (b.w <= 0 || b.h <= 0) continue;
        final double nx0 = b.x / f.width;
        final double ny0 = b.y / f.height;
        final double nx1 = (b.x + b.w) / f.width;
        final double ny1 = (b.y + b.h) / f.height;
        minNX = math.min(minNX, nx0);
        minNY = math.min(minNY, ny0);
        maxNX = math.max(maxNX, nx1);
        maxNY = math.max(maxNY, ny1);
        any = true;
      }
    }
    if (!any) return const SpriteZoomSpec();

    final double bw = (maxNX - minNX).clamp(0.001, 1.0);
    final double bh = (maxNY - minNY).clamp(0.001, 1.0);
    final double cov = coverage.clamp(0.1, 1.0);
    // Zoom so the box occupies `cov` of the canvas on its tighter axis (so the
    // whole box stays visible); centre the focus on the box. Auto-frame only
    // ever zooms *in* (the lower bound is 1.0) — content that already fills the
    // frame (or a fully transparent sprite, where the content box is the whole
    // frame) resolves to the identity camera instead of zooming out. Adding
    // margin is the Edit screen's job.
    final double zoom =
        math.min(cov / bw, cov / bh).clamp(1.0, ZoomLimits.maxZoom);
    return SpriteZoomSpec(
      zoom: zoom,
      focusX: ((minNX + maxNX) / 2).clamp(0.0, 1.0),
      focusY: ((minNY + maxNY) / 2).clamp(0.0, 1.0),
    );
  }
}
