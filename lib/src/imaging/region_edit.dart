import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'button_maker.dart' show IntRect;
import 'color_ops.dart';

/// A per-pixel selection mask (0 = unselected, 255 = fully selected, values in
/// between for soft/feathered edges). Editing operations are applied *through*
/// this mask, so you can target just the clothes, hair, a drawn rectangle, etc.
class SelectionMask {
  SelectionMask(this.width, this.height)
      : data = Uint8List(width * height);

  SelectionMask.full(this.width, this.height)
      : data = Uint8List(width * height)..fillRange(0, width * height, 255);

  final int width;
  final int height;
  final Uint8List data;

  int get(int x, int y) => data[y * width + x];
  void set(int x, int y, int v) => data[y * width + x] = v.clamp(0, 255);

  SelectionMask invert() {
    final SelectionMask m = SelectionMask(width, height);
    for (int i = 0; i < data.length; i++) {
      m.data[i] = 255 - data[i];
    }
    return m;
  }

  SelectionMask combine(SelectionMask other, _MaskCombine mode) {
    final SelectionMask m = SelectionMask(width, height);
    for (int i = 0; i < data.length; i++) {
      final int a = data[i], b = other.data[i];
      m.data[i] = switch (mode) {
        _MaskCombine.union => math.max(a, b),
        _MaskCombine.intersect => math.min(a, b),
        _MaskCombine.subtract => (a - b).clamp(0, 255),
      };
    }
    return m;
  }

  int get selectedCount => data.where((int v) => v > 0).length;
}

enum _MaskCombine { union, intersect, subtract }

/// Region/clothing editing — selection building + masked operations.
///
/// Typical "change the clothes" flow:
///   1. [selectByColor] on a clothing pixel (magic-wand) to grab the outfit.
///   2. [feather] the mask a little for clean edges.
///   3. [applyOps] a `colorize`/`hueShift` pipeline through the mask.
/// Other primitives: [erase] (cut a region out), [fill] (paint a colour),
/// rectangle/ellipse selections, grow/shrink, and mask combination.
class RegionEditor {
  const RegionEditor._();

  // ---- selection builders ----

  static SelectionMask rectangle(int w, int h, IntRect r, {int value = 255}) {
    final SelectionMask m = SelectionMask(w, h);
    for (int y = r.y; y < r.y + r.h && y < h; y++) {
      for (int x = r.x; x < r.x + r.w && x < w; x++) {
        if (x >= 0 && y >= 0) m.set(x, y, value);
      }
    }
    return m;
  }

  static SelectionMask ellipse(int w, int h, IntRect r) {
    final SelectionMask m = SelectionMask(w, h);
    final double cx = r.x + r.w / 2, cy = r.y + r.h / 2;
    final double rx = r.w / 2, ry = r.h / 2;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final double nx = (x - cx) / (rx == 0 ? 1 : rx);
        final double ny = (y - cy) / (ry == 0 ? 1 : ry);
        if (nx * nx + ny * ny <= 1.0) m.set(x, y, 255);
      }
    }
    return m;
  }

  /// Magic-wand: select pixels whose colour is within [tolerance] (0..441) of
  /// the colour at (x, y). When [contiguous] is true, only the connected blob is
  /// selected (flood fill); otherwise every matching pixel in the image is.
  static SelectionMask selectByColor(
    img.Image image,
    int x,
    int y, {
    double tolerance = 48,
    bool contiguous = true,
    bool ignoreTransparent = true,
  }) {
    final int w = image.width, h = image.height;
    final SelectionMask m = SelectionMask(w, h);
    final img.Pixel target = image.getPixel(x.clamp(0, w - 1), y.clamp(0, h - 1));
    final int tr = target.r.toInt(), tg = target.g.toInt(), tb = target.b.toInt();
    // Compare *squared* distance to the squared tolerance — exactly equivalent to
    // `sqrt(...) <= tolerance` but with no per-pixel `sqrt`/`pow` (the magic-wand
    // flood fill touches every connected pixel).
    final double tolSq = tolerance * tolerance;

    bool matches(int px, int py) {
      final img.Pixel p = image.getPixel(px, py);
      if (ignoreTransparent && p.a == 0) return false;
      final int dr = p.r.toInt() - tr, dg = p.g.toInt() - tg, db = p.b.toInt() - tb;
      return dr * dr + dg * dg + db * db <= tolSq;
    }

    if (!contiguous) {
      for (int py = 0; py < h; py++) {
        for (int px = 0; px < w; px++) {
          if (matches(px, py)) m.set(px, py, 255);
        }
      }
      return m;
    }

    // Flood fill (4-connected).
    final List<int> stack = <int>[y * w + x];
    final Uint8List seen = Uint8List(w * h);
    while (stack.isNotEmpty) {
      final int idx = stack.removeLast();
      if (seen[idx] != 0) continue;
      seen[idx] = 1;
      final int px = idx % w, py = idx ~/ w;
      if (!matches(px, py)) continue;
      m.data[idx] = 255;
      if (px > 0) stack.add(idx - 1);
      if (px < w - 1) stack.add(idx + 1);
      if (py > 0) stack.add(idx - w);
      if (py < h - 1) stack.add(idx + w);
    }
    return m;
  }

  /// Select by luminance band (e.g. only the shadows or only the highlights).
  static SelectionMask selectByLuminance(img.Image image,
      {int min = 0, int max = 255}) {
    final SelectionMask m = SelectionMask(image.width, image.height);
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final img.Pixel p = image.getPixel(x, y);
        if (p.a == 0) continue;
        final int l = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
        if (l >= min && l <= max) m.set(x, y, 255);
      }
    }
    return m;
  }

  // ---- mask shaping ----

  /// Soften mask edges with a separable box blur (radius in px).
  static SelectionMask feather(SelectionMask mask, {int radius = 2}) {
    if (radius <= 0) return mask;
    final SelectionMask tmp = SelectionMask(mask.width, mask.height);
    final SelectionMask out = SelectionMask(mask.width, mask.height);
    final int w = mask.width, h = mask.height;
    // Horizontal pass.
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int sum = 0, n = 0;
        for (int k = -radius; k <= radius; k++) {
          final int xx = x + k;
          if (xx >= 0 && xx < w) {
            sum += mask.get(xx, y);
            n++;
          }
        }
        tmp.set(x, y, sum ~/ n);
      }
    }
    // Vertical pass.
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int sum = 0, n = 0;
        for (int k = -radius; k <= radius; k++) {
          final int yy = y + k;
          if (yy >= 0 && yy < h) {
            sum += tmp.get(x, yy);
            n++;
          }
        }
        out.set(x, y, sum ~/ n);
      }
    }
    return out;
  }

  /// Grow (dilate) or shrink (erode) the selection by thresholding a blur.
  static SelectionMask grow(SelectionMask mask, int px) =>
      _morph(mask, px, grow: true);
  static SelectionMask shrink(SelectionMask mask, int px) =>
      _morph(mask, px, grow: false);

  static SelectionMask _morph(SelectionMask mask, int px, {required bool grow}) {
    if (px <= 0) return mask;
    final SelectionMask blurred = feather(mask, radius: px);
    final SelectionMask out = SelectionMask(mask.width, mask.height);
    for (int i = 0; i < out.data.length; i++) {
      out.data[i] = grow
          ? (blurred.data[i] > 0 ? 255 : 0)
          : (blurred.data[i] >= 255 ? 255 : 0);
    }
    return out;
  }

  // ---- masked operations ----

  /// Apply a colour-op [pipeline] only where the mask is set, blending by the
  /// mask weight. This is how "recolour just the clothes" works.
  static void applyOps(img.Image image, SelectionMask mask, List<ColorOp> pipeline) {
    final img.Image edited = image.clone();
    ImageOps.applyAll(edited, pipeline);
    _blendByMask(image, edited, mask);
  }

  /// Remove a (roughly solid) background by flood-filling inward from all four
  /// corners and erasing the matched region. Great for sprites on a flat colour.
  static void removeBackgroundFromCorners(img.Image image,
      {double tolerance = 40, int feather = 1}) {
    final int w = image.width, h = image.height;
    if (w == 0 || h == 0) return;
    SelectionMask mask = SelectionMask(w, h);
    for (final List<int> c in <List<int>>[
      <int>[0, 0],
      <int>[w - 1, 0],
      <int>[0, h - 1],
      <int>[w - 1, h - 1],
    ]) {
      final SelectionMask m = selectByColor(image, c[0], c[1],
          tolerance: tolerance, contiguous: true);
      mask = mask.combine(m, _MaskCombine.union);
    }
    erase(image, feather > 0 ? RegionEditor.feather(mask, radius: feather) : mask);
  }

  /// Make every pixel within [tolerance] of [argb] transparent (e.g. knock out
  /// a known background colour anywhere in the image).
  static void eraseColor(img.Image image, int argb, {double tolerance = 40}) {
    final int tr = (argb >> 16) & 0xFF, tg = (argb >> 8) & 0xFF, tb = argb & 0xFF;
    final double tolSq = tolerance * tolerance; // squared compare, no sqrt/pow
    for (final img.Pixel p in image) {
      if (p.a == 0) continue;
      final int dr = p.r.toInt() - tr, dg = p.g.toInt() - tg, db = p.b.toInt() - tb;
      if (dr * dr + dg * dg + db * db <= tolSq) {
        p.a = 0;
      }
    }
  }

  /// Erase (make transparent) through the mask — cut a region out of the sprite.
  static void erase(img.Image image, SelectionMask mask) {
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final int wgt = mask.get(x, y);
        if (wgt == 0) continue;
        final img.Pixel p = image.getPixel(x, y);
        final int a = (p.a.toInt() * (255 - wgt)) ~/ 255;
        image.setPixelRgba(x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(), a);
      }
    }
  }

  /// Paint a flat colour through the mask.
  static void fill(img.Image image, SelectionMask mask, int argb) {
    final int r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
    final int a = (argb >> 24) & 0xFF;
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final int wgt = mask.get(x, y);
        if (wgt == 0) continue;
        final double f = wgt / 255.0;
        final img.Pixel p = image.getPixel(x, y);
        image.setPixelRgba(
          x,
          y,
          (p.r + (r - p.r) * f).round(),
          (p.g + (g - p.g) * f).round(),
          (p.b + (b - p.b) * f).round(),
          (p.a + (a - p.a) * f).round(),
        );
      }
    }
  }

  static void _blendByMask(img.Image base, img.Image edited, SelectionMask mask) {
    for (int y = 0; y < base.height; y++) {
      for (int x = 0; x < base.width; x++) {
        final int wgt = mask.get(x, y);
        if (wgt == 0) continue;
        final double f = wgt / 255.0;
        final img.Pixel b = base.getPixel(x, y);
        final img.Pixel e = edited.getPixel(x, y);
        base.setPixelRgba(
          x,
          y,
          (b.r + (e.r - b.r) * f).round(),
          (b.g + (e.g - b.g) * f).round(),
          (b.b + (e.b - b.b) * f).round(),
          (b.a + (e.a - b.a) * f).round(),
        );
      }
    }
  }
}
