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

  test('JiggleSpec JSON round-trips (incl. direction)', () {
    final JiggleSpec j = jiggleByName('Bouncy');
    final JiggleSpec back = JiggleSpec.fromJson(j.toJson());
    expect(back.name, j.name);
    expect(back.amplitude, closeTo(j.amplitude, 1e-9));
    expect(back.frequency, j.frequency);
    expect(back.direction, closeTo(j.direction, 1e-9));
  });
}
