/// A **Live2D-style puppet**: assemble a character out of separate part layers
/// (head, hair, eyes, mouth, body, accessories — typically sliced from a sprite
/// sheet with the Ripper) and bake a gently *animated* AO sprite from it — an
/// idle (breathe / sway / blink) `(a)` and a talking `(b)` — without any of the
/// art being hand-animated.
///
/// AO can't render a real Live2D/Cubism model, so this **bakes** the rig down to
/// ordinary animated sprites (the engine never speaks a custom format). Each
/// [PuppetLayer] carries its own [AnimRecipe] motion, evaluated through the
/// shared [AnimEngine] (same recipe library + easing as the Animation Studio),
/// and is composited around its own **pivot** so hair swings from the scalp, the
/// jaw drops from the upper lip, the body breathes from the hips, etc.
///
/// Pure Dart (no Flutter), isolate-safe — mirrors `animation/jiggle.dart` and
/// `animation/lipsync.dart`. See docs/PUPPET.md.
library;

import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../animation/anim_clip.dart';
import '../animation/anim_engine.dart';

/// What part of the character a layer is. Drives the **auto-seeded** idle motion
/// + default pivot, and marks which layer opens when talking.
enum PuppetRole {
  body('Body'),
  head('Head'),
  hair('Hair'),
  eyes('Eyes'),
  mouth('Mouth'),
  accessory('Accessory');

  const PuppetRole(this.label);
  final String label;

  static PuppetRole fromName(String n) => PuppetRole.values.firstWhere(
        (PuppetRole r) => r.name == n,
        orElse: () => PuppetRole.accessory,
      );
}

/// One stacked, animatable part of a [PuppetRig] (back-to-front by list order).
///
/// Geometry is **normalized** to the rig canvas (0..1) so it's resolution-
/// independent: the small preview matches the full-res bake. [x]/[y] is where
/// the part's [pivotX]/[pivotY] point sits on the canvas; the layer scales /
/// rotates around that pivot, then its per-frame [motion] is applied on top.
class PuppetLayer {
  PuppetLayer(
    this.image, {
    this.name = 'part',
    this.role = PuppetRole.accessory,
    this.x = 0.5,
    this.y = 0.5,
    this.scale = 1.0,
    this.angle = 0.0,
    this.opacity = 1.0,
    this.pivotX = 0.5,
    this.pivotY = 0.5,
    this.phase = 0.0,
    this.visible = true,
    List<AnimRecipe>? motion,
  }) : motion = motion ?? <AnimRecipe>[];

  /// Build a layer with the [role]'s default pivot, idle motion and phase — the
  /// "auto-animate" path. Pass [x]/[y] to place it (defaults to centred).
  factory PuppetLayer.withRoleDefaults(
    img.Image image, {
    required String name,
    required PuppetRole role,
    double x = 0.5,
    double y = 0.5,
  }) {
    final (double px, double py) = defaultPivot(role);
    return PuppetLayer(
      image,
      name: name,
      role: role,
      x: x,
      y: y,
      pivotX: px,
      pivotY: py,
      phase: defaultPhase(role),
      motion: defaultMotion(role),
    );
  }

  img.Image image;
  String name;
  PuppetRole role;

  /// Canvas position of the part's pivot, as fractions of the rig canvas (0..1).
  double x;
  double y;

  double scale;
  double angle; // degrees
  double opacity; // 0..1

  /// Pivot inside the part (0..1) — the point that rotation/scale happen around
  /// and that lands at ([x],[y]) on the canvas.
  double pivotX;
  double pivotY;

  /// Phase offset (0..1) added to the animation clock for this layer, so e.g.
  /// hair sways slightly out of step with the body (organic, not robotic).
  double phase;

  bool visible;

  /// Per-frame idle motion (applies in both idle and talk). Empty = static.
  List<AnimRecipe> motion;

  // ---- Role defaults ----

  /// Sensible pivot per role (hair from the scalp, mouth from the upper lip, …).
  static (double, double) defaultPivot(PuppetRole role) {
    switch (role) {
      case PuppetRole.body:
        return (0.5, 1.0); // breathe up from the hips
      case PuppetRole.head:
        return (0.5, 0.95); // nod from the neck
      case PuppetRole.hair:
        return (0.5, 0.1); // swing from the scalp
      case PuppetRole.eyes:
        return (0.5, 0.5);
      case PuppetRole.mouth:
        return (0.5, 0.15); // jaw drops from the upper lip
      case PuppetRole.accessory:
        return (0.5, 0.2);
    }
  }

  static List<AnimRecipe> defaultMotion(PuppetRole role) {
    switch (role) {
      case PuppetRole.body:
        return <AnimRecipe>[
          AnimRecipe('breathe', p: <String, double>{'intensity': 3, 'cycles': 1})
        ];
      case PuppetRole.head:
        return <AnimRecipe>[
          AnimRecipe('nod', p: <String, double>{'intensity': 2, 'cycles': 1})
        ];
      case PuppetRole.hair:
        return <AnimRecipe>[
          AnimRecipe('sway', p: <String, double>{'intensity': 5, 'cycles': 1})
        ];
      case PuppetRole.accessory:
        return <AnimRecipe>[
          AnimRecipe('sway', p: <String, double>{'intensity': 3, 'cycles': 1})
        ];
      case PuppetRole.eyes:
        return <AnimRecipe>[
          AnimRecipe('blink', p: <String, double>{'count': 1})
        ];
      case PuppetRole.mouth:
        return <AnimRecipe>[]; // the talk clip animates the mouth
    }
  }

  static double defaultPhase(PuppetRole role) {
    switch (role) {
      case PuppetRole.hair:
        return 0.15;
      case PuppetRole.accessory:
        return 0.35;
      default:
        return 0.0;
    }
  }
}

/// A whole assembled character: a fixed canvas size + ordered [layers].
class PuppetRig {
  PuppetRig({required this.width, required this.height, List<PuppetLayer>? layers})
      : layers = layers ?? <PuppetLayer>[];

  int width;
  int height;
  final List<PuppetLayer> layers;

  bool get isEmpty => layers.isEmpty;

  /// True if anything actually moves for the given [talk] mode — lets the engine
  /// collapse a perfectly static rig to a single frame.
  bool animates({bool talk = false}) {
    for (final PuppetLayer l in layers) {
      if (!l.visible) continue;
      if (l.motion.isNotEmpty) return true;
      if (talk && l.role == PuppetRole.mouth) return true;
    }
    return false;
  }
}

/// Renders a [PuppetRig] to an [AnimClip] by compositing every layer per frame.
class PuppetEngine {
  const PuppetEngine._();

  /// Default mouth opening (extra vertical scale) for the talk clip.
  static const double defaultTalkOpen = 0.5;

  /// Render the rig to a seamless-looping clip. [talk] adds a mouth open/close
  /// cadence to every [PuppetRole.mouth] layer. A rig with no motion collapses
  /// to a single frame (a still composite).
  static AnimClip render(
    PuppetRig rig, {
    int frames = 16,
    int fps = 12,
    bool talk = false,
    double talkOpen = defaultTalkOpen,
    double talkSyllables = 3,
  }) {
    final int w = math.max(1, rig.width);
    final int h = math.max(1, rig.height);
    final int n = rig.animates(talk: talk) ? math.max(1, frames) : 1;
    final int delayCentis = math.max(1, (100 / math.max(1, fps)).round());

    // Pivot is constant per layer, so centre each part on its pivot ONCE.
    final List<img.Image> centered = <img.Image>[
      for (final PuppetLayer l in rig.layers)
        _centerOnPivot(l.image, l.pivotX, l.pivotY),
    ];

    final List<AnimFrame> out = <AnimFrame>[];
    for (int i = 0; i < n; i++) {
      final double t = n <= 1 ? 0.0 : i / n; // exclusive end ⇒ clean loop
      img.Image canvas = img.Image(width: w, height: h, numChannels: 4);

      for (int li = 0; li < rig.layers.length; li++) {
        final PuppetLayer l = rig.layers[li];
        if (!l.visible || l.opacity <= 0) continue;

        // Per-layer motion, evaluated on a phase-shifted clock (still seamless).
        final double lt = ((t + l.phase) % 1.0 + 1.0) % 1.0;
        final FrameSpec spec = AnimEngine.frameSpec(lt, l.motion);

        // Fold the layer's static placement into the spec so the shared
        // renderLayer maths handles everything in one transform.
        spec.scale *= l.scale;
        spec.angle += l.angle;
        spec.opacity *= l.opacity;
        if (talk && l.role == PuppetRole.mouth) {
          spec.scaleY *= 1.0 + talkOpen * _talkOpenness(t, talkSyllables);
        }

        final img.Image layerImg = AnimEngine.renderLayer(
          centered[li],
          spec,
          canvasW: w,
          canvasH: h,
          anchorX: l.x * w,
          anchorY: l.y * h,
        );
        canvas = img.compositeImage(canvas, layerImg);
      }
      out.add(AnimFrame(canvas, delayCentis: delayCentis));
    }
    return AnimClip(out);
  }

  /// Pad [part] so its [px]/[py] pivot sits at the centre of the returned image
  /// — then a symmetric scale + a rotate-about-centre keep the pivot fixed, so
  /// the layer can be placed by its pivot with [AnimEngine.renderLayer]'s
  /// centre-anchored maths.
  static img.Image _centerOnPivot(img.Image part, double px, double py) {
    final img.Image src =
        part.numChannels == 4 ? part : part.convert(numChannels: 4);
    final int left = (px * src.width).round();
    final int top = (py * src.height).round();
    final int right = src.width - left;
    final int bottom = src.height - top;
    final int halfW = math.max(1, math.max(left, right));
    final int halfH = math.max(1, math.max(top, bottom));
    final img.Image outImg =
        img.Image(width: halfW * 2, height: halfH * 2, numChannels: 4);
    // Place the part so its pivot pixel lands at the canvas centre (halfW,halfH).
    img.compositeImage(outImg, src, dstX: halfW - left, dstY: halfH - top);
    return outImg;
  }

  /// A simple, seamless mouth cadence over t∈[0,1): 0 (closed) → 1 (open) pulses,
  /// [syllables] per loop. Squared for a snappier open/close.
  static double _talkOpenness(double t, double syllables) {
    final double s = math.sin(math.pi * ((t * math.max(1, syllables)) % 1.0));
    return s * s;
  }
}
