import 'dart:math' as math;

import 'package:image/image.dart' as img;

import 'button_maker.dart' show IntRect, ButtonMaker;
import 'region_edit.dart';

/// A non-colour sprite edit: crop, auto-trim transparent margins, and/or remove
/// the background. Geometry (crop) is applied uniformly across every frame so
/// animations stay aligned.
class SpriteEditSpec {
  const SpriteEditSpec({
    this.cropLeft = 0,
    this.cropTop = 0,
    this.cropRight = 0,
    this.cropBottom = 0,
    this.padLeft = 0,
    this.padTop = 0,
    this.padRight = 0,
    this.padBottom = 0,
    this.autoTrim = false,
    this.removeBgCorners = false,
    this.eraseColorEnabled = false,
    this.eraseColorValue = 0xFFFFFFFF,
    this.bgTolerance = 40,
  });

  /// Crop insets as fractions of width/height (0..0.49 each) — reduce the canvas
  /// by pulling each edge *inward*.
  final double cropLeft;
  final double cropTop;
  final double cropRight;
  final double cropBottom;

  /// Pad (grow) fractions of width/height — *extend* the canvas outward on each
  /// edge with transparent pixels. The opposite of cropping; a side is never
  /// both cropped and padded (the UI maps one bidirectional slider per side to
  /// exactly one of these). Applied *after* crop/auto-trim, so growing always
  /// adds clean margin around the kept content.
  final double padLeft;
  final double padTop;
  final double padRight;
  final double padBottom;

  /// Trim fully-transparent margins (in addition to any crop insets).
  final bool autoTrim;

  /// Flood-fill the background from the corners and make it transparent.
  final bool removeBgCorners;

  /// Knock out a specific colour anywhere in the image.
  final bool eraseColorEnabled;
  final int eraseColorValue;

  /// Colour-distance tolerance for background/colour removal (0..441).
  final double bgTolerance;

  bool get isNoop =>
      cropLeft == 0 &&
      cropTop == 0 &&
      cropRight == 0 &&
      cropBottom == 0 &&
      padLeft == 0 &&
      padTop == 0 &&
      padRight == 0 &&
      padBottom == 0 &&
      !autoTrim &&
      !removeBgCorners &&
      !eraseColorEnabled;
}

class SpriteEdit {
  const SpriteEdit._();

  /// Compute the crop rectangle for a set of images (a whole emote group), so
  /// (a)/(b)/etc. all crop to the same box. Combines the fractional insets with
  /// the union of non-transparent bounds when [SpriteEditSpec.autoTrim] is on.
  static IntRect computeRect(List<img.Image> images, SpriteEditSpec spec) {
    final img.Image ref = images.first;
    final int w = ref.width, h = ref.height;
    int x0 = (spec.cropLeft.clamp(0.0, 0.49) * w).round();
    int y0 = (spec.cropTop.clamp(0.0, 0.49) * h).round();
    int x1 = w - (spec.cropRight.clamp(0.0, 0.49) * w).round();
    int y1 = h - (spec.cropBottom.clamp(0.0, 0.49) * h).round();

    if (spec.autoTrim) {
      int minX = w, minY = h, maxX = 0, maxY = 0;
      bool any = false;
      for (final img.Image im in images) {
        for (final img.Image f in im.frames.isEmpty ? <img.Image>[im] : im.frames) {
          final IntRect b = ButtonMaker.autoTrimBounds(f);
          if (b.w >= f.width && b.h >= f.height) continue; // nothing trimmable
          any = true;
          minX = math.min(minX, b.x);
          minY = math.min(minY, b.y);
          maxX = math.max(maxX, b.x + b.w);
          maxY = math.max(maxY, b.y + b.h);
        }
      }
      if (any) {
        x0 = math.max(x0, minX);
        y0 = math.max(y0, minY);
        x1 = math.min(x1, maxX);
        y1 = math.min(y1, maxY);
      }
    }

    x0 = x0.clamp(0, w - 1);
    y0 = y0.clamp(0, h - 1);
    x1 = x1.clamp(x0 + 1, w);
    y1 = y1.clamp(y0 + 1, h);

    // Grow outward (pad) by the pad fractions of the *original* dimensions, on
    // top of the inward crop/trim box. The result may have a negative origin or
    // exceed the image bounds — [cropTo] fills the extra area with transparency,
    // so this is how the Edit screen *adds* width/height instead of removing it.
    final int padL = (spec.padLeft.clamp(0.0, 4.0) * w).round();
    final int padT = (spec.padTop.clamp(0.0, 4.0) * h).round();
    final int padR = (spec.padRight.clamp(0.0, 4.0) * w).round();
    final int padB = (spec.padBottom.clamp(0.0, 4.0) * h).round();
    final int rx = x0 - padL;
    final int ry = y0 - padT;
    final int rw = (x1 - x0) + padL + padR;
    final int rh = (y1 - y0) + padT + padB;
    return IntRect(rx, ry, math.max(1, rw), math.max(1, rh));
  }

  /// Background/colour removal only (mutates [image]'s frames in place; no size
  /// change). Run this *before* [computeRect] so auto-trim sees the new
  /// transparency.
  static void removeBg(img.Image image, SpriteEditSpec spec) {
    if (!spec.removeBgCorners && !spec.eraseColorEnabled) return;
    for (final img.Image f
        in image.frames.isEmpty ? <img.Image>[image] : image.frames) {
      if (spec.removeBgCorners) {
        RegionEditor.removeBackgroundFromCorners(f, tolerance: spec.bgTolerance);
      }
      if (spec.eraseColorEnabled) {
        RegionEditor.eraseColor(f, spec.eraseColorValue, tolerance: spec.bgTolerance);
      }
    }
  }

  /// Crop **or grow** every frame to [r], preserving frame durations. No-op if
  /// [r] is the full frame. When [r] sits fully inside the image it's a plain
  /// crop; when it extends past an edge (a negative origin or oversize, produced
  /// by the pad/grow sliders) each frame is painted onto a transparent canvas of
  /// the new size so the added margin is empty — uniform across every frame so
  /// animations stay aligned.
  static img.Image cropTo(img.Image image, IntRect r) {
    final List<img.Image> frames =
        image.frames.isEmpty ? <img.Image>[image] : image.frames.toList();
    final int w = frames.first.width, h = frames.first.height;
    if (r.x == 0 && r.y == 0 && r.w == w && r.h == h) return image;
    final bool inside =
        r.x >= 0 && r.y >= 0 && r.x + r.w <= w && r.y + r.h <= h;
    final List<img.Image> cropped = frames.map((img.Image f) {
      if (inside) {
        return img.copyCrop(f, x: r.x, y: r.y, width: r.w, height: r.h);
      }
      final img.Image src = f.numChannels == 4 ? f : f.convert(numChannels: 4);
      final img.Image canvas =
          img.Image(width: r.w, height: r.h, numChannels: 4);
      img.compositeImage(canvas, src, dstX: -r.x, dstY: -r.y);
      return canvas;
    }).toList();
    final img.Image out = cropped.first;
    out.frameDuration = frames.first.frameDuration;
    for (int i = 1; i < cropped.length; i++) {
      cropped[i].frameDuration = frames[i].frameDuration;
      out.addFrame(cropped[i]);
    }
    return out;
  }

  /// Full single-image edit (preview path): remove background, then crop/trim.
  /// Pass [rect] to force a shared crop across a whole emote group.
  static img.Image apply(img.Image image, SpriteEditSpec spec, {IntRect? rect}) {
    removeBg(image, spec);
    return cropTo(image, rect ?? computeRect(<img.Image>[image], spec));
  }
}
