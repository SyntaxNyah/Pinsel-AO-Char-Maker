import 'dart:math' as math;

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

  double n(String k, [double f = 0]) => p[k] ?? f;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type,
        if (p.isNotEmpty) 'p': p,
        if (colors.isNotEmpty) 'colors': colors,
        if (region != null)
          'region': <int>[region!.x, region!.y, region!.w, region!.h],
        if (ease != 'linear') 'ease': ease,
      };

  static AnimRecipe fromJson(Map<String, dynamic> j) {
    final List<dynamic>? r = j['region'] as List<dynamic>?;
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
    final List<AnimRecipe> regional =
        recipes.where((AnimRecipe r) => r.region != null).toList();

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

      // Region layers on top.
      for (final AnimRecipe r in regional) {
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
