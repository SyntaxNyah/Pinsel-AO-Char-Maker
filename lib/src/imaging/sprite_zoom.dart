import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../core/ao_constants.dart';
import 'button_maker.dart' show IntRect, ButtonMaker;

/// A **normalized camera** over a sprite: where to look ([focusX]/[focusY], the
/// 0..1 point that lands in the centre of the output) and how close
/// ([zoom] — `>1` zooms in / crops to the focus and scales up, `<1` zooms out /
/// shrinks the character and shows transparent margin).
///
/// Why this lives in the imaging layer (pure Dart): the same [SpriteZoomSpec]
/// applied to **every** sprite of a character produces an identical transform,
/// so the cast stays aligned in-game — exactly what AO needs (it anchors and
/// rescales sprites; mismatched framing makes poses visibly jump). The maths is
/// a crop to the camera region (transparent-fills out-of-bounds when zoomed out)
/// then a single crisp resize back to the output size — applied **per frame** on
/// an isolated single-frame copy, so an animated sprite round-trips every frame
/// + its duration intact (see [SpriteZoom.apply]).
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
  ///
  /// Each frame is processed on an **isolated single-frame copy**
  /// ([_isolateFrame]) before cropping/resizing, then reassembled with
  /// `addFrame` (the same pattern as the animation exporter). This is deliberate:
  /// frames pulled from `image.frames` still reference the shared animation, so a
  /// frame-aware `copyCrop`/`copyResize` applied to one of them would re-process
  /// the *whole* clip and corrupt the frame count — isolating first keeps every
  /// frame + its duration intact.
  static img.Image apply(img.Image image, SpriteZoomSpec spec) {
    if (spec.isNoop) return image;
    final int w = image.width, h = image.height;
    final IntRect rect = cameraRect(w, h, spec);
    final int outW = math.max(1, (w * spec.outputScale).round());
    final int outH = math.max(1, (h * spec.outputScale).round());

    final List<img.Image> srcFrames =
        image.frames.isEmpty ? <img.Image>[image] : image.frames.toList();
    final List<img.Image> outFrames = <img.Image>[];
    for (final img.Image f in srcFrames) {
      final img.Image single = _isolateFrame(f);
      final img.Image cropped = _cropOrPad(single, rect);
      final img.Image scaled = _resizeTo(cropped, outW, outH);
      scaled.frameDuration = f.frameDuration;
      outFrames.add(scaled);
    }
    final img.Image out = outFrames.first;
    for (int i = 1; i < outFrames.length; i++) {
      out.addFrame(outFrames[i]);
    }
    return out;
  }

  /// Copy one [frame]'s own pixels into a fresh **standalone single-frame**
  /// image, so subsequent frame-aware ops can't reach back into the animation it
  /// came from. Pure getPixel/setPixel — independent of the codec's internals.
  static img.Image _isolateFrame(img.Image frame) {
    final img.Image out =
        img.Image(width: frame.width, height: frame.height, numChannels: 4);
    for (final img.Pixel p in frame) {
      out.setPixelRgba(p.x, p.y, p.r, p.g, p.b, p.a);
    }
    return out;
  }

  /// Crop [single] (a single-frame image) to [r], or — when [r] extends past an
  /// edge (zoomed out / panned to a border) — paint the overlapping region onto
  /// a transparent canvas of size [r] so the extra area is empty.
  static img.Image _cropOrPad(img.Image single, IntRect r) {
    final int w = single.width, h = single.height;
    if (r.x == 0 && r.y == 0 && r.w == w && r.h == h) return single;
    final bool inside = r.x >= 0 && r.y >= 0 && r.x + r.w <= w && r.y + r.h <= h;
    if (inside) {
      return img.copyCrop(single, x: r.x, y: r.y, width: r.w, height: r.h);
    }
    final img.Image canvas = img.Image(width: r.w, height: r.h, numChannels: 4);
    final int ox0 = r.x < 0 ? 0 : r.x;
    final int oy0 = r.y < 0 ? 0 : r.y;
    final int ox1 = math.min(w, r.x + r.w);
    final int oy1 = math.min(h, r.y + r.h);
    final int ow = ox1 - ox0, oh = oy1 - oy0;
    if (ow > 0 && oh > 0) {
      final img.Image piece =
          img.copyCrop(single, x: ox0, y: oy0, width: ow, height: oh);
      img.compositeImage(canvas, piece, dstX: ox0 - r.x, dstY: oy0 - r.y);
    }
    return canvas;
  }

  /// Resize a single-frame image to [outW]×[outH] (cubic up / average down).
  static img.Image _resizeTo(img.Image single, int outW, int outH) {
    if (single.width == outW && single.height == outH) return single;
    final bool down = outW < single.width || outH < single.height;
    return img.copyResize(single,
        width: outW,
        height: outH,
        interpolation:
            down ? img.Interpolation.average : img.Interpolation.cubic);
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
