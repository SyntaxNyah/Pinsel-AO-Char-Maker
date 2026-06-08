/// # Paint engine — gradients, fills, brushes, blend modes
///
/// The headline "advanced paint tools" surface. Everything here is **pure Dart**
/// (no `package:flutter`) so the Paint Studio behaves identically on every target
/// and is unit-testable (`test/paint_test.dart`).
///
/// ## The model: a journal of [PaintOp]s in normalized coordinates
/// Like recolour ([OpPipeline]) and animation ([AnimRecipe]), a paint edit is a
/// **serialisable journal** — a `List<PaintOp>`. Each op carries its geometry in
/// **normalized 0..1 coordinates** (fractions of the sprite), so the *exact same*
/// journal can be replayed onto a small preview frame and onto the full-res
/// sprite (and every animation frame) with identical results. This is why the
/// live preview matches the baked output, and why an op is resolution- and
/// frame-rate-independent.
///
/// ## Replay
/// `PaintOp.applyTo(frame)` re-derives its mask from that frame (or uses a
/// pre-built one) and composites. The caller ([AppState.applyPaint]) builds
/// content-derived masks (magic-wand / luminance) **once per sprite file** from
/// its first frame and reuses them across the file's animation frames, so a
/// recolour can't shimmer frame-to-frame. Geometric masks (rect/ellipse/lasso)
/// and brush strokes are coordinate-based and identical on every frame anyway.
///
/// See docs/PAINT.md for the field-by-field reference.
library;

import 'dart:math' as math;

import 'package:image/image.dart' as img;

import 'button_maker.dart' show IntRect;
import 'color_ops.dart';
import 'region_edit.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// How a [PaintGradient] maps its 0..1 ramp across a region's bounding box.
enum GradientType {
  /// Straight ramp along [PaintGradient.angle] (0° = left→right, 90° = top→bottom).
  linear,

  /// Linear, but mirrored about the centre (a V — same colour at both ends).
  reflected,

  /// Concentric ellipses from the centre out to the box edge.
  radial,

  /// Concentric diamonds (Manhattan distance) from the centre.
  diamond,

  /// Sweeps the ramp around the centre by angle (a colour wheel / pie sweep).
  conic,
}

extension GradientTypeInfo on GradientType {
  String get id => name;
  String get label => switch (this) {
        GradientType.linear => 'Linear',
        GradientType.reflected => 'Reflected',
        GradientType.radial => 'Radial',
        GradientType.diamond => 'Diamond',
        GradientType.conic => 'Conic',
      };
  static GradientType fromId(String? id) => GradientType.values.firstWhere(
      (GradientType t) => t.name == id,
      orElse: () => GradientType.linear);
}

/// Per-channel (and a few HSL-based) blend modes for fills and brushes — the
/// same family Photoshop/Krita expose. `normal` just lays the source on top;
/// `color`/`hue`/`saturation`/`luminosity` are the HSL "creative" modes that
/// make **recolour-preserving-shading** possible (pick `color` to repaint the
/// clothes while keeping their folds).
enum PaintBlend {
  normal,
  multiply,
  screen,
  overlay,
  darken,
  lighten,
  colorDodge,
  colorBurn,
  hardLight,
  softLight,
  difference,
  exclusion,
  add,
  subtract,
  hue,
  saturation,
  color,
  luminosity,
}

extension PaintBlendInfo on PaintBlend {
  String get id => name;
  String get label => switch (this) {
        PaintBlend.normal => 'Normal',
        PaintBlend.multiply => 'Multiply',
        PaintBlend.screen => 'Screen',
        PaintBlend.overlay => 'Overlay',
        PaintBlend.darken => 'Darken',
        PaintBlend.lighten => 'Lighten',
        PaintBlend.colorDodge => 'Color Dodge',
        PaintBlend.colorBurn => 'Color Burn',
        PaintBlend.hardLight => 'Hard Light',
        PaintBlend.softLight => 'Soft Light',
        PaintBlend.difference => 'Difference',
        PaintBlend.exclusion => 'Exclusion',
        PaintBlend.add => 'Add',
        PaintBlend.subtract => 'Subtract',
        PaintBlend.hue => 'Hue',
        PaintBlend.saturation => 'Saturation',
        PaintBlend.color => 'Color',
        PaintBlend.luminosity => 'Luminosity',
      };
  static PaintBlend fromId(String? id) => PaintBlend.values
      .firstWhere((PaintBlend b) => b.name == id, orElse: () => PaintBlend.normal);
}

/// What a brush stroke does to the pixels it covers.
enum BrushMode {
  /// Lay the brush colour down through [BrushSpec.blend].
  paint,

  /// Lower alpha (rub the sprite away).
  erase,

  /// Lighten toward white (tonal — colour ignored).
  dodge,

  /// Darken toward black (tonal — colour ignored).
  burn,

  /// Push neighbouring colour along the stroke (a soft blur/smear).
  smudge,
}

extension BrushModeInfo on BrushMode {
  String get id => name;
  String get label => switch (this) {
        BrushMode.paint => 'Paint',
        BrushMode.erase => 'Erase',
        BrushMode.dodge => 'Dodge',
        BrushMode.burn => 'Burn',
        BrushMode.smudge => 'Smudge',
      };
  static BrushMode fromId(String? id) => BrushMode.values
      .firstWhere((BrushMode m) => m.name == id, orElse: () => BrushMode.paint);
}

/// How a [PaintSelection] picks the pixels an op affects.
enum SelectionKind {
  /// Every pixel (optionally still clipped to opaque by the op).
  whole,

  /// Magic-wand: a colour-similar blob seeded at a point.
  wand,

  /// A rectangle.
  rect,

  /// An ellipse inscribed in a rectangle.
  ellipse,

  /// A freehand lasso polygon.
  lasso,

  /// A luminance band (only shadows / only highlights).
  luminance,
}

extension SelectionKindInfo on SelectionKind {
  String get id => name;
  String get label => switch (this) {
        SelectionKind.whole => 'Whole sprite',
        SelectionKind.wand => 'Magic wand',
        SelectionKind.rect => 'Rectangle',
        SelectionKind.ellipse => 'Ellipse',
        SelectionKind.lasso => 'Lasso',
        SelectionKind.luminance => 'Luminance',
      };
  static SelectionKind fromId(String? id) => SelectionKind.values.firstWhere(
      (SelectionKind k) => k.name == id,
      orElse: () => SelectionKind.whole);
}

/// What a [PaintOp] does.
enum PaintOpKind {
  /// Flood a region with one solid colour.
  fillSolid,

  /// Flood a region with a [PaintGradient].
  fillGradient,

  /// Run a colour-op [ColorOp] pipeline through a region (recolour the clothes,
  /// boost the hair's saturation, posterize a patch…).
  fillOps,

  /// A freehand brush stroke.
  brush,
}

// ---------------------------------------------------------------------------
// Gradient model
// ---------------------------------------------------------------------------

/// One colour stop in a [PaintGradient]: an ARGB colour at position [pos] (0..1).
class GradientStop {
  GradientStop(this.pos, this.argb);
  double pos;
  int argb;

  GradientStop copy() => GradientStop(pos, argb);
  Map<String, dynamic> toJson() => <String, dynamic>{'pos': pos, 'argb': argb};
  static GradientStop fromJson(Map<String, dynamic> m) =>
      GradientStop((m['pos'] as num).toDouble(), (m['argb'] as num).toInt());
}

/// An editable, multi-stop gradient + how it maps across a region. The model
/// behind the gradient editor and the gradient-fill tool.
class PaintGradient {
  PaintGradient(
    this.stops, {
    this.type = GradientType.linear,
    this.angle = 0,
    this.reverse = false,
    this.name = '',
    this.category = '',
  });

  /// Colour stops (any order; sampled sorted by [GradientStop.pos]).
  final List<GradientStop> stops;
  GradientType type;

  /// Degrees, for [GradientType.linear]/[GradientType.reflected]/[GradientType.conic].
  /// 0 = left→right, 90 = top→bottom.
  double angle;

  /// Flip the ramp end-for-end.
  bool reverse;

  final String name;
  final String category;

  /// A simple two-stop black→white linear gradient.
  factory PaintGradient.blackwhite() => PaintGradient(<GradientStop>[
        GradientStop(0, 0xFF000000),
        GradientStop(1, 0xFFFFFFFF),
      ]);

  /// Build from evenly-spaced ARGB stops (e.g. a [NamedGradient]'s list).
  factory PaintGradient.fromColors(List<int> colors,
      {GradientType type = GradientType.linear,
      double angle = 0,
      String name = '',
      String category = ''}) {
    final List<GradientStop> s = <GradientStop>[
      for (int i = 0; i < colors.length; i++)
        GradientStop(colors.length == 1 ? 0 : i / (colors.length - 1), colors[i]),
    ];
    return PaintGradient(s, type: type, angle: angle, name: name, category: category);
  }

  PaintGradient copy() => PaintGradient(
        <GradientStop>[for (final GradientStop s in stops) s.copy()],
        type: type,
        angle: angle,
        reverse: reverse,
        name: name,
        category: category,
      );

  /// The ARGB colour at ramp position [t] (clamped 0..1), interpolating between
  /// the two surrounding stops in straight (non-premultiplied) RGBA.
  int colorAt(double t) {
    if (stops.isEmpty) return 0x00000000;
    double tt = t.clamp(0.0, 1.0).toDouble();
    if (reverse) tt = 1 - tt;
    final List<GradientStop> sorted = <GradientStop>[...stops]
      ..sort((GradientStop a, GradientStop b) => a.pos.compareTo(b.pos));
    if (tt <= sorted.first.pos) return sorted.first.argb;
    if (tt >= sorted.last.pos) return sorted.last.argb;
    for (int i = 0; i < sorted.length - 1; i++) {
      final GradientStop a = sorted[i], b = sorted[i + 1];
      if (tt >= a.pos && tt <= b.pos) {
        final double span = (b.pos - a.pos);
        final double f = span <= 0 ? 0 : (tt - a.pos) / span;
        return _lerpArgb(a.argb, b.argb, f);
      }
    }
    return sorted.last.argb;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'stops': <Map<String, dynamic>>[for (final GradientStop s in stops) s.toJson()],
        'type': type.name,
        'angle': angle,
        'reverse': reverse,
        if (name.isNotEmpty) 'name': name,
        if (category.isNotEmpty) 'category': category,
      };

  static PaintGradient fromJson(Map<String, dynamic> m) => PaintGradient(
        <GradientStop>[
          for (final dynamic s in (m['stops'] as List<dynamic>? ?? <dynamic>[]))
            GradientStop.fromJson(Map<String, dynamic>.from(s as Map)),
        ],
        type: GradientTypeInfo.fromId(m['type'] as String?),
        angle: (m['angle'] as num?)?.toDouble() ?? 0,
        reverse: m['reverse'] as bool? ?? false,
        name: m['name'] as String? ?? '',
        category: m['category'] as String? ?? '',
      );
}

// ---------------------------------------------------------------------------
// Selection
// ---------------------------------------------------------------------------

/// A resolution-independent recipe for a [SelectionMask]: which pixels an op
/// touches. Geometry is in normalized 0..1 coordinates so it replays at any size.
class PaintSelection {
  PaintSelection(
    this.kind, {
    this.x = 0,
    this.y = 0,
    this.w = 1,
    this.h = 1,
    this.tolerance = 48,
    this.contiguous = true,
    this.ignoreTransparent = true,
    this.lumMin = 0,
    this.lumMax = 255,
    List<double>? poly,
    this.feather = 0,
    this.grow = 0,
    this.invert = false,
  }) : poly = poly ?? <double>[];

  final SelectionKind kind;

  /// rect/ellipse top-left + size (norm); for [SelectionKind.wand] (x,y) is the
  /// seed point.
  double x, y, w, h;

  /// Magic-wand match tolerance (0..441 in RGB distance).
  double tolerance;
  bool contiguous;
  bool ignoreTransparent;

  /// Luminance band (0..255).
  int lumMin, lumMax;

  /// Flattened lasso polygon in norm coords: [x0,y0,x1,y1,…].
  final List<double> poly;

  /// Soften the mask edge by this many px (at apply resolution).
  int feather;

  /// Grow (>0) / shrink (<0) the mask by px before feathering.
  int grow;

  /// Select everything *except* the chosen region.
  bool invert;

  /// Build the concrete [SelectionMask] for an image of [frame]'s size.
  SelectionMask build(img.Image frame) {
    final int w0 = frame.width, h0 = frame.height;
    SelectionMask m = switch (kind) {
      SelectionKind.whole => SelectionMask.full(w0, h0),
      SelectionKind.wand => RegionEditor.selectByColor(
          frame,
          (x * w0).round().clamp(0, w0 - 1),
          (y * h0).round().clamp(0, h0 - 1),
          tolerance: tolerance,
          contiguous: contiguous,
          ignoreTransparent: ignoreTransparent,
        ),
      SelectionKind.rect => RegionEditor.rectangle(w0, h0, _rectPx(w0, h0)),
      SelectionKind.ellipse => RegionEditor.ellipse(w0, h0, _rectPx(w0, h0)),
      SelectionKind.luminance =>
        RegionEditor.selectByLuminance(frame, min: lumMin, max: lumMax),
      SelectionKind.lasso => _polygonMask(w0, h0),
    };
    if (grow > 0) m = RegionEditor.grow(m, grow);
    if (grow < 0) m = RegionEditor.shrink(m, -grow);
    if (feather > 0) m = RegionEditor.feather(m, radius: feather);
    if (invert) m = m.invert();
    return m;
  }

  IntRect _rectPx(int w0, int h0) => IntRect(
        (x * w0).round(),
        (y * h0).round(),
        (w * w0).round().clamp(1, w0),
        (h * h0).round().clamp(1, h0),
      );

  SelectionMask _polygonMask(int w0, int h0) {
    final SelectionMask m = SelectionMask(w0, h0);
    if (poly.length < 6) return m;
    final int n = poly.length ~/ 2;
    final List<double> px = <double>[for (int i = 0; i < n; i++) poly[i * 2] * w0];
    final List<double> py = <double>[for (int i = 0; i < n; i++) poly[i * 2 + 1] * h0];
    for (int yy = 0; yy < h0; yy++) {
      for (int xx = 0; xx < w0; xx++) {
        if (_pointInPoly(xx + 0.5, yy + 0.5, px, py)) m.set(xx, yy, 255);
      }
    }
    return m;
  }

  static bool _pointInPoly(double x, double y, List<double> px, List<double> py) {
    bool inside = false;
    final int n = px.length;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final bool cross = (py[i] > y) != (py[j] > y) &&
          x < (px[j] - px[i]) * (y - py[i]) / (py[j] - py[i]) + px[i];
      if (cross) inside = !inside;
    }
    return inside;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': kind.name,
        'x': x, 'y': y, 'w': w, 'h': h,
        'tolerance': tolerance,
        'contiguous': contiguous,
        'ignoreTransparent': ignoreTransparent,
        'lumMin': lumMin, 'lumMax': lumMax,
        'poly': poly,
        'feather': feather, 'grow': grow, 'invert': invert,
      };

  static PaintSelection fromJson(Map<String, dynamic> m) => PaintSelection(
        SelectionKindInfo.fromId(m['kind'] as String?),
        x: (m['x'] as num?)?.toDouble() ?? 0,
        y: (m['y'] as num?)?.toDouble() ?? 0,
        w: (m['w'] as num?)?.toDouble() ?? 1,
        h: (m['h'] as num?)?.toDouble() ?? 1,
        tolerance: (m['tolerance'] as num?)?.toDouble() ?? 48,
        contiguous: m['contiguous'] as bool? ?? true,
        ignoreTransparent: m['ignoreTransparent'] as bool? ?? true,
        lumMin: (m['lumMin'] as num?)?.toInt() ?? 0,
        lumMax: (m['lumMax'] as num?)?.toInt() ?? 255,
        poly: <double>[
          for (final dynamic v in (m['poly'] as List<dynamic>? ?? <dynamic>[]))
            (v as num).toDouble()
        ],
        feather: (m['feather'] as num?)?.toInt() ?? 0,
        grow: (m['grow'] as num?)?.toInt() ?? 0,
        invert: m['invert'] as bool? ?? false,
      );
}

// ---------------------------------------------------------------------------
// Brush
// ---------------------------------------------------------------------------

/// A round brush: [size] and [hardness] are fractions of the image's **shorter
/// side**, so the brush is resolution-independent. [opacity] is the maximum
/// coverage of the whole stroke; [blend] lets a paint brush behave like a
/// recolour brush (`color`) etc.
class BrushSpec {
  BrushSpec({
    this.mode = BrushMode.paint,
    this.argb = 0xFF000000,
    this.size = 0.08,
    this.hardness = 0.6,
    this.opacity = 1.0,
    this.blend = PaintBlend.normal,
    this.clipToOpaque = true,
  });

  BrushMode mode;
  int argb;
  double size;
  double hardness;
  double opacity;
  PaintBlend blend;

  /// Only paint where the sprite is already opaque (stay inside the silhouette).
  bool clipToOpaque;

  BrushSpec copy() => BrushSpec(
        mode: mode,
        argb: argb,
        size: size,
        hardness: hardness,
        opacity: opacity,
        blend: blend,
        clipToOpaque: clipToOpaque,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'mode': mode.name,
        'argb': argb,
        'size': size,
        'hardness': hardness,
        'opacity': opacity,
        'blend': blend.name,
        'clipToOpaque': clipToOpaque,
      };

  static BrushSpec fromJson(Map<String, dynamic> m) => BrushSpec(
        mode: BrushModeInfo.fromId(m['mode'] as String?),
        argb: (m['argb'] as num?)?.toInt() ?? 0xFF000000,
        size: (m['size'] as num?)?.toDouble() ?? 0.08,
        hardness: (m['hardness'] as num?)?.toDouble() ?? 0.6,
        opacity: (m['opacity'] as num?)?.toDouble() ?? 1.0,
        blend: PaintBlendInfo.fromId(m['blend'] as String?),
        clipToOpaque: m['clipToOpaque'] as bool? ?? true,
      );
}

// ---------------------------------------------------------------------------
// PaintOp — one journalled edit
// ---------------------------------------------------------------------------

/// A single, serialisable paint edit. The Paint Studio appends these; preview
/// and bake both just replay the list.
class PaintOp {
  PaintOp(
    this.kind, {
    PaintSelection? selection,
    this.argb = 0xFFFFFFFF,
    PaintGradient? gradient,
    List<ColorOp>? ops,
    BrushSpec? brush,
    List<double>? stroke,
    this.blend = PaintBlend.normal,
    this.opacity = 1.0,
    this.preserveAlpha = true,
  })  : selection = selection ?? PaintSelection(SelectionKind.whole),
        gradient = gradient ?? PaintGradient.blackwhite(),
        ops = ops ?? <ColorOp>[],
        brush = brush ?? BrushSpec(),
        stroke = stroke ?? <double>[];

  final PaintOpKind kind;

  /// The region for fill ops (ignored by [PaintOpKind.brush]).
  final PaintSelection selection;

  /// Solid-fill colour.
  final int argb;

  /// Gradient-fill ramp.
  final PaintGradient gradient;

  /// Ops-fill pipeline.
  final List<ColorOp> ops;

  /// Brush + its [stroke] (flattened norm points [x0,y0,…]).
  final BrushSpec brush;
  final List<double> stroke;

  /// Blend mode + strength for fill ops.
  final PaintBlend blend;
  final double opacity;

  /// Keep each pixel's original alpha (recolour only; don't bleed colour into
  /// transparent areas). Fills default this on.
  final bool preserveAlpha;

  /// Build this op's mask against [frame] (null for brush ops). Exposed so the
  /// caller can compute a *content-derived* mask once and reuse it per frame.
  SelectionMask? buildMask(img.Image frame) =>
      kind == PaintOpKind.brush ? null : selection.build(frame);

  /// Replay this op onto [frame]. Pass [mask] to reuse a pre-built one (keeps a
  /// magic-wand recolour stable across animation frames); otherwise it's built
  /// from [frame].
  void applyTo(img.Image frame, {SelectionMask? mask}) {
    switch (kind) {
      case PaintOpKind.brush:
        Painter.stroke(frame, stroke, brush);
      case PaintOpKind.fillSolid:
        final SelectionMask m = mask ?? selection.build(frame);
        Painter.fillSolid(frame, m, argb,
            blend: blend, opacity: opacity, preserveAlpha: preserveAlpha);
      case PaintOpKind.fillGradient:
        final SelectionMask m = mask ?? selection.build(frame);
        Painter.fillGradient(frame, m, gradient,
            blend: blend, opacity: opacity, preserveAlpha: preserveAlpha);
      case PaintOpKind.fillOps:
        final SelectionMask m = mask ?? selection.build(frame);
        Painter.fillOps(frame, m, ops, opacity: opacity);
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': kind.name,
        'selection': selection.toJson(),
        'argb': argb,
        'gradient': gradient.toJson(),
        'ops': <Map<String, dynamic>>[for (final ColorOp o in ops) o.toJson()],
        'brush': brush.toJson(),
        'stroke': stroke,
        'blend': blend.name,
        'opacity': opacity,
        'preserveAlpha': preserveAlpha,
      };

  static PaintOp fromJson(Map<String, dynamic> m) => PaintOp(
        PaintOpKind.values
            .firstWhere((PaintOpKind k) => k.name == m['kind'], orElse: () => PaintOpKind.brush),
        selection: m['selection'] == null
            ? null
            : PaintSelection.fromJson(Map<String, dynamic>.from(m['selection'] as Map)),
        argb: (m['argb'] as num?)?.toInt() ?? 0xFFFFFFFF,
        gradient: m['gradient'] == null
            ? null
            : PaintGradient.fromJson(Map<String, dynamic>.from(m['gradient'] as Map)),
        ops: <ColorOp>[
          for (final dynamic o in (m['ops'] as List<dynamic>? ?? <dynamic>[]))
            ColorOp.fromJson(Map<String, dynamic>.from(o as Map)),
        ],
        brush: m['brush'] == null
            ? null
            : BrushSpec.fromJson(Map<String, dynamic>.from(m['brush'] as Map)),
        stroke: <double>[
          for (final dynamic v in (m['stroke'] as List<dynamic>? ?? <dynamic>[]))
            (v as num).toDouble()
        ],
        blend: PaintBlendInfo.fromId(m['blend'] as String?),
        opacity: (m['opacity'] as num?)?.toDouble() ?? 1.0,
        preserveAlpha: m['preserveAlpha'] as bool? ?? true,
      );
}

// ---------------------------------------------------------------------------
// The painter — the actual pixel work
// ---------------------------------------------------------------------------

/// Static pixel operations: fill a mask with a colour / gradient / op pipeline,
/// and stamp a brush stroke. All mutate the passed [img.Image] in place.
class Painter {
  const Painter._();

  /// Replay a whole journal onto [frame]. Content-derived masks are rebuilt from
  /// [frame] unless you pass a matching [masks] list (one entry per op, null for
  /// brush ops) — see [AppState.applyPaint] for the per-frame-stable variant.
  static void applyAll(img.Image frame, List<PaintOp> ops,
      {List<SelectionMask?>? masks}) {
    for (int i = 0; i < ops.length; i++) {
      ops[i].applyTo(frame, mask: masks != null && i < masks.length ? masks[i] : null);
    }
  }

  /// Fill [mask] with one solid [argb] through [blend].
  static void fillSolid(img.Image image, SelectionMask mask, int argb,
      {PaintBlend blend = PaintBlend.normal,
      double opacity = 1.0,
      bool preserveAlpha = true}) {
    _composite(image, mask,
        srcArgb: (int x, int y) => argb,
        blend: blend,
        opacity: opacity,
        preserveAlpha: preserveAlpha);
  }

  /// Fill [mask] with [gradient], mapped across the mask's bounding box.
  static void fillGradient(img.Image image, SelectionMask mask, PaintGradient gradient,
      {PaintBlend blend = PaintBlend.normal,
      double opacity = 1.0,
      bool preserveAlpha = true}) {
    final IntRect box = _maskBounds(mask) ?? IntRect(0, 0, image.width, image.height);
    final double cx = box.x + box.w / 2.0, cy = box.y + box.h / 2.0;
    final double hx = box.w / 2.0, hy = box.h / 2.0;
    final double rad = gradient.angle * math.pi / 180.0;
    final double ux = math.cos(rad), uy = math.sin(rad);
    final double proj = (hx * ux.abs() + hy * uy.abs());
    final double projSafe = proj <= 0 ? 1 : proj;
    final double hxSafe = hx <= 0 ? 1 : hx, hySafe = hy <= 0 ? 1 : hy;

    double tAt(int x, int y) {
      final double dx = x - cx, dy = y - cy;
      switch (gradient.type) {
        case GradientType.linear:
          final double raw = dx * ux + dy * uy;
          return (raw / (2 * projSafe) + 0.5).clamp(0.0, 1.0);
        case GradientType.reflected:
          final double raw = dx * ux + dy * uy;
          return (raw / projSafe).abs().clamp(0.0, 1.0);
        case GradientType.radial:
          final double nx = dx / hxSafe, ny = dy / hySafe;
          return math.sqrt(nx * nx + ny * ny).clamp(0.0, 1.0);
        case GradientType.diamond:
          return ((dx / hxSafe).abs() + (dy / hySafe).abs()).clamp(0.0, 1.0);
        case GradientType.conic:
          double a = math.atan2(dy, dx) - rad;
          a = a % (2 * math.pi);
          if (a < 0) a += 2 * math.pi;
          return a / (2 * math.pi);
      }
    }

    _composite(image, mask,
        srcArgb: (int x, int y) => gradient.colorAt(tAt(x, y)),
        blend: blend,
        opacity: opacity,
        preserveAlpha: preserveAlpha);
  }

  /// Run a [ColorOp] pipeline through [mask] (recolour just that region),
  /// blending by mask × [opacity]. Mirrors [RegionEditor.applyOps] but with a
  /// strength.
  static void fillOps(img.Image image, SelectionMask mask, List<ColorOp> ops,
      {double opacity = 1.0}) {
    if (ops.isEmpty) return;
    final img.Image edited = image.clone();
    ImageOps.applyAll(edited, ops);
    final int w = image.width, h = image.height;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final int mv = mask.get(x, y);
        if (mv == 0) continue;
        final double f = (mv / 255.0) * opacity;
        if (f <= 0) continue;
        final img.Pixel b = image.getPixel(x, y);
        final img.Pixel e = edited.getPixel(x, y);
        image.setPixelRgba(
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

  /// Stamp a brush [stroke] (flattened norm points) onto [image].
  static void stroke(img.Image image, List<double> stroke, BrushSpec brush) {
    if (stroke.length < 2) return;
    final int w = image.width, h = image.height;
    final int shorter = w < h ? w : h;
    final double radius = math.max(0.5, brush.size * shorter / 2.0);
    final double hardness = brush.hardness.clamp(0.0, 0.999);

    // Build a per-stroke coverage mask by max-stamping along interpolated
    // centres (so overlapping stamps within one stroke don't double-darken).
    final SelectionMask cov = SelectionMask(w, h);
    final List<double> pts = <double>[];
    for (int i = 0; i + 1 < stroke.length; i += 2) {
      pts.add(stroke[i] * w);
      pts.add(stroke[i + 1] * h);
    }
    final double spacing = math.max(1.0, radius * 0.25);
    double prevX = pts[0], prevY = pts[1];
    _stamp(cov, prevX, prevY, radius, hardness);
    for (int i = 2; i + 1 < pts.length; i += 2) {
      final double nx = pts[i], ny = pts[i + 1];
      final double dist = math.sqrt((nx - prevX) * (nx - prevX) + (ny - prevY) * (ny - prevY));
      final int steps = (dist / spacing).ceil();
      for (int s = 1; s <= steps; s++) {
        final double t = s / steps;
        _stamp(cov, prevX + (nx - prevX) * t, prevY + (ny - prevY) * t, radius, hardness);
      }
      prevX = nx;
      prevY = ny;
    }

    switch (brush.mode) {
      case BrushMode.erase:
        _erase(image, cov, brush.opacity);
      case BrushMode.dodge:
        _tone(image, cov, brush.opacity, lighten: true, clipToOpaque: brush.clipToOpaque);
      case BrushMode.burn:
        _tone(image, cov, brush.opacity, lighten: false, clipToOpaque: brush.clipToOpaque);
      case BrushMode.smudge:
        _smudge(image, cov, brush.opacity);
      case BrushMode.paint:
        _composite(image, cov,
            srcArgb: (int x, int y) => brush.argb,
            blend: brush.blend,
            opacity: brush.opacity,
            preserveAlpha: brush.clipToOpaque);
    }
  }

  // ---- internals ----

  static void _stamp(SelectionMask cov, double cxp, double cyp, double radius, double hardness) {
    final int minX = (cxp - radius).floor().clamp(0, cov.width - 1);
    final int maxX = (cxp + radius).ceil().clamp(0, cov.width - 1);
    final int minY = (cyp - radius).floor().clamp(0, cov.height - 1);
    final int maxY = (cyp + radius).ceil().clamp(0, cov.height - 1);
    for (int y = minY; y <= maxY; y++) {
      for (int x = minX; x <= maxX; x++) {
        final double dx = x + 0.5 - cxp, dy = y + 0.5 - cyp;
        final double d = math.sqrt(dx * dx + dy * dy) / radius;
        if (d >= 1) continue;
        final double a = d <= hardness ? 1.0 : (1 - d) / (1 - hardness);
        final int v = (a * 255).round();
        if (v > cov.get(x, y)) cov.set(x, y, v);
      }
    }
  }

  static void _erase(img.Image image, SelectionMask cov, double opacity) {
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final int mv = cov.get(x, y);
        if (mv == 0) continue;
        final double c = (mv / 255.0) * opacity;
        final img.Pixel p = image.getPixel(x, y);
        image.setPixelRgba(x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(),
            (p.a.toInt() * (1 - c)).round());
      }
    }
  }

  static void _tone(img.Image image, SelectionMask cov, double opacity,
      {required bool lighten, required bool clipToOpaque}) {
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final int mv = cov.get(x, y);
        if (mv == 0) continue;
        final img.Pixel p = image.getPixel(x, y);
        double c = (mv / 255.0) * opacity;
        if (clipToOpaque) c *= p.a.toInt() / 255.0;
        if (c <= 0) continue;
        final int r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
        final int tr = lighten ? 255 : 0;
        image.setPixelRgba(
          x,
          y,
          (r + (tr - r) * c).round(),
          (g + (tr - g) * c).round(),
          (b + (tr - b) * c).round(),
          p.a.toInt(),
        );
      }
    }
  }

  /// A cheap smear: pull a slightly blurred copy of the region toward the stroke
  /// (reuses the engine's own `blur` colour op so there's no extra image dep).
  static void _smudge(img.Image image, SelectionMask cov, double opacity) {
    final img.Image blurred = image.clone();
    ImageOps.apply(blurred, ColorOp('blur', nums: <String, double>{'radius': 2}));
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final int mv = cov.get(x, y);
        if (mv == 0) continue;
        final double c = (mv / 255.0) * opacity;
        if (c <= 0) continue;
        final img.Pixel p = image.getPixel(x, y);
        final img.Pixel q = blurred.getPixel(x, y);
        image.setPixelRgba(
          x,
          y,
          (p.r + (q.r - p.r) * c).round(),
          (p.g + (q.g - p.g) * c).round(),
          (p.b + (q.b - p.b) * c).round(),
          (p.a + (q.a - p.a) * c).round(),
        );
      }
    }
  }

  /// The shared compositor: blends a per-pixel source colour into [image]
  /// through [mask] × [opacity] (× source alpha), with [blend] + [preserveAlpha].
  static void _composite(img.Image image, SelectionMask mask,
      {required int Function(int x, int y) srcArgb,
      PaintBlend blend = PaintBlend.normal,
      double opacity = 1.0,
      bool preserveAlpha = true}) {
    final int w = image.width, h = image.height;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final int mv = mask.get(x, y);
        if (mv == 0) continue;
        final img.Pixel p = image.getPixel(x, y);
        final int ba = p.a.toInt();
        double cov = (mv / 255.0) * opacity;
        if (preserveAlpha) cov *= ba / 255.0;
        if (cov <= 0) continue;
        final int s = srcArgb(x, y);
        final int sa = (s >> 24) & 0xFF;
        final double c = cov * (sa / 255.0);
        if (c <= 0) continue;
        final int br = p.r.toInt(), bg = p.g.toInt(), bb = p.b.toInt();
        final List<int> blended =
            blendRgb(br, bg, bb, (s >> 16) & 0xFF, (s >> 8) & 0xFF, s & 0xFF, blend);
        final int na = preserveAlpha ? ba : (ba + (255 - ba) * c).round();
        image.setPixelRgba(
          x,
          y,
          (br + (blended[0] - br) * c).round(),
          (bg + (blended[1] - bg) * c).round(),
          (bb + (blended[2] - bb) * c).round(),
          na,
        );
      }
    }
  }

  static IntRect? _maskBounds(SelectionMask mask) {
    int minX = mask.width, minY = mask.height, maxX = -1, maxY = -1;
    for (int y = 0; y < mask.height; y++) {
      for (int x = 0; x < mask.width; x++) {
        if (mask.get(x, y) > 0) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (maxX < 0) return null;
    return IntRect(minX, minY, maxX - minX + 1, maxY - minY + 1);
  }
}

// ---------------------------------------------------------------------------
// Blend math
// ---------------------------------------------------------------------------

/// Blend a source RGB (0..255) over a base RGB by [mode]; returns `[r,g,b]`
/// (0..255). Pure + allocation-light; the building block of every fill/brush.
List<int> blendRgb(int br, int bg, int bb, int sr, int sg, int sb, PaintBlend mode) {
  switch (mode) {
    case PaintBlend.normal:
      return <int>[sr, sg, sb];
    case PaintBlend.multiply:
      return <int>[br * sr ~/ 255, bg * sg ~/ 255, bb * sb ~/ 255];
    case PaintBlend.screen:
      return <int>[_screen(br, sr), _screen(bg, sg), _screen(bb, sb)];
    case PaintBlend.overlay:
      return <int>[_overlay(br, sr), _overlay(bg, sg), _overlay(bb, sb)];
    case PaintBlend.darken:
      return <int>[math.min(br, sr), math.min(bg, sg), math.min(bb, sb)];
    case PaintBlend.lighten:
      return <int>[math.max(br, sr), math.max(bg, sg), math.max(bb, sb)];
    case PaintBlend.colorDodge:
      return <int>[_dodge(br, sr), _dodge(bg, sg), _dodge(bb, sb)];
    case PaintBlend.colorBurn:
      return <int>[_burn(br, sr), _burn(bg, sg), _burn(bb, sb)];
    case PaintBlend.hardLight:
      return <int>[_overlay(sr, br), _overlay(sg, bg), _overlay(sb, bb)];
    case PaintBlend.softLight:
      return <int>[_soft(br, sr), _soft(bg, sg), _soft(bb, sb)];
    case PaintBlend.difference:
      return <int>[(br - sr).abs(), (bg - sg).abs(), (bb - sb).abs()];
    case PaintBlend.exclusion:
      return <int>[_excl(br, sr), _excl(bg, sg), _excl(bb, sb)];
    case PaintBlend.add:
      return <int>[
        math.min(255, br + sr),
        math.min(255, bg + sg),
        math.min(255, bb + sb)
      ];
    case PaintBlend.subtract:
      return <int>[
        math.max(0, br - sr),
        math.max(0, bg - sg),
        math.max(0, bb - sb)
      ];
    case PaintBlend.hue:
      return _hslBlend(br, bg, bb, sr, sg, sb, takeH: true, takeS: false, takeL: false);
    case PaintBlend.saturation:
      return _hslBlend(br, bg, bb, sr, sg, sb, takeH: false, takeS: true, takeL: false);
    case PaintBlend.color:
      return _hslBlend(br, bg, bb, sr, sg, sb, takeH: true, takeS: true, takeL: false);
    case PaintBlend.luminosity:
      return _hslBlend(br, bg, bb, sr, sg, sb, takeH: false, takeS: false, takeL: true);
  }
}

int _screen(int b, int s) => 255 - (255 - b) * (255 - s) ~/ 255;
int _overlay(int b, int s) =>
    b < 128 ? (2 * b * s ~/ 255) : 255 - 2 * (255 - b) * (255 - s) ~/ 255;
int _dodge(int b, int s) => s >= 255 ? 255 : math.min(255, b * 255 ~/ (255 - s));
int _burn(int b, int s) => s <= 0 ? 0 : 255 - math.min(255, (255 - b) * 255 ~/ s);
int _excl(int b, int s) => b + s - 2 * b * s ~/ 255;
int _soft(int b, int s) {
  final double bb = b / 255.0, ss = s / 255.0;
  final double r = ss < 0.5
      ? bb - (1 - 2 * ss) * bb * (1 - bb)
      : bb + (2 * ss - 1) * ((bb < 0.25 ? ((16 * bb - 12) * bb + 4) * bb : math.sqrt(bb)) - bb);
  return (r * 255).round().clamp(0, 255);
}

/// HSL "creative" blend: keep some channels from the source, the rest from base.
/// `color` = source hue+sat over base luminosity (the recolour-keeps-shading mode).
List<int> _hslBlend(int br, int bg, int bb, int sr, int sg, int sb,
    {required bool takeH, required bool takeS, required bool takeL}) {
  final List<double> b = _rgb2hsl(br, bg, bb);
  final List<double> s = _rgb2hsl(sr, sg, sb);
  final double h = takeH ? s[0] : b[0];
  final double sat = takeS ? s[1] : b[1];
  final double l = takeL ? s[2] : b[2];
  return _hsl2rgb(h, sat, l);
}

List<double> _rgb2hsl(int r, int g, int b) {
  final double rr = r / 255.0, gg = g / 255.0, bb = b / 255.0;
  final double mx = math.max(rr, math.max(gg, bb));
  final double mn = math.min(rr, math.min(gg, bb));
  double h = 0, s = 0;
  final double l = (mx + mn) / 2;
  final double d = mx - mn;
  if (d != 0) {
    s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
    if (mx == rr) {
      h = (gg - bb) / d + (gg < bb ? 6 : 0);
    } else if (mx == gg) {
      h = (bb - rr) / d + 2;
    } else {
      h = (rr - gg) / d + 4;
    }
    h /= 6;
  }
  return <double>[h, s, l];
}

List<int> _hsl2rgb(double h, double s, double l) {
  double r, g, b;
  if (s == 0) {
    r = g = b = l;
  } else {
    final double q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    final double p = 2 * l - q;
    r = _hue2rgb(p, q, h + 1 / 3);
    g = _hue2rgb(p, q, h);
    b = _hue2rgb(p, q, h - 1 / 3);
  }
  return <int>[
    (r * 255).round().clamp(0, 255),
    (g * 255).round().clamp(0, 255),
    (b * 255).round().clamp(0, 255),
  ];
}

double _hue2rgb(double p, double q, double t) {
  double tt = t;
  if (tt < 0) tt += 1;
  if (tt > 1) tt -= 1;
  if (tt < 1 / 6) return p + (q - p) * 6 * tt;
  if (tt < 1 / 2) return q;
  if (tt < 2 / 3) return p + (q - p) * (2 / 3 - tt) * 6;
  return p;
}

int _lerpArgb(int a, int b, double f) {
  final int aa = (a >> 24) & 0xFF, ar = (a >> 16) & 0xFF, ag = (a >> 8) & 0xFF, ab = a & 0xFF;
  final int ba = (b >> 24) & 0xFF, brr = (b >> 16) & 0xFF, bg = (b >> 8) & 0xFF, bb = b & 0xFF;
  int mix(int x, int y) => (x + (y - x) * f).round().clamp(0, 255);
  return (mix(aa, ba) << 24) | (mix(ar, brr) << 16) | (mix(ag, bg) << 8) | mix(ab, bb);
}

// ---------------------------------------------------------------------------
// Gradient preset catalogue
// ---------------------------------------------------------------------------

/// A big, ready-to-use library of gradients for the editor's preset picker —
/// each can be tweaked (it loads into the editor as a real [PaintGradient]) and
/// new ones [savedGradient]-style persisted by the app. Grouped by category.
class GradientLibrary {
  GradientLibrary._();

  static final List<PaintGradient> presets = _build();

  static List<String> get categories =>
      <String>{for (final PaintGradient g in presets) g.category}.toList();

  static PaintGradient? byName(String name) {
    for (final PaintGradient g in presets) {
      if (g.name == name) return g;
    }
    return null;
  }

  static List<PaintGradient> forCategory(String category) =>
      <PaintGradient>[for (final PaintGradient g in presets) if (g.category == category) g];

  static List<PaintGradient> _build() {
    PaintGradient g(String name, String cat, List<int> colors,
            {GradientType type = GradientType.linear, double angle = 90}) =>
        PaintGradient.fromColors(colors,
            type: type, angle: angle, name: name, category: cat);
    return <PaintGradient>[
      // Fire & warmth
      g('Fire', 'Fire', <int>[0xFF000000, 0xFF7A1F00, 0xFFFF5A00, 0xFFFFD000, 0xFFFFFFC0]),
      g('Ember', 'Fire', <int>[0xFF1A0000, 0xFF8B1A00, 0xFFE25822, 0xFFFFB347]),
      g('Lava', 'Fire', <int>[0xFF2B0A00, 0xFFB22222, 0xFFFF7518, 0xFFFFE066]),
      g('Sunset', 'Fire', <int>[0xFF22223B, 0xFF9A348E, 0xFFEE6C4D, 0xFFFFD166]),
      g('Magma', 'Fire', <int>[0xFF000004, 0xFF3B0F70, 0xFF8C2981, 0xFFDE4968, 0xFFFE9F6D, 0xFFFCFDBF]),
      g('Peach', 'Fire', <int>[0xFFFFE5D9, 0xFFFFB4A2, 0xFFE5989B, 0xFFB5838D]),
      g('Gold', 'Fire', <int>[0xFF6E4B00, 0xFFC9A227, 0xFFFFD700, 0xFFFFF3B0]),
      // Cool & water
      g('Ice', 'Cool', <int>[0xFF001B3A, 0xFF0066AA, 0xFF66CCFF, 0xFFE8FBFF]),
      g('Ocean', 'Cool', <int>[0xFF001219, 0xFF005F73, 0xFF0A9396, 0xFF94D2BD]),
      g('Aqua', 'Cool', <int>[0xFF003B46, 0xFF07575B, 0xFF66A5AD, 0xFFC4DFE6]),
      g('Mint', 'Cool', <int>[0xFF0B3D2E, 0xFF1B998B, 0xFF7DDF64, 0xFFE9FFC2]),
      g('Glacier', 'Cool', <int>[0xFF12343B, 0xFF2D545E, 0xFFC89B7B, 0xFFE1B382]),
      g('Deep Sea', 'Cool', <int>[0xFF000814, 0xFF001D3D, 0xFF003566, 0xFF0077B6, 0xFF48CAE4]),
      // Sky
      g('Dawn', 'Sky', <int>[0xFF2C3E50, 0xFFFD746C, 0xFFFF9068, 0xFFFFE29F]),
      g('Dusk', 'Sky', <int>[0xFF0F2027, 0xFF203A43, 0xFF2C5364]),
      g('Aurora', 'Sky', <int>[0xFF00223E, 0xFF00B894, 0xFF55EFC4, 0xFFA29BFE, 0xFFFF7675]),
      g('Twilight', 'Sky', <int>[0xFF0D1B2A, 0xFF415A77, 0xFF778DA9, 0xFFE0B1CB]),
      g('Clear Sky', 'Sky', <int>[0xFF2980B9, 0xFF6DD5FA, 0xFFFFFFFF]),
      // Neon & vivid
      g('Neon Pink', 'Neon', <int>[0xFF120458, 0xFFB5179E, 0xFFFF006E, 0xFFFFBE0B]),
      g('Vaporwave', 'Neon', <int>[0xFF2B0F54, 0xFFFF4D9D, 0xFF4DE2FF]),
      g('Cyberpunk', 'Neon', <int>[0xFF0D0221, 0xFF2D00F7, 0xFFF20089, 0xFFFFD60A]),
      g('Synthwave', 'Neon', <int>[0xFF1A1A2E, 0xFFE94560, 0xFFFF2E63, 0xFFFFD460]),
      g('Toxic', 'Neon', <int>[0xFF071A00, 0xFF2E7D00, 0xFF8FE000, 0xFFE8FFB0]),
      g('Rainbow', 'Neon', <int>[
        0xFFFF0000, 0xFFFFA500, 0xFFFFFF00, 0xFF00FF00, 0xFF00FFFF, 0xFF0000FF, 0xFFFF00FF,
      ], type: GradientType.conic),
      // Pastel
      g('Cotton Candy', 'Pastel', <int>[0xFFFFC6FF, 0xFFBDB2FF, 0xFFA0C4FF, 0xFF9BF6FF]),
      g('Bubblegum', 'Pastel', <int>[0xFFFFADAD, 0xFFFFD6A5, 0xFFFDFFB6, 0xFFCAFFBF]),
      g('Lavender', 'Pastel', <int>[0xFFE0C3FC, 0xFF8EC5FC]),
      g('Sherbet', 'Pastel', <int>[0xFFFFE0AC, 0xFFFFACAC, 0xFFFFC8DD, 0xFFCDB4DB]),
      // Metal
      g('Steel', 'Metal', <int>[0xFF232526, 0xFF7B7F83, 0xFFE6E9EC, 0xFF7B7F83]),
      g('Chrome', 'Metal', <int>[0xFF4B6CB7, 0xFF182848, 0xFFB0C4DE, 0xFFFFFFFF],
          type: GradientType.reflected),
      g('Bronze', 'Metal', <int>[0xFF3E2723, 0xFF8D6E63, 0xFFCD7F32, 0xFFFFE0B2]),
      g('Copper', 'Metal', <int>[0xFF4A2511, 0xFFB87333, 0xFFDA8A67, 0xFFFFD9B3]),
      // Character helpers
      g('Skin Light', 'Character', <int>[0xFFC68642, 0xFFE0AC69, 0xFFF1C27D, 0xFFFFE0BD]),
      g('Skin Deep', 'Character', <int>[0xFF3B2219, 0xFF6B4226, 0xFF8D5524, 0xFFC68642]),
      g('Blonde', 'Character', <int>[0xFF7A5C00, 0xFFC9A227, 0xFFEED98C, 0xFFFFF6CC]),
      g('Brunette', 'Character', <int>[0xFF1C0F08, 0xFF3B2417, 0xFF6A4E42, 0xFFB08D57]),
      g('Crimson Hair', 'Character', <int>[0xFF2B0000, 0xFF8B0000, 0xFFD7263D, 0xFFFF6B6B]),
      g('Blue Hair', 'Character', <int>[0xFF03045E, 0xFF0077B6, 0xFF00B4D8, 0xFF90E0EF]),
      // Neutral / utility
      g('Mono', 'Neutral', <int>[0xFF000000, 0xFFFFFFFF]),
      g('Sepia', 'Neutral', <int>[0xFF2B1B0E, 0xFF8A6A45, 0xFFE8D5B0]),
      g('Shadow', 'Neutral', <int>[0x00000000, 0xCC000000], type: GradientType.radial),
      g('Spotlight', 'Neutral', <int>[0x66FFFFFF, 0x00FFFFFF], type: GradientType.radial),
      g('Fade Out', 'Neutral', <int>[0xFFFFFFFF, 0x00FFFFFF]),
    ];
  }
}
