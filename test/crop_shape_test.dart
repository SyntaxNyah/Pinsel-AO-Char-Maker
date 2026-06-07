import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pinsel/src/core/ao_constants.dart';
import 'package:pinsel/src/imaging/button_maker.dart';
import 'package:pinsel/src/imaging/crop_shape.dart';

img.Image _solid(int w, int h) {
  final img.Image im = img.Image(width: w, height: h, numChannels: 4);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      im.setPixelRgba(x, y, 200, 60, 60, 255);
    }
  }
  return im;
}

void main() {
  test('preset catalogue is non-trivial with unique names + categories', () {
    expect(cropShapePresets.length, greaterThanOrEqualTo(12));
    expect(cropShapePresets.map((CropShape s) => s.name).toSet().length,
        cropShapePresets.length);
    expect(cropShapeCategories, contains('Basic'));
    expect(cropShapeByName('Circle').kind, CropShapeKind.circle);
    expect(cropShapeByName('definitely-missing').name, 'Square'); // fallback
  });

  test('square clips nothing; other shapes clip', () {
    expect(CropShape.square.clips, isFalse);
    expect(const CropShape(name: 'c', kind: CropShapeKind.circle).clips, isTrue);
    expect(cropShapeByName('Heart').clips, isTrue);
  });

  test('circle mask is opaque centre, transparent corners; right size', () {
    final img.Image m =
        const CropShape(name: 'c', kind: CropShapeKind.circle).mask(64);
    expect(m.width, 64);
    expect(m.height, 64);
    expect(m.getPixel(32, 32).a, greaterThan(200));
    expect(m.getPixel(0, 0).a, lessThan(40));
    expect(m.getPixel(63, 63).a, lessThan(40));
  });

  test('square mask is fully opaque (no clipping)', () {
    final img.Image m = CropShape.square.mask(16);
    for (int y = 0; y < 16; y++) {
      for (int x = 0; x < 16; x++) {
        expect(m.getPixel(x, y).a, 255);
      }
    }
  });

  test('generators produce valid closed polygons', () {
    expect(CropShape.regularPolygon('Hex', 6).points.length, 12);
    expect(CropShape.star('Star', 5, 0.45).points.length, 20);
  });

  test('CropShape JSON round-trips (incl. polygon points)', () {
    final CropShape s = CropShape.star('Star', 5, 0.45);
    final CropShape back = CropShape.fromJson(s.toJson());
    expect(back.name, 'Star');
    expect(back.kind, CropShapeKind.polygon);
    expect(back.points.length, s.points.length);
    final CropShape rr = const CropShape(
        name: 'R', kind: CropShapeKind.roundedRect, radius: 0.3);
    expect(CropShape.fromJson(rr.toJson()).radius, closeTo(0.3, 1e-9));
  });

  test('renderFramed clips a button to the shape (transparent corners)', () {
    final Uint8List png = ButtonMaker.renderFramed(_solid(80, 80), 64,
        framing: CropFraming.full,
        shape: const CropShape(name: 'c', kind: CropShapeKind.circle),
        clipShape: true);
    final img.Image out = img.decodePng(png)!;
    expect(out.width, 64);
    expect(out.getPixel(32, 32).a, greaterThan(200)); // centre kept
    expect(out.getPixel(0, 0).a, lessThan(40)); // corner clipped away
  });

  test('renderFramed without clip keeps the full square (shape is a guide)', () {
    final Uint8List png = ButtonMaker.renderFramed(_solid(80, 80), 64,
        framing: CropFraming.full,
        shape: const CropShape(name: 'c', kind: CropShapeKind.circle),
        clipShape: false);
    final img.Image out = img.decodePng(png)!;
    expect(out.getPixel(0, 0).a, 255); // corner intact
  });
}
