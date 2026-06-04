import 'package:flutter_test/flutter_test.dart';
import 'package:pinsel/src/imaging/color_matrix.dart';
import 'package:pinsel/src/imaging/color_ops.dart';

void main() {
  test('empty pipeline is the identity matrix', () {
    expect(ColorMatrix.tryBuild(<ColorOp>[]), ColorMatrix.identity);
  });

  test('brightness scales the RGB diagonal, keeps alpha', () {
    final List<double>? m = ColorMatrix.tryBuild(
        <ColorOp>[ColorOp('brightness', nums: <String, double>{'amount': 2})]);
    expect(m, isNotNull);
    expect(m![0], 2.0); // R <- 2R
    expect(m[6], 2.0); // G <- 2G
    expect(m[12], 2.0); // B <- 2B
    expect(m[18], 1.0); // A unchanged
    expect(m[4], 0.0); // no offset
  });

  test('contrast is c·v + (128 − 128c)', () {
    final List<double> m = ColorMatrix.tryBuild(
        <ColorOp>[ColorOp('contrast', nums: <String, double>{'amount': 0.5})])!;
    expect(m[0], 0.5);
    expect(m[4], closeTo(64, 1e-9)); // 128 - 128*0.5
  });

  test('invert is −1 with a +255 offset', () {
    final List<double> m = ColorMatrix.tryBuild(<ColorOp>[ColorOp('invert')])!;
    expect(m[0], -1.0);
    expect(m[4], 255.0);
  });

  test('solidColor writes a constant colour and preserves alpha', () {
    final List<double> m = ColorMatrix.tryBuild(<ColorOp>[
      ColorOp('solidColor', strs: <String, String>{'color': '#FF8040'})
    ])!;
    expect(m[0], 0.0); // no contribution from source RGB
    expect(m[4], 255.0); // R = 0xFF
    expect(m[9], 128.0); // G = 0x80
    expect(m[14], 64.0); // B = 0x40
    expect(m[18], 1.0); // alpha preserved
  });

  test('an unsupported op bails to null (caller uses CPU preview)', () {
    final List<double>? m = ColorMatrix.tryBuild(<ColorOp>[
      ColorOp('brightness', nums: <String, double>{'amount': 1.2}),
      ColorOp('hueShift', nums: <String, double>{'degrees': 30}),
    ]);
    expect(m, isNull);
  });

  test('ops compose in order: invert after brightness ×2 → −2v + 255', () {
    final List<double> m = ColorMatrix.tryBuild(<ColorOp>[
      ColorOp('brightness', nums: <String, double>{'amount': 2}),
      ColorOp('invert'),
    ])!;
    expect(m[0], -2.0);
    expect(m[4], 255.0);
  });
}
