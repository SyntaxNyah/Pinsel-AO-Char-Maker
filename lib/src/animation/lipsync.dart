import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../imaging/button_maker.dart' show IntRect, ButtonMaker;
import 'anim_clip.dart';

/// A mouth box expressed as **fractions** of the sprite (`0..1`), so the same
/// region survives downscaled previews and applies sensibly to differently-sized
/// sprites. [x]/[y] are the top-left corner; [w]/[h] the size.
class MouthRegion {
  const MouthRegion(this.x, this.y, this.w, this.h);

  final double x, y, w, h;

  /// This region in pixels for an image of [imgW]×[imgH].
  IntRect toPixels(int imgW, int imgH) => IntRect(
        (x * imgW).round().clamp(0, imgW),
        (y * imgH).round().clamp(0, imgH),
        math.max(1, (w * imgW).round()),
        math.max(1, (h * imgH).round()),
      );

  MouthRegion copyWith({double? x, double? y, double? w, double? h}) =>
      MouthRegion(x ?? this.x, y ?? this.y, w ?? this.w, h ?? this.h);

  /// The face-derived default for [src], as fractions (see
  /// [LipSync.defaultMouthRegion]).
  static MouthRegion defaultFor(img.Image src) {
    final IntRect r = LipSync.defaultMouthRegion(src);
    return MouthRegion(
      r.x / src.width,
      r.y / src.height,
      r.w / src.width,
      r.h / src.height,
    );
  }
}

/// Builds talking ("(b)") animations so users can add lip-sync without knowing
/// anything about animation.
///
/// Four modes, easiest first:
///  1. [talk] — give it ONE sprite (and optionally where the mouth is) and it
///     fakes a natural, speech-like talking loop by dropping the jaw within the
///     mouth region with an irregular cadence. Zero extra art required; this is
///     what the Animation Studio's **Mouth** tab uses, with a live preview and a
///     fully adjustable mouth box.
///  2. [twoState] — give it a mouth-closed and a mouth-open sprite. Done.
///  3. [fromVisemes] — give it several mouth shapes; it cycles them naturally.
///  4. [auto] — the original single-pulse jaw-drop (kept for back-compat).
class LipSync {
  const LipSync._();

  /// Fraction of the detected/region height the jaw drops at full openness.
  static const double defaultOpenAmount = 0.32;

  /// A natural, **seamless-looping** talking animation faked from a single
  /// sprite [base]. The lower edge of [mouth] is stretched downward (a jaw
  /// drop) by a speech-like, periodic amount so it reads as talking and loops
  /// cleanly when AO plays the `(b)` sprite on repeat.
  ///
  ///  * [mouth] — the box to animate. Defaults to [defaultMouthRegion] (derived
  ///    from the face), so most sprites need no adjustment; the UI lets the user
  ///    nudge it.
  ///  * [openAmount] — how far the jaw drops (fraction of the region height).
  ///  * [frames] / [fps] — clip length and speed.
  static AnimClip talk(
    img.Image base, {
    IntRect? mouth,
    double openAmount = defaultOpenAmount,
    int frames = 8,
    int fps = 10,
  }) {
    final img.Image src = _rgba(base);
    final IntRect region = _clampRegion(mouth ?? defaultMouthRegion(src), src);
    final int delay = math.max(1, (100 / fps).round());
    final int n = math.max(2, frames);
    final List<AnimFrame> out = <AnimFrame>[];
    for (int i = 0; i < n; i++) {
      // i/n (exclusive of 1.0) keeps the motion periodic so frame n-1 → frame 0
      // is continuous: the loop has no visible seam.
      final double open = _talkOpenness(i / n) * openAmount;
      out.add(AnimFrame(_openMouth(src, region, open), delayCentis: delay));
    }
    return AnimClip(out);
  }

  /// Speech-like mouth openness in `0..1` over one looping period `t ∈ [0,1)`.
  ///
  /// A sum of integer harmonics: periodic (so it loops), but irregular enough to
  /// read as talking rather than a mechanical open/close. Public so the UI can
  /// draw the same cadence in its little preview meter.
  static double talkOpenness(double t) => _talkOpenness(t);

  static double _talkOpenness(double t) {
    final double a = math.sin(2 * math.pi * t); // slow open/close
    final double b = math.sin(2 * math.pi * 2 * t + 1.7); // flutter
    final double c = math.sin(2 * math.pi * 3 * t + 0.4); // chatter
    final double v = 0.55 * a + 0.30 * b + 0.15 * c; // ~[-1,1]
    return ((v + 1) / 2).clamp(0.0, 1.0);
  }

  /// Closed/open alternation. The resulting clip loops, which is exactly what AO
  /// wants for a talking sprite.
  static AnimClip twoState(
    img.Image closed,
    img.Image open, {
    int closedCentis = 7,
    int openCentis = 7,
  }) {
    return AnimClip(<AnimFrame>[
      AnimFrame(_rgba(closed), delayCentis: closedCentis),
      AnimFrame(_rgba(open), delayCentis: openCentis),
    ]);
  }

  /// Cycle through any number of mouth shapes (visemes). A natural talking mouth
  /// bounces between a few shapes; pass them in the order you want them played.
  static AnimClip fromVisemes(
    List<img.Image> visemes, {
    int perFrameCentis = 6,
    bool pingPong = true,
  }) {
    if (visemes.isEmpty) {
      throw ArgumentError('Need at least one viseme.');
    }
    final List<img.Image> seq = <img.Image>[...visemes];
    if (pingPong && visemes.length > 2) {
      seq.addAll(visemes.reversed.skip(1).take(visemes.length - 2));
    }
    return AnimClip(<AnimFrame>[
      for (final img.Image v in seq) AnimFrame(_rgba(v), delayCentis: perFrameCentis),
    ]);
  }

  /// Procedural fallback: fake a mouth opening on a single sprite by stretching
  /// the lower part of a mouth region downward (a "jaw drop") with a single
  /// open→close pulse. Kept for back-compat; [talk] produces a more convincing,
  /// continuously-talking loop.
  static AnimClip auto(
    img.Image base, {
    IntRect? mouth,
    double openAmount = 0.35,
    int frames = 4,
    int fps = 10,
  }) {
    final img.Image src = _rgba(base);
    final IntRect region = _clampRegion(mouth ?? defaultMouthRegion(src), src);
    final int delay = math.max(1, (100 / fps).round());
    final List<AnimFrame> out = <AnimFrame>[];
    for (int i = 0; i < frames; i++) {
      final double phase = frames <= 1 ? 0 : i / frames;
      final double open = (0.5 - 0.5 * math.cos(2 * math.pi * phase)) * openAmount;
      out.add(AnimFrame(_openMouth(src, region, open), delayCentis: delay));
    }
    return AnimClip(out);
  }

  // ---- helpers ----

  static img.Image _rgba(img.Image src) =>
      src.numChannels == 4 ? src.clone() : src.convert(numChannels: 4);

  /// A sensible default mouth box for [src]: it locates the **face** (via the
  /// alpha-silhouette head detector also used for buttons) and places the box
  /// across the lower-middle of the head — i.e. roughly where a mouth sits on an
  /// AO bust/full-body sprite. Far more accurate than assuming the mouth is in
  /// the lower third of the whole image (which is the knees on a full body).
  static IntRect defaultMouthRegion(img.Image src) {
    final IntRect head = ButtonMaker.headSquare(src);
    final int w = math.max(4, (head.w * 0.5).round());
    final int h = math.max(3, (head.h * 0.14).round());
    final int x = head.x + (head.w - w) ~/ 2;
    final int y = head.y + (head.h * 0.60).round();
    return _clampRegion(IntRect(x, y, w, h), src);
  }

  /// Keep a region inside the image bounds (and at least 1px each side).
  static IntRect _clampRegion(IntRect r, img.Image src) {
    final int w = r.w.clamp(1, src.width);
    final int h = r.h.clamp(1, src.height);
    final int x = r.x.clamp(0, src.width - w);
    final int y = r.y.clamp(0, src.height - h);
    return IntRect(x, y, w, h);
  }

  /// Stretch the mouth region taller by [open] (fraction of its height) and
  /// composite it back, nudged down — a cheap but convincing open mouth.
  static img.Image _openMouth(img.Image src, IntRect r, double open) {
    final img.Image frame = src.clone();
    if (open <= 0.001) return frame;
    final img.Image piece =
        img.copyCrop(src, x: r.x, y: r.y, width: r.w, height: r.h);
    final int newH = math.max(r.h, (r.h * (1 + open)).round());
    final img.Image stretched = img.copyResize(piece,
        width: r.w, height: newH, interpolation: img.Interpolation.cubic);
    return img.compositeImage(frame, stretched, dstX: r.x, dstY: r.y);
  }
}
