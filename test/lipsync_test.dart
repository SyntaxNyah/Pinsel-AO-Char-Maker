import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pinsel/src/animation/anim_clip.dart';
import 'package:pinsel/src/animation/lipsync.dart';
import 'package:pinsel/src/imaging/button_maker.dart';

/// A small sprite with an opaque body blob so the head/face detector has
/// something to work with.
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
  test('talk produces the requested number of same-size frames', () {
    final img.Image base = _sprite();
    final AnimClip clip = LipSync.talk(base, frames: 8, fps: 10);
    expect(clip.frames.length, 8);
    for (final AnimFrame f in clip.frames) {
      expect(f.image.width, base.width);
      expect(f.image.height, base.height);
    }
  });

  test('talk never mutates the source image', () {
    final img.Image base = _sprite();
    final img.Pixel before = base.getPixel(20, 30);
    final int r = before.r.toInt(),
        g = before.g.toInt(),
        b = before.b.toInt(),
        a = before.a.toInt();
    LipSync.talk(base, frames: 4);
    final img.Pixel after = base.getPixel(20, 30);
    expect(after.r.toInt(), r);
    expect(after.g.toInt(), g);
    expect(after.b.toInt(), b);
    expect(after.a.toInt(), a);
  });

  test('talkOpenness stays within 0..1 and loops seamlessly', () {
    for (int i = 0; i <= 10; i++) {
      expect(LipSync.talkOpenness(i / 10), inInclusiveRange(0.0, 1.0));
    }
    // Periodic: the value at t=0 matches t=1, so the clip has no seam.
    expect(LipSync.talkOpenness(0), closeTo(LipSync.talkOpenness(1), 1e-9));
  });

  test('default mouth region sits inside the image with positive size', () {
    final img.Image base = _sprite();
    final IntRect r = LipSync.defaultMouthRegion(base);
    expect(r.x, inInclusiveRange(0, base.width));
    expect(r.y, inInclusiveRange(0, base.height));
    expect(r.x + r.w, lessThanOrEqualTo(base.width));
    expect(r.y + r.h, lessThanOrEqualTo(base.height));
    expect(r.w, greaterThan(0));
    expect(r.h, greaterThan(0));
  });

  test('MouthRegion.toPixels scales fractions and clamps in-bounds', () {
    const MouthRegion m = MouthRegion(0.25, 0.5, 0.5, 0.1);
    final IntRect r = m.toPixels(100, 200);
    expect(r.x, 25);
    expect(r.y, 100);
    expect(r.w, 50);
    expect(r.h, 20);
  });

  test('MouthRegion.defaultFor returns fractions in 0..1', () {
    final MouthRegion m = MouthRegion.defaultFor(_sprite());
    expect(m.x, inInclusiveRange(0.0, 1.0));
    expect(m.y, inInclusiveRange(0.0, 1.0));
    expect(m.w, inInclusiveRange(0.0, 1.0));
    expect(m.h, inInclusiveRange(0.0, 1.0));
  });
}
