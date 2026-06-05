import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../core/ao_constants.dart';
import 'codecs.dart';

/// Integer rectangle in source-image pixels.
class IntRect {
  const IntRect(this.x, this.y, this.w, this.h);
  final int x, y, w, h;
}

/// A **manual** crop box (the KFO/DRO-style "drag a box on the sprite") as
/// fractions of the sprite, so a box is independent of the sprite's pixel size.
/// The Button Studio keeps **one box per sprite** (keyed by sprite base name —
/// see `AppState.buttonCrops`) so different poses can each be framed by hand;
/// the char_icon keeps its own single box. [x]/[y] are the top-left (fractions
/// of width/height); [side] is the box edge as a fraction of the **width**, so
/// the region is square in pixels (and looks square on an aspect-correct
/// preview). [toPixels] always returns a valid square fully inside the image —
/// that clamp is the safety net that makes the draggable editor robust (a
/// slightly-off drag can't produce a broken button).
class CropBox {
  const CropBox(this.x, this.y, this.side);

  final double x, y, side;

  /// A sensible starting box (upper-middle, half-width) before the auto
  /// head-square seeds it.
  static const CropBox initial = CropBox(0.25, 0.08, 0.5);

  IntRect toPixels(int w, int h) {
    if (w <= 0 || h <= 0) return const IntRect(0, 0, 1, 1);
    int s = (side * w).round();
    final int maxS = w < h ? w : h;
    if (s < 1) s = 1;
    if (s > maxS) s = maxS;
    int px = (x * w).round();
    int py = (y * h).round();
    if (px < 0) px = 0;
    if (py < 0) py = 0;
    if (px + s > w) px = w - s;
    if (py + s > h) py = h - s;
    return IntRect(px, py, s, s);
  }

  /// Build a box (fractions) from a pixel square on a [w]×[h] image — used to
  /// seed Manual mode from the auto head-square so you start at the detected
  /// face and nudge from there.
  static CropBox fromPixels(IntRect r, int w, int h) =>
      (w <= 0 || h <= 0) ? initial : CropBox(r.x / w, r.y / h, r.w / w);

  CropBox copyWith({double? x, double? y, double? side}) =>
      CropBox(x ?? this.x, y ?? this.y, side ?? this.side);
}

/// Produces emote button icons and character-select icons.
///
/// Entry points:
///  * [renderAuto] — fully automatic (used by the auto-organiser): decode the
///    first frame, frame it ([CropFraming.head] = the character's face by
///    default, or [CropFraming.full] = a square around the whole sprite), and
///    scale to size. Matches the injected `ButtonRenderer` typedef.
///  * [renderFramed] — the same, but from an already-decoded frame (lets the UI
///    reuse its decode cache for snappy previews).
///  * [renderComposite] — the advanced studio path: explicit crop rectangle
///    plus optional background / foreground / mask / "selected" overlays.
class ButtonMaker {
  const ButtonMaker._();

  /// The bare automatic render (no overlays/offsets/manual box). Defaults to
  /// **head/face** framing, the natural look for AO emote buttons and icons.
  /// The organiser's `ButtonRenderer` is supplied as a closure over this (see
  /// `AppState._studioOrganizer`) so it can add the per-sprite manual crop,
  /// offsets and overlays — this entry point stays simple for direct callers.
  ///
  /// [zoom] tunes the head crop: `1.0` is the default framing, `>1` zooms in
  /// (tighter on the face), `<1` zooms out (more head-and-shoulders). Ignored
  /// for [CropFraming.full]. [offsetX]/[offsetY] nudge the crop square (in
  /// fractions of its side: -0.5..0.5) so you can re-centre the face. Optional
  /// [background] sits behind the sprite and [foreground] is composited **on
  /// top** (e.g. a KFO-style border/frame) — both fit to [size].
  static Future<Uint8List?> renderAuto(
    Uint8List sourceBytes,
    String ext,
    int size, [
    CropFraming framing = CropFraming.head,
    double zoom = 1.0,
  ]) async =>
      renderAutoOverlaid(sourceBytes, ext, size,
          framing: framing, zoom: zoom);

  /// [renderAuto] with the full set of named knobs (offsets + overlays). Kept
  /// separate so the bare [renderAuto] still matches the plain `ButtonRenderer`
  /// tear-off, while callers that capture overlays use this.
  static Future<Uint8List?> renderAutoOverlaid(
    Uint8List sourceBytes,
    String ext,
    int size, {
    CropFraming framing = CropFraming.head,
    double zoom = 1.0,
    double offsetX = 0,
    double offsetY = 0,
    img.Image? background,
    img.Image? foreground,
    CropBox? manualCrop,
  }) async {
    final img.Image? frame = Codecs.decodeFirstFrame(sourceBytes, ext: ext);
    if (frame == null) return null;
    return renderFramed(frame, size,
        framing: framing,
        zoom: zoom,
        offsetX: offsetX,
        offsetY: offsetY,
        background: background,
        foreground: foreground,
        manualCrop: manualCrop);
  }

  /// Frame an already-decoded [frame] into a [size]×[size] PNG icon. See
  /// [renderAutoOverlaid] for [framing]/[zoom]/[offsetX]/[offsetY]/overlays.
  static Uint8List renderFramed(
    img.Image frame,
    int size, {
    CropFraming framing = CropFraming.head,
    double zoom = 1.0,
    double offsetX = 0,
    double offsetY = 0,
    img.Image? background,
    img.Image? foreground,
    CropBox? manualCrop,
  }) {
    final img.Image rgba = _ensureRgba(frame);
    IntRect square;
    if (framing == CropFraming.manual) {
      // The user's hand-placed box (KFO/DRO style). With **per-sprite** Manual
      // mode a sprite the user never touched has no box (`manualCrop == null`);
      // fall back to the auto head-square so every button still frames a face,
      // which is far better than a whole-sprite centre square. So "Manual" means
      // "a hand-placed box where you set one, the auto face crop everywhere
      // else" — you only customise the sprites you care about.
      square = manualCrop != null
          ? manualCrop.toPixels(rgba.width, rgba.height)
          : headSquare(rgba, zoom: zoom);
    } else if (framing == CropFraming.head) {
      square = headSquare(rgba, zoom: zoom);
    } else {
      square = _centerSquare(autoTrimBounds(rgba), rgba.width, rgba.height);
    }
    // Offsets nudge the *auto* crops; the manual box carries its own position.
    if (framing != CropFraming.manual && (offsetX != 0 || offsetY != 0)) {
      final int sx = (square.x + offsetX * square.w)
          .round()
          .clamp(0, math.max(0, rgba.width - square.w));
      final int sy = (square.y + offsetY * square.h)
          .round()
          .clamp(0, math.max(0, rgba.height - square.h));
      square = IntRect(sx, sy, square.w, square.h);
    }
    final img.Image cropped = img.copyCrop(rgba,
        x: square.x, y: square.y, width: square.w, height: square.h);
    // Quality: PNG output is lossless, so sharpness is decided here.
    //  * Never **upscale** the crop — enlarging a small region only blurs it
    //    (the "low quality button" regression from face framing's smaller crop).
    //  * When **downscaling**, area-average instead of bicubic — bicubic
    //    under-samples on big reductions (a ~600px head → 128px button), which
    //    aliases and softens; averaging samples every source pixel for a crisp,
    //    clean result (the same filter the live previews use).
    final int outSize = size < square.w ? size : square.w;
    final img.Image scaled = outSize >= square.w
        ? cropped
        : img.copyResize(cropped,
            width: outSize,
            height: outSize,
            interpolation: img.Interpolation.average);

    if (background == null && foreground == null) return Codecs.encodePng(scaled);
    final img.Image canvas = img.Image(width: outSize, height: outSize, numChannels: 4);
    if (background != null) {
      img.compositeImage(canvas, _fit(background, outSize), dstX: 0, dstY: 0);
    }
    img.compositeImage(canvas, scaled, dstX: 0, dstY: 0);
    if (foreground != null) {
      img.compositeImage(canvas, _fit(foreground, outSize), dstX: 0, dstY: 0);
    }
    return Codecs.encodePng(canvas);
  }

  /// Full control button render for the studio screen.
  static Uint8List renderComposite({
    required img.Image sourceFrame,
    required IntRect crop,
    int size = CharFolder.recommendedButtonSize,
    img.Image? background,
    img.Image? foreground,
    img.Image? mask,
    img.Image? selectedOverlay,
    bool on = false,
  }) {
    final img.Image rgba = _ensureRgba(sourceFrame);
    img.Image cut = img.copyCrop(rgba,
        x: crop.x, y: crop.y, width: crop.w, height: crop.h);
    cut = img.copyResize(cut,
        width: size, height: size, interpolation: img.Interpolation.cubic);

    img.Image canvas = img.Image(width: size, height: size, numChannels: 4);
    if (background != null) {
      img.compositeImage(canvas, _fit(background, size),
          dstX: 0, dstY: 0);
    }
    img.compositeImage(canvas, cut, dstX: 0, dstY: 0);
    if (on && selectedOverlay != null) {
      img.compositeImage(canvas, _fit(selectedOverlay, size), dstX: 0, dstY: 0);
    }
    if (foreground != null) {
      img.compositeImage(canvas, _fit(foreground, size), dstX: 0, dstY: 0);
    }
    if (mask != null) {
      canvas = _applyMaskAlpha(canvas, _fit(mask, size));
    }
    return Codecs.encodePng(canvas);
  }

  // ---- helpers ----

  static img.Image _ensureRgba(img.Image src) {
    if (src.numChannels == 4) return src;
    return src.convert(numChannels: 4);
  }

  static img.Image _fit(img.Image src, int size) =>
      (src.width == size && src.height == size)
          ? _ensureRgba(src)
          : img.copyResize(_ensureRgba(src),
              width: size, height: size, interpolation: img.Interpolation.cubic);

  /// Bounding box of all pixels with alpha > 0. Falls back to the full image if
  /// everything is opaque or everything is transparent.
  static IntRect autoTrimBounds(img.Image image, {int alphaThreshold = 1}) {
    int minX = image.width, minY = image.height, maxX = -1, maxY = -1;
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        if (image.getPixel(x, y).a >= alphaThreshold) {
          if (x < minX) minX = x;
          if (y < minY) minY = y;
          if (x > maxX) maxX = x;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (maxX < 0) return IntRect(0, 0, image.width, image.height);
    return IntRect(minX, minY, maxX - minX + 1, maxY - minY + 1);
  }

  /// A square framing the character's **head/face**, derived from the alpha
  /// silhouette (no ML, no model files — works offline on every platform).
  ///
  /// Method: find the content box, measure the head's width across the top band,
  /// then walk down until the silhouette widens into the shoulders — that's the
  /// chin/neck line. Frame a padded square on the head, centred on its
  /// horizontal middle with a little headroom. Falls back to a top-centred
  /// square when the silhouette is ambiguous (e.g. a non-character image).
  ///
  /// [zoom] > 1 tightens the crop (more face), < 1 loosens it (more shoulders).
  static IntRect headSquare(img.Image image, {double zoom = 1.0}) {
    final int imgW = image.width, imgH = image.height;
    final IntRect c = autoTrimBounds(image);
    if (c.w < 6 || c.h < 6) return _centerSquare(c, imgW, imgH);

    final int x0 = c.x, x1 = c.x + c.w, y0 = c.y;
    final int y1 = c.y + c.h;
    // Per-row opaque extents + widths within the content box.
    final List<int> left = <int>[];
    final List<int> right = <int>[];
    final List<int> width = <int>[];
    int maxW = 1;
    for (int y = y0; y < y1; y++) {
      int lx = -1, rx = -1;
      for (int x = x0; x < x1; x++) {
        if (image.getPixel(x, y).a >= 1) {
          if (lx < 0) lx = x;
          rx = x;
        }
      }
      left.add(lx);
      right.add(rx);
      final int w = lx < 0 ? 0 : (rx - lx + 1);
      width.add(w);
      if (w > maxW) maxW = w;
    }

    // Shoulder line: the first row (after a little headroom) that reaches ~70%
    // of the widest row — i.e. where the narrow head/neck widens into the
    // shoulders/body. Measuring head width as "top 30% of height" breaks on tall
    // full-body sprites (it swallows the shoulders); keying off the silhouette's
    // widest point instead works regardless of how tall the body is. The head
    // height is floored so a shallow/early widening still yields a sane crop.
    final int minRows = math.max(3, (c.h * 0.06).round());
    final int shoulderW = (maxW * 0.70).round();
    int shoulderIdx = width.length;
    for (int i = minRows; i < width.length; i++) {
      if (width[i] >= shoulderW) {
        shoulderIdx = i;
        break;
      }
    }
    final int headH = math.max(shoulderIdx, (c.h * 0.22).round()).clamp(1, c.h);

    // Head width + horizontal centre, from the rows above the shoulder line.
    int headW = 1, headCx = c.x + c.w ~/ 2;
    for (int i = 0; i < shoulderIdx && i < width.length; i++) {
      if (left[i] >= 0 && width[i] > headW) {
        headW = width[i];
        headCx = (left[i] + right[i]) ~/ 2;
      }
    }

    // Square side encompassing the head with a little margin; zoom tightens it.
    final double z = zoom <= 0 ? 1.0 : zoom;
    int side = (math.max(headW, headH) * 1.25 / z).round();
    side = side.clamp(8, math.min(imgW, imgH));

    // Centre horizontally on the head; give ~35% of the slack as headroom above
    // the crown so the face sits centred rather than the chin.
    final int extra = side - headH;
    int sx = headCx - side ~/ 2;
    int sy = y0 - (extra * 0.35).round();
    sx = sx.clamp(0, math.max(0, imgW - side));
    sy = sy.clamp(0, math.max(0, imgH - side));
    return IntRect(sx, sy, side, side);
  }

  /// Largest centred square that fits the content box, clamped to the image.
  static IntRect _centerSquare(IntRect box, int imgW, int imgH) {
    final int side = box.w > box.h ? box.w : box.h;
    final int cx = box.x + box.w ~/ 2;
    final int cy = box.y + box.h ~/ 2;
    int x = cx - side ~/ 2;
    int y = cy - side ~/ 2;
    int s = side;
    if (s > imgW) s = imgW;
    if (s > imgH) s = imgH;
    if (x < 0) x = 0;
    if (y < 0) y = 0;
    if (x + s > imgW) x = imgW - s;
    if (y + s > imgH) y = imgH - s;
    return IntRect(x, y, s, s);
  }

  /// Multiply destination alpha by the mask's alpha (black/transparent mask =
  /// hidden). Matches AO's mask convention.
  static img.Image _applyMaskAlpha(img.Image dst, img.Image mask) {
    for (int y = 0; y < dst.height; y++) {
      for (int x = 0; x < dst.width; x++) {
        final img.Pixel d = dst.getPixel(x, y);
        final img.Pixel m = mask.getPixel(x, y);
        final int a = (d.a.toInt() * m.a.toInt()) ~/ 255;
        dst.setPixelRgba(x, y, d.r.toInt(), d.g.toInt(), d.b.toInt(), a);
      }
    }
    return dst;
  }
}
