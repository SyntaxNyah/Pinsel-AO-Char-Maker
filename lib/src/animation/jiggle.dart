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
  /// chest-physics look — instead of one block. See [toRecipes].
  final bool twin;

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
      );

  /// Build the [AnimEngine] recipe for an image of [imgW]×[imgH] px. The region
  /// is converted to pixels here, and [amplitude] (a fraction of the region
  /// height) becomes the pixel travel — so the preview (downscaled) and the
  /// export (full-res) bounce by the same *relative* amount.
  AnimRecipe toRecipe(int imgW, int imgH) {
    final int rx = (x * imgW).round().clamp(0, imgW);
    final int ry = (y * imgH).round().clamp(0, imgH);
    final int rw = math.max(1, (w * imgW).round());
    final int rh = math.max(1, (h * imgH).round());
    return AnimRecipe(
      'jigglePhysics',
      region: IntRect(rx, ry, rw, rh),
      p: <String, double>{
        'amplitude': amplitude * rh,
        'frequency': frequency.toDouble(),
        'bounciness': bounciness,
        'squash': squash,
        'sway': sway,
        'direction': direction,
        'phase': phase,
      },
    );
  }

  /// Build the [AnimEngine] recipe(s) for an image of [imgW]x[imgH] px. Normally
  /// just one (= [toRecipe]); when [twin] the drawn box is split into a **left +
  /// right lobe** (with a small cleavage gap) that bounce in **opposite phase**,
  /// which reads as two breasts rather than one rigid block. Each lobe is a
  /// plain (non-twin) [JiggleSpec] so it goes through the normal warp path.
  List<AnimRecipe> toRecipes(int imgW, int imgH) {
    if (!twin) return <AnimRecipe>[toRecipe(imgW, imgH)];
    const double gap = 0.10; // fraction of the box width left clear in the middle
    final double lobeW = math.max(0.02, w * (1 - gap) / 2.0);
    final JiggleSpec left = copyWith(twin: false, w: lobeW);
    final JiggleSpec right = copyWith(
      twin: false,
      x: x + w - lobeW,
      w: lobeW,
      phase: (phase + 0.5) % 1.0,
    );
    return <AnimRecipe>[
      left.toRecipe(imgW, imgH),
      right.toRecipe(imgW, imgH),
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
    // Bust (boobs): twin lobes over the chest that bounce out of phase. Listed
    // first so the picker leads with the headline "anime jiggle" look.
    JiggleSpec(name: 'Bust', category: 'Bust', x: 0.28, y: 0.34, w: 0.44, h: 0.20, amplitude: 0.16, frequency: 2, bounciness: 0.55, squash: 0.6, sway: 2, twin: true),
    JiggleSpec(name: 'Bust Big', category: 'Bust', x: 0.25, y: 0.34, w: 0.50, h: 0.22, amplitude: 0.26, frequency: 2, bounciness: 0.7, squash: 0.72, sway: 3, twin: true),
    JiggleSpec(name: 'Bust Jelly', category: 'Bust', x: 0.27, y: 0.34, w: 0.46, h: 0.20, amplitude: 0.22, frequency: 3, bounciness: 0.9, squash: 0.85, sway: 4, twin: true),
    JiggleSpec(name: 'Bust Soft', category: 'Bust', x: 0.28, y: 0.35, w: 0.44, h: 0.18, amplitude: 0.11, frequency: 2, bounciness: 0.4, squash: 0.5, sway: 1, twin: true),
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
