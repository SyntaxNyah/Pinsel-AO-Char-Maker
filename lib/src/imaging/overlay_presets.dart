import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Built-in button/icon **overlay** art, generated procedurally (no asset files,
/// works on every platform, scales to any size). A [border] is laid on top of a
/// button (a frame); a [background] sits behind the sprite.
///
/// Themed sets — Umineko, Danganronpa, kawaii pastels — plus a big palette of
/// plain colours. Each preset is a `build(size)` that returns a fresh RGBA image.
enum OverlayKind { border, background }

/// Editable overlay styles. The first group are **borders** (frame the button),
/// the rest are **backgrounds** (fill behind the sprite). Every style is driven
/// by [OverlaySpec], so the in-app builder can make/tweak any of them.
enum OverlayStyle {
  // borders
  frame,
  doubleFrame,
  corners,
  cornerHearts,
  gradientFrame,
  rainbowFrame,
  splitFrame,
  // backgrounds
  solid,
  linearGradient,
  radialGradient,
  diagonalSplit,
  dots,
  hearts,
  sparkles,
  rainbow,
}

const Set<OverlayStyle> _borderStyles = <OverlayStyle>{
  OverlayStyle.frame,
  OverlayStyle.doubleFrame,
  OverlayStyle.corners,
  OverlayStyle.cornerHearts,
  OverlayStyle.gradientFrame,
  OverlayStyle.rainbowFrame,
  OverlayStyle.splitFrame,
};

extension OverlayStyleInfo on OverlayStyle {
  OverlayKind get kind =>
      _borderStyles.contains(this) ? OverlayKind.border : OverlayKind.background;

  String get label => switch (this) {
        OverlayStyle.frame => 'Frame',
        OverlayStyle.doubleFrame => 'Double frame',
        OverlayStyle.corners => 'Corner brackets',
        OverlayStyle.cornerHearts => 'Heart corners',
        OverlayStyle.gradientFrame => 'Gradient frame',
        OverlayStyle.rainbowFrame => 'Rainbow frame',
        OverlayStyle.splitFrame => 'Split frame',
        OverlayStyle.solid => 'Solid colour',
        OverlayStyle.linearGradient => 'Linear gradient',
        OverlayStyle.radialGradient => 'Radial gradient',
        OverlayStyle.diagonalSplit => 'Diagonal split',
        OverlayStyle.dots => 'Polka dots',
        OverlayStyle.hearts => 'Hearts',
        OverlayStyle.sparkles => 'Sparkles',
        OverlayStyle.rainbow => 'Rainbow',
      };

  bool get usesColor1 =>
      this != OverlayStyle.rainbow && this != OverlayStyle.rainbowFrame;
  bool get usesColor2 => const <OverlayStyle>{
        OverlayStyle.doubleFrame,
        OverlayStyle.gradientFrame,
        OverlayStyle.splitFrame,
        OverlayStyle.linearGradient,
        OverlayStyle.radialGradient,
        OverlayStyle.diagonalSplit,
      }.contains(this);
  bool get usesPattern => const <OverlayStyle>{
        OverlayStyle.dots,
        OverlayStyle.hearts,
        OverlayStyle.sparkles,
      }.contains(this);
  bool get usesThickness => kind == OverlayKind.border;
  bool get usesRadius => const <OverlayStyle>{
        OverlayStyle.frame,
        OverlayStyle.doubleFrame,
        OverlayStyle.cornerHearts,
        OverlayStyle.gradientFrame,
        OverlayStyle.rainbowFrame,
      }.contains(this);
  bool get usesInset =>
      this == OverlayStyle.frame || this == OverlayStyle.doubleFrame;
  bool get usesCell => usesPattern;
}

List<OverlayStyle> stylesForKind(OverlayKind k) =>
    OverlayStyle.values.where((OverlayStyle s) => s.kind == k).toList();

/// An editable, buildable overlay — the heart of both the built-in presets and
/// the in-app "build your own border/background" editor. Mutate the fields and
/// call [build] for a fresh image at any size.
class OverlaySpec {
  OverlaySpec({
    required this.style,
    this.color1 = 0xFF80AB,
    this.color2 = 0xA8D8EA,
    this.patternColor = 0xFFFFFF,
    this.thickness = 0.08,
    this.radius = 0.12,
    this.inset = 0.0,
    this.cell = 0.26,
  });

  OverlayStyle style;
  int color1;
  int color2;
  int patternColor;
  double thickness;
  double radius;
  double inset;
  double cell;

  OverlayKind get kind => style.kind;

  img.Image build(int size) => _buildSpec(this, size);

  OverlaySpec copy() => OverlaySpec(
        style: style,
        color1: color1,
        color2: color2,
        patternColor: patternColor,
        thickness: thickness,
        radius: radius,
        inset: inset,
        cell: cell,
      );

  /// JSON for persisting a user-built preset (the style is stored by its enum
  /// *name* so it survives reordering of the enum).
  Map<String, dynamic> toJson() => <String, dynamic>{
        'style': style.name,
        'c1': color1,
        'c2': color2,
        'pc': patternColor,
        'th': thickness,
        'r': radius,
        'in': inset,
        'cell': cell,
      };

  /// Rebuild a spec from [toJson] output; null if the style name is unknown
  /// (e.g. a preset saved by a newer build). Missing fields fall back to the
  /// constructor defaults.
  static OverlaySpec? fromJson(Map<String, dynamic> j) {
    final Object? s = j['style'];
    if (s is! String) return null;
    OverlayStyle? style;
    for (final OverlayStyle e in OverlayStyle.values) {
      if (e.name == s) {
        style = e;
        break;
      }
    }
    if (style == null) return null;
    int asInt(Object? v, int def) =>
        v is int ? v : (v is num ? v.toInt() : def);
    double asDouble(Object? v, double def) => v is num ? v.toDouble() : def;
    return OverlaySpec(
      style: style,
      color1: asInt(j['c1'], 0xFF80AB),
      color2: asInt(j['c2'], 0xA8D8EA),
      patternColor: asInt(j['pc'], 0xFFFFFF),
      thickness: asDouble(j['th'], 0.08),
      radius: asDouble(j['r'], 0.12),
      inset: asDouble(j['in'], 0.0),
      cell: asDouble(j['cell'], 0.26),
    );
  }
}

/// A named, categorised overlay. Its [spec] is editable, so the builder can
/// "start from" any preset.
class OverlayPreset {
  OverlayPreset(this.name, this.category, this.spec);
  final String name;
  final String category;
  final OverlaySpec spec;
  OverlayKind get kind => spec.kind;
  img.Image build(int size) => spec.build(size);
}

// ---- palettes ---------------------------------------------------------------

const int _uGold = 0xD4AF37;
const int _uCrimson = 0x7A0E1A;
const int _uBlood = 0xB11226;
const int _uPurple = 0x3A1F3D;

const int _drPink = 0xFF2E88;
const int _drDespair = 0xE5006E;
const int _drHope = 0xFF6FB5;
const int _drBlack = 0x171717;
const int _drWhite = 0xF5F5F5;

const int _limbusRed = 0x9E2B28; // Limbus Company identity-frame crimson

const int _sakura = 0xFFB7C5;
const int _lavender = 0xC9B6E4;
const int _mint = 0xB5EAD7;
const int _peach = 0xFFD9BA;
const int _babyBlue = 0xA8D8EA;
const int _lemon = 0xFDF3A0;
const int _rose = 0xFF9EC4;

/// Name → colour for the big "Colours" set (used for both a frame and a soft bg).
const List<(String, int)> _palette = <(String, int)>[
  ('White', 0xFFFFFF), ('Black', 0x141414), ('Red', 0xE53935),
  ('Crimson', 0xB11226), ('Pink', 0xFF80AB), ('Hot Pink', 0xFF2E88),
  ('Rose', 0xFF9EC4), ('Peach', 0xFFCBA4), ('Orange', 0xFB8C00),
  ('Gold', 0xD4AF37), ('Yellow', 0xFDD835), ('Lime', 0xAEEA00),
  ('Green', 0x43A047), ('Mint', 0xB5EAD7), ('Teal', 0x00897B),
  ('Cyan', 0x26C6DA), ('Sky', 0xA8D8EA), ('Blue', 0x1E88E5),
  ('Indigo', 0x5C6BC0), ('Lavender', 0xC9B6E4), ('Purple', 0x8E24AA),
  ('Lilac', 0xD7BDE2), ('Brown', 0x8D6E63), ('Grey', 0x9E9E9E),
];

class OverlayPresets {
  const OverlayPresets._();

  static final List<OverlayPreset> borders = <OverlayPreset>[
    // Umineko — gilded frames.
    OverlayPreset('Umineko Gold', 'Umineko',
        OverlaySpec(style: OverlayStyle.doubleFrame, color1: _uGold, color2: _uGold, thickness: .055, radius: .06)),
    OverlayPreset('Umineko Crimson', 'Umineko',
        OverlaySpec(style: OverlayStyle.doubleFrame, color1: _uCrimson, color2: _uGold, thickness: .08, radius: .05)),
    OverlayPreset('Golden Corners', 'Umineko',
        OverlaySpec(style: OverlayStyle.corners, color1: _uGold, thickness: .07)),

    // Danganronpa.
    OverlayPreset('DR Pink', 'Danganronpa',
        OverlaySpec(style: OverlayStyle.frame, color1: _drPink, thickness: .09, radius: .04)),
    OverlayPreset('Despair', 'Danganronpa',
        OverlaySpec(style: OverlayStyle.frame, color1: _drDespair, thickness: .08, radius: .2)),
    OverlayPreset('Monokuma', 'Danganronpa',
        OverlaySpec(style: OverlayStyle.splitFrame, color1: _drBlack, color2: _drWhite, thickness: .1)),

    // Limbus Company — thin inset crimson identity frame.
    OverlayPreset('Limbus', 'Limbus',
        OverlaySpec(style: OverlayStyle.frame, color1: _limbusRed, thickness: .032, radius: 0, inset: .025)),

    // Kawaii pastels.
    OverlayPreset('Sakura', 'Kawaii',
        OverlaySpec(style: OverlayStyle.frame, color1: _sakura, thickness: .08, radius: .24)),
    OverlayPreset('Lavender', 'Kawaii',
        OverlaySpec(style: OverlayStyle.frame, color1: _lavender, thickness: .08, radius: .24)),
    OverlayPreset('Mint', 'Kawaii',
        OverlaySpec(style: OverlayStyle.frame, color1: _mint, thickness: .08, radius: .24)),
    OverlayPreset('Cotton Candy', 'Kawaii',
        OverlaySpec(style: OverlayStyle.gradientFrame, color1: _sakura, color2: _babyBlue, thickness: .09, radius: .22)),
    OverlayPreset('Pastel Rainbow', 'Kawaii',
        OverlaySpec(style: OverlayStyle.rainbowFrame, thickness: .1, radius: .2)),
    OverlayPreset('Heart Corners', 'Kawaii',
        OverlaySpec(style: OverlayStyle.cornerHearts, color1: _rose, thickness: .075, radius: .22)),

    // Classic.
    OverlayPreset('White Frame', 'Classic',
        OverlaySpec(style: OverlayStyle.frame, color1: 0xFFFFFF, thickness: .06, radius: 0)),
    OverlayPreset('Black Frame', 'Classic',
        OverlaySpec(style: OverlayStyle.frame, color1: 0x000000, thickness: .06, radius: 0)),
    OverlayPreset('Double Gold', 'Classic',
        OverlaySpec(style: OverlayStyle.doubleFrame, color1: _uGold, color2: _uGold, thickness: .035, radius: 0)),

    // Many colours.
    for (final c in _palette)
      OverlayPreset(c.$1, 'Colours',
          OverlaySpec(style: OverlayStyle.frame, color1: c.$2, thickness: .08, radius: .14)),
  ];

  static final List<OverlayPreset> backgrounds = <OverlayPreset>[
    // Umineko.
    OverlayPreset('Umineko Crimson', 'Umineko',
        OverlaySpec(style: OverlayStyle.radialGradient, color1: _uBlood, color2: _uCrimson)),
    OverlayPreset('Umineko Night', 'Umineko',
        OverlaySpec(style: OverlayStyle.linearGradient, color1: _uPurple, color2: _uCrimson)),
    OverlayPreset('Golden Hour', 'Umineko',
        OverlaySpec(style: OverlayStyle.radialGradient, color1: _uGold, color2: _uCrimson)),

    // Danganronpa.
    OverlayPreset('Despair', 'Danganronpa',
        OverlaySpec(style: OverlayStyle.radialGradient, color1: _drPink, color2: _drBlack)),
    OverlayPreset('Monokuma', 'Danganronpa',
        OverlaySpec(style: OverlayStyle.diagonalSplit, color1: _drBlack, color2: _drWhite)),
    OverlayPreset('Hope Pink', 'Danganronpa',
        OverlaySpec(style: OverlayStyle.linearGradient, color1: _drHope, color2: _drPink)),

    // Kawaii.
    OverlayPreset('Pastel Dream', 'Kawaii',
        OverlaySpec(style: OverlayStyle.linearGradient, color1: _sakura, color2: _lavender)),
    OverlayPreset('Cotton Candy', 'Kawaii',
        OverlaySpec(style: OverlayStyle.linearGradient, color1: _sakura, color2: _babyBlue)),
    OverlayPreset('Sakura Petals', 'Kawaii',
        OverlaySpec(style: OverlayStyle.dots, color1: _sakura, patternColor: 0xFFFFFF)),
    OverlayPreset('Mint Hearts', 'Kawaii',
        OverlaySpec(style: OverlayStyle.hearts, color1: _mint, patternColor: 0xFFFFFF)),
    OverlayPreset('Peach Hearts', 'Kawaii',
        OverlaySpec(style: OverlayStyle.hearts, color1: _peach, patternColor: 0xFFFFFF)),
    OverlayPreset('Lemon Dots', 'Kawaii',
        OverlaySpec(style: OverlayStyle.dots, color1: _lemon, patternColor: 0xFFFFFF)),
    OverlayPreset('Lavender Sparkle', 'Kawaii',
        OverlaySpec(style: OverlayStyle.sparkles, color1: _lavender, patternColor: 0xFFFFFF)),

    // Vibes.
    OverlayPreset('Rainbow', 'Vibes', OverlaySpec(style: OverlayStyle.rainbow)),
    OverlayPreset('Sunset', 'Vibes',
        OverlaySpec(style: OverlayStyle.linearGradient, color1: 0xFFC371, color2: _uPurple)),
    OverlayPreset('Ocean', 'Vibes',
        OverlaySpec(style: OverlayStyle.linearGradient, color1: _babyBlue, color2: 0x1565C0)),
    OverlayPreset('Vaporwave', 'Vibes',
        OverlaySpec(style: OverlayStyle.linearGradient, color1: 0xFF6AD5, color2: 0x8795E8)),

    // Many colours (soft radial of each).
    for (final c in _palette)
      OverlayPreset(c.$1, 'Colours',
          OverlaySpec(style: OverlayStyle.radialGradient, color1: _lighten(c.$2, .35), color2: c.$2)),
  ];

  static List<OverlayPreset> forKind(OverlayKind kind) =>
      kind == OverlayKind.border ? borders : backgrounds;

  /// A sensible blank starting point for the builder, per slot kind.
  static OverlaySpec defaultSpec(OverlayKind kind) => kind == OverlayKind.border
      ? OverlaySpec(style: OverlayStyle.frame, color1: _drPink, thickness: .08, radius: .12)
      : OverlaySpec(style: OverlayStyle.linearGradient, color1: _sakura, color2: _lavender);
}

// ---- colour helpers ---------------------------------------------------------

int _ri(int c) => (c >> 16) & 0xFF;
int _gi(int c) => (c >> 8) & 0xFF;
int _bi(int c) => c & 0xFF;
int _mix(int a, int b, double t) => (a + (b - a) * t).round().clamp(0, 255);
int _lighten(int c, double t) =>
    (_mix(_ri(c), 255, t) << 16) | (_mix(_gi(c), 255, t) << 8) | _mix(_bi(c), 255, t);

int _hsv(double h, double s, double v) {
  h = h % 360;
  if (h < 0) h += 360;
  final double c = v * s;
  final double x = c * (1 - ((h / 60) % 2 - 1).abs());
  final double m = v - c;
  double r = 0, g = 0, b = 0;
  if (h < 60) {
    r = c;
    g = x;
  } else if (h < 120) {
    r = x;
    g = c;
  } else if (h < 180) {
    g = c;
    b = x;
  } else if (h < 240) {
    g = x;
    b = c;
  } else if (h < 300) {
    r = x;
    b = c;
  } else {
    r = c;
    b = x;
  }
  return (((r + m) * 255).round() << 16) |
      (((g + m) * 255).round() << 8) |
      ((b + m) * 255).round();
}

// ---- spec → image -----------------------------------------------------------

img.Image _buildSpec(OverlaySpec s, int size) {
  switch (s.style) {
    case OverlayStyle.frame:
      return _ring(size, s.color1,
          inset: s.inset, thickness: s.thickness, radiusFrac: s.radius);
    case OverlayStyle.doubleFrame:
      return _stack(size, <img.Image>[
        _ring(size, s.color1, inset: s.inset, thickness: s.thickness, radiusFrac: s.radius),
        _ring(size, s.color2,
            inset: s.inset + s.thickness + 0.045,
            thickness: (s.thickness * 0.45).clamp(0.01, 1.0),
            radiusFrac: math.max(0.0, s.radius - s.thickness)),
      ]);
    case OverlayStyle.corners:
      return _corners(size, s.color1, thickness: s.thickness);
    case OverlayStyle.cornerHearts:
      return _stack(size, <img.Image>[
        _ring(size, s.color1,
            thickness: (s.thickness * 0.6).clamp(0.01, 1.0), radiusFrac: s.radius),
        _cornerHearts(size, s.color1),
      ]);
    case OverlayStyle.gradientFrame:
      return _gradientRing(size, s.color1, s.color2,
          thickness: s.thickness, radiusFrac: s.radius);
    case OverlayStyle.rainbowFrame:
      return _rainbowRing(size, thickness: s.thickness, radiusFrac: s.radius, pastel: true);
    case OverlayStyle.splitFrame:
      return _splitFrame(size, s.color1, s.color2, thickness: s.thickness);
    case OverlayStyle.solid:
      return _solid(size, s.color1);
    case OverlayStyle.linearGradient:
      return _linear(size, s.color1, s.color2);
    case OverlayStyle.radialGradient:
      return _radial(size, s.color1, s.color2);
    case OverlayStyle.diagonalSplit:
      return _diagSplit(size, s.color1, s.color2);
    case OverlayStyle.dots:
      return _dots(size, s.color1, s.patternColor, cellFrac: s.cell);
    case OverlayStyle.hearts:
      return _hearts(size, s.color1, s.patternColor, cellFrac: s.cell);
    case OverlayStyle.sparkles:
      return _sparkles(size, s.color1, s.patternColor, cellFrac: s.cell);
    case OverlayStyle.rainbow:
      return _rainbowBg(size);
  }
}

// ---- drawing primitives -----------------------------------------------------

img.Image _canvas(int s) => img.Image(width: s, height: s, numChannels: 4);

img.Image _solid(int s, int c) {
  final img.Image im = _canvas(s);
  _fill(im, c);
  return im;
}

void _set(img.Image im, int x, int y, int c, [int a = 255]) {
  if (x >= 0 && y >= 0 && x < im.width && y < im.height) {
    im.setPixelRgba(x, y, _ri(c), _gi(c), _bi(c), a);
  }
}

void _fill(img.Image im, int c) {
  for (int y = 0; y < im.height; y++) {
    for (int x = 0; x < im.width; x++) {
      _set(im, x, y, c);
    }
  }
}

img.Image _stack(int s, List<img.Image> layers) {
  final img.Image im = _canvas(s);
  for (final img.Image l in layers) {
    img.compositeImage(im, l, dstX: 0, dstY: 0);
  }
  return im;
}

bool _inRoundRect(double x, double y, double l, double t, double r, double b, double rad) {
  if (x < l || x > r || y < t || y > b) return false;
  if (rad <= 0) return true;
  final double cxl = l + rad, cxr = r - rad, cyt = t + rad, cyb = b - rad;
  double dx, dy;
  if (x < cxl && y < cyt) {
    dx = x - cxl;
    dy = y - cyt;
  } else if (x > cxr && y < cyt) {
    dx = x - cxr;
    dy = y - cyt;
  } else if (x < cxl && y > cyb) {
    dx = x - cxl;
    dy = y - cyb;
  } else if (x > cxr && y > cyb) {
    dx = x - cxr;
    dy = y - cyb;
  } else {
    return true;
  }
  return dx * dx + dy * dy <= rad * rad;
}

/// A rectangular (optionally rounded) frame ring.
img.Image _ring(int s, int color,
    {double inset = 0, double thickness = 0.08, double radiusFrac = 0, int alpha = 255}) {
  final img.Image im = _canvas(s);
  final double ins = inset * s;
  final double t = (thickness * s).clamp(1, s / 2).toDouble();
  final double l = ins, top = ins, r = s - 1 - ins, b = s - 1 - ins;
  final double rad = radiusFrac * s;
  final double innerRad = math.max(0.0, rad - t);
  for (int y = 0; y < s; y++) {
    for (int x = 0; x < s; x++) {
      final double px = x + 0.5, py = y + 0.5;
      final bool outer = _inRoundRect(px, py, l, top, r, b, rad);
      final bool inner = _inRoundRect(px, py, l + t, top + t, r - t, b - t, innerRad);
      if (outer && !inner) _set(im, x, y, color, alpha);
    }
  }
  return im;
}

/// A ring recoloured left→right by a gradient.
img.Image _gradientRing(int s, int c0, int c1, {double thickness = .09, double radiusFrac = .1}) {
  final img.Image im = _ring(s, 0xFFFFFF, thickness: thickness, radiusFrac: radiusFrac);
  for (int y = 0; y < s; y++) {
    for (int x = 0; x < s; x++) {
      final img.Pixel p = im.getPixel(x, y);
      if (p.a > 0) {
        final double t = s <= 1 ? 0 : x / (s - 1);
        im.setPixelRgba(x, y, _mix(_ri(c0), _ri(c1), t), _mix(_gi(c0), _gi(c1), t),
            _mix(_bi(c0), _bi(c1), t), p.a.toInt());
      }
    }
  }
  return im;
}

img.Image _rainbowRing(int s, {double thickness = .1, double radiusFrac = .15, bool pastel = false}) {
  final img.Image im = _ring(s, 0xFFFFFF, thickness: thickness, radiusFrac: radiusFrac);
  for (int y = 0; y < s; y++) {
    for (int x = 0; x < s; x++) {
      final img.Pixel p = im.getPixel(x, y);
      if (p.a > 0) {
        final int col = _hsv((x / s) * 320, pastel ? 0.45 : 0.9, 1.0);
        im.setPixelRgba(x, y, _ri(col), _gi(col), _bi(col), p.a.toInt());
      }
    }
  }
  return im;
}

/// Frame whose left half is [left] and right half [right] (Monokuma).
img.Image _splitFrame(int s, int left, int right, {double thickness = .09}) {
  final img.Image im = _canvas(s);
  final int t = (s * thickness).round().clamp(1, s ~/ 2);
  for (int y = 0; y < s; y++) {
    for (int x = 0; x < s; x++) {
      final int edge = math.min(math.min(x, y), math.min(s - 1 - x, s - 1 - y));
      if (edge < t) _set(im, x, y, x < s / 2 ? left : right);
    }
  }
  return im;
}

/// L-shaped brackets in the four corners.
img.Image _corners(int s, int color, {double thickness = .07, double lenFrac = .3}) {
  final img.Image im = _canvas(s);
  final int t = (s * thickness).round().clamp(1, s);
  final int len = (s * lenFrac).round().clamp(t, s);
  void bar(int x0, int y0, int w, int h) {
    for (int y = y0; y < y0 + h; y++) {
      for (int x = x0; x < x0 + w; x++) {
        _set(im, x, y, color);
      }
    }
  }

  bar(0, 0, len, t);
  bar(0, 0, t, len); // TL
  bar(s - len, 0, len, t);
  bar(s - t, 0, t, len); // TR
  bar(0, s - t, len, t);
  bar(0, s - len, t, len); // BL
  bar(s - len, s - t, len, t);
  bar(s - t, s - len, t, len); // BR
  return im;
}

img.Image _cornerHearts(int s, int color) {
  final img.Image im = _canvas(s);
  final double h = s * 0.12;
  final double off = s * 0.16;
  for (final List<double> c in <List<double>>[
    <double>[off, off],
    <double>[s - off, off],
    <double>[off, s - off],
    <double>[s - off, s - off],
  ]) {
    _drawHeart(im, c[0], c[1], h, color);
  }
  return im;
}

bool _inHeart(double nx, double ny) {
  final double a = nx * nx + ny * ny - 1;
  return a * a * a - nx * nx * ny * ny * ny <= 0;
}

void _drawHeart(img.Image im, double cx, double cy, double h, int color, [int alpha = 235]) {
  final int x0 = (cx - h * 1.3).floor(), x1 = (cx + h * 1.3).ceil();
  final int y0 = (cy - h * 1.3).floor(), y1 = (cy + h * 1.3).ceil();
  for (int y = y0; y <= y1; y++) {
    for (int x = x0; x <= x1; x++) {
      final double nx = (x - cx) / h;
      final double ny = (cy - y) / h + 0.25; // shift so the heart sits centred
      if (_inHeart(nx, ny)) _set(im, x, y, color, alpha);
    }
  }
}

// ---- backgrounds ------------------------------------------------------------

img.Image _linear(int s, int c0, int c1, {bool vertical = true}) {
  final img.Image im = _canvas(s);
  for (int y = 0; y < s; y++) {
    for (int x = 0; x < s; x++) {
      final double t = s <= 1 ? 0 : (vertical ? y : x) / (s - 1);
      im.setPixelRgba(x, y, _mix(_ri(c0), _ri(c1), t), _mix(_gi(c0), _gi(c1), t),
          _mix(_bi(c0), _bi(c1), t), 255);
    }
  }
  return im;
}

img.Image _radial(int s, int inner, int outer) {
  final img.Image im = _canvas(s);
  final double cx = s / 2, cy = s / 2;
  final double maxR = math.sqrt(2) * s / 2;
  for (int y = 0; y < s; y++) {
    for (int x = 0; x < s; x++) {
      final double dx = x - cx, dy = y - cy;
      final double t = (math.sqrt(dx * dx + dy * dy) / maxR).clamp(0.0, 1.0);
      im.setPixelRgba(x, y, _mix(_ri(inner), _ri(outer), t),
          _mix(_gi(inner), _gi(outer), t), _mix(_bi(inner), _bi(outer), t), 255);
    }
  }
  return im;
}

img.Image _diagSplit(int s, int a, int b) {
  final img.Image im = _canvas(s);
  for (int y = 0; y < s; y++) {
    for (int x = 0; x < s; x++) {
      _set(im, x, y, x + y < s ? a : b);
    }
  }
  return im;
}

img.Image _rainbowBg(int s) {
  final img.Image im = _canvas(s);
  for (int y = 0; y < s; y++) {
    final int col = _hsv((y / s) * 320, 0.7, 1.0);
    for (int x = 0; x < s; x++) {
      _set(im, x, y, col);
    }
  }
  return im;
}

img.Image _dots(int s, int bg, int dot, {double cellFrac = .26, double rFrac = .06, int alpha = 190}) {
  final img.Image im = _canvas(s);
  _fill(im, bg);
  final int cell = (s * cellFrac).round().clamp(4, s);
  final double r = s * rFrac;
  int row = 0;
  for (int cyc = cell ~/ 2; cyc < s + cell; cyc += cell) {
    final int xoff = row.isEven ? 0 : cell ~/ 2;
    for (int cxc = cell ~/ 2 - cell; cxc < s + cell; cxc += cell) {
      _disc(im, (cxc + xoff).toDouble(), cyc.toDouble(), r, dot, alpha);
    }
    row++;
  }
  return im;
}

void _disc(img.Image im, double cx, double cy, double r, int color, int alpha) {
  final int x0 = (cx - r).floor(), x1 = (cx + r).ceil();
  final int y0 = (cy - r).floor(), y1 = (cy + r).ceil();
  for (int y = y0; y <= y1; y++) {
    for (int x = x0; x <= x1; x++) {
      final double dx = x - cx, dy = y - cy;
      if (dx * dx + dy * dy <= r * r) _set(im, x, y, color, alpha);
    }
  }
}

img.Image _hearts(int s, int bg, int heart, {double cellFrac = .3, int alpha = 200}) {
  final img.Image im = _canvas(s);
  _fill(im, bg);
  final int cell = (s * cellFrac).round().clamp(6, s);
  final double h = cell * 0.32;
  int row = 0;
  for (int cyc = cell ~/ 2; cyc < s + cell; cyc += cell) {
    final int xoff = row.isEven ? 0 : cell ~/ 2;
    for (int cxc = cell ~/ 2 - cell; cxc < s + cell; cxc += cell) {
      _drawHeart(im, (cxc + xoff).toDouble(), cyc.toDouble(), h, heart, alpha);
    }
    row++;
  }
  return im;
}

img.Image _sparkles(int s, int bg, int spark, {double cellFrac = .28, int alpha = 210}) {
  final img.Image im = _canvas(s);
  _fill(im, bg);
  final int cell = (s * cellFrac).round().clamp(6, s);
  final double h = cell * 0.34;
  int row = 0;
  for (int cyc = cell ~/ 2; cyc < s + cell; cyc += cell) {
    final int xoff = row.isEven ? 0 : cell ~/ 2;
    for (int cxc = cell ~/ 2 - cell; cxc < s + cell; cxc += cell) {
      _drawSpark(im, (cxc + xoff).toDouble(), cyc.toDouble(), h, spark, alpha);
    }
    row++;
  }
  return im;
}

/// A 4-point sparkle (an astroid: |x|^0.5 + |y|^0.5 ≤ 1).
void _drawSpark(img.Image im, double cx, double cy, double h, int color, int alpha) {
  final int x0 = (cx - h).floor(), x1 = (cx + h).ceil();
  final int y0 = (cy - h).floor(), y1 = (cy + h).ceil();
  for (int y = y0; y <= y1; y++) {
    for (int x = x0; x <= x1; x++) {
      final double nx = ((x - cx) / h).abs();
      final double ny = ((y - cy) / h).abs();
      if (math.sqrt(nx) + math.sqrt(ny) <= 1.0) _set(im, x, y, color, alpha);
    }
  }
}
