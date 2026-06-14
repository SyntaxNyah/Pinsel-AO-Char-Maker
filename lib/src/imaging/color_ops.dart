/// The colour-operation pipeline.
///
/// Every recolouring/manipulation feature in the app is expressed as a list of
/// [ColorOp]s. The *same* pipeline drives:
///   * the real-time preview (applied to a small downscaled image as you drag),
///   * bulk processing (applied to full-resolution sprites across many files),
///   * saved presets (a named pipeline), and
///   * plugin packs (JSON that composes built-in ops into new presets).
///
/// Ops are identified by a string id (not an enum) so plugins can reference any
/// registered op. New *code* ops can be registered via [ImageOps.register]
/// (native plugins); data packs compose existing ops into presets (works on web
/// too, since no native code is required).
library;

import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// A single configured operation. Numeric and string/colour params are stored
/// generically so the whole thing serialises trivially to/from JSON.
class ColorOp {
  ColorOp(this.type, {Map<String, double>? nums, Map<String, String>? strs})
      : nums = nums ?? <String, double>{},
        strs = strs ?? <String, String>{};

  final String type;
  final Map<String, double> nums;
  final Map<String, String> strs;

  double n(String key, [double fallback = 0]) => nums[key] ?? fallback;
  String s(String key, [String fallback = '']) => strs[key] ?? fallback;

  /// Parse `#rrggbb`/`#aarrggbb`/`rrggbb` colour params into ARGB ints.
  int color(String key, [int fallback = 0xFFFFFFFF]) =>
      parseHexColor(strs[key]) ?? fallback;

  ColorOp copyWith({Map<String, double>? nums, Map<String, String>? strs}) =>
      ColorOp(type,
          nums: <String, double>{...this.nums, ...?nums},
          strs: <String, String>{...this.strs, ...?strs});

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type,
        if (nums.isNotEmpty) 'nums': nums,
        if (strs.isNotEmpty) 'strs': strs,
      };

  static ColorOp fromJson(Map<String, dynamic> j) => ColorOp(
        j['type'] as String,
        nums: (j['nums'] as Map?)?.map(
            (Object? k, Object? v) => MapEntry<String, double>(
                k.toString(), (v as num).toDouble())),
        strs: (j['strs'] as Map?)?.map((Object? k, Object? v) =>
            MapEntry<String, String>(k.toString(), v.toString())),
      );
}

/// A named, reusable pipeline (this is what a "preset" is).
class OpPipeline {
  OpPipeline(this.name, this.ops, {this.category = 'Custom', this.description});

  String name;
  String category;
  String? description;
  List<ColorOp> ops;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'category': category,
        if (description != null) 'description': description,
        'ops': ops.map((ColorOp o) => o.toJson()).toList(),
      };

  static OpPipeline fromJson(Map<String, dynamic> j) => OpPipeline(
        j['name'] as String? ?? 'Preset',
        ((j['ops'] as List?) ?? <dynamic>[])
            .map((dynamic e) => ColorOp.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        category: j['category'] as String? ?? 'Custom',
        description: j['description'] as String?,
      );
}

typedef OpApply = void Function(img.Image frame, ColorOp op);

/// Registry + executor for colour ops.
class ImageOps {
  ImageOps._();

  static final Map<String, OpApply> _registry = <String, OpApply>{
    'hueShift': _hueShift,
    'saturation': _saturation,
    'vibrance': _vibrance,
    'brightness': _brightness,
    'contrast': _contrast,
    'gamma': _gamma,
    'exposure': _exposure,
    'levels': _levels,
    'invert': _invert,
    'grayscale': _grayscale,
    'sepia': _sepia,
    'temperature': _temperature,
    'tint': _tint,
    'colorize': _colorize,
    'solidColor': _solidColor,
    'gradientMap': _gradientMap,
    'duotone': _duotone,
    'replaceColor': _replaceColor,
    'selectiveHue': _selectiveHue,
    'posterize': _posterize,
    'threshold': _threshold,
    'opacity': _opacity,
    'alphaThreshold': _alphaThreshold,
    'channelSwap': _channelSwap,
    'colorBalance': _colorBalance,
    'splitTone': _splitTone,
    'selectiveSaturation': _selectiveSaturation,
    'hsvAdjust': _hsvAdjust,
    'vignette': _vignette,
    'scanlines': _scanlines,
    'noise': _noise,
    'chromaShift': _chromaShift,
    'pixelate': _pixelate,
    'solarize': _solarize,
    'gradientTint': _gradientTint,
    'dither': _dither,
    'crossProcess': _crossProcess,
    'bleachBypass': _bleachBypass,
    'sharpen': _sharpen,
    'blur': _blur,
    'outline': _outline,
    'dropShadow': _dropShadow,
    'glow': _glow,
  };

  /// All op ids currently registered (built-ins + any plugin code ops).
  static List<String> get registeredOps => _registry.keys.toList()..sort();

  /// Register a new code op (native plugin extension point).
  static void register(String id, OpApply fn) => _registry[id] = fn;

  /// Apply a single op across every frame of [image], in place.
  static void apply(img.Image image, ColorOp op) {
    final OpApply? fn = _registry[op.type];
    if (fn == null) return; // unknown op id -> silently skipped
    for (final img.Image frame in _framesOf(image)) {
      fn(frame, op);
    }
  }

  /// Apply a full pipeline in order, in place.
  static void applyAll(img.Image image, List<ColorOp> ops) {
    for (final ColorOp op in ops) {
      apply(image, op);
    }
  }

  static Iterable<img.Image> _framesOf(img.Image image) =>
      image.frames.isEmpty ? <img.Image>[image] : image.frames;

  // ---------------------------------------------------------------------------
  // Built-in operations. Each respects alpha: fully-transparent pixels are
  // never recoloured, so silhouettes stay clean.
  // ---------------------------------------------------------------------------

  static void _eachPixel(
      img.Image f, void Function(int x, int y, _Rgba px) body) {
    // Hot path. Iterate the frame's pixel cursor **sequentially** (no per-pixel
    // `getPixel(x,y)` random access) and reuse one `_Rgba` instead of allocating
    // one per pixel — this is the single biggest speed-up for recolour, bulk
    // ops and animation (every op funnels through here).
    final _Rgba px = _Rgba(0, 0, 0, 0);
    for (final img.Pixel p in f) {
      final int a = p.a.toInt();
      if (a == 0) continue; // never touch fully transparent pixels
      px.r = p.r.toInt();
      px.g = p.g.toInt();
      px.b = p.b.toInt();
      px.a = a;
      body(p.x, p.y, px);
      p
        ..r = px.r
        ..g = px.g
        ..b = px.b
        ..a = px.a;
    }
  }

  static void _hueShift(img.Image f, ColorOp op) {
    final double deg = op.n('degrees');
    _eachPixel(f, (int x, int y, _Rgba px) {
      final _Hsv h = _Hsv.fromRgb(px);
      h.h = (h.h + deg) % 360.0;
      if (h.h < 0) h.h += 360.0;
      h.toRgb(px);
    });
  }

  static void _saturation(img.Image f, ColorOp op) {
    final double mul = op.n('amount', 1);
    _eachPixel(f, (int x, int y, _Rgba px) {
      final _Hsv h = _Hsv.fromRgb(px);
      h.s = (h.s * mul).clamp(0.0, 1.0);
      h.toRgb(px);
    });
  }

  static void _vibrance(img.Image f, ColorOp op) {
    final double amt = op.n('amount'); // -1..1, boosts low-sat pixels more
    _eachPixel(f, (int x, int y, _Rgba px) {
      final _Hsv h = _Hsv.fromRgb(px);
      final double boost = amt * (1.0 - h.s);
      h.s = (h.s + boost).clamp(0.0, 1.0);
      h.toRgb(px);
    });
  }

  static void _brightness(img.Image f, ColorOp op) {
    final double mul = op.n('amount', 1);
    _eachPixel(f, (int x, int y, _Rgba px) {
      px.r = (px.r * mul).round().clamp(0, 255);
      px.g = (px.g * mul).round().clamp(0, 255);
      px.b = (px.b * mul).round().clamp(0, 255);
    });
  }

  static void _contrast(img.Image f, ColorOp op) {
    final double c = op.n('amount', 1);
    _eachPixel(f, (int x, int y, _Rgba px) {
      px.r = (((px.r - 128) * c) + 128).round().clamp(0, 255);
      px.g = (((px.g - 128) * c) + 128).round().clamp(0, 255);
      px.b = (((px.b - 128) * c) + 128).round().clamp(0, 255);
    });
  }

  static void _gamma(img.Image f, ColorOp op) {
    final double g = math.max(0.01, op.n('amount', 1));
    final double inv = 1.0 / g;
    _eachPixel(f, (int x, int y, _Rgba px) {
      px.r = (math.pow(px.r / 255.0, inv) * 255).round().clamp(0, 255);
      px.g = (math.pow(px.g / 255.0, inv) * 255).round().clamp(0, 255);
      px.b = (math.pow(px.b / 255.0, inv) * 255).round().clamp(0, 255);
    });
  }

  static void _exposure(img.Image f, ColorOp op) {
    final double stops = op.n('stops');
    final double mul = math.pow(2.0, stops).toDouble();
    _eachPixel(f, (int x, int y, _Rgba px) {
      px.r = (px.r * mul).round().clamp(0, 255);
      px.g = (px.g * mul).round().clamp(0, 255);
      px.b = (px.b * mul).round().clamp(0, 255);
    });
  }

  static void _levels(img.Image f, ColorOp op) {
    final double inB = op.n('inBlack');
    final double inW = op.n('inWhite', 255);
    final double outB = op.n('outBlack');
    final double outW = op.n('outWhite', 255);
    final double gamma = math.max(0.01, op.n('gamma', 1));
    final double range = math.max(1.0, inW - inB);
    int map(int v) {
      double t = ((v - inB) / range).clamp(0.0, 1.0);
      t = math.pow(t, 1.0 / gamma).toDouble();
      return (outB + t * (outW - outB)).round().clamp(0, 255);
    }

    _eachPixel(f, (int x, int y, _Rgba px) {
      px.r = map(px.r);
      px.g = map(px.g);
      px.b = map(px.b);
    });
  }

  static void _invert(img.Image f, ColorOp op) {
    _eachPixel(f, (int x, int y, _Rgba px) {
      px.r = 255 - px.r;
      px.g = 255 - px.g;
      px.b = 255 - px.b;
    });
  }

  static void _grayscale(img.Image f, ColorOp op) {
    final double amt = op.n('amount', 1).clamp(0.0, 1.0);
    _eachPixel(f, (int x, int y, _Rgba px) {
      final int l = _luma(px);
      px.r = (px.r + (l - px.r) * amt).round();
      px.g = (px.g + (l - px.g) * amt).round();
      px.b = (px.b + (l - px.b) * amt).round();
    });
  }

  static void _sepia(img.Image f, ColorOp op) {
    final double amt = op.n('amount', 1).clamp(0.0, 1.0);
    _eachPixel(f, (int x, int y, _Rgba px) {
      final int r = px.r, g = px.g, b = px.b;
      final int sr = (0.393 * r + 0.769 * g + 0.189 * b).round().clamp(0, 255);
      final int sg = (0.349 * r + 0.686 * g + 0.168 * b).round().clamp(0, 255);
      final int sb = (0.272 * r + 0.534 * g + 0.131 * b).round().clamp(0, 255);
      px.r = (r + (sr - r) * amt).round();
      px.g = (g + (sg - g) * amt).round();
      px.b = (b + (sb - b) * amt).round();
    });
  }

  static void _temperature(img.Image f, ColorOp op) {
    // amount -1 (cool) .. +1 (warm)
    final double amt = op.n('amount');
    final int rShift = (amt * 40).round();
    final int bShift = (-amt * 40).round();
    _eachPixel(f, (int x, int y, _Rgba px) {
      px.r = (px.r + rShift).clamp(0, 255);
      px.b = (px.b + bShift).clamp(0, 255);
    });
  }

  static void _tint(img.Image f, ColorOp op) {
    final int c = op.color('color');
    final double amt = op.n('amount', 0.5).clamp(0.0, 1.0);
    final int tr = (c >> 16) & 0xFF, tg = (c >> 8) & 0xFF, tb = c & 0xFF;
    _eachPixel(f, (int x, int y, _Rgba px) {
      px.r = (px.r + (tr - px.r) * amt).round();
      px.g = (px.g + (tg - px.g) * amt).round();
      px.b = (px.b + (tb - px.b) * amt).round();
    });
  }

  /// The "make Mario pink" op: re-hue every pixel toward a target hue/sat while
  /// preserving each pixel's brightness, so shading and highlights are kept.
  static void _colorize(img.Image f, ColorOp op) {
    final double hue = op.n('hue');
    final double sat = op.n('saturation', 1).clamp(0.0, 1.0);
    final double strength = op.n('strength', 1).clamp(0.0, 1.0);
    _eachPixel(f, (int x, int y, _Rgba px) {
      final _Hsv src = _Hsv.fromRgb(px);
      final _Hsv tgt = _Hsv(hue, sat, src.v);
      final _Rgba out = _Rgba(0, 0, 0, px.a);
      tgt.toRgb(out);
      px.r = (px.r + (out.r - px.r) * strength).round();
      px.g = (px.g + (out.g - px.g) * strength).round();
      px.b = (px.b + (out.b - px.b) * strength).round();
    });
  }

  static void _solidColor(img.Image f, ColorOp op) {
    final int c = op.color('color');
    final int r = (c >> 16) & 0xFF, g = (c >> 8) & 0xFF, b = c & 0xFF;
    _eachPixel(f, (int x, int y, _Rgba px) {
      px.r = r;
      px.g = g;
      px.b = b;
    });
  }

  /// Map luminance through a multi-stop gradient (stops packed as
  /// `stop0`=#rrggbb @ `pos0`=0..1, `stop1`, `pos1`, ...).
  static void _gradientMap(img.Image f, ColorOp op) {
    final List<_GradStop> stops = _readStops(op);
    if (stops.isEmpty) return;
    final double strength = op.n('strength', 1).clamp(0.0, 1.0);
    _eachPixel(f, (int x, int y, _Rgba px) {
      final double t = _luma(px) / 255.0;
      final _Rgba g = _sampleGradient(stops, t, px.a);
      px.r = (px.r + (g.r - px.r) * strength).round();
      px.g = (px.g + (g.g - px.g) * strength).round();
      px.b = (px.b + (g.b - px.b) * strength).round();
    });
  }

  static void _duotone(img.Image f, ColorOp op) {
    final int shadow = op.color('shadow', 0xFF000000);
    final int high = op.color('highlight', 0xFFFFFFFF);
    final List<_GradStop> stops = <_GradStop>[
      _GradStop(0, shadow),
      _GradStop(1, high),
    ];
    final double strength = op.n('strength', 1).clamp(0.0, 1.0);
    _eachPixel(f, (int x, int y, _Rgba px) {
      final _Rgba g = _sampleGradient(stops, _luma(px) / 255.0, px.a);
      px.r = (px.r + (g.r - px.r) * strength).round();
      px.g = (px.g + (g.g - px.g) * strength).round();
      px.b = (px.b + (g.b - px.b) * strength).round();
    });
  }

  /// Swap one colour for another within a tolerance, with soft falloff.
  static void _replaceColor(img.Image f, ColorOp op) {
    final int from = op.color('from');
    final int to = op.color('to');
    final double tol = op.n('tolerance', 32);
    final double soft = math.max(0.001, op.n('softness', 16));
    final int fr = (from >> 16) & 0xFF, fg = (from >> 8) & 0xFF, fb = from & 0xFF;
    final int tr = (to >> 16) & 0xFF, tg = (to >> 8) & 0xFF, tb = to & 0xFF;
    _eachPixel(f, (int x, int y, _Rgba px) {
      // Squared colour distance avoids three per-pixel `math.pow` calls; sqrt is
      // kept because the soft-edge weight below needs the real distance.
      final int dr = px.r - fr, dg = px.g - fg, db = px.b - fb;
      final double d = math.sqrt((dr * dr + dg * dg + db * db).toDouble());
      if (d > tol + soft) return;
      final double w = d <= tol ? 1.0 : (1.0 - (d - tol) / soft).clamp(0.0, 1.0);
      px.r = (px.r + (tr - px.r) * w).round();
      px.g = (px.g + (tg - px.g) * w).round();
      px.b = (px.b + (tb - px.b) * w).round();
    });
  }

  /// Shift only hues falling within a range (e.g. recolour just the red parts).
  static void _selectiveHue(img.Image f, ColorOp op) {
    final double center = op.n('center');
    final double width = op.n('width', 30);
    final double shift = op.n('shift');
    final double satMul = op.n('saturation', 1);
    _eachPixel(f, (int x, int y, _Rgba px) {
      final _Hsv h = _Hsv.fromRgb(px);
      double diff = (h.h - center).abs();
      if (diff > 180) diff = 360 - diff;
      if (diff <= width) {
        h.h = (h.h + shift) % 360;
        if (h.h < 0) h.h += 360;
        h.s = (h.s * satMul).clamp(0.0, 1.0);
        h.toRgb(px);
      }
    });
  }

  static void _posterize(img.Image f, ColorOp op) {
    final int levels = math.max(2, op.n('levels', 4).round());
    final double step = 255.0 / (levels - 1);
    int q(int v) => (((v / step).round()) * step).round().clamp(0, 255);
    _eachPixel(f, (int x, int y, _Rgba px) {
      px.r = q(px.r);
      px.g = q(px.g);
      px.b = q(px.b);
    });
  }

  static void _threshold(img.Image f, ColorOp op) {
    final int t = op.n('level', 128).round();
    _eachPixel(f, (int x, int y, _Rgba px) {
      final int v = _luma(px) >= t ? 255 : 0;
      px.r = v;
      px.g = v;
      px.b = v;
    });
  }

  static void _opacity(img.Image f, ColorOp op) {
    final double mul = op.n('amount', 1).clamp(0.0, 1.0);
    _eachPixel(f, (int x, int y, _Rgba px) {
      px.a = (px.a * mul).round().clamp(0, 255);
    });
  }

  static void _alphaThreshold(img.Image f, ColorOp op) {
    final int t = op.n('level', 128).round();
    _eachPixel(f, (int x, int y, _Rgba px) {
      px.a = px.a >= t ? 255 : 0;
    });
  }

  static void _channelSwap(img.Image f, ColorOp op) {
    final String order = op.s('order', 'rgb').toLowerCase();
    if (order.length < 3) return;
    _eachPixel(f, (int x, int y, _Rgba px) {
      final Map<String, int> ch = <String, int>{
        'r': px.r,
        'g': px.g,
        'b': px.b,
      };
      px.r = ch[order[0]] ?? px.r;
      px.g = ch[order[1]] ?? px.g;
      px.b = ch[order[2]] ?? px.b;
    });
  }

  static void _colorBalance(img.Image f, ColorOp op) {
    final int dr = op.n('r').round();
    final int dg = op.n('g').round();
    final int db = op.n('b').round();
    _eachPixel(f, (int x, int y, _Rgba px) {
      px.r = (px.r + dr).clamp(0, 255);
      px.g = (px.g + dg).clamp(0, 255);
      px.b = (px.b + db).clamp(0, 255);
    });
  }

  /// Tint shadows and highlights with two different colours (keeps midtones).
  static void _splitTone(img.Image f, ColorOp op) {
    final int sh = op.color('shadow', 0xFF1B2A4A);
    final int hi = op.color('highlight', 0xFFF5D08A);
    final double amt = op.n('amount', 0.4).clamp(0.0, 1.0);
    final int sr = (sh >> 16) & 0xFF, sg = (sh >> 8) & 0xFF, sb = sh & 0xFF;
    final int hr = (hi >> 16) & 0xFF, hg = (hi >> 8) & 0xFF, hb = hi & 0xFF;
    _eachPixel(f, (int x, int y, _Rgba px) {
      final double l = _luma(px) / 255.0;
      final double sw = (1 - l) * amt;
      final double hw = l * amt;
      px.r = (px.r + (sr - px.r) * sw + (hr - px.r) * hw).round().clamp(0, 255);
      px.g = (px.g + (sg - px.g) * sw + (hg - px.g) * hw).round().clamp(0, 255);
      px.b = (px.b + (sb - px.b) * sw + (hb - px.b) * hw).round().clamp(0, 255);
    });
  }

  /// Saturate/desaturate only a hue band.
  static void _selectiveSaturation(img.Image f, ColorOp op) {
    final double center = op.n('center');
    final double width = op.n('width', 40);
    final double mul = op.n('amount', 1.5);
    _eachPixel(f, (int x, int y, _Rgba px) {
      final _Hsv h = _Hsv.fromRgb(px);
      double diff = (h.h - center).abs();
      if (diff > 180) diff = 360 - diff;
      if (diff <= width) {
        h.s = (h.s * mul).clamp(0.0, 1.0);
        h.toRgb(px);
      }
    });
  }

  /// Additive HSV control (degrees / −1..1 / −1..1).
  static void _hsvAdjust(img.Image f, ColorOp op) {
    final double dh = op.n('h');
    final double ds = op.n('s');
    final double dv = op.n('v');
    _eachPixel(f, (int x, int y, _Rgba px) {
      final _Hsv h = _Hsv.fromRgb(px);
      h.h = (h.h + dh) % 360;
      if (h.h < 0) h.h += 360;
      h.s = (h.s + ds).clamp(0.0, 1.0);
      h.v = (h.v + dv).clamp(0.0, 1.0);
      h.toRgb(px);
    });
  }

  /// Darken toward the edges. [amount] 0..1, [feather] how soft.
  static void _vignette(img.Image f, ColorOp op) {
    final double amt = op.n('amount', 0.6).clamp(0.0, 1.0);
    final double feather = op.n('feather', 0.5).clamp(0.05, 1.0);
    final double cx = f.width / 2, cy = f.height / 2;
    final double maxD = math.sqrt(cx * cx + cy * cy);
    _eachPixel(f, (int x, int y, _Rgba px) {
      final double ex = x - cx, ey = y - cy;
      final double d = math.sqrt(ex * ex + ey * ey) / maxD;
      final double t = ((d - (1 - feather)) / feather).clamp(0.0, 1.0);
      final double k = 1 - t * amt;
      px.r = (px.r * k).round();
      px.g = (px.g * k).round();
      px.b = (px.b * k).round();
    });
  }

  /// CRT-style scanlines: darken every [gap]-th row.
  static void _scanlines(img.Image f, ColorOp op) {
    final int gap = math.max(2, op.n('gap', 2).round());
    final double amt = op.n('amount', 0.4).clamp(0.0, 1.0);
    _eachPixel(f, (int x, int y, _Rgba px) {
      if (y % gap == 0) {
        final double k = 1 - amt;
        px.r = (px.r * k).round();
        px.g = (px.g * k).round();
        px.b = (px.b * k).round();
      }
    });
  }

  /// Deterministic film grain.
  static void _noise(img.Image f, ColorOp op) {
    final double amt = op.n('amount', 24);
    final bool mono = op.n('mono', 1) >= 0.5;
    _eachPixel(f, (int x, int y, _Rgba px) {
      double rnd(int salt) {
        final double v = math.sin((x * 12.9898 + y * 78.233 + salt) * 1.0) * 43758.5453;
        return (v - v.floorToDouble()) * 2 - 1; // -1..1
      }
      if (mono) {
        final int n = (rnd(0) * amt).round();
        px.r = (px.r + n).clamp(0, 255);
        px.g = (px.g + n).clamp(0, 255);
        px.b = (px.b + n).clamp(0, 255);
      } else {
        px.r = (px.r + rnd(1) * amt).round().clamp(0, 255);
        px.g = (px.g + rnd(2) * amt).round().clamp(0, 255);
        px.b = (px.b + rnd(3) * amt).round().clamp(0, 255);
      }
    });
  }

  /// Chromatic aberration: shift red/blue channels horizontally.
  static void _chromaShift(img.Image f, ColorOp op) {
    final int off = op.n('offset', 2).round();
    if (off == 0) return;
    final img.Image src = f.clone();
    for (int y = 0; y < f.height; y++) {
      for (int x = 0; x < f.width; x++) {
        final img.Pixel base = src.getPixel(x, y);
        if (base.a == 0) continue;
        final int rx = (x - off).clamp(0, f.width - 1);
        final int bx = (x + off).clamp(0, f.width - 1);
        f.setPixelRgba(
          x,
          y,
          src.getPixel(rx, y).r.toInt(),
          base.g.toInt(),
          src.getPixel(bx, y).b.toInt(),
          base.a.toInt(),
        );
      }
    }
  }

  /// Mosaic / pixelation by averaging [size]×[size] blocks.
  static void _pixelate(img.Image f, ColorOp op) {
    final int size = math.max(2, op.n('size', 6).round());
    for (int by = 0; by < f.height; by += size) {
      for (int bx = 0; bx < f.width; bx += size) {
        int r = 0, g = 0, b = 0, a = 0, n = 0;
        for (int y = by; y < by + size && y < f.height; y++) {
          for (int x = bx; x < bx + size && x < f.width; x++) {
            final img.Pixel p = f.getPixel(x, y);
            r += p.r.toInt();
            g += p.g.toInt();
            b += p.b.toInt();
            a += p.a.toInt();
            n++;
          }
        }
        if (n == 0) continue;
        r ~/= n;
        g ~/= n;
        b ~/= n;
        a ~/= n;
        for (int y = by; y < by + size && y < f.height; y++) {
          for (int x = bx; x < bx + size && x < f.width; x++) {
            f.setPixelRgba(x, y, r, g, b, a);
          }
        }
      }
    }
  }

  /// Invert only channels brighter than [threshold] (classic darkroom look).
  static void _solarize(img.Image f, ColorOp op) {
    final int t = op.n('threshold', 128).round();
    _eachPixel(f, (int x, int y, _Rgba px) {
      if (px.r > t) px.r = 255 - px.r;
      if (px.g > t) px.g = 255 - px.g;
      if (px.b > t) px.b = 255 - px.b;
    });
  }

  /// Blend a directional two-colour gradient over the sprite. [angle] in degrees
  /// (0 = left→right), [strength] 0..1, [color0]/[color1] the endpoints.
  static void _gradientTint(img.Image f, ColorOp op) {
    final int c0 = op.color('color0', 0xFF000000);
    final int c1 = op.color('color1', 0xFFFFFFFF);
    final double ang = op.n('angle') * math.pi / 180.0;
    final double strength = op.n('strength', 0.5).clamp(0.0, 1.0);
    final double dx = math.cos(ang), dy = math.sin(ang);
    final double w = f.width.toDouble(), h = f.height.toDouble();
    final List<double> projs = <double>[0, w * dx, h * dy, w * dx + h * dy];
    double mn = projs[0], mx = projs[0];
    for (final double v in projs) {
      if (v < mn) mn = v;
      if (v > mx) mx = v;
    }
    final double range = math.max(1e-6, mx - mn);
    final int r0 = (c0 >> 16) & 0xFF, g0 = (c0 >> 8) & 0xFF, b0 = c0 & 0xFF;
    final int r1 = (c1 >> 16) & 0xFF, g1 = (c1 >> 8) & 0xFF, b1 = c1 & 0xFF;
    _eachPixel(f, (int x, int y, _Rgba px) {
      final double tt = ((x * dx + y * dy) - mn) / range;
      final int tr = (r0 + (r1 - r0) * tt).round();
      final int tg = (g0 + (g1 - g0) * tt).round();
      final int tb = (b0 + (b1 - b0) * tt).round();
      px.r = (px.r + (tr - px.r) * strength).round().clamp(0, 255);
      px.g = (px.g + (tg - px.g) * strength).round().clamp(0, 255);
      px.b = (px.b + (tb - px.b) * strength).round().clamp(0, 255);
    });
  }

  static const List<List<int>> _bayer4 = <List<int>>[
    <int>[0, 8, 2, 10],
    <int>[12, 4, 14, 6],
    <int>[3, 11, 1, 9],
    <int>[15, 7, 13, 5],
  ];

  /// Ordered (Bayer 4×4) dithering down to [levels] tones per channel — a retro,
  /// low-bit look that keeps gradients readable.
  static void _dither(img.Image f, ColorOp op) {
    final int levels = math.max(2, op.n('levels', 3).round());
    final double step = 255.0 / (levels - 1);
    _eachPixel(f, (int x, int y, _Rgba px) {
      final double thr = ((_bayer4[y % 4][x % 4] + 0.5) / 16.0 - 0.5) * step;
      int q(int v) => (((v + thr) / step).round() * step).round().clamp(0, 255);
      px.r = q(px.r);
      px.g = q(px.g);
      px.b = q(px.b);
    });
  }

  /// Cross-processing: filmic per-channel curves (lifted greens, cool shadows,
  /// warm highlights). [strength] 0..1.
  static void _crossProcess(img.Image f, ColorOp op) {
    final double amt = op.n('strength', 1).clamp(0.0, 1.0);
    _eachPixel(f, (int x, int y, _Rgba px) {
      final double r = math.pow(px.r / 255.0, 1.0 / 1.2).toDouble();
      final double g = (px.g / 255.0) * 1.05;
      final double b = (px.b / 255.0) * 0.9 + 0.05;
      final int nr = (r * 255).round().clamp(0, 255);
      final int ng = (g * 255).round().clamp(0, 255);
      final int nb = (b * 255).round().clamp(0, 255);
      px.r = (px.r + (nr - px.r) * amt).round();
      px.g = (px.g + (ng - px.g) * amt).round();
      px.b = (px.b + (nb - px.b) * amt).round();
    });
  }

  /// Bleach-bypass: overlay the luminance back over the image for the silvery,
  /// high-contrast, desaturated cinema look. [strength] 0..1.
  static void _bleachBypass(img.Image f, ColorOp op) {
    final double amt = op.n('strength', 1).clamp(0.0, 1.0);
    _eachPixel(f, (int x, int y, _Rgba px) {
      final int l = _luma(px);
      int overlay(int base) => base < 128
          ? (2 * base * l / 255).round()
          : (255 - 2 * (255 - base) * (255 - l) / 255).round();
      px.r = (px.r + (overlay(px.r) - px.r) * amt).round().clamp(0, 255);
      px.g = (px.g + (overlay(px.g) - px.g) * amt).round().clamp(0, 255);
      px.b = (px.b + (overlay(px.b) - px.b) * amt).round().clamp(0, 255);
    });
  }

  /// 3×3 unsharp-mask sharpen. [amount] 0..3.
  static void _sharpen(img.Image f, ColorOp op) {
    final double amt = op.n('amount', 1).clamp(0.0, 3.0);
    if (amt <= 0) return;
    final img.Image src = f.clone();
    int sample(int xx, int yy, int shift) {
      final int cx = xx.clamp(0, f.width - 1), cy = yy.clamp(0, f.height - 1);
      final img.Pixel p = src.getPixel(cx, cy);
      return shift == 16 ? p.r.toInt() : (shift == 8 ? p.g.toInt() : p.b.toInt());
    }
    for (int y = 0; y < f.height; y++) {
      for (int x = 0; x < f.width; x++) {
        final img.Pixel c = src.getPixel(x, y);
        if (c.a == 0) continue;
        int conv(int shift) {
          final double v = sample(x, y, shift) * (1 + 4 * amt) -
              amt *
                  (sample(x - 1, y, shift) +
                      sample(x + 1, y, shift) +
                      sample(x, y - 1, shift) +
                      sample(x, y + 1, shift));
          return v.round().clamp(0, 255);
        }
        f.setPixelRgba(x, y, conv(16), conv(8), conv(0), c.a.toInt());
      }
    }
  }

  /// Alpha-weighted box blur of [radius] px (softens without dark fringes).
  static void _blur(img.Image f, ColorOp op) {
    final int radius = math.max(1, op.n('radius', 2).round());
    final img.Image src = f.clone();
    for (int y = 0; y < f.height; y++) {
      for (int x = 0; x < f.width; x++) {
        double sr = 0, sg = 0, sb = 0, sa = 0;
        int cells = 0;
        for (int dy = -radius; dy <= radius; dy++) {
          for (int dx = -radius; dx <= radius; dx++) {
            final int xx = x + dx, yy = y + dy;
            if (xx < 0 || yy < 0 || xx >= f.width || yy >= f.height) continue;
            final img.Pixel p = src.getPixel(xx, yy);
            final double a = p.a.toDouble();
            sr += p.r * a;
            sg += p.g * a;
            sb += p.b * a;
            sa += a;
            cells++;
          }
        }
        final int na = cells == 0 ? 0 : (sa / cells).round().clamp(0, 255);
        if (sa > 0) {
          f.setPixelRgba(x, y, (sr / sa).round().clamp(0, 255),
              (sg / sa).round().clamp(0, 255), (sb / sa).round().clamp(0, 255), na);
        } else {
          f.setPixelRgba(x, y, 0, 0, 0, 0);
        }
      }
    }
  }

  /// Draw a solid [color] outline of [size] px around the sprite's silhouette
  /// (fills the transparent halo touching pixels with alpha ≥ [threshold]).
  static void _outline(img.Image f, ColorOp op) {
    final int size = math.max(1, op.n('size', 2).round());
    final int c = op.color('color', 0xFF000000);
    final int at = op.n('threshold', 128).round();
    final int cr = (c >> 16) & 0xFF, cg = (c >> 8) & 0xFF, cb = c & 0xFF, ca = (c >> 24) & 0xFF;
    final img.Image src = f.clone();
    final int r2 = size * size;
    for (int y = 0; y < f.height; y++) {
      for (int x = 0; x < f.width; x++) {
        if (src.getPixel(x, y).a >= at) continue; // keep existing solid pixels
        bool near = false;
        for (int dy = -size; dy <= size && !near; dy++) {
          for (int dx = -size; dx <= size; dx++) {
            if (dx * dx + dy * dy > r2) continue;
            final int xx = x + dx, yy = y + dy;
            if (xx < 0 || yy < 0 || xx >= f.width || yy >= f.height) continue;
            if (src.getPixel(xx, yy).a >= at) {
              near = true;
              break;
            }
          }
        }
        if (near) f.setPixelRgba(x, y, cr, cg, cb, ca);
      }
    }
  }

  /// Cast a soft drop shadow behind the sprite, offset by [dx]/[dy] px.
  static void _dropShadow(img.Image f, ColorOp op) {
    final int dx = op.n('dx', 3).round();
    final int dy = op.n('dy', 3).round();
    final int c = op.color('color', 0xFF000000);
    final double opacity = op.n('opacity', 0.5).clamp(0.0, 1.0);
    final int at = op.n('threshold', 16).round();
    final int sr = (c >> 16) & 0xFF, sg = (c >> 8) & 0xFF, sb = c & 0xFF;
    final img.Image src = f.clone();
    for (int y = 0; y < f.height; y++) {
      for (int x = 0; x < f.width; x++) {
        final img.Pixel cur = src.getPixel(x, y);
        if (cur.a >= at) continue; // sprite stays on top
        final int fx = x - dx, fy = y - dy;
        if (fx < 0 || fy < 0 || fx >= f.width || fy >= f.height) continue;
        final int srcA = src.getPixel(fx, fy).a.toInt();
        if (srcA < at) continue;
        final int sa = (srcA * opacity).round().clamp(0, 255);
        final int curA = cur.a.toInt();
        final int outA = (sa + curA * (255 - sa) ~/ 255).clamp(0, 255);
        f.setPixelRgba(x, y, sr, sg, sb, outA);
      }
    }
  }

  /// Soft outer glow: a coloured halo around the silhouette fading over
  /// [radius] px. [strength] scales the halo's opacity.
  static void _glow(img.Image f, ColorOp op) {
    final int radius = math.max(1, op.n('radius', 4).round());
    final int c = op.color('color', 0xFFFFFFAA);
    final double strength = op.n('strength', 1).clamp(0.0, 2.0);
    final int at = op.n('threshold', 16).round();
    final int gr = (c >> 16) & 0xFF, gg = (c >> 8) & 0xFF, gb = c & 0xFF;
    final img.Image src = f.clone();
    for (int y = 0; y < f.height; y++) {
      for (int x = 0; x < f.width; x++) {
        final img.Pixel cur = src.getPixel(x, y);
        if (cur.a >= at) continue;
        double best = double.infinity;
        for (int dy = -radius; dy <= radius; dy++) {
          for (int dx = -radius; dx <= radius; dx++) {
            final int xx = x + dx, yy = y + dy;
            if (xx < 0 || yy < 0 || xx >= f.width || yy >= f.height) continue;
            if (src.getPixel(xx, yy).a >= at) {
              final double d = math.sqrt((dx * dx + dy * dy).toDouble());
              if (d < best) best = d;
            }
          }
        }
        if (best == double.infinity) continue;
        final double falloff = (1 - best / radius).clamp(0.0, 1.0);
        final int ga = (255 * falloff * strength).round().clamp(0, 255);
        if (ga <= 0) continue;
        final int curA = cur.a.toInt();
        final int outA = (ga + curA * (255 - ga) ~/ 255).clamp(0, 255);
        f.setPixelRgba(x, y, gr, gg, gb, outA);
      }
    }
  }

  // ---- shared helpers ----

  static int _luma(_Rgba px) =>
      (0.299 * px.r + 0.587 * px.g + 0.114 * px.b).round().clamp(0, 255);

  static List<_GradStop> _readStops(ColorOp op) {
    final List<_GradStop> out = <_GradStop>[];
    for (int i = 0; i < 16; i++) {
      final String hex = op.s('stop$i');
      if (hex.isEmpty) break;
      final int? c = parseHexColor(hex);
      if (c == null) break;
      out.add(_GradStop(op.n('pos$i', i.toDouble()), c));
    }
    out.sort((_GradStop a, _GradStop b) => a.pos.compareTo(b.pos));
    return out;
  }

  static _Rgba _sampleGradient(List<_GradStop> stops, double t, int alpha) {
    if (stops.length == 1) {
      return _Rgba((stops[0].color >> 16) & 0xFF, (stops[0].color >> 8) & 0xFF,
          stops[0].color & 0xFF, alpha);
    }
    for (int i = 0; i < stops.length - 1; i++) {
      final _GradStop a = stops[i], b = stops[i + 1];
      if (t >= a.pos && t <= b.pos) {
        final double span = math.max(1e-6, b.pos - a.pos);
        final double f = (t - a.pos) / span;
        return _Rgba(
          _lerpC(a.color, b.color, f, 16),
          _lerpC(a.color, b.color, f, 8),
          _lerpC(a.color, b.color, f, 0),
          alpha,
        );
      }
    }
    final int c = t < stops.first.pos ? stops.first.color : stops.last.color;
    return _Rgba((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF, alpha);
  }

  static int _lerpC(int a, int b, double f, int shift) {
    final int ca = (a >> shift) & 0xFF, cb = (b >> shift) & 0xFF;
    return (ca + (cb - ca) * f).round().clamp(0, 255);
  }
}

class _GradStop {
  _GradStop(this.pos, this.color);
  final double pos;
  final int color;
}

/// Mutable RGBA used inside the per-pixel loop.
class _Rgba {
  _Rgba(this.r, this.g, this.b, this.a);
  int r, g, b, a;
}

/// Minimal HSV with conversions tuned for in-place editing.
class _Hsv {
  _Hsv(this.h, this.s, this.v);

  double h; // 0..360
  double s; // 0..1
  double v; // 0..1

  factory _Hsv.fromRgb(_Rgba px) {
    final double r = px.r / 255.0, g = px.g / 255.0, b = px.b / 255.0;
    final double mx = math.max(r, math.max(g, b));
    final double mn = math.min(r, math.min(g, b));
    final double d = mx - mn;
    double h = 0;
    if (d != 0) {
      if (mx == r) {
        h = 60 * (((g - b) / d) % 6);
      } else if (mx == g) {
        h = 60 * (((b - r) / d) + 2);
      } else {
        h = 60 * (((r - g) / d) + 4);
      }
    }
    if (h < 0) h += 360;
    final double s = mx == 0 ? 0 : d / mx;
    return _Hsv(h, s, mx);
  }

  void toRgb(_Rgba out) {
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
    out.r = ((r + m) * 255).round().clamp(0, 255);
    out.g = ((g + m) * 255).round().clamp(0, 255);
    out.b = ((b + m) * 255).round().clamp(0, 255);
  }
}

/// Parse `#aarrggbb`, `#rrggbb`, `aarrggbb`, or `rrggbb` into an ARGB int.
int? parseHexColor(String? hex) {
  if (hex == null) return null;
  String h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  return int.tryParse(h, radix: 16);
}

/// Format an ARGB int as `#aarrggbb`.
String formatHexColor(int argb) =>
    '#${argb.toRadixString(16).padLeft(8, '0')}';
