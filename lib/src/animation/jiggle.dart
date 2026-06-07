import 'dart:math' as math;

import '../imaging/button_maker.dart' show IntRect;
import 'anim_engine.dart';

/// A **jiggle region** + its physics knobs. Pick a box on the sprite (chest,
/// hair, belly, anything) and tune how it bounces. Everything is in **fractions**
/// of the sprite (so the same spec works on the downscaled preview and the
/// full-res bake) and is plain data, so a spec JSON-round-trips and rides into a
/// background isolate for bulk baking.
///
/// It renders by becoming an [AnimEngine] `jigglePhysics` recipe on this region
/// (see [toRecipe]/[toRecipes]), which `AnimEngine.render` deforms with a
/// **per-pixel soft-body warp** (`AnimEngine.warpJiggle`) — the flesh stretches
/// continuously and joins the static body seamlessly, instead of a cut-out
/// rectangle sliding around. The motion is a **looping oscillation tuned to feel
/// springy**, not an impulse/settle physics sim (a true damped spring wouldn't
/// loop cleanly), so keep [frequency] a whole number for a seamless loop. Set
/// [twin] for two opposite-phase lobes (the two-breast look).
class JiggleSpec {
  const JiggleSpec({
    this.name = 'Jiggle',
    this.category = 'General',
    this.x = 0.30,
    this.y = 0.33,
    this.w = 0.40,
    this.h = 0.18,
    this.amplitude = 0.15,
    this.frequency = 2,
    this.bounciness = 0.5,
    this.squash = 0.5,
    this.sway = 0.0,
    this.direction = 0.0,
    this.phase = 0.0,
    this.twin = false,
    this.anchor = 0.0,
    this.gravity = 0.0,
    this.organic = 0.0,
    this.followThrough = 0.0,
    this.lobes = 1,
    this.spread = 0.5,
    this.poly = const <double>[],
    this.crossAmount = 0.0,
    this.swirl = 0.0,
    this.pulse = 0.0,
  });

  /// Preset name (unique within [jigglePresets]).
  final String name;

  /// Picker grouping.
  final String category;

  /// Region as fractions of the sprite (top-left [x],[y]; size [w],[h]).
  final double x, y, w, h;

  /// Peak travel of the free end as a fraction of the **region height** (the
  /// soft-body warp stretches the flesh continuously, so larger values stay
  /// seamless — they just swing further).
  final double amplitude;

  /// Bounces per loop — keep a whole number so the clip loops seamlessly.
  final int frequency;

  /// 0..1 — how much overshoot ("spring") rides on top of the base bounce.
  final double bounciness;

  /// 0..1 — squash-&-stretch coupled to velocity (the bread-and-butter of jiggle).
  final double squash;

  /// Rotation sway in degrees (a sideways wobble).
  final double sway;

  /// The **angle** (degrees) the bounce travels along: 0 = up/down (default),
  /// 90 = left/right, anything in between = diagonal — so you can make a region
  /// jiggle in *any* direction.
  final double direction;

  /// 0..1 phase offset, so two regions can bounce out of sync.
  final double phase;

  /// **Twin lobes** (boobs): when true the drawn box is split down the middle
  /// into a left + right lobe that bounce in **opposite phase** — the gacha
  /// chest-physics look — instead of one block. Shorthand for [lobes] = 2. See
  /// [toRecipes].
  final bool twin;

  /// Where the **pinned point** sits along the travel axis: 0 = trailing/top
  /// pinned (the boob "hang", default), 1 = leading pinned, 0.5 = centre pinned
  /// (both ends swing). 0 reproduces the original motion.
  final double anchor;

  /// 0..1 — **asymmetric gravity**: a heavier, quicker fall and a gentler rise
  /// (weighty flesh) instead of a symmetric sine. 0 = symmetric (original).
  final double gravity;

  /// 0..1 — **organic** variation: a higher harmonic so the motion reads natural
  /// rather than a perfect robotic sine. 0 = pure (original).
  final double organic;

  /// 0..1 — **follow-through**: the swinging end lags the pin so the jiggle
  /// travels through the flesh as a wave (soft-body realism). 0 = rigid (orig).
  final double followThrough;

  /// Number of side-by-side **lobes** to split the box into (1 = one region).
  /// >1 generalises [twin] (which is lobes = 2); each lobe is phase-offset by
  /// [spread] so they bounce out of sync. See [toRecipes].
  final int lobes;

  /// 0..1 — phase offset between consecutive [lobes] (0.5 = exactly opposite,
  /// the natural two-breast look).
  final double spread;

  /// **Freeform outline** (flattened `[x0,y0, x1,y1, …]` as fractions 0..1) — the
  /// "draw around" lasso. When it has ≥ 3 points the jiggle masks to this exact
  /// shape (inside + a soft edge) instead of the [x]/[y]/[w]/[h] box, and lobe
  /// splitting is skipped (it's one drawn region). Empty = use the box.
  final List<double> poly;

  /// 0..1 — **cross-bounce**: a perpendicular wobble 90° out of phase with the
  /// main bounce so the tip traces an **ellipse**, not a straight line (the
  /// natural "moves in a little circle" look). 0 = pure up/down.
  final double crossAmount;

  /// degrees — **swirl**: a small back-and-forth **rotation** of the region about
  /// its centre on top of the bounce. 0 = none.
  final double swirl;

  /// 0..1 — **pulse**: the whole jiggle **swells then fades** once per loop (a
  /// breathing intensity) instead of a constant strength. 0 = steady.
  final double pulse;

  JiggleSpec copyWith({
    String? name,
    String? category,
    double? x,
    double? y,
    double? w,
    double? h,
    double? amplitude,
    int? frequency,
    double? bounciness,
    double? squash,
    double? sway,
    double? direction,
    double? phase,
    bool? twin,
    double? anchor,
    double? gravity,
    double? organic,
    double? followThrough,
    int? lobes,
    double? spread,
    List<double>? poly,
    double? crossAmount,
    double? swirl,
    double? pulse,
  }) =>
      JiggleSpec(
        name: name ?? this.name,
        category: category ?? this.category,
        x: x ?? this.x,
        y: y ?? this.y,
        w: w ?? this.w,
        h: h ?? this.h,
        amplitude: amplitude ?? this.amplitude,
        frequency: frequency ?? this.frequency,
        bounciness: bounciness ?? this.bounciness,
        squash: squash ?? this.squash,
        sway: sway ?? this.sway,
        direction: direction ?? this.direction,
        phase: phase ?? this.phase,
        twin: twin ?? this.twin,
        anchor: anchor ?? this.anchor,
        gravity: gravity ?? this.gravity,
        organic: organic ?? this.organic,
        followThrough: followThrough ?? this.followThrough,
        lobes: lobes ?? this.lobes,
        spread: spread ?? this.spread,
        poly: poly ?? this.poly,
        crossAmount: crossAmount ?? this.crossAmount,
        swirl: swirl ?? this.swirl,
        pulse: pulse ?? this.pulse,
      );

  /// Build the [AnimEngine] recipe for an image of [imgW]×[imgH] px. The region
  /// is converted to pixels here, and [amplitude] (a fraction of the region
  /// height) becomes the pixel travel — so the preview (downscaled) and the
  /// export (full-res) bounce by the same *relative* amount.
  AnimRecipe toRecipe(int imgW, int imgH) {
    int rx, ry, rw, rh;
    List<double>? polyPx;
    if (poly.length >= 6) {
      // Freeform: region = the drawn polygon's bounding box; carry the polygon
      // (in px) so the warp masks to the actual shape.
      double minx = 1, miny = 1, maxx = 0, maxy = 0;
      for (int i = 0; i + 1 < poly.length; i += 2) {
        if (poly[i] < minx) minx = poly[i];
        if (poly[i] > maxx) maxx = poly[i];
        if (poly[i + 1] < miny) miny = poly[i + 1];
        if (poly[i + 1] > maxy) maxy = poly[i + 1];
      }
      rx = (minx * imgW).round().clamp(0, imgW);
      ry = (miny * imgH).round().clamp(0, imgH);
      rw = math.max(1, ((maxx - minx) * imgW).round());
      rh = math.max(1, ((maxy - miny) * imgH).round());
      polyPx = <double>[
        for (int i = 0; i + 1 < poly.length; i += 2) ...<double>[
          poly[i] * imgW,
          poly[i + 1] * imgH,
        ],
      ];
    } else {
      rx = (x * imgW).round().clamp(0, imgW);
      ry = (y * imgH).round().clamp(0, imgH);
      rw = math.max(1, (w * imgW).round());
      rh = math.max(1, (h * imgH).round());
    }
    return AnimRecipe(
      'jigglePhysics',
      region: IntRect(rx, ry, rw, rh),
      poly: polyPx,
      p: <String, double>{
        'amplitude': amplitude * rh,
        'frequency': frequency.toDouble(),
        'bounciness': bounciness,
        'squash': squash,
        'sway': sway,
        'direction': direction,
        'phase': phase,
        'anchor': anchor,
        'gravity': gravity,
        'organic': organic,
        'followThrough': followThrough,
        'crossAmount': crossAmount,
        'swirl': swirl,
        'pulse': pulse,
      },
    );
  }

  /// Build the [AnimEngine] recipe(s) for an image of [imgW]x[imgH] px. Normally
  /// just one (= [toRecipe]); when [twin] the drawn box is split into a **left +
  /// right lobe** (with a small cleavage gap) that bounce in **opposite phase**,
  /// which reads as two breasts rather than one rigid block. Each lobe is a
  /// plain (non-twin) [JiggleSpec] so it goes through the normal warp path.
  List<AnimRecipe> toRecipes(int imgW, int imgH) {
    // A freeform drawn region is one shape — never split it into lobes.
    if (poly.length >= 6) return <AnimRecipe>[toRecipe(imgW, imgH)];
    final int n = lobes > 1 ? lobes : (twin ? 2 : 1);
    if (n <= 1) return <AnimRecipe>[toRecipe(imgW, imgH)];
    const double gap = 0.10; // fraction of the box width kept clear between lobes
    final double lobeW = math.max(0.02, w * (1 - gap) / n);
    final double step = (w - lobeW) / (n - 1);
    return <AnimRecipe>[
      for (int i = 0; i < n; i++)
        copyWith(
          twin: false,
          lobes: 1,
          x: x + step * i,
          w: lobeW,
          phase: (phase + spread * i) % 1.0,
        ).toRecipe(imgW, imgH),
    ];
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'category': category,
        'x': x, 'y': y, 'w': w, 'h': h,
        'amplitude': amplitude,
        'frequency': frequency,
        'bounciness': bounciness,
        'squash': squash,
        'sway': sway,
        'direction': direction,
        'phase': phase,
        'twin': twin,
        'anchor': anchor,
        'gravity': gravity,
        'organic': organic,
        'followThrough': followThrough,
        'lobes': lobes,
        'spread': spread,
        if (poly.isNotEmpty) 'poly': poly,
        'crossAmount': crossAmount,
        'swirl': swirl,
        'pulse': pulse,
      };

  static JiggleSpec fromJson(Map<String, Object?> m) => JiggleSpec(
        name: (m['name'] as String?) ?? 'Jiggle',
        category: (m['category'] as String?) ?? 'General',
        x: (m['x'] as num?)?.toDouble() ?? 0.30,
        y: (m['y'] as num?)?.toDouble() ?? 0.33,
        w: (m['w'] as num?)?.toDouble() ?? 0.40,
        h: (m['h'] as num?)?.toDouble() ?? 0.18,
        amplitude: (m['amplitude'] as num?)?.toDouble() ?? 0.15,
        frequency: (m['frequency'] as num?)?.toInt() ?? 2,
        bounciness: (m['bounciness'] as num?)?.toDouble() ?? 0.5,
        squash: (m['squash'] as num?)?.toDouble() ?? 0.5,
        sway: (m['sway'] as num?)?.toDouble() ?? 0.0,
        direction: (m['direction'] as num?)?.toDouble() ?? 0.0,
        phase: (m['phase'] as num?)?.toDouble() ?? 0.0,
        twin: (m['twin'] as bool?) ?? false,
        anchor: (m['anchor'] as num?)?.toDouble() ?? 0.0,
        gravity: (m['gravity'] as num?)?.toDouble() ?? 0.0,
        organic: (m['organic'] as num?)?.toDouble() ?? 0.0,
        followThrough: (m['followThrough'] as num?)?.toDouble() ?? 0.0,
        lobes: (m['lobes'] as num?)?.toInt() ?? 1,
        spread: (m['spread'] as num?)?.toDouble() ?? 0.5,
        poly: (m['poly'] as List?)
                ?.map((Object? v) => (v as num).toDouble())
                .toList() ??
            const <double>[],
        crossAmount: (m['crossAmount'] as num?)?.toDouble() ?? 0.0,
        swirl: (m['swirl'] as num?)?.toDouble() ?? 0.0,
        pulse: (m['pulse'] as num?)?.toDouble() ?? 0.0,
      );
}

/// Hundreds of jiggle presets — every "feel" archetype × intensity/speed
/// variant. They keep the default chest-ish region; you drag the box where you
/// want it. Generated once, deterministically.
final List<JiggleSpec> jigglePresets = _buildJigglePresets();

/// The catalogue's category names in order (for grouped pickers).
List<String> get jiggleCategories {
  final List<String> out = <String>[];
  for (final JiggleSpec j in jigglePresets) {
    if (!out.contains(j.category)) out.add(j.category);
  }
  return out;
}

JiggleSpec jiggleByName(String? name) {
  if (name != null) {
    for (final JiggleSpec j in jigglePresets) {
      if (j.name == name) return j;
    }
  }
  return jigglePresets.isEmpty ? const JiggleSpec() : jigglePresets.first;
}

List<JiggleSpec> _buildJigglePresets() {
  // (name, category, amplitude, frequency, bounciness, squash, sway, direction)
  const List<JiggleSpec> archetypes = <JiggleSpec>[
    // Bust (boobs): twin lobes over the chest, bouncing out of phase, with the
    // soft-body realism knobs (weighty gravity, organic harmonic, follow-through
    // wave) dialed in so they read like pro animation. Listed first.
    JiggleSpec(name: 'Bust Realistic', category: 'Bust', x: 0.27, y: 0.34, w: 0.46, h: 0.21, amplitude: 0.18, frequency: 2, bounciness: 0.62, squash: 0.7, sway: 3, twin: true, gravity: 0.5, organic: 0.4, followThrough: 0.65),
    JiggleSpec(name: 'Bust', category: 'Bust', x: 0.28, y: 0.34, w: 0.44, h: 0.20, amplitude: 0.16, frequency: 2, bounciness: 0.58, squash: 0.62, sway: 2, twin: true, gravity: 0.35, organic: 0.3, followThrough: 0.5),
    JiggleSpec(name: 'Bust Big', category: 'Bust', x: 0.25, y: 0.34, w: 0.50, h: 0.22, amplitude: 0.27, frequency: 2, bounciness: 0.72, squash: 0.74, sway: 3, twin: true, gravity: 0.45, organic: 0.35, followThrough: 0.55),
    JiggleSpec(name: 'Bust Jelly', category: 'Bust', x: 0.27, y: 0.34, w: 0.46, h: 0.20, amplitude: 0.22, frequency: 3, bounciness: 0.9, squash: 0.85, sway: 4, twin: true, gravity: 0.25, organic: 0.45, followThrough: 0.7),
    JiggleSpec(name: 'Bust Soft', category: 'Bust', x: 0.28, y: 0.35, w: 0.44, h: 0.18, amplitude: 0.11, frequency: 2, bounciness: 0.42, squash: 0.52, sway: 1, twin: true, gravity: 0.25, organic: 0.25, followThrough: 0.4),
    JiggleSpec(name: 'Natural', category: 'Soft', amplitude: 0.14, frequency: 2, bounciness: 0.45, squash: 0.5, sway: 0),
    JiggleSpec(name: 'Subtle', category: 'Soft', amplitude: 0.08, frequency: 2, bounciness: 0.3, squash: 0.35, sway: 0),
    JiggleSpec(name: 'Gentle', category: 'Soft', amplitude: 0.11, frequency: 2, bounciness: 0.4, squash: 0.45, sway: 0),
    JiggleSpec(name: 'Breathe', category: 'Soft', amplitude: 0.06, frequency: 1, bounciness: 0.2, squash: 0.6, sway: 0),
    JiggleSpec(name: 'Bouncy', category: 'Bounce', amplitude: 0.22, frequency: 3, bounciness: 0.7, squash: 0.6, sway: 0),
    JiggleSpec(name: 'Heavy', category: 'Bounce', amplitude: 0.26, frequency: 2, bounciness: 0.55, squash: 0.7, sway: 0),
    JiggleSpec(name: 'Big Bounce', category: 'Bounce', amplitude: 0.34, frequency: 2, bounciness: 0.75, squash: 0.75, sway: 0),
    JiggleSpec(name: 'Perky', category: 'Bounce', amplitude: 0.18, frequency: 4, bounciness: 0.8, squash: 0.55, sway: 0),
    JiggleSpec(name: 'Jelly', category: 'Jelly', amplitude: 0.2, frequency: 3, bounciness: 0.9, squash: 0.85, sway: 3),
    JiggleSpec(name: 'Wobble', category: 'Jelly', amplitude: 0.16, frequency: 3, bounciness: 0.85, squash: 0.7, sway: 5),
    JiggleSpec(name: 'Floppy', category: 'Jelly', amplitude: 0.28, frequency: 2, bounciness: 0.95, squash: 0.9, sway: 4),
    JiggleSpec(name: 'Pendulum', category: 'Sway', amplitude: 0.12, frequency: 1, bounciness: 0.3, squash: 0.3, sway: 8, direction: 90),
    JiggleSpec(name: 'Sway', category: 'Sway', amplitude: 0.1, frequency: 2, bounciness: 0.35, squash: 0.3, sway: 6, direction: 90),
    JiggleSpec(name: 'Sideways', category: 'Sway', amplitude: 0.16, frequency: 2, bounciness: 0.5, squash: 0.4, sway: 0, direction: 90),
    JiggleSpec(name: 'Earthquake', category: 'Wild', amplitude: 0.3, frequency: 6, bounciness: 0.4, squash: 0.5, sway: 2, direction: 45),
    JiggleSpec(name: 'Rapid', category: 'Wild', amplitude: 0.12, frequency: 6, bounciness: 0.6, squash: 0.5, sway: 0),
    // Physics showcases — the new realism knobs (gravity / follow-through /
    // multi-lobe / centre-pin).
    JiggleSpec(name: 'Gravity Drop', category: 'Physics', amplitude: 0.24, frequency: 2, bounciness: 0.5, squash: 0.65, sway: 1, gravity: 0.8, followThrough: 0.4),
    JiggleSpec(name: 'Wave', category: 'Physics', amplitude: 0.2, frequency: 2, bounciness: 0.7, squash: 0.7, sway: 2, followThrough: 0.85, organic: 0.3),
    JiggleSpec(name: 'Organic', category: 'Physics', amplitude: 0.16, frequency: 2, bounciness: 0.55, squash: 0.6, sway: 2, organic: 0.7, gravity: 0.3),
    JiggleSpec(name: 'Free Float', category: 'Physics', amplitude: 0.14, frequency: 2, bounciness: 0.5, squash: 0.55, sway: 3, anchor: 0.5, followThrough: 0.3),
    JiggleSpec(name: 'Triple', category: 'Physics', amplitude: 0.16, frequency: 2, bounciness: 0.6, squash: 0.6, sway: 2, lobes: 3, spread: 0.33, gravity: 0.3, followThrough: 0.4),
    JiggleSpec(name: 'Quad', category: 'Physics', amplitude: 0.14, frequency: 2, bounciness: 0.6, squash: 0.6, sway: 2, lobes: 4, spread: 0.25, gravity: 0.3, followThrough: 0.4),
    // Lifelike — realism knobs dialed for natural, weighty, non-mechanical motion
    // (zero extra cost: just different parameter mixes of the same warp).
    JiggleSpec(name: 'Heave', category: 'Lifelike', amplitude: 0.2, frequency: 1, bounciness: 0.5, squash: 0.65, sway: 2, gravity: 0.7, organic: 0.4, followThrough: 0.6, twin: true, x: 0.27, y: 0.34, w: 0.46, h: 0.21),
    JiggleSpec(name: 'Sultry', category: 'Lifelike', amplitude: 0.16, frequency: 1, bounciness: 0.6, squash: 0.7, sway: 3, gravity: 0.5, organic: 0.5, followThrough: 0.8, twin: true, x: 0.27, y: 0.34, w: 0.46, h: 0.21),
    JiggleSpec(name: 'Quiver', category: 'Lifelike', amplitude: 0.08, frequency: 5, bounciness: 0.5, squash: 0.5, sway: 1, organic: 0.55, followThrough: 0.4),
    JiggleSpec(name: 'Sashay', category: 'Lifelike', amplitude: 0.14, frequency: 2, bounciness: 0.45, squash: 0.5, sway: 8, direction: 90, gravity: 0.3, followThrough: 0.5),
    JiggleSpec(name: 'Drop Settle', category: 'Lifelike', amplitude: 0.24, frequency: 2, bounciness: 0.72, squash: 0.7, sway: 2, gravity: 0.85, organic: 0.3, followThrough: 0.7, twin: true, x: 0.26, y: 0.34, w: 0.48, h: 0.22),
    JiggleSpec(name: 'Flutter', category: 'Lifelike', amplitude: 0.1, frequency: 4, bounciness: 0.6, squash: 0.55, sway: 2, organic: 0.45, followThrough: 0.5),
    JiggleSpec(name: 'Pillowy', category: 'Lifelike', amplitude: 0.18, frequency: 2, bounciness: 0.85, squash: 0.8, sway: 3, gravity: 0.4, organic: 0.5, followThrough: 0.75, twin: true, x: 0.26, y: 0.34, w: 0.48, h: 0.22),
    // Motion — showcases the new ways of moving (circular / swirl / pulse).
    JiggleSpec(name: 'Circular', category: 'Motion', amplitude: 0.16, frequency: 2, bounciness: 0.55, squash: 0.6, sway: 2, crossAmount: 0.7, gravity: 0.3, followThrough: 0.5, twin: true, x: 0.27, y: 0.34, w: 0.46, h: 0.21),
    JiggleSpec(name: 'Swirl', category: 'Motion', amplitude: 0.14, frequency: 2, bounciness: 0.5, squash: 0.55, sway: 2, swirl: 10, gravity: 0.3, followThrough: 0.4),
    JiggleSpec(name: 'Pulse', category: 'Motion', amplitude: 0.16, frequency: 2, bounciness: 0.6, squash: 0.6, sway: 2, pulse: 0.7, gravity: 0.3, followThrough: 0.5),
    JiggleSpec(name: 'Orbit', category: 'Motion', amplitude: 0.15, frequency: 2, bounciness: 0.5, squash: 0.55, sway: 3, crossAmount: 0.85, swirl: 6, gravity: 0.3, followThrough: 0.5, twin: true, x: 0.27, y: 0.34, w: 0.46, h: 0.21),
    JiggleSpec(name: 'Hypnotic', category: 'Motion', amplitude: 0.14, frequency: 1, bounciness: 0.6, squash: 0.6, sway: 4, crossAmount: 0.6, swirl: 8, pulse: 0.5, gravity: 0.3, followThrough: 0.6, twin: true, x: 0.27, y: 0.34, w: 0.46, h: 0.21),
  ];
  // (suffix, ampMul, freqDelta, bounceMul, squashMul, swayMul)
  const List<(String, double, int, double, double, double)> mods =
      <(String, double, int, double, double, double)>[
    ('', 1.0, 0, 1.0, 1.0, 1.0),
    ('Soft', 0.6, 0, 0.8, 0.9, 0.7),
    ('Big', 1.7, 0, 1.1, 1.1, 1.2),
    ('Fast', 1.0, 2, 1.1, 1.0, 1.0),
    ('Slow', 1.0, -1, 0.9, 1.0, 1.0),
    ('Springy', 1.1, 0, 1.4, 1.0, 1.0),
    ('Extreme', 2.1, 1, 1.3, 1.3, 1.4),
  ];
  final List<JiggleSpec> out = <JiggleSpec>[];
  for (final JiggleSpec a in archetypes) {
    for (final (String, double, int, double, double, double) m in mods) {
      out.add(a.copyWith(
        name: m.$1.isEmpty ? a.name : '${a.name} (${m.$1})',
        amplitude: (a.amplitude * m.$2).clamp(0.02, 0.7),
        frequency: (a.frequency + m.$3).clamp(1, 8),
        bounciness: (a.bounciness * m.$4).clamp(0.0, 1.0),
        squash: (a.squash * m.$5).clamp(0.0, 1.0),
        sway: (a.sway * m.$6).clamp(0.0, 20.0),
      ));
    }
  }
  return out;
}
