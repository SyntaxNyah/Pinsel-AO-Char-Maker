import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pinsel/src/imaging/button_maker.dart' show IntRect;
import 'package:pinsel/src/imaging/sprite_edit.dart';

/// A solid opaque [w]×[h] image (red), so transparency added by growing is easy
/// to detect (alpha 0 in the new margin, 255 over the original content).
img.Image _solid(int w, int h) {
  final img.Image im = img.Image(width: w, height: h, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(255, 0, 0, 255));
  return im;
}

void main() {
  group('SpriteEditSpec', () {
    test('isNoop is true only when nothing changes', () {
      expect(const SpriteEditSpec().isNoop, isTrue);
      expect(const SpriteEditSpec(cropLeft: 0.1).isNoop, isFalse);
      expect(const SpriteEditSpec(padRight: 0.1).isNoop, isFalse);
      expect(const SpriteEditSpec(autoTrim: true).isNoop, isFalse);
      expect(const SpriteEditSpec(scaleX: 0.5).isNoop, isFalse);
      expect(const SpriteEditSpec(scaleY: 2.0).isNoop, isFalse);
    });
  });

  group('resize', () {
    test('scales width and height by the factors', () {
      final img.Image out = SpriteEdit.resize(_solid(40, 20), 0.5, 2.0);
      expect(out.width, 20);
      expect(out.height, 40);
    });

    test('scale 1×1 is a no-op (returns the same instance)', () {
      final img.Image src = _solid(10, 10);
      expect(identical(SpriteEdit.resize(src, 1.0, 1.0), src), isTrue);
    });

    test('apply() resizes after cropping (crop then scale)', () {
      // 20×20, crop 50% off the right → 10×20, then 2× → 20×40.
      final img.Image out = SpriteEdit.apply(
          _solid(20, 20), const SpriteEditSpec(cropRight: 0.5, scaleX: 2, scaleY: 2));
      expect(out.width, 20);
      expect(out.height, 40);
    });

    test('preserves frame count for an animation', () {
      final img.Image anim = _solid(10, 10)..addFrame(_solid(10, 10));
      final img.Image out = SpriteEdit.resize(anim, 2.0, 2.0);
      expect(out.frames.length, 2);
      expect(out.width, 20);
    });
  });

  group('computeRect', () {
    test('crop pulls the requested edge inward', () {
      final IntRect r = SpriteEdit.computeRect(
          <img.Image>[_solid(10, 10)], const SpriteEditSpec(cropLeft: 0.2));
      expect(r.x, 2);
      expect(r.y, 0);
      expect(r.w, 8);
      expect(r.h, 10);
    });

    test('grow extends the rect past the image (negative origin / oversize)', () {
      final IntRect r = SpriteEdit.computeRect(
          <img.Image>[_solid(10, 10)], const SpriteEditSpec(padLeft: 0.5));
      expect(r.x, -5); // 5px added on the left
      expect(r.w, 15); // 10 + 5
      expect(r.h, 10);
    });

    test('crop one side + grow the opposite side compose', () {
      final IntRect r = SpriteEdit.computeRect(
          <img.Image>[_solid(10, 10)],
          const SpriteEditSpec(cropLeft: 0.1, padRight: 0.3));
      // inward box starts at x=1 (10% crop), grows 3px on the right.
      expect(r.x, 1);
      expect(r.w, 9 + 3); // (10-1) + 3
    });
  });

  group('cropTo', () {
    test('cropping returns a smaller image of the kept region', () {
      final img.Image out = SpriteEdit.cropTo(_solid(10, 10), const IntRect(2, 0, 8, 10));
      expect(out.width, 8);
      expect(out.height, 10);
      expect(out.getPixel(0, 0).a, 255); // still opaque content
    });

    test('growing pads with transparency and keeps the content opaque', () {
      // 5px added on the left → 15×10, content shifted right by 5.
      final img.Image out = SpriteEdit.cropTo(_solid(10, 10), const IntRect(-5, 0, 15, 10));
      expect(out.width, 15);
      expect(out.height, 10);
      expect(out.getPixel(0, 0).a, 0); // new left margin is transparent
      expect(out.getPixel(4, 0).a, 0); // still inside the 5px margin
      expect(out.getPixel(5, 0).a, 255); // original content begins here
      expect(out.getPixel(14, 0).a, 255);
    });

    test('a full-frame rect is a no-op (same instance)', () {
      final img.Image src = _solid(10, 10);
      expect(identical(SpriteEdit.cropTo(src, const IntRect(0, 0, 10, 10)), src), isTrue);
    });

    test('crop one side + grow the other (mixed offset, no negative dstX)', () {
      // What `computeRect(cropLeft:0.1, padRight:0.3)` yields on a 10×10: drop
      // the left column, add 3px of margin on the right. The grow branch must
      // copy src cols 1..9 to canvas cols 0..8 and leave cols 9..11 empty —
      // i.e. a positive srcX with a zero (never negative) dstX.
      final img.Image out = SpriteEdit.cropTo(_solid(10, 10), const IntRect(1, 0, 12, 10));
      expect(out.width, 12);
      expect(out.height, 10);
      expect(out.getPixel(0, 0).a, 255); // src col 1 → here, opaque
      expect(out.getPixel(8, 0).a, 255); // src col 9 → here, opaque
      expect(out.getPixel(9, 0).a, 0); // new right margin transparent
      expect(out.getPixel(11, 0).a, 0);
    });
  });

  group('apply (preview path)', () {
    test('grow produces a larger canvas with transparent margins', () {
      final img.Image out =
          SpriteEdit.apply(_solid(20, 20), const SpriteEditSpec(padTop: 0.25, padBottom: 0.25));
      expect(out.width, 20);
      expect(out.height, 30); // 20 + 5 top + 5 bottom
      expect(out.getPixel(0, 0).a, 0); // top margin transparent
      expect(out.getPixel(0, 29).a, 0); // bottom margin transparent
      expect(out.getPixel(0, 10).a, 255); // original content
    });
  });
}
