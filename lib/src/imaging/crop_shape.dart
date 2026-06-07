import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// The geometric family of a [CropShape].
enum CropShapeKind { square, circle, roundedRect, polygon }

/// A **mask shape** for a button / char_icon crop — circle, rounded square, a
/// preset (heart, star, hexagon…) or a custom polygon. It rasterises to an
/// antialiased **alpha mask** ([mask]) that the [ButtonMaker] multiplies into the
/// rendered button when "clip to shape" is on, giving e.g. a real circular button
/// with transparent corners. When clipping is off the shape is just a guide and
/// the output stays the full square.
///
/// Everything is **normalised** (the outline lives in the unit square `[0,1]²`)
/// so one shape works at any button size, and it's plain data — pure Dart, no
/// Flutter — so it JSON-round-trips for saved/custom shapes and is testable.
class CropShape {
  const CropShape({
    required this.name,
    this.category = 'Basic',
    this.kind = CropShapeKind.square,
    this.radius = 0.0,
    this.points = const <double>[],
  });

  /// Display / lookup name (unique within [cropShapePresets]).
  final String name;

  /// Picker grouping.
  final String category;

  /// Geometric family.
  final CropShapeKind kind;

  /// Corner radius as a fraction of the side (0..0.5), for [CropShapeKind.roundedRect].
  final double radius;

  /// Custom outline for [CropShapeKind.polygon]: a flattened, closed list of
  /// normalised `[x0,y0, x1,y1, …]` points in `[0,1]`.
  final List<double> points;

  /// The default no-op shape — fills the whole square, so it clips nothing.
  static const CropShape square = CropShape(name: 'Square');

  /// Whether clipping to this shape actually removes anything (a plain square
  /// doesn't, so callers can skip the mask entirely).
  bool get clips =>
      kind != CropShapeKind.square || (kind == CropShapeKind.square && radius > 0);

  CropShape copyWith({
    String? name,
    String? category,
    CropShapeKind? kind,
    double? radius,
    List<double>? points,
  }) =>
      CropShape(
        name: name ?? this.name,
        category: category ?? this.category,
        kind: kind ?? this.kind,
        radius: radius ?? this.radius,
        points: points ?? this.points,
      );

  /// A **regular polygon** ([sides] ≥ 3) inscribed in the unit square, first
  /// vertex pointing up. Used for triangle/pentagon/hexagon/… presets and the
  /// custom "N-sided" generator.
  static CropShape regularPolygon(String name, int sides,
      {String category = 'Polygons', double rotation = -math.pi / 2}) {
    final int n = sides < 3 ? 3 : sides;
    final List<double> pts = <double>[];
    for (int i = 0; i < n; i++) {
      final double a = rotation + 2 * math.pi * i / n;
      pts.add(0.5 + 0.5 * math.cos(a));
      pts.add(0.5 + 0.5 * math.sin(a));
    }
    return CropShape(
        name: name,
        category: category,
        kind: CropShapeKind.polygon,
        points: pts);
  }

  /// A **star** with [points] tips and an [innerRatio] (0..1) inner radius. Used
  /// for the star presets and the custom "star" generator.
  static CropShape star(String name, int points, double innerRatio,
      {String category = 'Stars', double rotation = -math.pi / 2}) {
    final int n = points < 2 ? 2 : points;
    final double inner = innerRatio.clamp(0.05, 0.95);
    final List<double> pts = <double>[];
    for (int i = 0; i < n * 2; i++) {
      final double r = (i.isEven ? 0.5 : 0.5 * inner);
      final double a = rotation + math.pi * i / n;
      pts.add(0.5 + r * math.cos(a));
      pts.add(0.5 + r * math.sin(a));
    }
    return CropShape(
        name: name,
        category: category,
        kind: CropShapeKind.polygon,
        points: pts);
  }

  /// The shape outline as flattened normalised `[x0,y0,…]` in `[0,1]` (closed) —
  /// for drawing the editor overlay / a Flutter `Path`, and the raster fill.
  /// Circle and rounded-rect are sampled into points here too.
  List<double> outline({int segments = 96}) {
    switch (kind) {
      case CropShapeKind.square:
        return radius > 0
            ? _roundedRectOutline(radius.clamp(0.0, 0.5))
            : const <double>[0, 0, 1, 0, 1, 1, 0, 1];
      case CropShapeKind.circle:
        final List<double> o = <double>[];
        for (int i = 0; i < segments; i++) {
          final double a = 2 * math.pi * i / segments;
          o.add(0.5 + 0.5 * math.cos(a));
          o.add(0.5 + 0.5 * math.sin(a));
        }
        return o;
      case CropShapeKind.roundedRect:
        return _roundedRectOutline(radius.clamp(0.0, 0.5));
      case CropShapeKind.polygon:
        return points.length >= 6
            ? points
            : const <double>[0, 0, 1, 0, 1, 1, 0, 1];
    }
  }

  static List<double> _roundedRectOutline(double r) {
    if (r <= 0) return const <double>[0, 0, 1, 0, 1, 1, 0, 1];
    const int arc = 8;
    final List<double> o = <double>[];
    // Four corners (centre, start angle) going clockwise from top-left.
    final List<List<double>> corners = <List<double>>[
      <double>[r, r, math.pi, 1.5 * math.pi], // top-left
      <double>[1 - r, r, 1.5 * math.pi, 2 * math.pi], // top-right
      <double>[1 - r, 1 - r, 0, 0.5 * math.pi], // bottom-right
      <double>[r, 1 - r, 0.5 * math.pi, math.pi], // bottom-left
    ];
    for (final List<double> c in corners) {
      for (int i = 0; i <= arc; i++) {
        final double a = c[2] + (c[3] - c[2]) * i / arc;
        o.add(c[0] + r * math.cos(a));
        o.add(c[1] + r * math.sin(a));
      }
    }
    return o;
  }

  /// Rasterise an antialiased alpha mask [size]×[size] — opaque (white) inside
  /// the shape, transparent outside. A plain square returns a fully-opaque mask
  /// (clips nothing). Supersampled 4× then area-averaged down for clean edges.
  img.Image mask(int size) {
    final int s = size < 1 ? 1 : size;
    if (!clips) {
      final img.Image full = img.Image(width: s, height: s, numChannels: 4);
      for (int y = 0; y < s; y++) {
        for (int x = 0; x < s; x++) {
          full.setPixelRgba(x, y, 255, 255, 255, 255);
        }
      }
      return full;
    }
    const int ss = 4;
    final int hi = s * ss;
    final img.Image big = img.Image(width: hi, height: hi, numChannels: 4);
    final List<double> norm = outline();
    final List<double> px = <double>[for (final double v in norm) v * hi];
    _scanFill(big, px, hi, hi);
    return img.copyResize(big,
        width: s, height: s, interpolation: img.Interpolation.average);
  }

  /// Even-odd scanline polygon fill (handles concave shapes like stars/hearts):
  /// paint white-opaque between sorted edge intersections on each row.
  static void _scanFill(img.Image m, List<double> pts, int w, int h) {
    final int n = pts.length ~/ 2;
    if (n < 3) return;
    final List<double> xs = <double>[];
    for (int y = 0; y < h; y++) {
      final double yc = y + 0.5;
      xs.clear();
      for (int i = 0; i < n; i++) {
        final int j = (i + 1) % n;
        final double y0 = pts[i * 2 + 1];
        final double y1 = pts[j * 2 + 1];
        if ((y0 <= yc && yc < y1) || (y1 <= yc && yc < y0)) {
          final double t = (yc - y0) / (y1 - y0);
          xs.add(pts[i * 2] + t * (pts[j * 2] - pts[i * 2]));
        }
      }
      if (xs.length < 2) continue;
      xs.sort();
      for (int k = 0; k + 1 < xs.length; k += 2) {
        int xa = xs[k].ceil();
        int xb = xs[k + 1].floor();
        if (xa < 0) xa = 0;
        if (xb > w - 1) xb = w - 1;
        for (int x = xa; x <= xb; x++) {
          m.setPixelRgba(x, y, 255, 255, 255, 255);
        }
      }
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'category': category,
        'kind': kind.name,
        'radius': radius,
        if (points.isNotEmpty) 'points': points,
      };

  static CropShape fromJson(Map<String, Object?> m) {
    final String k = (m['kind'] as String?) ?? 'square';
    return CropShape(
      name: (m['name'] as String?) ?? 'Shape',
      category: (m['category'] as String?) ?? 'Custom',
      kind: CropShapeKind.values.firstWhere((CropShapeKind e) => e.name == k,
          orElse: () => CropShapeKind.square),
      radius: (m['radius'] as num?)?.toDouble() ?? 0.0,
      points: (m['points'] as List?)
              ?.map((Object? v) => (v as num).toDouble())
              .toList() ??
          const <double>[],
    );
  }
}

/// A heart outline (the classic `16sin³t` curve), normalised into the unit square.
CropShape _heart() {
  const int seg = 80;
  final List<double> pts = <double>[];
  for (int i = 0; i < seg; i++) {
    final double t = 2 * math.pi * i / seg;
    final double x = 16 * math.pow(math.sin(t), 3).toDouble();
    final double y = 13 * math.cos(t) -
        5 * math.cos(2 * t) -
        2 * math.cos(3 * t) -
        math.cos(4 * t);
    pts.add(0.5 + x / 35.0);
    pts.add(0.5 - y / 35.0); // flip: image y grows downward
  }
  return CropShape(
      name: 'Heart',
      category: 'Fun',
      kind: CropShapeKind.polygon,
      points: pts);
}

/// A soft organic blob (a few low harmonics on the radius).
CropShape _blob() {
  const int seg = 56;
  final List<double> pts = <double>[];
  for (int i = 0; i < seg; i++) {
    final double a = 2 * math.pi * i / seg;
    final double r = 0.5 *
        (0.84 + 0.10 * math.sin(3 * a + 0.6) + 0.05 * math.sin(5 * a + 1.7));
    pts.add(0.5 + r * math.cos(a));
    pts.add(0.5 + r * math.sin(a));
  }
  return CropShape(
      name: 'Blob', category: 'Fun', kind: CropShapeKind.polygon, points: pts);
}

/// A rounded flower with [petals] lobes.
CropShape _flower(String name, int petals) {
  const int seg = 96;
  final List<double> pts = <double>[];
  for (int i = 0; i < seg; i++) {
    final double a = 2 * math.pi * i / seg;
    final double r = 0.5 * (0.55 + 0.45 * math.cos(petals * a).abs());
    pts.add(0.5 + r * math.cos(a));
    pts.add(0.5 + r * math.sin(a));
  }
  return CropShape(
      name: name, category: 'Fun', kind: CropShapeKind.polygon, points: pts);
}

/// A plus / cross.
CropShape _cross() {
  const double t = 0.34, u = 0.66;
  return const CropShape(
    name: 'Cross',
    category: 'Fun',
    kind: CropShapeKind.polygon,
    points: <double>[
      t, 0, u, 0, u, t, 1, t, 1, u, u, u, //
      u, 1, t, 1, t, u, 0, u, 0, t, t, t,
    ],
  );
}

/// The built-in shape catalogue surfaced in the Button/Icon Studio picker.
final List<CropShape> cropShapePresets = <CropShape>[
  CropShape.square,
  const CropShape(name: 'Circle', kind: CropShapeKind.circle),
  const CropShape(name: 'Rounded', kind: CropShapeKind.roundedRect, radius: 0.22),
  const CropShape(name: 'Pill', kind: CropShapeKind.roundedRect, radius: 0.5),
  CropShape.regularPolygon('Triangle', 3, category: 'Polygons'),
  CropShape.regularPolygon('Diamond', 4, category: 'Polygons', rotation: 0),
  CropShape.regularPolygon('Pentagon', 5, category: 'Polygons'),
  CropShape.regularPolygon('Hexagon', 6, category: 'Polygons'),
  CropShape.regularPolygon('Heptagon', 7, category: 'Polygons'),
  CropShape.regularPolygon('Octagon', 8, category: 'Polygons'),
  CropShape.star('Star', 5, 0.45),
  CropShape.star('Star 6', 6, 0.5),
  CropShape.star('Sheriff', 6, 0.62),
  CropShape.star('Burst', 12, 0.7),
  CropShape.star('Spikes', 16, 0.78),
  _heart(),
  _blob(),
  _flower('Flower', 6),
  _flower('Daisy', 8),
  _cross(),
];

/// Ordered category names for grouped pickers.
List<String> get cropShapeCategories {
  final List<String> out = <String>[];
  for (final CropShape s in cropShapePresets) {
    if (!out.contains(s.category)) out.add(s.category);
  }
  return out;
}

/// Look a preset up by name (falls back to [CropShape.square]).
CropShape cropShapeByName(String? name) {
  if (name != null) {
    for (final CropShape s in cropShapePresets) {
      if (s.name == name) return s;
    }
  }
  return CropShape.square;
}
