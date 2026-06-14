import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pinsel/src/imaging/region_edit.dart';

/// A 1-row image from a list of (r,g,b,a) tuples.
img.Image _row(List<List<int>> px) {
  final img.Image im = img.Image(width: px.length, height: 1, numChannels: 4);
  for (int x = 0; x < px.length; x++) {
    final List<int> c = px[x];
    im.setPixelRgba(x, 0, c[0], c[1], c[2], c[3]);
  }
  return im;
}

void main() {
  // These lock the squared-distance equivalence (sqrt/pow removed) — the magic
  // wand + colour-erase must still pick exactly the same pixels.
  group('eraseColor (squared-distance)', () {
    test('erases the target colour and near matches within tolerance', () {
      final img.Image im = _row(<List<int>>[
        <int>[255, 0, 0, 255], // exact red
        <int>[250, 5, 0, 255], // near red (dist ~7)
        <int>[0, 0, 255, 255], // blue (far)
      ]);
      RegionEditor.eraseColor(im, 0xFFFF0000, tolerance: 40);
      expect(im.getPixel(0, 0).a, 0); // erased
      expect(im.getPixel(1, 0).a, 0); // near match erased
      expect(im.getPixel(2, 0).a, 255); // blue untouched
    });

    test('respects the tolerance boundary', () {
      // Distance from red to (215,0,0) is exactly 40.
      final img.Image im = _row(<List<int>>[
        <int>[215, 0, 0, 255], // dist 40 — within tol 40
        <int>[210, 0, 0, 255], // dist 45 — outside tol 40
      ]);
      RegionEditor.eraseColor(im, 0xFFFF0000, tolerance: 40);
      expect(im.getPixel(0, 0).a, 0); // d == tol → erased
      expect(im.getPixel(1, 0).a, 255); // d > tol → kept
    });

    test('never touches already-transparent pixels', () {
      final img.Image im = _row(<List<int>>[
        <int>[255, 0, 0, 0], // transparent red
      ]);
      RegionEditor.eraseColor(im, 0xFFFF0000, tolerance: 40);
      expect(im.getPixel(0, 0).a, 0); // still 0, no crash
    });
  });

  group('despillBackground (un-mix the edge fringe)', () {
    test('recovers the foreground colour on a 50% over-white edge pixel', () {
      // A red (255,0,0) hair edge that the source blended 50% over white bg
      // reads as (255,128,128) @ alpha 128. Un-mixing white should give ~red.
      final img.Image im = _row(<List<int>>[
        <int>[255, 128, 128, 128],
      ]);
      RegionEditor.despillBackground(im, 0xFFFFFFFF); // white bg
      final img.Pixel p = im.getPixel(0, 0);
      expect(p.r, 255);
      expect(p.g, lessThanOrEqualTo(5)); // ~0
      expect(p.b, lessThanOrEqualTo(5));
      expect(p.a, 128); // alpha is untouched
    });

    test('leaves fully-opaque and fully-transparent pixels untouched', () {
      final img.Image im = _row(<List<int>>[
        <int>[100, 50, 50, 255], // solid
        <int>[10, 20, 30, 0], // transparent
      ]);
      RegionEditor.despillBackground(im, 0xFF00FF00); // green bg
      expect(im.getPixel(0, 0).r, 100);
      expect(im.getPixel(0, 0).g, 50);
      expect(im.getPixel(0, 0).b, 50);
      expect(im.getPixel(1, 0).a, 0);
    });

    test('strength 0 is a no-op', () {
      final img.Image im = _row(<List<int>>[
        <int>[255, 128, 128, 128],
      ]);
      RegionEditor.despillBackground(im, 0xFFFFFFFF, strength: 0);
      expect(im.getPixel(0, 0).g, 128); // unchanged
    });
  });

  group('selectByColor (squared-distance flood fill)', () {
    test('contiguous wand selects the connected blob only', () {
      final img.Image im = _row(<List<int>>[
        <int>[255, 0, 0, 255], // red
        <int>[255, 0, 0, 255], // red (connected)
        <int>[0, 0, 255, 255], // blue (wall)
        <int>[255, 0, 0, 255], // red (disconnected)
      ]);
      final SelectionMask m =
          RegionEditor.selectByColor(im, 0, 0, tolerance: 40, contiguous: true);
      expect(m.get(0, 0), 255);
      expect(m.get(1, 0), 255);
      expect(m.get(2, 0), 0); // blue not selected
      expect(m.get(3, 0), 0); // disconnected red not reached
    });

    test('non-contiguous selects every matching pixel', () {
      final img.Image im = _row(<List<int>>[
        <int>[255, 0, 0, 255],
        <int>[0, 0, 255, 255],
        <int>[255, 0, 0, 255],
      ]);
      final SelectionMask m = RegionEditor.selectByColor(im, 0, 0,
          tolerance: 40, contiguous: false);
      expect(m.get(0, 0), 255);
      expect(m.get(1, 0), 0);
      expect(m.get(2, 0), 255); // matched despite the gap
    });
  });

  // Lock the sequential-cursor conversions of the masked ops.
  group('mask ops (cursor-based)', () {
    test('erase lowers alpha by the mask weight', () {
      final img.Image im = _row(<List<int>>[
        <int>[255, 0, 0, 255],
        <int>[0, 255, 0, 255],
      ]);
      final SelectionMask m = SelectionMask(2, 1);
      m.set(0, 0, 255); // fully erase pixel 0
      // pixel 1 left at 0 → untouched
      RegionEditor.erase(im, m);
      expect(im.getPixel(0, 0).a, 0);
      expect(im.getPixel(1, 0).a, 255);
    });

    test('erase at half weight halves the alpha', () {
      final img.Image im = _row(<List<int>>[
        <int>[10, 20, 30, 200],
      ]);
      final SelectionMask m = SelectionMask(1, 1)..set(0, 0, 128);
      RegionEditor.erase(im, m);
      // a = 200 * (255-128) ~/ 255 = 99; rgb untouched.
      expect(im.getPixel(0, 0).a, 99);
      expect(im.getPixel(0, 0).r, 10);
    });

    test('fill blends the colour by the mask weight', () {
      final img.Image im = _row(<List<int>>[
        <int>[0, 0, 0, 255],
      ]);
      final SelectionMask m = SelectionMask(1, 1)..set(0, 0, 255);
      RegionEditor.fill(im, m, 0xFFFF0000); // full red
      final img.Pixel p = im.getPixel(0, 0);
      expect(p.r, 255);
      expect(p.g, 0);
      expect(p.b, 0);
    });

    test('selectByLuminance picks the bright band only', () {
      final img.Image im = _row(<List<int>>[
        <int>[250, 250, 250, 255], // bright
        <int>[10, 10, 10, 255], // dark
      ]);
      final SelectionMask m = RegionEditor.selectByLuminance(im, min: 200);
      expect(m.get(0, 0), 255);
      expect(m.get(1, 0), 0);
    });
  });
}
