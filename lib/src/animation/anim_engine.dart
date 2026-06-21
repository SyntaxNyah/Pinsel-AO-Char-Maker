import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../imaging/button_maker.dart' show IntRect;
import '../imaging/color_ops.dart';
import 'anim_clip.dart';
import 'easing.dart';

/// Per-frame transform + colour state for one layer.
class FrameSpec {
  double dx = 0;
  double dy = 0;
  double scale = 1; // uniform scale
  double scaleX = 1; // extra horizontal scale (for squash & stretch)
  double scaleY = 1; // extra vertical scale
  double angle = 0; // degrees
  double opacity = 1;
  final List<ColorOp> colorOps = <ColorOp>[];

  void add(FrameSpec other) {
    dx += other.dx;
    dy += other.dy;
    scale *= other.scale;
    scaleX *= other.scaleX;
    scaleY *= other.scaleY;
    angle += other.angle;
    opacity *= other.opacity;
    colorOps.addAll(other.colorOps);
  }
}

/// A configured, serializable animation effect. Stack several to combine them
/// ("move + glow + rainbow"). Attach a [region] to animate only part of the
/// sprite (e.g. wave a hand).
class AnimRecipe {
  AnimRecipe(
    this.type, {
    Map<String, double>? p,
    Map<String, String>? colors,
    this.region,
    this.poly,
    this.ease = 'linear',
  })  : p = p ?? <String, double>{},
        colors = colors ?? <String, String>{};

  final String type;
  final Map<String, double> p;
  final Map<String, String> colors;

  /// Easing curve name (see [Easing]) reshaping this recipe's phase.
  String ease;

  /// If non-null, this recipe animates only this sub-rectangle as a layer on
  /// top of the otherwise-static sprite.
  IntRect? region;

  /// Optional **freeform outline** (flattened `[x0,y0, x1,y1, …]` in *pixels*)
  /// for `jigglePhysics`: when set, [AnimEngine.warpJiggle] masks to this drawn
  /// shape (inside + a soft edge jiggle) instead of the rectangular [region]'s
  /// ellipse — the "draw around the boobs" lasso. [region] is still the polygon's
  /// bounding box (it drives the motion axes).
  List<double>? poly;

  double n(String k, [double f = 0]) => p[k] ?? f;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type,
        if (p.isNotEmpty) 'p': p,
        if (colors.isNotEmpty) 'colors': colors,
        if (region != null)
          'region': <int>[region!.x, region!.y, region!.w, region!.h],
        if (poly != null && poly!.isNotEmpty) 'poly': poly,
        if (ease != 'linear') 'ease': ease,
      };

  static AnimRecipe fromJson(Map<String, dynamic> j) {
    final List<dynamic>? r = j['region'] as List<dynamic>?;
    final List<dynamic>? pl = j['poly'] as List<dynamic>?;
    return AnimRecipe(
      j['type'] as String,
      ease: j['ease'] as String? ?? 'linear',
      p: (j['p'] as Map?)?.map((Object? k, Object? v) =>
          MapEntry<String, double>(k.toString(), (v as num).toDouble())),
      colors: (j['colors'] as Map?)?.map((Object? k, Object? v) =>
          MapEntry<String, String>(k.toString(), v.toString())),
      region: r == null
          ? null
          : IntRect(r[0] as int, r[1] as int, r[2] as int, r[3] as int),
      poly: pl == null
          ? null
          : <double>[for (final Object? v in pl) (v as num).toDouble()],
    );
  }
}

/// Computes a [FrameSpec] for a recipe at animation phase `t` (0..1).
typedef RecipeFn = FrameSpec Function(double t, AnimRecipe r);

/// The animation generator. Renders standard multi-frame sprites (APNG/GIF) so
/// the output is 100% AO-compatible — the engine never speaks a custom format.
class AnimEngine {
  AnimEngine._();

  static final Map<String, RecipeFn> _registry = <String, RecipeFn>{
    'none': (double t, AnimRecipe r) => FrameSpec(),
    'sway': _sway,
    'bob': _bob,
    'bounce': _bounce,
    'float': _float,
    'breathe': _breathe,
    'blink': _blink,
    'shake': _shake,
    'spin': _spin,
    'tilt': _tilt,
    'wiggle': _wiggle,
    'zoomPulse': _zoomPulse,
    'jump': _jump,
    'glow': _glow,
    'flash': _flash,
    'pulse': _pulse,
    'rainbow': _rainbow,
    'tintPulse': _tintPulse,
    'fadeIn': _fadeIn,
    'fadeOut': _fadeOut,
    'throb': _throb,
    'nod': _nod,
    'headShake': _headShake,
    'swing': _swing,
    'drift': _drift,
    'orbit': _orbit,
    'heartbeat': _heartbeat,
    'strobe': _strobe,
    'flicker': _flicker,
    'neon': _neon,
    'hologram': _hologram,
    'glitch': _glitch,
    'colorCycle': _colorCycle,
    'wave': _wave,
    'pendulum': _pendulum,
    'vibrate': _vibrate,
    'pop': _pop,
    'wobble': _wobble,
    'slideIn': _slideIn,
    'slideOut': _slideOut,
    'squashStretch': _squashStretch,
    'twitch': _twitch,
    'breatheGlow': _breatheGlow,
    'rubberBand': _rubberBand,
    'jelly': _jelly,
    'tada': _tada,
    'rollIn': _rollIn,
    'rollOut': _rollOut,
    'spiralIn': _spiralIn,
    'levitate': _levitate,
    'recoil': _recoil,
    'lunge': _lunge,
    'duck': _duck,
    'sideStep': _sideStep,
    'figure8': _figure8,
    'tiltShake': _tiltShake,
    'zoomBounce': _zoomBounce,
    'fadeBlink': _fadeBlink,
    'desaturatePulse': _desaturatePulse,
    'colorFlash': _colorFlash,
    'ghostFloat': _ghostFloat,
    'rainbowGlow': _rainbowGlow,
    'matrixGlitch': _matrixGlitch,
    'emphasisPop': _emphasisPop,
    'breatheHeavy': _breatheHeavy,
    'sheen': _sheen,
    'anticipate': _anticipate,
    'springIn': _springIn,
    'shiver': _shiver,
    'gallop': _gallop,
    'peek': _peek,
    'dropIn': _dropIn,
    'breatheSway': _breatheSway,
    'pant': _pant,
    'sparkle': _sparkle,
    'chromaPulse': _chromaPulse,
    'outlinePulse': _outlinePulse,
    'auraGlow': _auraGlow,
    'shadowDance': _shadowDance,
    'focusPull': _focusPull,
    'jigglePhysics': _jigglePhysics,
  };

  static List<String> get recipeTypes => _registry.keys.toList()..sort();

  /// Plugin hook: register a new code recipe.
  static void register(String id, RecipeFn fn) => _registry[id] = fn;

  static FrameSpec _spec(double t, AnimRecipe r) {
    final double et = Easing.apply(r.ease, t);
    return (_registry[r.type] ?? _registry['none']!)(et, r);
  }

  /// Evaluate [recipes] (summed) into a single [FrameSpec] at animation phase
  /// [t] (0..1). Public so other engines — e.g. the **puppet** compositor — can
  /// drive their own per-layer transforms through the same recipe library +
  /// easing, instead of re-implementing the motion maths.
  static FrameSpec frameSpec(double t, List<AnimRecipe> recipes) {
    final FrameSpec s = FrameSpec();
    for (final AnimRecipe r in recipes) {
      s.add(_spec(t, r));
    }
    return s;
  }

  /// Public wrapper over the verified per-layer transform-and-composite that
  /// [render] uses, so the puppet compositor can place each part with the same
  /// maths (handles `scaleX`/`scaleY`, rotate, opacity, colour ops; centres the
  /// transformed [src] at `(anchorX+dx, anchorY+dy)` on a `canvasW×canvasH`
  /// transparent canvas).
  static img.Image renderLayer(
    img.Image src,
    FrameSpec spec, {
    required int canvasW,
    required int canvasH,
    required double anchorX,
    required double anchorY,
  }) =>
      _renderLayer(src, spec,
          canvasW: canvasW,
          canvasH: canvasH,
          anchorX: anchorX,
          anchorY: anchorY);

  /// Render [base] into a clip by stacking [recipes].
  ///
  /// [frames] frames are produced over one loop; [fps] sets the playback rate.
  static AnimClip render(
    img.Image base,
    List<AnimRecipe> recipes, {
    int frames = 12,
    int fps = 12,
    bool loop = true,
  }) {
    final img.Image src = base.numChannels == 4 ? base : base.convert(numChannels: 4);
    final int delayCentis = math.max(1, (100 / fps).round());

    final List<AnimRecipe> global =
        recipes.where((AnimRecipe r) => r.region == null).toList();
    // Region recipes split two ways: `jigglePhysics` **warps** its region with a
    // smooth per-pixel displacement field (soft-body flesh — the pixels stretch
    // continuously into the static body, no hard rectangle), while every other
    // region recipe stays on the original rigid crop-and-composite layer path.
    final List<AnimRecipe> rigidRegional = <AnimRecipe>[];
    final List<AnimRecipe> warpRegional = <AnimRecipe>[];
    for (final AnimRecipe r in recipes) {
      if (r.region == null) continue;
      (r.type == 'jigglePhysics' ? warpRegional : rigidRegional).add(r);
    }

    final List<AnimFrame> out = <AnimFrame>[];
    for (int i = 0; i < frames; i++) {
      final double t = frames <= 1 ? 0 : i / frames; // 0..1 (exclusive end => clean loop)

      // Whole-sprite layer.
      final FrameSpec g = FrameSpec();
      for (final AnimRecipe r in global) {
        g.add(_spec(t, r));
      }
      img.Image canvas = _renderLayer(
        src,
        g,
        canvasW: src.width,
        canvasH: src.height,
        anchorX: src.width / 2,
        anchorY: src.height / 2,
      );

      // Rigid region layers on top (e.g. wave a hand).
      for (final AnimRecipe r in rigidRegional) {
        final IntRect reg = r.region!;
        final img.Image piece =
            img.copyCrop(src, x: reg.x, y: reg.y, width: reg.w, height: reg.h);
        final FrameSpec spec = _spec(t, r);
        final img.Image layer = _renderLayer(
          piece,
          spec,
          canvasW: src.width,
          canvasH: src.height,
          anchorX: reg.x + reg.w / 2,
          anchorY: reg.y + reg.h / 2,
        );
        canvas = img.compositeImage(canvas, layer, dstX: 0, dstY: 0);
      }

      // Soft-body jiggle warps — each deforms the running canvas in place.
      for (final AnimRecipe r in warpRegional) {
        canvas = warpJiggle(canvas, r, t);
      }

      out.add(AnimFrame(canvas, delayCentis: delayCentis));
    }
    return AnimClip(out);
  }

  /// Render directly from a per-phase [FrameSpec] function (used by the manual
  /// keyframe [Timeline]). Whole-sprite only.
  static AnimClip renderSpec(
    img.Image base,
    FrameSpec Function(double t) specAt, {
    int frames = 16,
    int fps = 12,
  }) {
    final img.Image src =
        base.numChannels == 4 ? base : base.convert(numChannels: 4);
    final int delayCentis = math.max(1, (100 / fps).round());
    final List<AnimFrame> out = <AnimFrame>[];
    for (int i = 0; i < frames; i++) {
      final double t = frames <= 1 ? 0 : i / frames;
      final img.Image canvas = _renderLayer(
        src,
        specAt(t),
        canvasW: src.width,
        canvasH: src.height,
        anchorX: src.width / 2,
        anchorY: src.height / 2,
      );
      out.add(AnimFrame(canvas, delayCentis: delayCentis));
    }
    return AnimClip(out);
  }

  /// Render one layer ([src]) transformed by [spec] onto a transparent canvas of
  /// [canvasW] x [canvasH], so its center lands at (anchor + dx, anchor + dy).
  static img.Image _renderLayer(
    img.Image src,
    FrameSpec spec, {
    required int canvasW,
    required int canvasH,
    required double anchorX,
    required double anchorY,
  }) {
    img.Image work = src.clone();
    if (spec.colorOps.isNotEmpty) ImageOps.applyAll(work, spec.colorOps);
    if (spec.opacity < 1.0) {
      ImageOps.apply(work, ColorOp('opacity', nums: <String, double>{'amount': spec.opacity}));
    }
    final double sx = spec.scale * spec.scaleX;
    final double sy = spec.scale * spec.scaleY;
    if ((sx != 1.0 || sy != 1.0) && sx > 0 && sy > 0) {
      work = img.copyResize(work,
          width: math.max(1, (work.width * sx).round()),
          height: math.max(1, (work.height * sy).round()),
          interpolation: img.Interpolation.cubic);
    }
    if (spec.angle.abs() > 0.001) {
      work = img.copyRotate(work, angle: spec.angle, interpolation: img.Interpolation.cubic);
    }

    final img.Image canvas = img.Image(width: canvasW, height: canvasH, numChannels: 4);
    final int dstX = (anchorX + spec.dx - work.width / 2).round();
    final int dstY = (anchorY + spec.dy - work.height / 2).round();
    return img.compositeImage(canvas, work, dstX: dstX, dstY: dstY);
  }

  // ---------------------------------------------------------------------------
  // Soft-body jiggle warp
  // ---------------------------------------------------------------------------

  /// Deform the [r].`region` of [src] with a smooth per-pixel **displacement
  /// warp** at animation phase [t] (0..1) — the soft, fleshy "anime / gacha
  /// jiggle" look. Unlike cutting out a rectangle and sliding it (which reads as
  /// a moving cropped PNG), this stretches the pixels that are *already there*:
  /// the displacement is **zero at the influence boundary** so the warped flesh
  /// blends seamlessly into the static body (no hard edges), is largest at the
  /// **free end** of the region while the attachment stays put (the anchored
  /// "hang"), and adds velocity-coupled **squash-&-stretch** plus an optional
  /// lateral **sway**. On a flat sprite there is no data hidden behind the
  /// region, so a continuous warp is the most natural jiggle achievable.
  ///
  /// Params (read from [r], each an independent knob):
  ///  * `amplitude` px — peak travel of the free end.
  ///  * `frequency` — bounces per loop (integer ⇒ seamless loop).
  ///  * `bounciness` 0..1 — overshoot harmonic (the springy rebound).
  ///  * `squash` 0..1 — squash-&-stretch coupled to velocity.
  ///  * `sway` deg — lateral wobble of the free end (rotation-like).
  ///  * `direction` deg — axis the jiggle travels (0 = up/down, 90 = sideways).
  ///  * `phase` 0..1 — phase offset (use opposite phases for twin lobes/boobs).
  ///  * `anchor` 0..1 — where the pinned point sits along the travel axis (0 =
  ///    trailing/top pinned [boobs, default], 1 = leading pinned, 0.5 = centre).
  ///  * `gravity` 0..1 — asymmetric timing: heavier fall, gentler rise.
  ///  * `organic` 0..1 — extra harmonic so the motion isn't a pure sine.
  ///  * `followThrough` 0..1 — the swinging end lags the pin, so the jiggle
  ///    travels through the flesh as a wave (soft-body realism).
  ///  * `crossAmount` 0..1 — perpendicular cross-bounce 90° out of phase ⇒ the
  ///    tip traces an **ellipse** (2D motion), not a straight line.
  ///  * `swirl` deg — a back-and-forth **rotation** of the region about its centre.
  ///  * `pulse` 0..1 — the whole jiggle **swells then fades** once per loop.
  ///    All of these default to 0 ⇒ the original motion, so existing presets are
  ///    unchanged, and they're a few cheap ops each (no real per-pixel cost).
  ///
  /// Pure + isolate-safe (the bulk worker calls this through [render]). Returns a
  /// new image; [src] is never mutated. Sampling is premultiplied bilinear so
  /// transparent edges don't get a dark fringe.
  static img.Image warpJiggle(img.Image src, AnimRecipe r, double t) {
    final IntRect? reg = r.region;
    final img.Image base =
        src.numChannels == 4 ? src : src.convert(numChannels: 4);
    if (reg == null || reg.w <= 0 || reg.h <= 0) return base;
    final int w = base.width, h = base.height;
    if (w == 0 || h == 0) return base;

    final double amp = r.n('amplitude', 6);
    final double freq = r.n('frequency', 2);
    final double bounce = r.n('bounciness', 0.5);
    final double squash = r.n('squash', 0.5);
    final double swayDeg = r.n('sway', 0);
    final double dir = r.n('direction', 0) * math.pi / 180.0;
    final double phase = r.n('phase', 0) * 2 * math.pi;
    // New knobs (all default to reproducing the original motion):
    final double anchorPin = r.n('anchor', 0).clamp(0.0, 1.0); // pinned point 0..1
    final double gravity = r.n('gravity', 0); // asymmetric fall vs rise
    final double organic = r.n('organic', 0); // extra harmonic = less robotic
    final double followThrough = r.n('followThrough', 0); // tip lags base (wave)
    // More "ways" of moving (all 0 by default ⇒ identical to the original):
    final double crossAmt = r.n('crossAmount', 0); // perpendicular bounce (2D ellipse)
    final double swirlDeg = r.n('swirl', 0); // rotational wobble about the centre
    final double pulseAmt = r.n('pulse', 0); // intensity swells/fades over the loop
    final double pinDen = math.max(anchorPin, 1 - anchorPin);

    final double cx = reg.x + reg.w / 2.0;
    final double cy = reg.y + reg.h / 2.0;
    final double hw = math.max(0.5, reg.w / 2.0);
    final double hh = math.max(0.5, reg.h / 2.0);
    const double inf = 1.35; // elliptical influence reaches 1.35x the box radius.

    // Time-varying scalars (hoisted out of the pixel loop).
    final double ww = 2 * math.pi * freq * t + phase;
    // Oscillator (periodic ⇒ seamless loop). `gravity` skews the fall vs the
    // rise (weighty drop, gentle return); `organic` adds a higher harmonic so it
    // isn't a pure robotic sine. The base bounce + overshoot is the spring feel.
    double oscAt(double a) =>
        math.sin(a) +
        bounce * 0.4 * math.sin(2 * a + 0.6) -
        gravity * 0.28 * math.cos(2 * a) +
        organic * 0.22 * math.sin(3 * a + 1.7);
    final double oscBase = oscAt(ww);
    // Follow-through: the swinging end runs an *earlier* phase than the pin, so
    // the jiggle travels through the flesh as a wave (the key "pro animation"
    // tell). Blended per-pixel by `weight`; followThrough 0 ⇒ uniform (original).
    final double oscTip = oscAt(ww - followThrough * 0.7);
    final double velo = math.cos(ww);
    final double str = squash * 0.12 * velo; // squash strain (low ⇒ less smear)
    final double dX = math.sin(dir), dY = math.cos(dir); // travel axis
    final double pX = math.cos(dir), pY = -math.sin(dir); // perpendicular axis
    final double alongMax = math.max(1.0, hw * dX.abs() + hh * dY.abs());
    final double swLat = math.sin(swayDeg * math.pi / 180.0) *
        2 *
        alongMax *
        math.sin(ww + 1.2);
    // (4) cross-bounce: a perpendicular wobble 90° out of phase with the main
    //     bounce, so the tip traces an **ellipse** instead of a straight line —
    //     the natural "boobs move in a little circle" look.
    // (5) swirl: a small **rotation** of the region about its centre.
    // (6) pulse: the whole jiggle **swells and fades** once per loop.
    final double ampEff =
        amp * (1 + pulseAmt * 0.5 * math.sin(2 * math.pi * t));
    final double crossDisp = crossAmt * ampEff * math.cos(ww);
    final double swirlRad = swirlDeg * (math.pi / 180.0) * math.sin(ww);

    // The influence box. A **freeform [poly]** uses the drawn shape's bounds
    // grown by a feather; otherwise the radial influence around the region.
    // Outside it nothing changes — that's what keeps the join with the static
    // body seamless.
    final List<double>? poly = r.poly;
    final bool usePoly = poly != null && poly.length >= 6;
    final double feather =
        math.max(3.0, 0.12 * math.min(reg.w.toDouble(), reg.h.toDouble()));
    final int x0 = usePoly
        ? math.max(0, (reg.x - feather).floor())
        : math.max(0, (cx - hw * inf).floor());
    final int x1 = usePoly
        ? math.min(w - 1, (reg.x + reg.w + feather).ceil())
        : math.min(w - 1, (cx + hw * inf).ceil());
    final int y0 = usePoly
        ? math.max(0, (reg.y - feather).floor())
        : math.max(0, (cy - hh * inf).floor());
    final int y1 = usePoly
        ? math.min(h - 1, (reg.y + reg.h + feather).ceil())
        : math.min(h - 1, (cy + hh * inf).ceil());
    if (x1 < x0 || y1 < y0) return base;
    final int bw = x1 - x0 + 1;
    // Feathered alpha mask over the bbox for the drawn shape (full inside, soft
    // just outside) — built once per clip and reused across its frames.
    final Uint8List? polyMask =
        usePoly ? _jigglePolyMask(poly, x0, y0, bw, y1 - y0 + 1, feather) : null;

    final Uint8List sp = base.getBytes(order: img.ChannelOrder.rgba);
    final img.Image dst = base.clone();

    for (int y = y0; y <= y1; y++) {
      final double oy = y - cy;
      if (!usePoly && (oy / hh).abs() >= inf) {
        continue; // outside the ellipse for every x in this row
      }
      for (int x = x0; x <= x1; x++) {
        final double ox = x - cx;
        final double m;
        if (usePoly) {
          m = polyMask![(y - y0) * bw + (x - x0)] / 255.0;
        } else {
          // **Elliptical (radial) falloff** — no rectangular edge (the "blocky"
          // fix): full motion inside the breast ellipse, feathering into the
          // surrounding body so there's no visible box.
          final double rx = ox / hw, ry = oy / hh;
          m = 1.0 - _smoothstep(1.0, inf, math.sqrt(rx * rx + ry * ry));
        }
        if (m <= 0) continue;
        final double along = ox * dX + oy * dY;
        final double perp = ox * pX + oy * pY;
        // Position along the travel axis, 0 = trailing edge … 1 = leading edge.
        final double s = ((along / alongMax) + 1) * 0.5;
        // Distance from the pinned point (`anchor`): the pin barely moves, the
        // far end swings most. anchor 0 = trailing pinned (boobs/top, default),
        // 1 = leading pinned, 0.5 = centre pinned (both ends free).
        final double weight =
            (pinDen <= 0 ? 1.0 : (s - anchorPin).abs() / pinDen).clamp(0.0, 1.0);
        // Per-pixel oscillator: the tip lags the pin (follow-through wave).
        final double osc = oscBase + (oscTip - oscBase) * weight;
        // (1) bounce: **mostly a uniform translation** of the mass (crisp — a
        // steep per-pixel gradient is what smears the art) with only a gentle
        // anchored lean so the swinging end still leads a little.
        final double bAmt = ampEff * osc * (0.7 + 0.3 * weight);
        final double crossW = crossDisp * weight; // perp bounce (2D ellipse)
        final double swirlW = swirlRad * weight; // rotation (tangential)
        // (1) bounce + (2) squash/stretch + (3) sway + (4) cross + (5) swirl.
        final double dispX = (dX * bAmt +
                dX * (along * str) +
                pX * (perp * -0.5 * str) +
                pX * (swLat * weight) +
                pX * crossW -
                oy * swirlW) *
            m;
        final double dispY = (dY * bAmt +
                dY * (along * str) +
                pY * (perp * -0.5 * str) +
                pY * (swLat * weight) +
                pY * crossW +
                ox * swirlW) *
            m;
        // Inverse map: this destination pixel pulls from (x,y) - disp.
        double sx = x - dispX;
        double sy = y - dispY;
        if (sx < 0) {
          sx = 0;
        } else if (sx > w - 1) {
          sx = (w - 1).toDouble();
        }
        if (sy < 0) {
          sy = 0;
        } else if (sy > h - 1) {
          sy = (h - 1).toDouble();
        }
        final int xi = sx.floor();
        final int yi = sy.floor();
        final int xi1 = xi + 1 < w ? xi + 1 : xi;
        final int yi1 = yi + 1 < h ? yi + 1 : yi;
        final double fx = sx - xi;
        final double fy = sy - yi;
        final int i00 = (yi * w + xi) * 4;
        final int i10 = (yi * w + xi1) * 4;
        final int i01 = (yi1 * w + xi) * 4;
        final int i11 = (yi1 * w + xi1) * 4;
        final double a00 = sp[i00 + 3].toDouble();
        final double a10 = sp[i10 + 3].toDouble();
        final double a01 = sp[i01 + 3].toDouble();
        final double a11 = sp[i11 + 3].toDouble();
        final double aI = _bilerp(a00, a10, a01, a11, fx, fy);
        if (aI <= 0.5) {
          dst.setPixelRgba(x, y, 0, 0, 0, 0);
          continue;
        }
        // Premultiplied bilinear: interpolate colour*alpha, then divide back.
        final double rPm = _bilerp(sp[i00] * a00, sp[i10] * a10, sp[i01] * a01,
            sp[i11] * a11, fx, fy);
        final double gPm = _bilerp(sp[i00 + 1] * a00, sp[i10 + 1] * a10,
            sp[i01 + 1] * a01, sp[i11 + 1] * a11, fx, fy);
        final double bPm = _bilerp(sp[i00 + 2] * a00, sp[i10 + 2] * a10,
            sp[i01 + 2] * a01, sp[i11 + 2] * a11, fx, fy);
        dst.setPixelRgba(
          x,
          y,
          (rPm / aI).round().clamp(0, 255),
          (gPm / aI).round().clamp(0, 255),
          (bPm / aI).round().clamp(0, 255),
          aI.round().clamp(0, 255),
        );
      }
    }
    return dst;
  }

  // Size-1 cache so a freeform mask is built **once per clip** (its geometry is
  // constant across frames), not per frame. Per-isolate statics are fine — render
  // bakes all of a clip's frames in one isolate before moving on.
  static List<double>? _pmPoly;
  static int _pmX0 = 0, _pmY0 = 0, _pmW = 0, _pmH = 0;
  static Uint8List? _pmMask;

  /// Feathered alpha mask (0..255) over a [bw]×[bh] window at ([x0],[y0]) for the
  /// pixel-space polygon [poly]: 255 inside the drawn shape, falling to 0 across
  /// [feather] px just outside it (so the warp blends into the body — no hard
  /// edge). Cached by polygon identity + window.
  static Uint8List _jigglePolyMask(
      List<double> poly, int x0, int y0, int bw, int bh, double feather) {
    if (identical(poly, _pmPoly) &&
        x0 == _pmX0 &&
        y0 == _pmY0 &&
        bw == _pmW &&
        bh == _pmH &&
        _pmMask != null) {
      return _pmMask!;
    }
    final Uint8List buf = Uint8List(bw * bh);
    final int n = poly.length ~/ 2;
    for (int ly = 0; ly < bh; ly++) {
      final double py = (y0 + ly) + 0.5;
      for (int lx = 0; lx < bw; lx++) {
        final double px = (x0 + lx) + 0.5;
        if (_pointInPoly(poly, n, px, py)) {
          buf[ly * bw + lx] = 255;
        } else {
          final double d = _distToPoly(poly, n, px, py);
          if (d < feather) {
            buf[ly * bw + lx] =
                ((1.0 - _smoothstep(0, feather, d)) * 255).round().clamp(0, 255);
          }
        }
      }
    }
    _pmPoly = poly;
    _pmX0 = x0;
    _pmY0 = y0;
    _pmW = bw;
    _pmH = bh;
    _pmMask = buf;
    return buf;
  }

  /// Even-odd point-in-polygon test ([poly] = flattened px x,y pairs, [n] verts).
  static bool _pointInPoly(List<double> poly, int n, double x, double y) {
    bool inside = false;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final double yi = poly[i * 2 + 1], yj = poly[j * 2 + 1];
      if ((yi > y) != (yj > y)) {
        final double xi = poly[i * 2], xj = poly[j * 2];
        if (x < (xj - xi) * (y - yi) / (yj - yi) + xi) inside = !inside;
      }
    }
    return inside;
  }

  /// Minimum distance from (x,y) to any of the polygon's edges.
  static double _distToPoly(List<double> poly, int n, double x, double y) {
    double best = double.infinity;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final double d = _distToSeg(
          x, y, poly[j * 2], poly[j * 2 + 1], poly[i * 2], poly[i * 2 + 1]);
      if (d < best) best = d;
    }
    return best;
  }

  static double _distToSeg(
      double px, double py, double ax, double ay, double bx, double by) {
    final double dx = bx - ax, dy = by - ay;
    final double len2 = dx * dx + dy * dy;
    double t = len2 <= 0 ? 0 : ((px - ax) * dx + (py - ay) * dy) / len2;
    if (t < 0) {
      t = 0;
    } else if (t > 1) {
      t = 1;
    }
    final double ex = px - (ax + t * dx), ey = py - (ay + t * dy);
    return math.sqrt(ex * ex + ey * ey);
  }

  /// Bilinear blend of four corner values.
  static double _bilerp(double c00, double c10, double c01, double c11,
      double fx, double fy) {
    final double top = c00 + (c10 - c00) * fx;
    final double bot = c01 + (c11 - c01) * fx;
    return top + (bot - top) * fy;
  }

  /// Hermite smoothstep: 0 below [edge0], 1 above [edge1], eased between.
  static double _smoothstep(double edge0, double edge1, double x) {
    if (edge0 == edge1) return x < edge0 ? 0.0 : 1.0;
    double t = (x - edge0) / (edge1 - edge0);
    if (t < 0) {
      t = 0;
    } else if (t > 1) {
      t = 1;
    }
    return t * t * (3 - 2 * t);
  }

  // ---------------------------------------------------------------------------
  // Built-in recipes. `intensity` and `cycles` are the common knobs; all are
  // smooth and loop seamlessly (phase t is exclusive of 1.0).
  // ---------------------------------------------------------------------------

  static double _tau(double t, double cycles) => 2 * math.pi * t * cycles;

  static FrameSpec _sway(double t, AnimRecipe r) => FrameSpec()
    ..angle = r.n('intensity', 6) * math.sin(_tau(t, r.n('cycles', 1)));

  static FrameSpec _bob(double t, AnimRecipe r) => FrameSpec()
    ..dy = r.n('intensity', 6) * math.sin(_tau(t, r.n('cycles', 1)));

  static FrameSpec _bounce(double t, AnimRecipe r) => FrameSpec()
    ..dy = -r.n('intensity', 12) * math.sin(_tau(t, r.n('cycles', 1))).abs();

  static FrameSpec _float(double t, AnimRecipe r) => FrameSpec()
    ..dy = r.n('intensity', 4) * math.sin(_tau(t, r.n('cycles', 1)))
    ..dx = r.n('drift', 2) * math.cos(_tau(t, r.n('cycles', 1)));

  static FrameSpec _breathe(double t, AnimRecipe r) => FrameSpec()
    ..scale = 1 + r.n('intensity', 3) / 100.0 * (0.5 + 0.5 * math.sin(_tau(t, r.n('cycles', 1))));

  /// A quick eye-blink: the layer squashes vertically (scaleY dips toward
  /// `1-depth`) for a brief window, [count] times per loop, fully open the rest
  /// of the time. Pair with a centre/eye pivot. Seamless when [count] is an
  /// integer (scaleY == 1 at t==0 and t==1). Used by the **puppet** eyes layer.
  static FrameSpec _blink(double t, AnimRecipe r) {
    final double count = math.max(1, r.n('count', 1));
    final double width = r.n('width', 0.10).clamp(0.02, 0.5); // closed fraction
    final double depth = r.n('depth', 0.9).clamp(0.0, 1.0); // 1 = shut fully
    final double local = (t * count) % 1.0; // 0..1 within one blink cycle
    double sy = 1.0;
    if (local > 1 - width) {
      final double bp = (local - (1 - width)) / width; // 0..1 across the blink
      sy = 1.0 - depth * math.sin(math.pi * bp); // 1 → (1-depth) → 1
    }
    return FrameSpec()..scaleY = sy;
  }

  static FrameSpec _shake(double t, AnimRecipe r) {
    final double i = r.n('intensity', 4);
    final double c = r.n('cycles', 6);
    return FrameSpec()
      ..dx = i * math.sin(_tau(t, c))
      ..dy = i * 0.6 * math.sin(_tau(t, c * 1.7) + 1.3);
  }

  static FrameSpec _spin(double t, AnimRecipe r) =>
      FrameSpec()..angle = 360.0 * r.n('cycles', 1) * t;

  static FrameSpec _tilt(double t, AnimRecipe r) => FrameSpec()
    ..angle = r.n('intensity', 10) * math.sin(_tau(t, r.n('cycles', 1)));

  static FrameSpec _wiggle(double t, AnimRecipe r) => FrameSpec()
    ..angle = r.n('intensity', 5) * math.sin(_tau(t, r.n('cycles', 3)));

  static FrameSpec _zoomPulse(double t, AnimRecipe r) => FrameSpec()
    ..scale = 1 + r.n('intensity', 8) / 100.0 * (0.5 + 0.5 * math.sin(_tau(t, r.n('cycles', 1))));

  static FrameSpec _jump(double t, AnimRecipe r) {
    // Parabolic hop within the loop.
    final double h = r.n('intensity', 20);
    final double x = (t * 2 - 1); // -1..1
    return FrameSpec()..dy = -h * (1 - x * x);
  }

  static FrameSpec _glow(double t, AnimRecipe r) {
    final double amt = (0.5 + 0.5 * math.sin(_tau(t, r.n('cycles', 1)))) * r.n('intensity', 0.6);
    return FrameSpec()
      ..colorOps.add(ColorOp('tint',
          nums: <String, double>{'amount': amt},
          strs: <String, String>{'color': r.colors['color'] ?? '#FFFFE08A'}))
      ..colorOps.add(ColorOp('brightness', nums: <String, double>{'amount': 1 + 0.3 * amt}));
  }

  static FrameSpec _flash(double t, AnimRecipe r) {
    final double spike = math.pow(0.5 + 0.5 * math.sin(_tau(t, r.n('cycles', 1))), 6).toDouble();
    return FrameSpec()
      ..colorOps.add(ColorOp('brightness', nums: <String, double>{'amount': 1 + r.n('intensity', 1.2) * spike}));
  }

  static FrameSpec _pulse(double t, AnimRecipe r) => FrameSpec()
    ..opacity = (1 - r.n('intensity', 0.5) * (0.5 + 0.5 * math.sin(_tau(t, r.n('cycles', 1)))))
        .clamp(0.0, 1.0);

  static FrameSpec _rainbow(double t, AnimRecipe r) => FrameSpec()
    ..colorOps.add(ColorOp('hueShift',
        nums: <String, double>{'degrees': 360.0 * r.n('cycles', 1) * t}));

  static FrameSpec _tintPulse(double t, AnimRecipe r) {
    final double amt = (0.5 + 0.5 * math.sin(_tau(t, r.n('cycles', 1)))) * r.n('intensity', 0.5);
    return FrameSpec()
      ..colorOps.add(ColorOp('tint',
          nums: <String, double>{'amount': amt},
          strs: <String, String>{'color': r.colors['color'] ?? '#FFFF5577'}));
  }

  static FrameSpec _fadeIn(double t, AnimRecipe r) => FrameSpec()..opacity = t;
  static FrameSpec _fadeOut(double t, AnimRecipe r) => FrameSpec()..opacity = 1 - t;

  static FrameSpec _throb(double t, AnimRecipe r) {
    final FrameSpec s = _zoomPulse(t, r);
    s.add(_glow(t, r));
    return s;
  }

  static FrameSpec _nod(double t, AnimRecipe r) => FrameSpec()
    ..dy = r.n('intensity', 5) * math.sin(_tau(t, r.n('cycles', 1)))
    ..angle = r.n('intensity', 5) * 0.4 * math.sin(_tau(t, r.n('cycles', 1)));

  static FrameSpec _headShake(double t, AnimRecipe r) => FrameSpec()
    ..dx = r.n('intensity', 6) * math.sin(_tau(t, r.n('cycles', 2)))
    ..angle = r.n('intensity', 6) * 0.3 * math.sin(_tau(t, r.n('cycles', 2)));

  static FrameSpec _swing(double t, AnimRecipe r) => FrameSpec()
    ..angle = r.n('intensity', 12) * math.sin(_tau(t, r.n('cycles', 1)))
    ..dx = r.n('intensity', 12) * 0.5 * math.sin(_tau(t, r.n('cycles', 1)));

  static FrameSpec _drift(double t, AnimRecipe r) => FrameSpec()
    ..dx = r.n('intensity', 8) * math.sin(_tau(t, r.n('cycles', 1)))
    ..dy = r.n('intensity', 8) * 0.3 * math.cos(_tau(t, r.n('cycles', 1)));

  static FrameSpec _orbit(double t, AnimRecipe r) {
    final double rad = r.n('intensity', 8);
    return FrameSpec()
      ..dx = rad * math.cos(_tau(t, r.n('cycles', 1)))
      ..dy = rad * math.sin(_tau(t, r.n('cycles', 1)));
  }

  static FrameSpec _heartbeat(double t, AnimRecipe r) {
    // Two quick bumps per cycle.
    final double base = math.sin(_tau(t, r.n('cycles', 1)));
    final double bump = math.max(0, base).toDouble() +
        0.6 * math.max(0, math.sin(_tau(t, r.n('cycles', 1)) - 0.9)).toDouble();
    return FrameSpec()..scale = 1 + r.n('intensity', 6) / 100.0 * bump;
  }

  static FrameSpec _strobe(double t, AnimRecipe r) {
    final int step = (t * r.n('cycles', 6) * 2).floor();
    return FrameSpec()..opacity = step.isEven ? 1.0 : (1 - r.n('intensity', 1)).clamp(0.0, 1.0);
  }

  static FrameSpec _flicker(double t, AnimRecipe r) {
    final double noise = (math.sin(t * 97.13) * 43758.5453);
    final double f = (noise - noise.floorToDouble());
    return FrameSpec()..opacity = (1 - r.n('intensity', 0.3) * f).clamp(0.0, 1.0);
  }

  static FrameSpec _neon(double t, AnimRecipe r) {
    final FrameSpec s = _glow(t, r);
    s.colorOps.add(ColorOp('saturation', nums: <String, double>{'amount': 1.4}));
    return s;
  }

  static FrameSpec _hologram(double t, AnimRecipe r) {
    final FrameSpec s = FrameSpec()
      ..opacity = 0.7
      ..dx = r.n('intensity', 2) * math.sin(_tau(t, r.n('cycles', 8)));
    s.colorOps.add(ColorOp('tint',
        nums: <String, double>{'amount': 0.35},
        strs: <String, String>{'color': r.colors['color'] ?? '#FF66E0FF'}));
    return s;
  }

  static FrameSpec _glitch(double t, AnimRecipe r) {
    final int step = (t * r.n('cycles', 10)).floor();
    final double j = ((step * 2654435761) % 1000) / 1000.0 - 0.5;
    final FrameSpec s = FrameSpec()..dx = r.n('intensity', 6) * j * 2;
    if (step.isOdd) {
      s.colorOps.add(ColorOp('channelSwap', strs: <String, String>{'order': 'gbr'}));
    }
    return s;
  }

  static FrameSpec _colorCycle(double t, AnimRecipe r) => FrameSpec()
    ..colorOps.add(ColorOp('hueShift',
        nums: <String, double>{'degrees': 360.0 * r.n('cycles', 1) * t}));

  static FrameSpec _wave(double t, AnimRecipe r) {
    final double c = r.n('cycles', 2);
    return FrameSpec()
      ..dx = r.n('intensity', 5) * math.sin(_tau(t, c))
      ..angle = r.n('intensity', 5) * 0.5 * math.sin(_tau(t, c) + 0.6);
  }

  static FrameSpec _pendulum(double t, AnimRecipe r) =>
      FrameSpec()..angle = r.n('intensity', 16) * math.sin(_tau(t, r.n('cycles', 1)));

  static FrameSpec _vibrate(double t, AnimRecipe r) {
    final double i = r.n('intensity', 2);
    return FrameSpec()
      ..dx = i * math.sin(_tau(t, r.n('cycles', 20)))
      ..dy = i * math.cos(_tau(t, r.n('cycles', 23)));
  }

  static FrameSpec _pop(double t, AnimRecipe r) =>
      FrameSpec()..scale = 1 + r.n('intensity', 12) / 100.0 * math.sin(math.pi * t);

  static FrameSpec _wobble(double t, AnimRecipe r) {
    final double i = r.n('intensity', 8);
    return FrameSpec()
      ..angle = i * math.sin(_tau(t, r.n('cycles', 2)))
      ..scale = 1 + i / 200.0 * math.sin(_tau(t, r.n('cycles', 2) * 2));
  }

  static FrameSpec _slideIn(double t, AnimRecipe r) =>
      FrameSpec()..dx = -r.n('intensity', 40) * (1 - t);

  static FrameSpec _slideOut(double t, AnimRecipe r) =>
      FrameSpec()..dx = r.n('intensity', 40) * t;

  /// Volume-preserving squash & stretch (uses the non-uniform scale channels).
  static FrameSpec _squashStretch(double t, AnimRecipe r) {
    final double a = r.n('intensity', 12) / 100.0 * math.sin(_tau(t, r.n('cycles', 1)));
    return FrameSpec()
      ..scaleX = 1 - a
      ..scaleY = 1 + a;
  }

  static FrameSpec _twitch(double t, AnimRecipe r) {
    final double trigger = math.sin(_tau(t, r.n('cycles', 6)));
    final double i = r.n('intensity', 6);
    return FrameSpec()
      ..dx = trigger > 0.85 ? i : 0
      ..angle = trigger > 0.85 ? i * 0.5 : 0;
  }

  static FrameSpec _breatheGlow(double t, AnimRecipe r) {
    final FrameSpec s = _breathe(t, r);
    s.add(_glow(t, r));
    return s;
  }

  static FrameSpec _rubberBand(double t, AnimRecipe r) {
    final double a = r.n('intensity', 12) / 100.0 * math.sin(_tau(t, r.n('cycles', 1)));
    return FrameSpec()
      ..scaleX = 1 + a
      ..scaleY = 1 - a;
  }

  static FrameSpec _jelly(double t, AnimRecipe r) {
    final double c = r.n('cycles', 2);
    final double a = r.n('intensity', 10) / 100.0;
    return FrameSpec()
      ..scaleX = 1 + a * math.sin(_tau(t, c))
      ..scaleY = 1 + a * math.sin(_tau(t, c) + math.pi / 2)
      ..angle = r.n('intensity', 10) * 0.2 * math.sin(_tau(t, c));
  }

  static FrameSpec _tada(double t, AnimRecipe r) {
    final double s = 1 + r.n('intensity', 10) / 100.0 * (0.5 + 0.5 * math.sin(_tau(t, r.n('cycles', 1))));
    return FrameSpec()
      ..scale = s
      ..angle = r.n('intensity', 10) * 0.5 * math.sin(_tau(t, r.n('cycles', 3)));
  }

  static FrameSpec _rollIn(double t, AnimRecipe r) => FrameSpec()
    ..dx = -r.n('intensity', 40) * (1 - t)
    ..angle = -180.0 * (1 - t);

  static FrameSpec _rollOut(double t, AnimRecipe r) => FrameSpec()
    ..dx = r.n('intensity', 40) * t
    ..angle = 180.0 * t;

  static FrameSpec _spiralIn(double t, AnimRecipe r) => FrameSpec()
    ..scale = t.clamp(0.05, 1).toDouble()
    ..angle = 360.0 * r.n('cycles', 1) * (1 - t)
    ..opacity = t;

  static FrameSpec _levitate(double t, AnimRecipe r) {
    final double phase = _tau(t, r.n('cycles', 1));
    return FrameSpec()
      ..dy = r.n('intensity', 6) * math.sin(phase)
      ..scale = 1 + r.n('intensity', 6) / 400.0 * math.sin(phase);
  }

  static FrameSpec _recoil(double t, AnimRecipe r) {
    // Quick knock back near the start of the loop, then settle.
    final double hit = math.max(0, math.sin(math.pi * (1 - t))).toDouble();
    return FrameSpec()..dx = -r.n('intensity', 14) * hit * hit;
  }

  static FrameSpec _lunge(double t, AnimRecipe r) =>
      FrameSpec()..dx = r.n('intensity', 14) * math.sin(_tau(t, r.n('cycles', 1)));

  static FrameSpec _duck(double t, AnimRecipe r) {
    final double d = (0.5 - 0.5 * math.cos(_tau(t, r.n('cycles', 1))));
    return FrameSpec()
      ..dy = r.n('intensity', 12) * d
      ..scaleY = 1 - 0.12 * d;
  }

  static FrameSpec _sideStep(double t, AnimRecipe r) =>
      FrameSpec()..dx = r.n('intensity', 8) * math.sin(_tau(t, r.n('cycles', 1))).sign;

  static FrameSpec _figure8(double t, AnimRecipe r) {
    final double rad = r.n('intensity', 8);
    return FrameSpec()
      ..dx = rad * math.sin(_tau(t, r.n('cycles', 1)))
      ..dy = rad * 0.5 * math.sin(_tau(t, r.n('cycles', 2)));
  }

  static FrameSpec _tiltShake(double t, AnimRecipe r) => FrameSpec()
    ..angle = r.n('intensity', 6) * math.sin(_tau(t, r.n('cycles', 10)));

  static FrameSpec _zoomBounce(double t, AnimRecipe r) => FrameSpec()
    ..scale = 1 + r.n('intensity', 10) / 100.0 * math.sin(_tau(t, r.n('cycles', 1))).abs();

  static FrameSpec _fadeBlink(double t, AnimRecipe r) {
    final int step = (t * r.n('cycles', 4) * 2).floor();
    return FrameSpec()..opacity = step.isEven ? 1.0 : (1 - r.n('intensity', 0.8)).clamp(0.0, 1.0);
  }

  static FrameSpec _desaturatePulse(double t, AnimRecipe r) {
    final double amt = 0.5 + 0.5 * math.sin(_tau(t, r.n('cycles', 1)));
    return FrameSpec()
      ..colorOps.add(ColorOp('saturation',
          nums: <String, double>{'amount': (1 - r.n('intensity', 0.8) * amt).clamp(0.0, 1.0)}));
  }

  static FrameSpec _colorFlash(double t, AnimRecipe r) {
    final double amt = math.pow(0.5 + 0.5 * math.sin(_tau(t, r.n('cycles', 1))), 4).toDouble();
    return FrameSpec()
      ..colorOps.add(ColorOp('tint',
          nums: <String, double>{'amount': r.n('intensity', 0.6) * amt},
          strs: <String, String>{'color': r.colors['color'] ?? '#FFFFFFFF'}));
  }

  static FrameSpec _ghostFloat(double t, AnimRecipe r) {
    final double phase = _tau(t, r.n('cycles', 1));
    final FrameSpec s = FrameSpec()
      ..dy = r.n('intensity', 5) * math.sin(phase)
      ..opacity = 0.75 + 0.2 * math.sin(phase);
    s.colorOps.add(ColorOp('tint',
        nums: <String, double>{'amount': 0.25},
        strs: <String, String>{'color': r.colors['color'] ?? '#FFAEEAFF'}));
    return s;
  }

  static FrameSpec _rainbowGlow(double t, AnimRecipe r) {
    final FrameSpec s = _rainbow(t, r);
    s.add(_glow(t, r));
    return s;
  }

  static FrameSpec _matrixGlitch(double t, AnimRecipe r) {
    final FrameSpec s = _glitch(t, r);
    s.colorOps.add(ColorOp('tint',
        nums: <String, double>{'amount': 0.35},
        strs: <String, String>{'color': r.colors['color'] ?? '#FF35FF6A'}));
    return s;
  }

  static FrameSpec _emphasisPop(double t, AnimRecipe r) {
    final FrameSpec s = _pop(t, r);
    s.add(_glow(t, r));
    return s;
  }

  static FrameSpec _breatheHeavy(double t, AnimRecipe r) => FrameSpec()
    ..scale = 1 + r.n('intensity', 8) / 100.0 * (0.5 + 0.5 * math.sin(_tau(t, r.n('cycles', 1))))
    ..dy = r.n('intensity', 8) * 0.2 * math.sin(_tau(t, r.n('cycles', 1)));

  static FrameSpec _sheen(double t, AnimRecipe r) {
    // A brightness sweep that passes through, like a light glint.
    final double g = math.exp(-math.pow((t - 0.5) * 6, 2)).toDouble();
    return FrameSpec()
      ..colorOps.add(ColorOp('brightness',
          nums: <String, double>{'amount': 1 + r.n('intensity', 0.8) * g}));
  }

  // --- newer motion recipes ---

  /// Wind back, then thrust forward — classic anticipation (one loop).
  static FrameSpec _anticipate(double t, AnimRecipe r) {
    final double i = r.n('intensity', 16);
    final double x = t < 0.4 ? -i * (t / 0.4) : i * (1 - (t - 0.4) / 0.6);
    return FrameSpec()..dx = x;
  }

  /// Damped springy scale jiggle that settles to rest.
  static FrameSpec _springIn(double t, AnimRecipe r) {
    final double amp = r.n('intensity', 30) / 100.0;
    final double s = 1 + amp * math.exp(-5.0 * t) * math.sin(_tau(t, r.n('cycles', 2)));
    return FrameSpec()..scale = s.clamp(0.1, 3).toDouble();
  }

  /// Tiny fast tremor with a hint of rotation (cold / scared / tense).
  static FrameSpec _shiver(double t, AnimRecipe r) {
    final double i = r.n('intensity', 2);
    final double c = r.n('cycles', 24);
    return FrameSpec()
      ..dx = i * math.sin(_tau(t, c))
      ..dy = i * 0.5 * math.sin(_tau(t, c * 1.3) + 0.7)
      ..angle = i * 0.4 * math.sin(_tau(t, c * 0.9));
  }

  /// A galloping hop with a forward-back lean.
  static FrameSpec _gallop(double t, AnimRecipe r) {
    final double i = r.n('intensity', 8);
    final double c = r.n('cycles', 2);
    return FrameSpec()
      ..dy = -i * math.sin(_tau(t, c)).abs()
      ..angle = i * 0.5 * math.sin(_tau(t, c));
  }

  /// Slide in from a side, hold, then slide back out (`side` < 0 = from left).
  static FrameSpec _peek(double t, AnimRecipe r) {
    final double dist = r.n('intensity', 40);
    final double side = r.n('side', -1) < 0 ? -1.0 : 1.0;
    final double off = t < 0.25
        ? (1 - t / 0.25)
        : t > 0.75
            ? (t - 0.75) / 0.25
            : 0.0;
    return FrameSpec()..dx = side * dist * off;
  }

  /// Fall in from above and settle with a small bounce (one loop).
  static FrameSpec _dropIn(double t, AnimRecipe r) {
    final double h = r.n('intensity', 40);
    final double y = t < 0.6
        ? -h * (1 - t / 0.6)
        : -h * 0.12 * math.sin(math.pi * (t - 0.6) / 0.4) * (1 - (t - 0.6) / 0.4);
    return FrameSpec()..dy = y;
  }

  /// Gentle idle: a slow breathe blended with a slow sway.
  static FrameSpec _breatheSway(double t, AnimRecipe r) {
    final double i = r.n('intensity', 3);
    final double c = r.n('cycles', 1);
    return FrameSpec()
      ..scale = 1 + i / 100.0 * (0.5 + 0.5 * math.sin(_tau(t, c)))
      ..angle = i * 0.8 * math.sin(_tau(t, c) + 0.5);
  }

  /// Fast, shallow panting (out-of-breath).
  static FrameSpec _pant(double t, AnimRecipe r) {
    final double i = r.n('intensity', 5);
    final double c = r.n('cycles', 4);
    return FrameSpec()
      ..scaleY = 1 + i / 200.0 * (0.5 + 0.5 * math.sin(_tau(t, c)))
      ..dy = i * 0.2 * math.sin(_tau(t, c));
  }

  /// Quick white twinkles (high-frequency soft flashes).
  static FrameSpec _sparkle(double t, AnimRecipe r) {
    final double s = math.pow(0.5 + 0.5 * math.sin(_tau(t, r.n('cycles', 8))), 8).toDouble();
    return FrameSpec()
      ..colorOps.add(ColorOp('brightness',
          nums: <String, double>{'amount': 1 + r.n('intensity', 0.8) * s}));
  }

  /// Pulsing chromatic aberration (uses the `chromaShift` colour op).
  static FrameSpec _chromaPulse(double t, AnimRecipe r) {
    final double off =
        (r.n('intensity', 4) * (0.5 + 0.5 * math.sin(_tau(t, r.n('cycles', 2))))).abs();
    return FrameSpec()
      ..colorOps.add(ColorOp('chromaShift',
          nums: <String, double>{'offset': off.roundToDouble()}));
  }

  /// A coloured outline that pulses in thickness (uses the `outline` colour op).
  static FrameSpec _outlinePulse(double t, AnimRecipe r) {
    final double w = 1 + r.n('intensity', 3) * (0.5 + 0.5 * math.sin(_tau(t, r.n('cycles', 1))));
    return FrameSpec()
      ..colorOps.add(ColorOp('outline',
          nums: <String, double>{'size': w.roundToDouble(), 'threshold': 128},
          strs: <String, String>{'color': r.colors['color'] ?? '#FFFFFFFF'}));
  }

  /// A soft outer glow that breathes in and out (uses the `glow` colour op).
  static FrameSpec _auraGlow(double t, AnimRecipe r) {
    final double k = 0.5 + 0.5 * math.sin(_tau(t, r.n('cycles', 1)));
    return FrameSpec()
      ..colorOps.add(ColorOp('glow',
          nums: <String, double>{
            'radius': r.n('intensity', 6),
            'strength': 0.4 + 0.8 * k,
            'threshold': 16,
          },
          strs: <String, String>{'color': r.colors['color'] ?? '#FF8AD0FF'}));
  }

  /// A hop with a shifting drop shadow underneath (uses the `dropShadow` op).
  static FrameSpec _shadowDance(double t, AnimRecipe r) {
    final double phase = _tau(t, r.n('cycles', 1));
    final double i = r.n('intensity', 6);
    final double dy = -i * math.sin(phase).abs();
    final double sx = 3 + i * 0.5 * math.sin(phase);
    return FrameSpec()
      ..dy = dy
      ..colorOps.add(ColorOp('dropShadow', nums: <String, double>{
        'dx': sx.roundToDouble(),
        'dy': (6 - dy * 0.3).roundToDouble(),
        'opacity': 0.45,
        'threshold': 16,
      }));
  }

  /// A subtle zoom with a sharpen pulse — like a rack focus (uses `sharpen`).
  static FrameSpec _focusPull(double t, AnimRecipe r) {
    final double k = 0.5 + 0.5 * math.sin(_tau(t, r.n('cycles', 1)));
    return FrameSpec()
      ..scale = 1 + r.n('intensity', 4) / 100.0 * k
      ..colorOps.add(ColorOp('sharpen', nums: <String, double>{'amount': 0.4 + 1.2 * k}));
  }

  /// **Jiggle physics** — a looping oscillation tuned to *feel* springy (it is
  /// not an impulse/settle simulation; a true damped spring wouldn't loop). Drive
  /// it on a `region` (a chest/body box) to get bounce. Params (all read from
  /// `p`):
  ///  * `amplitude` — peak travel **in pixels** of the rendered image (the
  ///    `JiggleSpec` derives this from a fraction × image height, so preview and
  ///    full-res bake match).
  ///  * `frequency` — bounces per loop (keep integer so it loops seamlessly).
  ///  * `bounciness` 0..1 — weight of a 2× overshoot harmonic (the "spring" feel).
  ///  * `squash` 0..1 — squash-&-stretch coupled to velocity.
  ///  * `sway` — rotation degrees (a sideways wobble).
  ///  * `direction` — the **angle** (degrees) the bounce travels along: 0 = up/
  ///    down (default), 90 = left/right, anything in between = diagonal.
  ///  * `phase` 0..1 — offset, so two regions can bounce out of sync.
  static FrameSpec _jigglePhysics(double t, AnimRecipe r) {
    final double amp = r.n('amplitude', 6);
    final double freq = r.n('frequency', 2);
    final double bounce = r.n('bounciness', 0.5);
    final double squash = r.n('squash', 0.5);
    final double sway = r.n('sway', 0);
    final double phase = r.n('phase', 0) * 2 * math.pi;
    final double dir = r.n('direction', 0) * math.pi / 180.0;
    final double w = 2 * math.pi * freq * t + phase;
    // Base sine + a higher harmonic (the overshoot) = the springy "jiggle".
    final double osc = math.sin(w) + bounce * 0.45 * math.sin(2 * w + 0.5);
    final FrameSpec s = FrameSpec()
      // Travel along the chosen direction (0° = vertical, 90° = horizontal).
      ..dx = amp * osc * math.sin(dir)
      ..dy = amp * osc * math.cos(dir);
    // Squash & stretch with velocity: tallest as it whips through the middle.
    final double sq = squash * 0.16 * math.cos(w);
    s.scaleY = 1 + sq;
    s.scaleX = 1 - sq * 0.6;
    if (sway != 0) s.angle = sway * math.sin(w);
    return s;
  }
}
