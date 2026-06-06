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

  // ---- VN talk styles ------------------------------------------------------

  test('the talk-style catalogue is large and has unique names', () {
    final List<TalkStyle> all = LipSync.styleCatalogue;
    // "Hundreds of ways of talking."
    expect(all.length, greaterThanOrEqualTo(250));
    expect(all.map((TalkStyle s) => s.name).toSet().length, all.length,
        reason: 'style names must be unique');
    expect(LipSync.styleCategories.length, greaterThanOrEqualTo(5));
  });

  test('every style openness stays in 0..1 and loops seamlessly', () {
    for (final TalkStyle s in LipSync.styleCatalogue) {
      for (int i = 0; i <= 8; i++) {
        expect(LipSync.styleOpenness(s, i / 8), inInclusiveRange(0.0, 1.0),
            reason: 'style "${s.name}" went out of range');
      }
      // t=0 equals t=1 → no seam when AO loops the (b) sprite.
      expect(LipSync.styleOpenness(s, 0),
          closeTo(LipSync.styleOpenness(s, 1), 1e-9),
          reason: 'style "${s.name}" does not loop');
    }
  });

  test('talkStyled produces same-size frames and never mutates the source', () {
    final img.Image base = _sprite();
    final img.Pixel before = base.getPixel(20, 30);
    final int r = before.r.toInt(), g = before.g.toInt(), b = before.b.toInt();
    final TalkStyle style = LipSync.styleByName('Excited');
    final AnimClip clip = LipSync.talkStyled(base, style, frames: 10, fps: 12);
    expect(clip.frames.length, 10);
    for (final AnimFrame f in clip.frames) {
      expect(f.image.width, base.width);
      expect(f.image.height, base.height);
    }
    final img.Pixel after = base.getPixel(20, 30);
    expect(<int>[after.r.toInt(), after.g.toInt(), after.b.toInt()],
        <int>[r, g, b]);
  });

  test('styleByName falls back to the default for unknown names', () {
    expect(LipSync.styleByName('not-a-real-style').name,
        LipSync.defaultStyle.name);
    expect(LipSync.styleByName(null).name, LipSync.defaultStyle.name);
  });

  test('TalkStyle survives a JSON round-trip', () {
    final TalkStyle s = LipSync.styleByName('Whisper (Slow)');
    final TalkStyle back = TalkStyle.fromJson(s.toJson());
    expect(back.name, s.name);
    expect(back.category, s.category);
    expect(back.syllables, s.syllables);
    expect(back.openAmount, closeTo(s.openAmount, 1e-9));
    expect(back.bob, closeTo(s.bob, 1e-9));
  });

  // ---- Anime mouth shapes --------------------------------------------------

  test('mouth-shape catalogue is large with unique names', () {
    expect(LipSync.mouthShapes.length, greaterThanOrEqualTo(80));
    expect(LipSync.mouthShapes.map((MouthShape s) => s.name).toSet().length,
        LipSync.mouthShapes.length);
    expect(LipSync.mouthShapeCategories.length, greaterThanOrEqualTo(3));
  });

  test('talkStyled with a drawn shape makes same-size frames, no mutation', () {
    final img.Image base = _sprite();
    final img.Pixel before = base.getPixel(20, 30);
    final int r = before.r.toInt(), g = before.g.toInt(), b = before.b.toInt();
    final AnimClip clip = LipSync.talkStyled(base, LipSync.defaultStyle,
        frames: 8, shape: LipSync.mouthShapes.first);
    expect(clip.frames.length, 8);
    for (final AnimFrame f in clip.frames) {
      expect(f.image.width, base.width);
      expect(f.image.height, base.height);
    }
    final img.Pixel after = base.getPixel(20, 30);
    expect(<int>[after.r.toInt(), after.g.toInt(), after.b.toInt()],
        <int>[r, g, b]);
  });

  test('MouthShape JSON round-trips', () {
    final MouthShape s = LipSync.mouthShapes.first;
    final MouthShape back = MouthShape.fromJson(s.toJson());
    expect(back.name, s.name);
    expect(back.widthFrac, closeTo(s.widthFrac, 1e-9));
    expect(back.teeth, s.teeth);
  });

  // ---- Mesh (cut a real open mouth, blend it) ------------------------------

  test('cutMouthPiece returns a region-sized, edge-feathered piece', () {
    final img.Image base = _sprite();
    final IntRect r = LipSync.defaultMouthRegion(base);
    final img.Image piece = LipSync.cutMouthPiece(base, r);
    expect(piece.width, r.w);
    expect(piece.height, r.h);
    // The rim is feathered, so a corner pixel is no more opaque than the centre.
    final int corner = piece.getPixel(0, 0).a.toInt();
    final int centre =
        piece.getPixel(piece.width ~/ 2, piece.height ~/ 2).a.toInt();
    expect(corner, lessThanOrEqualTo(centre));
  });

  test('talkMeshed produces the requested same-size frames', () {
    final img.Image base = _sprite();
    final IntRect r = LipSync.defaultMouthRegion(base);
    final img.Image piece = LipSync.cutMouthPiece(base, r);
    final AnimClip clip =
        LipSync.talkMeshed(base, piece, r, LipSync.defaultStyle, frames: 6);
    expect(clip.frames.length, 6);
    for (final AnimFrame f in clip.frames) {
      expect(f.image.width, base.width);
      expect(f.image.height, base.height);
    }
  });
}
