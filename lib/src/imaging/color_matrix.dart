import 'dart:math' as math;

import 'color_ops.dart';

/// Builds a 4×5 colour matrix (Flutter `ColorFilter.matrix` format) from a
/// [ColorOp] pipeline — but **only** when every op in it is an exact linear
/// RGBA transform.
///
/// This powers the **GPU-accelerated live preview**: a representable pipeline is
/// previewed by the compositor (a `ColorFilter` laid over the already-decoded
/// sprite image) instead of CPU-baking a new image on every slider tick. The
/// per-pixel maths then run on the GPU, so dragging Brightness/Contrast updates
/// instantly with zero work on the UI isolate.
///
/// [tryBuild] returns `null` when the pipeline contains any op that is *not* an
/// exact linear transform — HSV ops (hueShift/saturation/vibrance/colorize),
/// tone curves (gamma/levels/posterize), or spatial ops (blur/outline/glow). The
/// caller then falls back to the CPU preview, so the displayed result is always
/// faithful: the GPU path is a fast, **exact** subset, never an approximation
/// that could drift from what "Apply" bakes.
///
/// The matrix is row-major `[r0..r4, g0..g4, b0..b4, a0..a4]` operating on 0–255
/// channels, exactly matching `dart:ui`'s `ColorFilter.matrix` contract:
/// `R' = m[0]·R + m[1]·G + m[2]·B + m[3]·A + m[4]`, and so on per row.
class ColorMatrix {
  const ColorMatrix._();

  /// Luma weights — must match `ImageOps._luma` so the GPU grayscale matrix is
  /// pixel-identical to the CPU bake.
  static const double _wr = 0.299, _wg = 0.587, _wb = 0.114;

  /// Op ids this builder can represent exactly as a colour matrix.
  static const Set<String> supportedTypes = <String>{
    'brightness',
    'contrast',
    'exposure',
    'invert',
    'grayscale',
    'sepia',
    'temperature',
    'tint',
    'solidColor',
    'opacity',
  };

  /// True if [op] can be represented exactly as a colour matrix.
  static bool supports(ColorOp op) => supportedTypes.contains(op.type);

  /// The 20-element identity matrix (no-op).
  static List<double> get identity => <double>[
        1, 0, 0, 0, 0, //
        0, 1, 0, 0, 0, //
        0, 0, 1, 0, 0, //
        0, 0, 0, 1, 0, //
      ];

  /// The combined matrix for [ops] applied in order, or `null` if any op is not
  /// matrix-representable (see class doc).
  static List<double>? tryBuild(List<ColorOp> ops) {
    List<double> m = identity;
    for (final ColorOp op in ops) {
      final List<double>? step = _forOp(op);
      if (step == null) return null; // bail → caller uses the CPU preview
      m = _compose(step, m); // apply this op *after* everything so far
    }
    return m;
  }

  // ---- per-op matrices ----------------------------------------------------
  // Each op gets its own helper (a switch expression keeps every arm in its own
  // scope — no shared-scope variable clashes between cases).

  static List<double>? _forOp(ColorOp op) => switch (op.type) {
        'brightness' => _scaleRgb(op.n('amount', 1)),
        'exposure' => _scaleRgb(math.pow(2.0, op.n('stops')).toDouble()),
        'contrast' => _contrast(op.n('amount', 1)),
        'invert' => const <double>[
            -1, 0, 0, 0, 255, //
            0, -1, 0, 0, 255, //
            0, 0, -1, 0, 255, //
            0, 0, 0, 1, 0, //
          ],
        'grayscale' => _grayscale(op.n('amount', 1).clamp(0.0, 1.0)),
        'sepia' => _sepia(op.n('amount', 1).clamp(0.0, 1.0)),
        'temperature' => _temperature(op.n('amount')),
        'tint' =>
          _tint(op.color('color'), op.n('amount', 0.5).clamp(0.0, 1.0)),
        'solidColor' => _solid(op.color('color')),
        'opacity' => _opacityMatrix(op.n('amount', 1).clamp(0.0, 1.0)),
        _ => null,
      };

  static List<double> _scaleRgb(double m) => <double>[
        m, 0, 0, 0, 0, //
        0, m, 0, 0, 0, //
        0, 0, m, 0, 0, //
        0, 0, 0, 1, 0, //
      ];

  static List<double> _contrast(double c) {
    final double off = 128 - 128 * c;
    return <double>[
      c, 0, 0, 0, off, //
      0, c, 0, 0, off, //
      0, 0, c, 0, off, //
      0, 0, 0, 1, 0, //
    ];
  }

  static List<double> _grayscale(double a) => <double>[
        1 - a + a * _wr, a * _wg, a * _wb, 0, 0, //
        a * _wr, 1 - a + a * _wg, a * _wb, 0, 0, //
        a * _wr, a * _wg, 1 - a + a * _wb, 0, 0, //
        0, 0, 0, 1, 0, //
      ];

  static List<double> _sepia(double a) {
    double mix(double base, double s) => (1 - a) * base + a * s;
    return <double>[
      mix(1, 0.393), mix(0, 0.769), mix(0, 0.189), 0, 0, //
      mix(0, 0.349), mix(1, 0.686), mix(0, 0.168), 0, 0, //
      mix(0, 0.272), mix(0, 0.534), mix(1, 0.131), 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }

  static List<double> _temperature(double amt) {
    final double rShift = (amt * 40).roundToDouble();
    final double bShift = (-amt * 40).roundToDouble();
    return <double>[
      1, 0, 0, 0, rShift, //
      0, 1, 0, 0, 0, //
      0, 0, 1, 0, bShift, //
      0, 0, 0, 1, 0, //
    ];
  }

  static List<double> _tint(int c, double amt) {
    final double k = 1 - amt;
    return <double>[
      k, 0, 0, 0, ((c >> 16) & 0xFF) * amt, //
      0, k, 0, 0, ((c >> 8) & 0xFF) * amt, //
      0, 0, k, 0, (c & 0xFF) * amt, //
      0, 0, 0, 1, 0, //
    ];
  }

  static List<double> _solid(int c) => <double>[
        0, 0, 0, 0, ((c >> 16) & 0xFF).toDouble(), //
        0, 0, 0, 0, ((c >> 8) & 0xFF).toDouble(), //
        0, 0, 0, 0, (c & 0xFF).toDouble(), //
        0, 0, 0, 1, 0, //
      ];

  static List<double> _opacityMatrix(double m) => <double>[
        1, 0, 0, 0, 0, //
        0, 1, 0, 0, 0, //
        0, 0, 1, 0, 0, //
        0, 0, 0, m, 0, //
      ];

  /// Matrix product equivalent to applying [b] first, then [a] — i.e. `a ∘ b`.
  /// Both are 4×5 with an implicit homogeneous 5th row `[0,0,0,0,1]`.
  static List<double> _compose(List<double> a, List<double> b) {
    final List<double> r = List<double>.filled(20, 0);
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 5; j++) {
        double sum = 0;
        for (int k = 0; k < 4; k++) {
          sum += a[i * 5 + k] * b[k * 5 + j];
        }
        if (j == 4) sum += a[i * 5 + 4]; // b's homogeneous offset row
        r[i * 5 + j] = sum;
      }
    }
    return r;
  }
}
