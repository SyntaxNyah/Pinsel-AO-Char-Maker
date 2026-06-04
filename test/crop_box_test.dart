import 'package:flutter_test/flutter_test.dart';
import 'package:pinsel/src/imaging/button_maker.dart';

void main() {
  test('toPixels is a square at the requested fractions', () {
    const CropBox b = CropBox(0.25, 0.1, 0.5);
    final IntRect r = b.toPixels(100, 200); // side = 0.5*100 = 50
    expect(r.w, r.h);
    expect(r.w, 50);
    expect(r.x, 25);
    expect(r.y, 20);
  });

  test('toPixels clamps an out-of-bounds box fully inside the image', () {
    const CropBox b = CropBox(0.9, 0.9, 0.5);
    final IntRect r = b.toPixels(100, 100); // side 50; x/y would overflow → clamp
    expect(r.x + r.w, lessThanOrEqualTo(100));
    expect(r.y + r.h, lessThanOrEqualTo(100));
    expect(r.w, r.h);
  });

  test('toPixels caps the side to the shorter edge (stays square)', () {
    const CropBox b = CropBox(0, 0, 1.0);
    final IntRect r = b.toPixels(200, 80); // 1.0*200=200 capped to min(200,80)=80
    expect(r.w, 80);
    expect(r.h, 80);
  });

  test('fromPixels round-trips to fractions', () {
    final CropBox b = CropBox.fromPixels(const IntRect(20, 40, 60, 60), 120, 200);
    expect(b.x, closeTo(20 / 120, 1e-9));
    expect(b.y, closeTo(40 / 200, 1e-9));
    expect(b.side, closeTo(60 / 120, 1e-9));
  });
}
