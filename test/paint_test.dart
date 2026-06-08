import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pinsel/src/imaging/button_maker.dart' show IntRect;
import 'package:pinsel/src/imaging/color_ops.dart';
import 'package:pinsel/src/imaging/paint.dart';
import 'package:pinsel/src/imaging/region_edit.dart';

/// A solid opaque [w]×[h] image of one colour.
img.Image _solid(int w, int h, int r, int g, int b, [int a = 255]) {
  final img.Image im = img.Image(width: w, height: h, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(r, g, b, a));
  return im;
}

void main() {
  group('PaintGradient', () {
    test('colorAt hits the endpoints and the midpoint', () {
      final PaintGradient g = PaintGradient.blackwhite();
      expect(g.colorAt(0), 0xFF000000);
      expect(g.colorAt(1), 0xFFFFFFFF);
      final int mid = g.colorAt(0.5);
      expect((mid >> 16) & 0xFF, closeTo(128, 1));
      expect((mid >> 8) & 0xFF, closeTo(128, 1));
      expect(mid & 0xFF, closeTo(128, 1));
      expect((mid >> 24) & 0xFF, 255);
    });

    test('clamps out-of-range t', () {
      final PaintGradient g = PaintGradient.blackwhite();
      expect(g.colorAt(-5), 0xFF000000);
      expect(g.colorAt(5), 0xFFFFFFFF);
    });

    test('reverse flips the ramp', () {
      final PaintGradient g = PaintGradient.blackwhite()..reverse = true;
      expect(g.colorAt(0), 0xFFFFFFFF);
      expect(g.colorAt(1), 0xFF000000);
    });

    test('fromColors spaces stops evenly', () {
      final PaintGradient g =
          PaintGradient.fromColors(<int>[0xFF000000, 0xFF808080, 0xFFFFFFFF]);
      expect(g.stops.map((GradientStop s) => s.pos).toList(), <double>[0, 0.5, 1]);
    });

    test('json round-trips', () {
      final PaintGradient g = PaintGradient.fromColors(
          <int>[0xFFFF0000, 0xFF00FF00, 0xFF0000FF],
          type: GradientType.radial, angle: 45);
      final PaintGradient back = PaintGradient.fromJson(g.toJson());
      expect(back.type, GradientType.radial);
      expect(back.angle, 45);
      expect(back.stops.length, 3);
      expect(back.colorAt(0), 0xFFFF0000);
      expect(back.colorAt(1), 0xFF0000FF);
    });
  });

  group('blendRgb', () {
    test('normal returns the source', () {
      expect(blendRgb(10, 20, 30, 200, 100, 50, PaintBlend.normal),
          <int>[200, 100, 50]);
    });
    test('multiply by white is identity; by black is black', () {
      expect(blendRgb(120, 130, 140, 255, 255, 255, PaintBlend.multiply),
          <int>[120, 130, 140]);
      expect(blendRgb(120, 130, 140, 0, 0, 0, PaintBlend.multiply),
          <int>[0, 0, 0]);
    });
    test('screen by black is identity; by white is white', () {
      expect(blendRgb(120, 130, 140, 0, 0, 0, PaintBlend.screen),
          <int>[120, 130, 140]);
      expect(blendRgb(120, 130, 140, 255, 255, 255, PaintBlend.screen),
          <int>[255, 255, 255]);
    });
    test('color mode keeps base luminosity (recolour-keeps-shading)', () {
      // A dark base recoloured with bright red stays dark.
      final List<int> out = blendRgb(40, 40, 40, 255, 0, 0, PaintBlend.color);
      final List<int> bright = blendRgb(220, 220, 220, 255, 0, 0, PaintBlend.color);
      final int lumDark = (0.3 * out[0] + 0.59 * out[1] + 0.11 * out[2]).round();
      final int lumBright =
          (0.3 * bright[0] + 0.59 * bright[1] + 0.11 * bright[2]).round();
      expect(lumDark, lessThan(lumBright));
    });
  });

  group('Painter fills', () {
    test('fillSolid recolours opaque pixels and preserves alpha', () {
      final img.Image im = _solid(4, 4, 255, 0, 0);
      final SelectionMask mask = SelectionMask.full(4, 4);
      Painter.fillSolid(im, mask, 0xFF0000FF); // blue, normal, preserveAlpha
      final img.Pixel p = im.getPixel(1, 1);
      expect(p.b.toInt(), 255);
      expect(p.r.toInt(), 0);
      expect(p.a.toInt(), 255);
    });

    test('fillSolid with preserveAlpha leaves transparent pixels untouched', () {
      final img.Image im = _solid(4, 4, 0, 0, 0, 0); // fully transparent
      Painter.fillSolid(im, SelectionMask.full(4, 4), 0xFFFF00FF);
      expect(im.getPixel(2, 2).a.toInt(), 0);
    });

    test('fillGradient (linear, angle 0) ramps left→right', () {
      final img.Image im = _solid(16, 4, 128, 128, 128);
      final PaintGradient g = PaintGradient.blackwhite()..angle = 0;
      Painter.fillGradient(im, SelectionMask.full(16, 4), g);
      final int left = im.getPixel(0, 1).r.toInt();
      final int right = im.getPixel(15, 1).r.toInt();
      expect(left, lessThan(right));
    });

    test('fillOps recolours through a mask only', () {
      final img.Image im = _solid(8, 8, 100, 100, 100);
      final SelectionMask mask =
          RegionEditor.rectangle(8, 8, const IntRect(0, 0, 4, 8));
      Painter.fillOps(im, mask, <ColorOp>[
        ColorOp('solidColor', strs: <String, String>{'color': '#FFFF0000'}),
      ]);
      expect(im.getPixel(1, 1).r.toInt(), greaterThan(im.getPixel(6, 1).r.toInt()));
    });
  });

  group('Painter brush', () {
    test('paint brush lays colour at the stroke centre', () {
      final img.Image im = _solid(21, 21, 255, 255, 255);
      Painter.stroke(im, <double>[0.5, 0.5],
          BrushSpec(argb: 0xFF0000FF, size: 0.4, hardness: 1.0));
      final img.Pixel c = im.getPixel(10, 10);
      expect(c.b.toInt(), 255);
      expect(c.r.toInt(), lessThan(40));
      // A corner well outside the brush is untouched.
      expect(im.getPixel(0, 0).r.toInt(), 255);
    });

    test('erase brush lowers alpha at the centre', () {
      final img.Image im = _solid(21, 21, 255, 0, 0);
      Painter.stroke(im, <double>[0.5, 0.5],
          BrushSpec(mode: BrushMode.erase, size: 0.4, hardness: 1.0));
      expect(im.getPixel(10, 10).a.toInt(), lessThan(40));
      expect(im.getPixel(0, 0).a.toInt(), 255);
    });
  });

  group('PaintOp', () {
    test('json round-trips a gradient fill', () {
      final PaintOp op = PaintOp(
        PaintOpKind.fillGradient,
        selection: PaintSelection(SelectionKind.rect, x: 0.1, y: 0.1, w: 0.5, h: 0.5),
        gradient: PaintGradient.fromColors(<int>[0xFF112233, 0xFF445566]),
        blend: PaintBlend.multiply,
        opacity: 0.7,
      );
      final PaintOp back = PaintOp.fromJson(op.toJson());
      expect(back.kind, PaintOpKind.fillGradient);
      expect(back.blend, PaintBlend.multiply);
      expect(back.opacity, 0.7);
      expect(back.selection.kind, SelectionKind.rect);
      expect(back.selection.w, 0.5);
      expect(back.gradient.stops.length, 2);
    });

    test('applyTo replays a solid fill via the journal', () {
      final img.Image im = _solid(6, 6, 10, 10, 10);
      final PaintOp op = PaintOp(PaintOpKind.fillSolid, argb: 0xFF00FF00);
      Painter.applyAll(im, <PaintOp>[op]);
      expect(im.getPixel(3, 3).g.toInt(), 255);
    });
  });

  group('PaintSelection', () {
    test('wand selects a contiguous blob of one colour', () {
      final img.Image im = _solid(10, 10, 255, 0, 0);
      // Paint the right half green.
      for (int y = 0; y < 10; y++) {
        for (int x = 5; x < 10; x++) {
          im.setPixelRgba(x, y, 0, 255, 0, 255);
        }
      }
      final PaintSelection sel =
          PaintSelection(SelectionKind.wand, x: 0.1, y: 0.5, tolerance: 30);
      final SelectionMask m = sel.build(im);
      expect(m.get(1, 5), 255); // red side selected
      expect(m.get(8, 5), 0); // green side not
    });

    test('luminance band selects highlights only', () {
      final img.Image im = _solid(4, 4, 20, 20, 20);
      im.setPixelRgba(0, 0, 240, 240, 240, 255);
      final PaintSelection sel =
          PaintSelection(SelectionKind.luminance, lumMin: 200, lumMax: 255);
      final SelectionMask m = sel.build(im);
      expect(m.get(0, 0), 255);
      expect(m.get(3, 3), 0);
    });
  });
}
