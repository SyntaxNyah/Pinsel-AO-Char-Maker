import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'button_maker.dart' show IntRect;

/// How a sprite sheet is sliced into cells.
enum SheetMode {
  /// Detect each sprite automatically from the background (any layout).
  auto,

  /// Slice on a uniform rows×columns grid.
  grid,

  /// Hand-drawn boxes: you draw/move/resize each sprite box yourself.
  manual,
}

/// One sliced region of a sprite sheet — a future sprite.
class SheetCell {
  SheetCell(this.rect, {this.enabled = true, this.name = ''});

  /// Bounds in sheet pixels.
  IntRect rect;

  /// Whether this cell is included in the export.
  bool enabled;

  /// Export name (without extension); the ripper fills a default.
  String name;

  int get area => rect.w * rect.h;
}

/// Uniform-grid slicing parameters. Set [cellW]/[cellH] to 0 to derive the cell
/// size so the columns/rows fill the sheet (minus the offset and gutters).
class GridSpec {
  const GridSpec({
    this.cols = 4,
    this.rows = 4,
    this.offsetX = 0,
    this.offsetY = 0,
    this.gutterX = 0,
    this.gutterY = 0,
    this.cellW = 0,
    this.cellH = 0,
  });

  final int cols;
  final int rows;
  final int offsetX;
  final int offsetY;
  final int gutterX;
  final int gutterY;
  final int cellW;
  final int cellH;

  GridSpec copyWith({
    int? cols,
    int? rows,
    int? offsetX,
    int? offsetY,
    int? gutterX,
    int? gutterY,
    int? cellW,
    int? cellH,
  }) =>
      GridSpec(
        cols: cols ?? this.cols,
        rows: rows ?? this.rows,
        offsetX: offsetX ?? this.offsetX,
        offsetY: offsetY ?? this.offsetY,
        gutterX: gutterX ?? this.gutterX,
        gutterY: gutterY ?? this.gutterY,
        cellW: cellW ?? this.cellW,
        cellH: cellH ?? this.cellH,
      );
}

/// Content/blob auto-detection parameters.
class AutoSpec {
  const AutoSpec({
    this.bgColor,
    this.tolerance = 24,
    this.minSide = 16,
    this.gap = 10,
    this.padding = 2,
    this.trim = true,
  });

  /// Background ARGB; null samples the sheet's four corners.
  final int? bgColor;

  /// Per-channel match tolerance for "is this the background" (0..255).
  final int tolerance;

  /// Ignore blobs whose larger side is below this (px) — kills specks.
  final int minSide;

  /// Merge blobs whose bounding boxes are within this gap (px), so a sprite
  /// split into disconnected pieces (a stray hand, hair, accessory) stays one.
  final int gap;

  /// Pad each detected box by this many px (clamped to the sheet).
  final int padding;

  /// Tighten each box to its actual content after merging.
  final bool trim;

  AutoSpec copyWith({
    int? bgColor,
    bool clearBgColor = false,
    int? tolerance,
    int? minSide,
    int? gap,
    int? padding,
    bool? trim,
  }) =>
      AutoSpec(
        bgColor: clearBgColor ? null : (bgColor ?? this.bgColor),
        tolerance: tolerance ?? this.tolerance,
        minSide: minSide ?? this.minSide,
        gap: gap ?? this.gap,
        padding: padding ?? this.padding,
        trim: trim ?? this.trim,
      );
}

/// Pure-Dart sprite-sheet ripper: slices a sheet of visual-novel sprites into
/// individual transparent sprites, by uniform grid or by automatic background
/// detection. No Flutter — drives the preview and the export alike.
class SpriteSheet {
  const SpriteSheet._();

  /// Threshold below which a pixel's alpha counts as "transparent" (background).
  static const int _alphaThreshold = 16;

  // ---------------------------------------------------------------------------
  // Grid mode
  // ---------------------------------------------------------------------------

  /// Uniform grid cells (row-major) covering the sheet for [g].
  static List<IntRect> grid(int sheetW, int sheetH, GridSpec g) {
    final int cols = g.cols.clamp(1, 256);
    final int rows = g.rows.clamp(1, 256);
    final int availW = (sheetW - g.offsetX - g.gutterX * (cols - 1)).clamp(0, sheetW);
    final int availH = (sheetH - g.offsetY - g.gutterY * (rows - 1)).clamp(0, sheetH);
    final int cw = g.cellW > 0 ? g.cellW : (availW / cols).floor();
    final int ch = g.cellH > 0 ? g.cellH : (availH / rows).floor();
    final List<IntRect> out = <IntRect>[];
    if (cw <= 0 || ch <= 0) return out;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final int x = g.offsetX + c * (cw + g.gutterX);
        final int y = g.offsetY + r * (ch + g.gutterY);
        if (x >= sheetW || y >= sheetH) continue;
        final int w = (x + cw > sheetW) ? sheetW - x : cw;
        final int h = (y + ch > sheetH) ? sheetH - y : ch;
        if (w > 0 && h > 0) out.add(IntRect(x, y, w, h));
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Auto mode (background flood + connected components)
  // ---------------------------------------------------------------------------

  /// Auto-detect sprite bounding boxes. Flood-fills the background inward from
  /// the borders (so interior same-as-background regions — e.g. white clothing
  /// on a white sheet — are kept), connected-component labels the foreground,
  /// merges near boxes, drops specks, and returns them row-major.
  static List<IntRect> autoDetect(img.Image sheet, AutoSpec spec) {
    final img.Image src = sheet.numChannels == 4 ? sheet : sheet.convert(numChannels: 4);
    final int w = src.width, h = src.height;
    if (w == 0 || h == 0) return <IntRect>[];
    final Uint8List px = src.getBytes(order: img.ChannelOrder.rgba);
    final int bg = spec.bgColor ?? _sampleCornerBg(px, w, h);
    final int br = (bg >> 16) & 0xFF, bgc = (bg >> 8) & 0xFF, bb = bg & 0xFF;

    final Uint8List bgMask = _borderBackgroundMask(px, w, h, br, bgc, bb, spec.tolerance);

    // Connected-component label the foreground (everything not background).
    final List<IntRect> boxes = _labelForeground(px, w, h, bgMask);

    // Merge boxes that sit within `gap` of each other, then drop specks.
    final List<IntRect> merged = _mergeNearby(boxes, spec.gap);
    final List<IntRect> kept = <IntRect>[
      for (final IntRect b in merged)
        if (b.w >= spec.minSide || b.h >= spec.minSide) b,
    ];

    final List<IntRect> result = <IntRect>[];
    for (IntRect b in kept) {
      if (spec.trim) b = _trim(px, w, h, b, bgMask);
      if (spec.padding > 0) b = _pad(b, spec.padding, w, h);
      if (b.w > 0 && b.h > 0) result.add(b);
    }
    return _sortRowMajor(result);
  }

  // ---------------------------------------------------------------------------
  // Extraction
  // ---------------------------------------------------------------------------

  /// Crop [rect] out of [sheet] and (when [removeBg]) erase the surrounding
  /// background to transparency by flood-filling inward from the crop's borders,
  /// so the sprite keeps interior same-coloured regions. Returns RGBA.
  static img.Image extract(
    img.Image sheet,
    IntRect rect, {
    bool removeBg = true,
    int? bgColor,
    int tolerance = 24,
  }) {
    final img.Image src = sheet.numChannels == 4 ? sheet : sheet.convert(numChannels: 4);
    final int x = rect.x.clamp(0, src.width - 1);
    final int y = rect.y.clamp(0, src.height - 1);
    final int w = rect.w.clamp(1, src.width - x);
    final int h = rect.h.clamp(1, src.height - y);
    final img.Image crop = img.copyCrop(src, x: x, y: y, width: w, height: h);
    final img.Image out = crop.numChannels == 4 ? crop : crop.convert(numChannels: 4);
    if (!removeBg) return out;

    final Uint8List px = out.getBytes(order: img.ChannelOrder.rgba);
    final int bg = bgColor ?? _sampleCornerBg(px, w, h);
    final int br = (bg >> 16) & 0xFF, bgc = (bg >> 8) & 0xFF, bb = bg & 0xFF;
    final Uint8List bgMask = _borderBackgroundMask(px, w, h, br, bgc, bb, tolerance);
    // Knock the masked background pixels transparent (alpha 0 = colour ignored).
    for (int i = 0; i < bgMask.length; i++) {
      if (bgMask[i] == 1) {
        out.setPixelRgba(i % w, i ~/ w, 0, 0, 0, 0);
      }
    }
    return out;
  }

  /// Assign each ripped cell a **unique** base name (no extension) so a second
  /// sheet added to a project doesn't reuse — and overwrite — the first sheet's
  /// sprite files (the reported bug: rip sheet A → `sprite1..4`, rip sheet B →
  /// `sprite1..4` again, clobbering A).
  ///
  /// [existing] is the set of base names already in the project (any case).
  /// Cells the ripper auto-named (`"<prefix><number>"`) are **renumbered to
  /// continue past** what exists (so sheet B becomes `sprite5, sprite6, …`),
  /// while hand-typed names are preserved. Illegal filename characters are
  /// sanitised and any remaining duplicates get a `_2`, `_3`, … suffix. Dedups
  /// case-insensitively (Windows paths are case-insensitive). Pure → testable.
  static List<String> uniqueNames(
      Set<String> existing, List<String> rawNames, String prefix) {
    final Set<String> used = <String>{
      for (final String e in existing) e.toLowerCase(),
    };
    final RegExp autoName = RegExp('^${RegExp.escape(prefix)}\\d+\$');
    int counter = 1;
    String nextAuto() {
      while (used.contains('$prefix$counter'.toLowerCase())) {
        counter++;
      }
      return '$prefix${counter++}';
    }

    final List<String> out = <String>[];
    for (final String raw0 in rawNames) {
      final String raw = raw0.trim();
      String base = (raw.isEmpty || autoName.hasMatch(raw)) ? nextAuto() : raw;
      base = base.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');
      if (base.isEmpty) base = nextAuto();
      String unique = base;
      int n = 2;
      while (used.contains(unique.toLowerCase())) {
        unique = '${base}_${n++}';
      }
      used.add(unique.toLowerCase());
      out.add(unique);
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // internals
  // ---------------------------------------------------------------------------

  static int _sampleCornerBg(Uint8List px, int w, int h) {
    final List<int> idx = <int>[
      0,
      (w - 1) * 4,
      (w * (h - 1)) * 4,
      (w * h - 1) * 4,
    ];
    int r = 0, g = 0, b = 0;
    for (final int i in idx) {
      r += px[i];
      g += px[i + 1];
      b += px[i + 2];
    }
    return 0xFF000000 | ((r ~/ 4) << 16) | ((g ~/ 4) << 8) | (b ~/ 4);
  }

  static bool _isBg(Uint8List px, int p, int br, int bg, int bb, int tol) {
    final int base = p * 4;
    if (px[base + 3] < _alphaThreshold) return true; // transparent
    return (px[base] - br).abs() <= tol &&
        (px[base + 1] - bg).abs() <= tol &&
        (px[base + 2] - bb).abs() <= tol;
  }

  /// 4-connected flood fill of background-coloured pixels reachable from any
  /// border pixel. Returns a mask (1 = background) of length w*h.
  static Uint8List _borderBackgroundMask(
      Uint8List px, int w, int h, int br, int bg, int bb, int tol) {
    final Uint8List mask = Uint8List(w * h);
    final Int32List stack = Int32List(w * h);
    int sp = 0;

    void push(int p) {
      if (mask[p] == 0 && _isBg(px, p, br, bg, bb, tol)) {
        mask[p] = 1;
        stack[sp++] = p;
      }
    }

    for (int x = 0; x < w; x++) {
      push(x); // top row
      push((h - 1) * w + x); // bottom row
    }
    for (int y = 0; y < h; y++) {
      push(y * w); // left col
      push(y * w + (w - 1)); // right col
    }

    while (sp > 0) {
      final int p = stack[--sp];
      final int x = p % w, y = p ~/ w;
      if (x > 0) push(p - 1);
      if (x < w - 1) push(p + 1);
      if (y > 0) push(p - w);
      if (y < h - 1) push(p + w);
    }
    return mask;
  }

  /// 8-connected labelling of foreground (mask==0) pixels into bounding boxes.
  static List<IntRect> _labelForeground(
      Uint8List px, int w, int h, Uint8List bgMask) {
    final Uint8List seen = Uint8List(w * h);
    final Int32List stack = Int32List(w * h);
    final List<IntRect> boxes = <IntRect>[];

    for (int start = 0; start < w * h; start++) {
      if (seen[start] == 1 || bgMask[start] == 1) continue;
      int sp = 0;
      stack[sp++] = start;
      seen[start] = 1;
      int minX = w, minY = h, maxX = 0, maxY = 0, count = 0;
      while (sp > 0) {
        final int p = stack[--sp];
        final int x = p % w, y = p ~/ w;
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
        count++;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final int nx = x + dx, ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            final int np = ny * w + nx;
            if (seen[np] == 0 && bgMask[np] == 0) {
              seen[np] = 1;
              stack[sp++] = np;
            }
          }
        }
      }
      // Skip near-empty 1px noise immediately; real culling happens later.
      if (count >= 4) {
        boxes.add(IntRect(minX, minY, maxX - minX + 1, maxY - minY + 1));
      }
    }
    return boxes;
  }

  static List<IntRect> _mergeNearby(List<IntRect> boxes, int gap) {
    final List<IntRect?> work = List<IntRect?>.of(boxes);
    bool changed = true;
    while (changed) {
      changed = false;
      for (int i = 0; i < work.length; i++) {
        final IntRect? a = work[i];
        if (a == null) continue;
        for (int j = i + 1; j < work.length; j++) {
          final IntRect? b = work[j];
          if (b == null) continue;
          if (_within(a, b, gap)) {
            work[i] = _union(a, b);
            work[j] = null;
            changed = true;
          }
        }
      }
    }
    return <IntRect>[for (final IntRect? b in work) if (b != null) b];
  }

  static bool _within(IntRect a, IntRect b, int gap) {
    final bool xOverlap = a.x - gap < b.x + b.w && b.x - gap < a.x + a.w;
    final bool yOverlap = a.y - gap < b.y + b.h && b.y - gap < a.y + a.h;
    return xOverlap && yOverlap;
  }

  static IntRect _union(IntRect a, IntRect b) {
    final int x = a.x < b.x ? a.x : b.x;
    final int y = a.y < b.y ? a.y : b.y;
    final int r = (a.x + a.w) > (b.x + b.w) ? a.x + a.w : b.x + b.w;
    final int d = (a.y + a.h) > (b.y + b.h) ? a.y + a.h : b.y + b.h;
    return IntRect(x, y, r - x, d - y);
  }

  /// Shrink [box] to the content (non-background) pixels inside it.
  static IntRect _trim(Uint8List px, int w, int h, IntRect box, Uint8List bgMask) {
    int minX = box.x + box.w, minY = box.y + box.h, maxX = box.x - 1, maxY = box.y - 1;
    final int x1 = box.x + box.w, y1 = box.y + box.h;
    for (int y = box.y; y < y1; y++) {
      for (int x = box.x; x < x1; x++) {
        if (bgMask[y * w + x] == 0) {
          if (x < minX) minX = x;
          if (y < minY) minY = y;
          if (x > maxX) maxX = x;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (maxX < minX || maxY < minY) return box;
    return IntRect(minX, minY, maxX - minX + 1, maxY - minY + 1);
  }

  static IntRect _pad(IntRect b, int pad, int w, int h) {
    final int x = (b.x - pad).clamp(0, w - 1);
    final int y = (b.y - pad).clamp(0, h - 1);
    final int r = (b.x + b.w + pad).clamp(0, w);
    final int d = (b.y + b.h + pad).clamp(0, h);
    return IntRect(x, y, r - x, d - y);
  }

  /// Sort boxes reading order: top-to-bottom in rows, left-to-right within a row.
  static List<IntRect> _sortRowMajor(List<IntRect> boxes) {
    if (boxes.isEmpty) return boxes;
    final List<int> heights = <int>[for (final IntRect b in boxes) b.h]..sort();
    final int medianH = heights[heights.length ~/ 2];
    final int rowStep = (medianH * 0.6).clamp(1, double.infinity).toInt();
    final List<IntRect> sorted = List<IntRect>.of(boxes)
      ..sort((IntRect a, IntRect b) {
        final int ra = (a.y + a.h ~/ 2) ~/ rowStep;
        final int rb = (b.y + b.h ~/ 2) ~/ rowStep;
        if (ra != rb) return ra.compareTo(rb);
        return a.x.compareTo(b.x);
      });
    return sorted;
  }
}
