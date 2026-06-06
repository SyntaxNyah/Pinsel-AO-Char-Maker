import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pinsel/src/imaging/overlay_presets.dart';

void main() {
  test('presets exist, are categorised, and cover the themed sets', () {
    expect(OverlayPresets.borders, isNotEmpty);
    expect(OverlayPresets.backgrounds, isNotEmpty);
    expect(OverlayPresets.borders.every((OverlayPreset p) => p.kind == OverlayKind.border),
        isTrue);
    expect(
        OverlayPresets.backgrounds
            .every((OverlayPreset p) => p.kind == OverlayKind.background),
        isTrue);

    final Set<String> cats = <String>{
      for (final OverlayPreset p in OverlayPresets.borders) p.category,
      for (final OverlayPreset p in OverlayPresets.backgrounds) p.category,
    };
    expect(cats, containsAll(<String>['Umineko', 'Danganronpa', 'Kawaii', 'Colours']));
  });

  test('every OverlayStyle builds via a spec (covers the builder)', () {
    for (final OverlayStyle style in OverlayStyle.values) {
      expect(stylesForKind(style.kind), contains(style),
          reason: '$style should be listed for its kind');
      final OverlaySpec spec = OverlaySpec(style: style);
      for (final int size in <int>[16, 64]) {
        final img.Image im = spec.build(size);
        expect(im.width, size, reason: '$style width @ $size');
        expect(im.height, size, reason: '$style height @ $size');
        expect(im.numChannels, 4, reason: '$style channels');
      }
    }
  });

  test('every preset builds a size×size RGBA image at any size', () {
    final List<OverlayPreset> all = <OverlayPreset>[
      ...OverlayPresets.borders,
      ...OverlayPresets.backgrounds,
    ];
    for (final int size in <int>[16, 48, 128]) {
      for (final OverlayPreset p in all) {
        final img.Image im = p.build(size);
        expect(im.width, size, reason: '${p.name} (${p.kind}) width @ $size');
        expect(im.height, size, reason: '${p.name} (${p.kind}) height @ $size');
        expect(im.numChannels, 4, reason: '${p.name} (${p.kind}) channels');
      }
    }
  });

  test('OverlaySpec.toJson/fromJson round-trips every field (saved presets)', () {
    // A spec with deliberately non-default values for every field, for every
    // style — this is what a user-saved overlay preset persists + restores.
    for (final OverlayStyle style in OverlayStyle.values) {
      final OverlaySpec original = OverlaySpec(
        style: style,
        color1: 0x123456,
        color2: 0xABCDEF,
        patternColor: 0x0FF00F,
        thickness: 0.17,
        radius: 0.33,
        inset: 0.09,
        cell: 0.41,
      );
      final OverlaySpec? back = OverlaySpec.fromJson(original.toJson());
      expect(back, isNotNull, reason: '$style should round-trip');
      expect(back!.style, original.style, reason: '$style style');
      expect(back.color1, original.color1);
      expect(back.color2, original.color2);
      expect(back.patternColor, original.patternColor);
      expect(back.thickness, closeTo(original.thickness, 1e-9));
      expect(back.radius, closeTo(original.radius, 1e-9));
      expect(back.inset, closeTo(original.inset, 1e-9));
      expect(back.cell, closeTo(original.cell, 1e-9));
      expect(back.kind, original.kind);
    }
  });

  test('OverlaySpec.fromJson rejects junk / unknown styles', () {
    expect(OverlaySpec.fromJson(<String, dynamic>{}), isNull);
    expect(OverlaySpec.fromJson(<String, dynamic>{'style': 'not_a_real_style'}),
        isNull);
    // A known style with missing numeric fields falls back to the defaults.
    final OverlaySpec? def =
        OverlaySpec.fromJson(<String, dynamic>{'style': OverlayStyle.frame.name});
    expect(def, isNotNull);
    expect(def!.style, OverlayStyle.frame);
    expect(def.thickness, OverlaySpec(style: OverlayStyle.frame).thickness);
  });
}
