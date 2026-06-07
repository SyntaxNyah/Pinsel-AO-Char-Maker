import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pinsel/src/animation/anim_clip.dart';
import 'package:pinsel/src/animation/anim_engine.dart';
import 'package:pinsel/src/animation/jiggle.dart';

img.Image _sprite() {
  final img.Image im = img.Image(width: 40, height: 60, numChannels: 4);
  for (int y = 5; y < 55; y++) {
    for (int x = 12; x < 28; x++) {
      im.setPixelRgba(x, y, 200, 150, 120, 255);
    }
  }
  return im;
}

void main() {
  test('jiggle preset catalogue is large with unique names', () {
    expect(jigglePresets.length, greaterThanOrEqualTo(80));
    expect(jigglePresets.map((JiggleSpec j) => j.name).toSet().length,
        jigglePresets.length);
    expect(jiggleCategories.length, greaterThanOrEqualTo(4));
  });

  test('jigglePhysics is a registered animation recipe', () {
    expect(AnimEngine.recipeTypes, contains('jigglePhysics'));
  });

  test('toRecipe yields a jigglePhysics recipe with a pixel region', () {
    const JiggleSpec j = JiggleSpec(x: 0.3, y: 0.3, w: 0.4, h: 0.2);
    final AnimRecipe r = j.toRecipe(100, 200);
    expect(r.type, 'jigglePhysics');
    expect(r.region, isNotNull);
    expect(r.region!.x, 30);
    expect(r.region!.w, 40);
    expect(r.p['frequency'], isNotNull);
    expect(r.p['direction'], isNotNull);
  });

  test('rendering a jiggle produces same-size frames', () {
    final img.Image base = _sprite();
    final AnimClip clip = AnimEngine.render(
      base,
      <AnimRecipe>[const JiggleSpec().toRecipe(base.width, base.height)],
      frames: 8,
      fps: 12,
    );
    expect(clip.frames.length, 8);
    for (final AnimFrame f in clip.frames) {
      expect(f.image.width, base.width);
      expect(f.image.height, base.height);
    }
  });

  test('JiggleSpec JSON round-trips (incl. direction + twin)', () {
    final JiggleSpec j = jiggleByName('Bouncy');
    final JiggleSpec back = JiggleSpec.fromJson(j.toJson());
    expect(back.name, j.name);
    expect(back.amplitude, closeTo(j.amplitude, 1e-9));
    expect(back.frequency, j.frequency);
    expect(back.direction, closeTo(j.direction, 1e-9));
    final JiggleSpec bust = jiggleByName('Bust');
    expect(JiggleSpec.fromJson(bust.toJson()).twin, bust.twin);
  });

  // The warp is a *visual* effect that can't be eyeballed in CI, so these pin
  // the invariants that distinguish a real soft-body jiggle from the old
  // sliding-rectangle: seamless edges, actual motion, a clean loop, no blanking.

  AnimRecipe _strongRecipe() =>
      // A deliberately violent spec — and it exercises every new realism knob,
      // so the seam/motion/loop invariants below also guard gravity/organic/
      // follow-through/anchor (a non-periodic term would trip the loop test).
      const JiggleSpec(
              amplitude: 0.5,
              squash: 1.0,
              sway: 12,
              gravity: 0.8,
              organic: 0.7,
              followThrough: 0.8,
              anchor: 0.3)
          .toRecipe(_sprite().width, _sprite().height);

  test('warpJiggle preserves size and leaves the body outside the region '
      'untouched (seamless join)', () {
    final img.Image base = _sprite(); // 40x60; chest box is well inside it
    final AnimRecipe r = _strongRecipe();
    const List<List<int>> corners = <List<int>>[
      <int>[0, 0],
      <int>[39, 0],
      <int>[0, 59],
      <int>[39, 59],
    ];
    for (final double t in <double>[0.0, 0.25, 0.5, 0.75]) {
      final img.Image f = AnimEngine.warpJiggle(base, r, t);
      expect(f.width, base.width);
      expect(f.height, base.height);
      for (final List<int> c in corners) {
        final img.Pixel a = base.getPixel(c[0], c[1]);
        final img.Pixel b = f.getPixel(c[0], c[1]);
        expect(<num>[b.r, b.g, b.b, b.a], <num>[a.r, a.g, a.b, a.a],
            reason: 'corner ${c} changed at t=$t — warp leaked past its region');
      }
    }
  });

  test('warpJiggle actually deforms the region across the loop', () {
    final img.Image base = _sprite();
    final AnimRecipe r = _strongRecipe();
    final img.Image f0 = AnimEngine.warpJiggle(base, r, 0.0);
    final img.Image fm = AnimEngine.warpJiggle(base, r, 0.3);
    int diff = 0;
    for (int y = 0; y < base.height; y++) {
      for (int x = 0; x < base.width; x++) {
        final img.Pixel p0 = f0.getPixel(x, y);
        final img.Pixel pm = fm.getPixel(x, y);
        if (p0.r != pm.r || p0.g != pm.g || p0.b != pm.b || p0.a != pm.a) {
          diff++;
        }
      }
    }
    expect(diff, greaterThan(0), reason: 'warp produced no motion');
  });

  test('warpJiggle loops seamlessly (t=0 ~= t=1 for integer frequency)', () {
    // Periodic oscillators ⇒ phase 0 and 1 are the same instant. Allow ≤1 LSB
    // for float rounding; a real non-periodic seam would differ by hundreds.
    final img.Image base = _sprite();
    final AnimRecipe r = _strongRecipe();
    final img.Image f0 = AnimEngine.warpJiggle(base, r, 0.0);
    final img.Image f1 = AnimEngine.warpJiggle(base, r, 1.0);
    int big = 0;
    for (int y = 0; y < base.height; y++) {
      for (int x = 0; x < base.width; x++) {
        final img.Pixel p0 = f0.getPixel(x, y);
        final img.Pixel p1 = f1.getPixel(x, y);
        if ((p1.r - p0.r).abs() > 1 ||
            (p1.g - p0.g).abs() > 1 ||
            (p1.b - p0.b).abs() > 1 ||
            (p1.a - p0.a).abs() > 1) {
          big++;
        }
      }
    }
    expect(big, 0, reason: 'loop is not seamless — $big pixels jump at the wrap');
  });

  test('warpJiggle keeps the sprite visible (never blanks/NaNs it out)', () {
    final img.Image base = _sprite();
    final img.Image f = AnimEngine.warpJiggle(base, _strongRecipe(), 0.4);
    int opaque = 0;
    for (int y = 0; y < base.height; y++) {
      for (int x = 0; x < base.width; x++) {
        if (f.getPixel(x, y).a > 0) opaque++;
      }
    }
    expect(opaque, greaterThan(100));
  });

  test('twin JiggleSpec expands to two out-of-phase lobes', () {
    const JiggleSpec j =
        JiggleSpec(x: 0.2, y: 0.3, w: 0.5, h: 0.2, phase: 0.0, twin: true);
    final List<AnimRecipe> rs = j.toRecipes(100, 100);
    expect(rs.length, 2);
    expect(rs[0].type, 'jigglePhysics');
    expect(rs[1].type, 'jigglePhysics');
    expect((rs[1].p['phase']! - rs[0].p['phase']!).abs(), closeTo(0.5, 1e-9));
    expect(rs[1].region!.x, greaterThan(rs[0].region!.x));
    expect(const JiggleSpec().toRecipes(100, 100).length, 1);
  });

  test('Bust presets exist, are twin, and lead the catalogue', () {
    expect(jiggleCategories.first, 'Bust');
    final JiggleSpec bust = jiggleByName('Bust');
    expect(bust.name, 'Bust');
    expect(bust.twin, isTrue);
  });

  test('lobes splits into N out-of-phase regions (generalises twin)', () {
    const JiggleSpec j =
        JiggleSpec(x: 0.1, y: 0.3, w: 0.8, h: 0.2, lobes: 3, spread: 0.33);
    final List<AnimRecipe> rs = j.toRecipes(100, 100);
    expect(rs.length, 3);
    expect(rs[1].region!.x, greaterThan(rs[0].region!.x));
    expect(rs[2].region!.x, greaterThan(rs[1].region!.x));
    expect(rs[1].p['phase']!, closeTo(0.33, 1e-9));
    expect(rs[2].p['phase']!, closeTo(0.66, 1e-9));
  });

  test('toRecipe carries the new realism warp params', () {
    final AnimRecipe r = const JiggleSpec(
            anchor: 0.3, gravity: 0.5, organic: 0.4, followThrough: 0.6)
        .toRecipe(100, 100);
    expect(r.p['anchor'], closeTo(0.3, 1e-9));
    expect(r.p['gravity'], closeTo(0.5, 1e-9));
    expect(r.p['organic'], closeTo(0.4, 1e-9));
    expect(r.p['followThrough'], closeTo(0.6, 1e-9));
  });

  test('new jiggle params round-trip through JSON', () {
    const JiggleSpec j = JiggleSpec(
        anchor: 0.4,
        gravity: 0.6,
        organic: 0.5,
        followThrough: 0.7,
        lobes: 3,
        spread: 0.4);
    final JiggleSpec back = JiggleSpec.fromJson(j.toJson());
    expect(back.anchor, closeTo(0.4, 1e-9));
    expect(back.gravity, closeTo(0.6, 1e-9));
    expect(back.organic, closeTo(0.5, 1e-9));
    expect(back.followThrough, closeTo(0.7, 1e-9));
    expect(back.lobes, 3);
    expect(back.spread, closeTo(0.4, 1e-9));
  });
}
