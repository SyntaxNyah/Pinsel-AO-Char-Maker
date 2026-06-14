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
    // Sequential pixel cursor instead of per-pixel getPixel(x,y) random access.
    for (final img.Pixel p in image) {
      if (p.a == 0) continue;
      final int l = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
      if (l >= min && l <= max) m.set(p.x, p.y, 255);
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
  ///
  /// When [despill] is set, the edge fringe is **un-tinted** afterwards (see
  /// [despillBackground]) using the averaged corner colour — so soft hair/edge
  /// pixels don't keep a coloured halo of the removed background. A wider
  /// [feather] gives the despill a softer band to clean.
  static void removeBackgroundFromCorners(img.Image image,
      {double tolerance = 40, int feather = 1, bool despill = false}) {
    final int w = image.width, h = image.height;
    if (w == 0 || h == 0) return;
    final List<List<int>> corners = <List<int>>[
      <int>[0, 0],
      <int>[w - 1, 0],
      <int>[0, h - 1],
      <int>[w - 1, h - 1],
    ];
    // Average the corners up front (before we erase them) as the background
    // colour to un-mix during despill.
    int sr = 0, sg = 0, sb = 0;
    for (final List<int> c in corners) {
      final img.Pixel p = image.getPixel(c[0], c[1]);
      sr += p.r.toInt();
      sg += p.g.toInt();
      sb += p.b.toInt();
    }
    final int bgArgb = (0xFF << 24) |
        ((sr ~/ 4) << 16) |
        ((sg ~/ 4) << 8) |
        (sb ~/ 4);
    SelectionMask mask = SelectionMask(w, h);
    for (final List<int> c in corners) {
      final SelectionMask m = selectByColor(image, c[0], c[1],
          tolerance: tolerance, contiguous: true);
      mask = mask.combine(m, _MaskCombine.union);
    }
    erase(image, feather > 0 ? RegionEditor.feather(mask, radius: feather) : mask);
    if (despill) despillBackground(image, bgArgb);
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

  /// **Despill** soft edges: recover the true foreground colour on
  /// semi-transparent pixels by *un-mixing* the background colour they bled into.
  ///
  /// A feathered background cut leaves hair/edge pixels partly transparent but
  /// still tinted by the old background (a coloured "halo"/fringe). A pixel's
  /// observed colour is the matte equation `observed = a·fg + (1-a)·bg`, so the
  /// real foreground is `fg = (observed - (1-a)·bg) / a`. We solve that per soft
  /// pixel and blend toward it by [strength]. Fully-opaque (`a==255`) and fully-
  /// transparent (`a==0`) pixels are untouched (the formula is a no-op / skipped),
  /// so this is safe to run over a whole frame. This is the cheap, deterministic
  /// alternative to a full alpha-matting solver — it cleans the fringe without
  /// per-target solving and is identical on every platform.
  static void despillBackground(img.Image image, int bgArgb,
      {double strength = 1.0}) {
    final int br = (bgArgb >> 16) & 0xFF;
    final int bg = (bgArgb >> 8) & 0xFF;
    final int bb = bgArgb & 0xFF;
    final double s = strength.clamp(0.0, 1.0);
    if (s <= 0) return;
    for (final img.Pixel p in image) {
      final int a = p.a.toInt();
      if (a == 0 || a >= 255) continue; // only the soft edge band
      final double af = a / 255.0;
      final double inv = (1 - af) / af;
      // Un-mix: fg = observed/af - (1-af)/af · bg.
      final double nr = p.r / af - inv * br;
      final double ng = p.g / af - inv * bg;
      final double nb = p.b / af - inv * bb;
      p
        ..r = (p.r + (nr - p.r) * s).round().clamp(0, 255)
        ..g = (p.g + (ng - p.g) * s).round().clamp(0, 255)
        ..b = (p.b + (nb - p.b) * s).round().clamp(0, 255);
    }
  }

  /// Erase (make transparent) through the mask — cut a region out of the sprite.
  static void erase(img.Image image, SelectionMask mask) {
    for (final img.Pixel p in image) {
      final int wgt = mask.get(p.x, p.y);
      if (wgt == 0) continue;
      p.a = (p.a.toInt() * (255 - wgt)) ~/ 255;
    }
  }

  /// Paint a flat colour through the mask.
  static void fill(img.Image image, SelectionMask mask, int argb) {
    final int r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
    final int a = (argb >> 24) & 0xFF;
    for (final img.Pixel p in image) {
      final int wgt = mask.get(p.x, p.y);
      if (wgt == 0) continue;
      final double f = wgt / 255.0;
      p
        ..r = (p.r + (r - p.r) * f).round()
        ..g = (p.g + (g - p.g) * f).round()
        ..b = (p.b + (b - p.b) * f).round()
        ..a = (p.a + (a - p.a) * f).round();
    }
  }

  static void _blendByMask(img.Image base, img.Image edited, SelectionMask mask) {
    // Walk `base` with the sequential cursor (the write-back side); `edited` is
    // sampled by coordinate.
    for (final img.Pixel b in base) {
      final int wgt = mask.get(b.x, b.y);
      if (wgt == 0) continue;
      final double f = wgt / 255.0;
      final img.Pixel e = edited.getPixel(b.x, b.y);
      b
        ..r = (b.r + (e.r - b.r) * f).round()
        ..g = (b.g + (e.g - b.g) * f).round()
        ..b = (b.b + (e.b - b.b) * f).round()
        ..a = (b.a + (e.a - b.a) * f).round();
    }
  }
}
