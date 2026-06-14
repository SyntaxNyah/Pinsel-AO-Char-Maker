import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pinsel/src/core/ao_constants.dart';
import 'package:pinsel/src/imaging/button_maker.dart' show IntRect;
import 'package:pinsel/src/imaging/sprite_zoom.dart';

/// A solid opaque [w]×[h] image (red).
img.Image _solid(int w, int h) {
  final img.Image im = img.Image(width: w, height: h, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(255, 0, 0, 255));
  return im;
}

/// A transparent [w]×[h] canvas with an opaque [bw]×[bh] block at ([bx],[by]).
img.Image _withBlock(int w, int h, int bx, int by, int bw, int bh) {
  final img.Image im = img.Image(width: w, height: h, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(0, 0, 0, 0));
  final img.Color green = img.ColorRgba8(0, 200, 0, 255);
  for (int y = by; y < by + bh; y++) {
    for (int x = bx; x < bx + bw; x++) {
      im.setPixel(x, y, green);
    }
  }
  return im;
}

int _opaqueCount(img.Image im) {
  int n = 0;
  for (final img.Pixel p in im) {
    if (p.a > 0) n++;
  }
  return n;
}

void main() {
  group('SpriteZoomSpec', () {
    test('isNoop only when the camera shows the whole sprite at native size',
        () {
      expect(const SpriteZoomSpec().isNoop, isTrue);
      expect(const SpriteZoomSpec(focusX: 0.7).isNoop, isTrue); // pan irrelevant
      expect(const SpriteZoomSpec(zoom: 2).isNoop, isFalse);
      expect(const SpriteZoomSpec(zoom: 0.5).isNoop, isFalse);
      expect(const SpriteZoomSpec(outputScale: 2).isNoop, isFalse);
    });

    test('copyWith clamps to the limits', () {
      final SpriteZoomSpec s =
          const SpriteZoomSpec().copyWith(zoom: 999, focusX: 5, focusY: -3);
      expect(s.zoom, ZoomLimits.maxZoom);
      expect(s.focusX, 1.0);
      expect(s.focusY, 0.0);
    });

    test('round-trips through JSON', () {
      const SpriteZoomSpec s =
          SpriteZoomSpec(zoom: 2.5, focusX: 0.3, focusY: 0.7, outputScale: 2);
      final SpriteZoomSpec back = SpriteZoomSpec.fromJson(s.toJson());
      expect(back.zoom, 2.5);
      expect(back.focusX, 0.3);
      expect(back.focusY, 0.7);
      expect(back.outputScale, 2);
    });
  });

  group('cameraRect', () {
    test('zoom 2 centred crops the middle quarter', () {
      final IntRect r = SpriteZoom.cameraRect(20, 20, const SpriteZoomSpec(zoom: 2));
      expect(r.w, 10);
      expect(r.h, 10);
      expect(r.x, 5);
      expect(r.y, 5);
    });

    test('zoom out (<1) sees past the edges (negative origin / oversize)', () {
      final IntRect r =
          SpriteZoom.cameraRect(20, 20, const SpriteZoomSpec(zoom: 0.5));
      expect(r.w, 40);
      expect(r.h, 40);
      expect(r.x, -10);
      expect(r.y, -10);
    });

    test('focus moves the camera', () {
      final IntRect r = SpriteZoom.cameraRect(
          100, 100, const SpriteZoomSpec(zoom: 2, focusX: 0.25, focusY: 0.75));
      // region 50×50 centred at (25,75) → origin (0,50).
      expect(r.x, 0);
      expect(r.y, 50);
    });
  });

  group('apply', () {
    test('identity (noop) returns the same instance', () {
      final img.Image src = _solid(20, 20);
      expect(identical(SpriteZoom.apply(src, const SpriteZoomSpec()), src),
          isTrue);
    });

    test('zoom keeps the output dimensions equal to the source', () {
      final img.Image out =
          SpriteZoom.apply(_solid(40, 30), const SpriteZoomSpec(zoom: 2));
      expect(out.width, 40);
      expect(out.height, 30);
    });

    test('zooming in enlarges the content (more opaque pixels)', () {
      final img.Image src = _withBlock(40, 40, 18, 18, 4, 4); // tiny centred dot
      final int before = _opaqueCount(src);
      final img.Image out = SpriteZoom.apply(src, const SpriteZoomSpec(zoom: 3));
      expect(out.width, 40);
      expect(out.height, 40);
      expect(_opaqueCount(out), greaterThan(before));
    });

    test('outputScale bakes at a higher resolution (bigger dimensions)', () {
      final img.Image out =
          SpriteZoom.apply(_solid(20, 20), const SpriteZoomSpec(outputScale: 2));
      expect(out.width, 40);
      expect(out.height, 40);
    });

    test('preserves frame count AND per-frame durations on an animation', () {
      final img.Image anim = _solid(20, 20)..frameDuration = 50;
      final img.Image f2 = _solid(20, 20)..frameDuration = 80;
      anim.addFrame(f2);
      expect(anim.frames.length, 2);

      final img.Image out = SpriteZoom.apply(anim, const SpriteZoomSpec(zoom: 2));
      expect(out.frames.length, 2);
      expect(out.width, 20);
      expect(out.frames[0].frameDuration, 50);
      expect(out.frames[1].frameDuration, 80);
    });
  });

  group('fitToContent', () {
    test('frames a small off-centre character (zoom in, focus on it)', () {
      // 20×20 opaque block at (10,10) of a 100×100 canvas → box 0.1..0.3.
      final img.Image im = _withBlock(100, 100, 10, 10, 20, 20);
      final SpriteZoomSpec s =
          SpriteZoom.fitToContent(<img.Image>[im], coverage: 0.92);
      expect(s.zoom, closeTo(0.92 / 0.2, 0.05)); // ~4.6×
      expect(s.focusX, closeTo(0.2, 0.01));
      expect(s.focusY, closeTo(0.2, 0.01));
    });

    test('uses the UNION across sprites so the cast stays aligned', () {
      final img.Image a = _withBlock(100, 100, 10, 10, 20, 20); // top-left
      final img.Image b = _withBlock(100, 100, 70, 70, 20, 20); // bottom-right
      final SpriteZoomSpec s =
          SpriteZoom.fitToContent(<img.Image>[a, b], coverage: 0.92);
      // Union box spans 0.1..0.9 on both axes → width 0.8 → zoom ~1.15, centred.
      expect(s.zoom, closeTo(0.92 / 0.8, 0.05));
      expect(s.focusX, closeTo(0.5, 0.01));
      expect(s.focusY, closeTo(0.5, 0.01));
    });

    test('returns the identity camera when there is no content', () {
      final img.Image blank = img.Image(width: 10, height: 10, numChannels: 4);
      img.fill(blank, color: img.ColorRgba8(0, 0, 0, 0));
      final SpriteZoomSpec s = SpriteZoom.fitToContent(<img.Image>[blank]);
      expect(s.zoom, 1.0);
      expect(s.focusX, 0.5);
    });
  });
}
