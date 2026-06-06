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

/// A named **"way of talking"** — a parametric speech cadence used by
/// [LipSync.talkStyled] to fake natural, visual-novel-style lip movement from a
/// single static sprite (no separate mouth art needed). It captures *how* the
/// jaw moves over one seamless loop, the same idea Live2D/VN engines use when
/// they drive a 0..1 "mouth open" parameter from a voice line — except here the
/// curve is generated to read like speech instead of being sampled from audio.
///
/// All fields are plain numbers/strings, so a style is cheap to copy and
/// **sendable to a background isolate** (it rides along in the bulk-bake job).
/// The catalogue ([LipSync.styleCatalogue]) ships hundreds of these across
/// expressive categories (calm, energetic, loud, soft, emotional, stylised…).
class TalkStyle {
  const TalkStyle(
    this.name,
    this.category, {
    this.syllables = 4,
    this.openAmount = 0.32,
    this.jitter = 0.3,
    this.pause = 0.15,
    this.tension = 0.12,
    this.bob = 0.15,
  });

  /// Display name — unique within [LipSync.styleCatalogue].
  final String name;

  /// Picker grouping (e.g. `Calm`, `Energetic`, `Emotional`, `Stylised`).
  final String category;

  /// Mouth opens per loop — higher = faster chatter. Clamped to 2..12.
  final int syllables;

  /// Peak jaw drop as a fraction of the mouth-box height (≈0.05..0.7).
  final double openAmount;

  /// Rhythm irregularity 0..1 — 0 = metronomic, 1 = very uneven / chattery.
  final double jitter;

  /// How much of the loop falls quiet 0..1 — gaps between words/phrases.
  final double pause;

  /// Resting openness 0..1 — a mumbler never fully closes; a crisp speaker does.
  final double tension;

  /// Subtle head bob 0..1 (a few px at most) — adds life like a Live2D sway.
  final double bob;

  /// Deterministic seed for the per-syllable jitter, derived from [name], so a
  /// style always renders identically (preview == single bake == bulk bake).
  int get seed => name.hashCode & 0x7fffffff;

  TalkStyle copyWith({
    String? name,
    String? category,
    int? syllables,
    double? openAmount,
    double? jitter,
    double? pause,
    double? tension,
    double? bob,
  }) =>
      TalkStyle(
        name ?? this.name,
        category ?? this.category,
        syllables: syllables ?? this.syllables,
        openAmount: openAmount ?? this.openAmount,
        jitter: jitter ?? this.jitter,
        pause: pause ?? this.pause,
        tension: tension ?? this.tension,
        bob: bob ?? this.bob,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'category': category,
        'syllables': syllables,
        'openAmount': openAmount,
        'jitter': jitter,
        'pause': pause,
        'tension': tension,
        'bob': bob,
      };

  static TalkStyle fromJson(Map<String, Object?> m) => TalkStyle(
        (m['name'] as String?) ?? 'Natural',
        (m['category'] as String?) ?? 'Calm',
        syllables: (m['syllables'] as num?)?.toInt() ?? 4,
        openAmount: (m['openAmount'] as num?)?.toDouble() ?? 0.32,
        jitter: (m['jitter'] as num?)?.toDouble() ?? 0.3,
        pause: (m['pause'] as num?)?.toDouble() ?? 0.15,
        tension: (m['tension'] as num?)?.toDouble() ?? 0.12,
        bob: (m['bob'] as num?)?.toDouble() ?? 0.15,
      );
}

/// Builds talking ("(b)") animations so users can add lip-sync without knowing
/// anything about animation.
///
/// Five modes, easiest first:
///  0. [talkStyled] — pick one of hundreds of named [TalkStyle]s ("Calm",
///     "Excited", "Whisper", "Robotic", "Sobbing"…) and it bakes a natural,
///     seamless VN-style talking loop. This is the headline path for "make this
///     static sprite talk like it's in a visual novel".
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

  // ===========================================================================
  // VN talk styles — hundreds of named "ways of talking"
  // ===========================================================================

  /// The default style (a balanced, natural-sounding cadence). Used when no
  /// style is chosen, so existing call-sites keep working.
  static const TalkStyle defaultStyle =
      TalkStyle('Natural', 'Calm', syllables: 4, openAmount: 0.34, jitter: 0.30, pause: 0.15, tension: 0.12, bob: 0.15);

  /// **The headline VN path.** Bake a seamless talking loop for [base] using the
  /// chosen [style]'s cadence — fast/slow, jittery/steady, pausing, mumbling,
  /// bobbing — so a single static Danganronpa/Umineko-style sprite reads as if
  /// it's *talking inside a visual novel*. Zero extra art required.
  ///
  ///  * [mouth] — the box to animate (defaults to the face-derived
  ///    [defaultMouthRegion]).
  ///  * [openAmount] — overrides the style's jaw drop when given (the UI's
  ///    "openness" slider); otherwise [TalkStyle.openAmount] is used.
  ///  * [frames]/[fps] — clip length and speed. More frames = smoother motion.
  static AnimClip talkStyled(
    img.Image base,
    TalkStyle style, {
    IntRect? mouth,
    int frames = 10,
    int fps = 12,
    double? openAmount,
  }) {
    final img.Image src = _rgba(base);
    final IntRect region = _clampRegion(mouth ?? defaultMouthRegion(src), src);
    final int delay = math.max(1, (100 / fps).round());
    final int n = math.max(2, frames);
    final double amp = openAmount ?? style.openAmount;
    // You can't render more distinct mouth-opens than ~half the frame count
    // (Nyquist) — beyond that fast styles alias into noise instead of reading as
    // fast. Cap the *rendered* syllables to n/2 (the name/seed are unchanged, so
    // the cadence's character is preserved); raise the frame count to make a
    // "Fast"/"Hyper" style actually look fast.
    final TalkStyle eff = style.syllables > n ~/ 2
        ? style.copyWith(syllables: math.max(2, n ~/ 2))
        : style;
    // Head bob: ~2.5% of height but clamped to a few px, so a tall full-body
    // sprite gets a subtle sway (not a big bounce that clips or pops against
    // AO's fixed desk when idle⇄talk swaps).
    final int bobMax = math.min(6, (style.bob * 0.025 * src.height).round());
    final List<AnimFrame> out = <AnimFrame>[];
    for (int i = 0; i < n; i++) {
      final double o = styleOpenness(eff, i / n);
      img.Image frame = _openMouth(src, region, o * amp);
      if (bobMax > 0) {
        frame = _shiftV(frame, ((o - 0.5) * bobMax).round());
      }
      out.add(AnimFrame(frame, delayCentis: delay));
    }
    return AnimClip(out);
  }

  /// Speech-like mouth openness `0..1` for [style] over one looping period
  /// `t ∈ [0,1)`. Built from per-syllable Gaussian pulses (placed evenly, then
  /// jittered/silenced deterministically) plus a slow "breath" dip — periodic,
  /// so frame `n-1 → 0` is seamless, but irregular enough to read as real
  /// talking rather than a mechanical sine. Public so the UI can draw the same
  /// cadence in its preview meter.
  static double styleOpenness(TalkStyle style, double t) {
    final double tt = t - t.floorToDouble(); // wrap into [0,1)
    final int n = style.syllables.clamp(1, 24);
    final double width = 0.5 / n;
    double env = 0;
    for (int k = 0; k < n; k++) {
      final double rPos = _rand01(style.seed, k);
      final double rAmp = _rand01(style.seed, k + 4099);
      final double rGap = _rand01(style.seed, k + 8209);
      double amp = 1 - style.jitter * rAmp * 0.85;
      if (rGap < style.pause * 0.55) amp = 0; // a silent beat (a word gap)
      final double center = (k + 0.5) / n + (rPos - 0.5) * style.jitter * width;
      double d = (tt - center).abs();
      d = math.min(d, 1 - d); // circular distance, so pulses wrap at the seam
      final double x = d / (width * 0.95);
      final double v = math.exp(-x * x * 3.2) * amp;
      if (v > env) env = v;
    }
    final double breath = 1 -
        style.pause *
            0.5 *
            (0.5 + 0.5 * math.sin(2 * math.pi * tt + (style.seed % 13) * 0.4));
    final double floor = style.tension * 0.3;
    return (floor + (1 - floor) * env * breath).clamp(0.0, 1.0);
  }

  /// Deterministic pseudo-random in `0..1` from a [seed] and index [k] — drives
  /// the per-syllable jitter so a style renders identically every time.
  static double _rand01(int seed, int k) {
    int h = (seed ^ (k * 0x9E3779B1)) & 0x7fffffff;
    h = (h * 1103515245 + 12345) & 0x7fffffff;
    h ^= h >> 13;
    h = (h * 1103515245 + 12345) & 0x7fffffff;
    return (h & 0xffffff) / 0x1000000;
  }

  /// Shift a frame's content vertically by [dy] px on a same-size transparent
  /// canvas (the head bob). Positive [dy] moves it down.
  static img.Image _shiftV(img.Image f, int dy) {
    if (dy == 0) return f;
    final img.Image canvas =
        img.Image(width: f.width, height: f.height, numChannels: 4);
    return img.compositeImage(canvas, f, dstY: dy);
  }

  /// Look up a style by [name] (e.g. a persisted/JSON choice); falls back to
  /// [defaultStyle] when not found.
  static TalkStyle styleByName(String? name) {
    if (name == null) return defaultStyle;
    for (final TalkStyle s in styleCatalogue) {
      if (s.name == name) return s;
    }
    return defaultStyle;
  }

  /// The catalogue's category names, in catalogue order (for grouped pickers).
  static List<String> get styleCategories {
    final List<String> out = <String>[];
    for (final TalkStyle s in styleCatalogue) {
      if (!out.contains(s.category)) out.add(s.category);
    }
    return out;
  }

  /// Hundreds of named talk styles: every expressive **archetype** ×
  /// {base, Soft, Intense, Fast, Slow}. Generated once, deterministically.
  static final List<TalkStyle> styleCatalogue = _buildCatalogue();

  static List<TalkStyle> _buildCatalogue() {
    final List<TalkStyle> out = <TalkStyle>[];
    for (final TalkStyle a in _archetypes) {
      out.add(a);
      out.add(TalkStyle('${a.name} (Soft)', a.category,
          syllables: a.syllables,
          openAmount: (a.openAmount * 0.6).clamp(0.05, 0.7),
          jitter: (a.jitter * 0.8).clamp(0.0, 1.0),
          pause: (a.pause + 0.06).clamp(0.0, 0.85),
          tension: (a.tension * 1.1).clamp(0.0, 0.6),
          bob: (a.bob * 0.55).clamp(0.0, 1.0)));
      out.add(TalkStyle('${a.name} (Intense)', a.category,
          syllables: (a.syllables + 1).clamp(2, 12),
          openAmount: (a.openAmount * 1.45).clamp(0.05, 0.7),
          jitter: (a.jitter * 1.25).clamp(0.0, 1.0),
          pause: (a.pause * 0.7).clamp(0.0, 0.85),
          tension: a.tension.clamp(0.0, 0.6),
          bob: (a.bob * 1.4).clamp(0.0, 1.0)));
      out.add(TalkStyle('${a.name} (Fast)', a.category,
          syllables: (a.syllables + 2).clamp(2, 12),
          openAmount: a.openAmount.clamp(0.05, 0.7),
          jitter: (a.jitter * 1.1).clamp(0.0, 1.0),
          pause: (a.pause * 0.6).clamp(0.0, 0.85),
          tension: a.tension,
          bob: a.bob));
      out.add(TalkStyle('${a.name} (Slow)', a.category,
          syllables: (a.syllables - 1).clamp(2, 12),
          openAmount: (a.openAmount * 0.92).clamp(0.05, 0.7),
          jitter: a.jitter,
          pause: (a.pause + 0.16).clamp(0.0, 0.85),
          tension: a.tension,
          bob: (a.bob * 0.8).clamp(0.0, 1.0)));
    }
    return out;
  }

  /// The expressive base archetypes (one per "personality" of speech). Each is
  /// expanded into five catalogue entries by [_buildCatalogue].
  static const List<TalkStyle> _archetypes = <TalkStyle>[
    // --- Calm / neutral -----------------------------------------------------
    defaultStyle,
    TalkStyle('Calm', 'Calm', syllables: 3, openAmount: 0.26, jitter: 0.18, pause: 0.22, tension: 0.08, bob: 0.08),
    TalkStyle('Narration', 'Calm', syllables: 4, openAmount: 0.28, jitter: 0.20, pause: 0.28, tension: 0.06, bob: 0.05),
    TalkStyle('Monotone', 'Calm', syllables: 4, openAmount: 0.20, jitter: 0.05, pause: 0.10, tension: 0.05, bob: 0.02),
    TalkStyle('Gentle', 'Calm', syllables: 3, openAmount: 0.24, jitter: 0.15, pause: 0.24, tension: 0.10, bob: 0.10),
    TalkStyle('Thoughtful', 'Calm', syllables: 3, openAmount: 0.27, jitter: 0.25, pause: 0.34, tension: 0.08, bob: 0.08),
    TalkStyle('Formal', 'Calm', syllables: 4, openAmount: 0.30, jitter: 0.12, pause: 0.20, tension: 0.05, bob: 0.04),
    TalkStyle('Storyteller', 'Calm', syllables: 4, openAmount: 0.33, jitter: 0.30, pause: 0.26, tension: 0.10, bob: 0.16),
    TalkStyle('Deadpan', 'Calm', syllables: 3, openAmount: 0.18, jitter: 0.05, pause: 0.14, tension: 0.04, bob: 0.00),
    TalkStyle('Cold', 'Calm', syllables: 3, openAmount: 0.20, jitter: 0.08, pause: 0.20, tension: 0.04, bob: 0.02),
    TalkStyle('Warm', 'Calm', syllables: 4, openAmount: 0.30, jitter: 0.22, pause: 0.20, tension: 0.12, bob: 0.14),
    TalkStyle('Confident', 'Calm', syllables: 4, openAmount: 0.36, jitter: 0.20, pause: 0.16, tension: 0.10, bob: 0.16),
    // --- Energetic ----------------------------------------------------------
    TalkStyle('Excited', 'Energetic', syllables: 6, openAmount: 0.42, jitter: 0.45, pause: 0.06, tension: 0.16, bob: 0.30),
    TalkStyle('Cheerful', 'Energetic', syllables: 5, openAmount: 0.38, jitter: 0.40, pause: 0.10, tension: 0.14, bob: 0.28),
    TalkStyle('Hyper', 'Energetic', syllables: 8, openAmount: 0.46, jitter: 0.60, pause: 0.04, tension: 0.18, bob: 0.40),
    TalkStyle('Bubbly', 'Energetic', syllables: 6, openAmount: 0.40, jitter: 0.50, pause: 0.08, tension: 0.16, bob: 0.34),
    TalkStyle('Energetic', 'Energetic', syllables: 6, openAmount: 0.40, jitter: 0.40, pause: 0.08, tension: 0.15, bob: 0.30),
    TalkStyle('Peppy', 'Energetic', syllables: 6, openAmount: 0.38, jitter: 0.45, pause: 0.08, tension: 0.14, bob: 0.32),
    TalkStyle('Chattering', 'Energetic', syllables: 8, openAmount: 0.34, jitter: 0.55, pause: 0.06, tension: 0.20, bob: 0.26),
    TalkStyle('Rambling', 'Energetic', syllables: 7, openAmount: 0.32, jitter: 0.50, pause: 0.05, tension: 0.22, bob: 0.20),
    // --- Loud / aggressive --------------------------------------------------
    TalkStyle('Shouting', 'Loud', syllables: 5, openAmount: 0.55, jitter: 0.35, pause: 0.08, tension: 0.20, bob: 0.40),
    TalkStyle('Angry', 'Loud', syllables: 5, openAmount: 0.50, jitter: 0.45, pause: 0.10, tension: 0.22, bob: 0.36),
    TalkStyle('Furious', 'Loud', syllables: 6, openAmount: 0.58, jitter: 0.55, pause: 0.06, tension: 0.26, bob: 0.46),
    TalkStyle('Commanding', 'Loud', syllables: 4, openAmount: 0.50, jitter: 0.25, pause: 0.14, tension: 0.15, bob: 0.30),
    TalkStyle('Booming', 'Loud', syllables: 4, openAmount: 0.60, jitter: 0.20, pause: 0.16, tension: 0.18, bob: 0.34),
    TalkStyle('Aggressive', 'Loud', syllables: 5, openAmount: 0.50, jitter: 0.45, pause: 0.08, tension: 0.24, bob: 0.40),
    TalkStyle('Menacing', 'Loud', syllables: 3, openAmount: 0.40, jitter: 0.20, pause: 0.24, tension: 0.16, bob: 0.18),
    TalkStyle('Villainous', 'Loud', syllables: 4, openAmount: 0.45, jitter: 0.30, pause: 0.20, tension: 0.18, bob: 0.24),
    // --- Soft / quiet -------------------------------------------------------
    TalkStyle('Whisper', 'Soft', syllables: 4, openAmount: 0.16, jitter: 0.20, pause: 0.22, tension: 0.10, bob: 0.06),
    TalkStyle('Shy', 'Soft', syllables: 3, openAmount: 0.18, jitter: 0.25, pause: 0.30, tension: 0.12, bob: 0.08),
    TalkStyle('Timid', 'Soft', syllables: 3, openAmount: 0.16, jitter: 0.30, pause: 0.34, tension: 0.12, bob: 0.06),
    TalkStyle('Sleepy', 'Soft', syllables: 2, openAmount: 0.22, jitter: 0.15, pause: 0.40, tension: 0.16, bob: 0.10),
    TalkStyle('Tired', 'Soft', syllables: 3, openAmount: 0.20, jitter: 0.20, pause: 0.36, tension: 0.14, bob: 0.08),
    TalkStyle('Mumbling', 'Soft', syllables: 4, openAmount: 0.18, jitter: 0.40, pause: 0.16, tension: 0.30, bob: 0.06),
    TalkStyle('Breathy', 'Soft', syllables: 3, openAmount: 0.22, jitter: 0.30, pause: 0.28, tension: 0.20, bob: 0.10),
    TalkStyle('Hesitant', 'Soft', syllables: 3, openAmount: 0.24, jitter: 0.50, pause: 0.40, tension: 0.12, bob: 0.08),
    // --- Emotional ----------------------------------------------------------
    TalkStyle('Sobbing', 'Emotional', syllables: 4, openAmount: 0.34, jitter: 0.60, pause: 0.30, tension: 0.22, bob: 0.40),
    TalkStyle('Crying', 'Emotional', syllables: 4, openAmount: 0.32, jitter: 0.55, pause: 0.28, tension: 0.24, bob: 0.38),
    TalkStyle('Trembling', 'Emotional', syllables: 6, openAmount: 0.26, jitter: 0.70, pause: 0.20, tension: 0.26, bob: 0.50),
    TalkStyle('Nervous', 'Emotional', syllables: 5, openAmount: 0.26, jitter: 0.60, pause: 0.22, tension: 0.20, bob: 0.30),
    TalkStyle('Panicked', 'Emotional', syllables: 8, openAmount: 0.40, jitter: 0.70, pause: 0.05, tension: 0.20, bob: 0.50),
    TalkStyle('Anxious', 'Emotional', syllables: 6, openAmount: 0.28, jitter: 0.60, pause: 0.18, tension: 0.22, bob: 0.34),
    TalkStyle('Heartfelt', 'Emotional', syllables: 4, openAmount: 0.32, jitter: 0.25, pause: 0.24, tension: 0.14, bob: 0.20),
    TalkStyle('Pleading', 'Emotional', syllables: 4, openAmount: 0.34, jitter: 0.40, pause: 0.22, tension: 0.18, bob: 0.26),
    // --- Stylised / quirky --------------------------------------------------
    TalkStyle('Robotic', 'Stylised', syllables: 5, openAmount: 0.30, jitter: 0.00, pause: 0.12, tension: 0.00, bob: 0.00),
    TalkStyle('Glitchy', 'Stylised', syllables: 8, openAmount: 0.40, jitter: 0.85, pause: 0.10, tension: 0.10, bob: 0.30),
    TalkStyle('Singing', 'Stylised', syllables: 3, openAmount: 0.50, jitter: 0.20, pause: 0.12, tension: 0.30, bob: 0.22),
    TalkStyle('Chanting', 'Stylised', syllables: 4, openAmount: 0.40, jitter: 0.10, pause: 0.18, tension: 0.24, bob: 0.16),
    TalkStyle('Stuttering', 'Stylised', syllables: 9, openAmount: 0.30, jitter: 0.75, pause: 0.18, tension: 0.12, bob: 0.20),
    TalkStyle('Laughing', 'Stylised', syllables: 7, openAmount: 0.42, jitter: 0.50, pause: 0.12, tension: 0.18, bob: 0.45),
    TalkStyle('Giggling', 'Stylised', syllables: 8, openAmount: 0.30, jitter: 0.55, pause: 0.14, tension: 0.16, bob: 0.40),
    TalkStyle('Smug', 'Stylised', syllables: 3, openAmount: 0.30, jitter: 0.20, pause: 0.26, tension: 0.10, bob: 0.12),
    TalkStyle('Sarcastic', 'Stylised', syllables: 4, openAmount: 0.30, jitter: 0.30, pause: 0.24, tension: 0.12, bob: 0.14),
    TalkStyle('Dramatic', 'Stylised', syllables: 4, openAmount: 0.46, jitter: 0.30, pause: 0.30, tension: 0.16, bob: 0.30),
    TalkStyle('Theatrical', 'Stylised', syllables: 5, openAmount: 0.50, jitter: 0.35, pause: 0.24, tension: 0.18, bob: 0.36),
    TalkStyle('Seductive', 'Stylised', syllables: 3, openAmount: 0.30, jitter: 0.20, pause: 0.30, tension: 0.22, bob: 0.16),
    TalkStyle('Cute', 'Stylised', syllables: 5, openAmount: 0.30, jitter: 0.40, pause: 0.14, tension: 0.14, bob: 0.30),
    TalkStyle('Tsundere', 'Stylised', syllables: 5, openAmount: 0.36, jitter: 0.50, pause: 0.16, tension: 0.16, bob: 0.30),
    TalkStyle('Yandere', 'Stylised', syllables: 6, openAmount: 0.40, jitter: 0.60, pause: 0.20, tension: 0.20, bob: 0.34),
    TalkStyle('Whimsical', 'Stylised', syllables: 5, openAmount: 0.34, jitter: 0.45, pause: 0.16, tension: 0.14, bob: 0.30),
  ];

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
