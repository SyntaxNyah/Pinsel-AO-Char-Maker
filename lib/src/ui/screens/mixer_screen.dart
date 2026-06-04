import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart' show PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

import '../../imaging/button_maker.dart' show IntRect;
import '../../imaging/codecs.dart';
import '../../imaging/color_ops.dart';
import '../../imaging/compositor.dart';
import '../../platform/folder_picker.dart';
import '../app_state.dart';
import '../widgets/checker_image.dart';

/// "Frankensprite" mixer: snip **one or more** regions from sprites and place
/// them on a body sprite, then save the result as a new emote.
///
/// Mouse-first: in **Arrange** mode drag a snip to move it, drag its corner to
/// scale (or scroll the wheel), and drag the round handle to rotate; in **Snip**
/// mode drag the crop box on the source sprite. Every action also has a precise
/// **slider** in the panel on the right.
///
/// Performance: each snip's cut piece is baked **once** (debounced, only when its
/// crop/recolour/source changes) into a small image; moving/scaling/rotating it
/// is a pure Flutter transform of that cached image (no re-compositing per
/// frame). Only **Save** bakes the full-resolution composite.
class MixerScreen extends StatefulWidget {
  const MixerScreen({super.key});

  @override
  State<MixerScreen> createState() => _MixerScreenState();
}

enum _Mode { arrange, snip, layers }

class _MixerScreenState extends State<MixerScreen> {
  String? _base; // body base, always from the project
  final List<_Snip> _snips = <_Snip>[];
  int _sel = 0;
  int _nextId = 1;
  _Mode _mode = _Mode.arrange;

  /// "Link everything" mode: whole sprites stacked at their native position
  /// (for art that ships each feature/part as a separate, pre-aligned file).
  final List<_Layer> _layers = <_Layer>[];
  int _layerNextId = 1;
  String? _addAllSource; // which source the "Add all" button pulls from

  // output crop (fractions of the final image)
  double _cropL = 0, _cropT = 0, _cropR = 0, _cropB = 0;

  // Body (full-res dims for mapping + a downscaled PNG for the canvas backdrop).
  int _bodyW = 0, _bodyH = 0;
  Uint8List? _bodyPng;

  // Cached cut pieces (per snip id) and source views (per resolved rel).
  final Map<int, _Piece> _pieces = <int, _Piece>{};
  final Map<String, _SourceView> _sourceViews = <String, _SourceView>{};

  final TextEditingController _name = TextEditingController(text: 'mix');
  final GlobalKey _canvasKey = GlobalKey();
  Timer? _bakeDebounce;

  // Transient handle-drag state (canvas-local).
  Offset _dragCenter = Offset.zero;
  double _dragStartScale = 1, _dragStartAngle = 0, _dragStartDist = 1, _dragStartAngleDeg = 0;

  _Snip? get _selSnip =>
      (_sel >= 0 && _sel < _snips.length) ? _snips[_sel] : null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initFromProject();
    });
  }

  @override
  void dispose() {
    _bakeDebounce?.cancel();
    _name.dispose();
    super.dispose();
  }

  Future<void> _initFromProject() async {
    final AppState app = context.read<AppState>();
    final List<String> bases = app.spriteBases();
    _base ??= bases.isNotEmpty ? bases.first : null;
    await _loadBody(app);
    if (_snips.isEmpty && bases.isNotEmpty) {
      _addSnip(initialBase: bases.first);
    } else {
      _rebakeAll(app);
    }
  }

  // ---- snip management ------------------------------------------------------

  void _addSnip({String? initialBase}) {
    final AppState app = context.read<AppState>();
    final _Snip s = _Snip(_nextId++)..base = initialBase ?? _firstBaseFor(app, null);
    setState(() {
      _snips.add(s);
      _sel = _snips.length - 1;
    });
    _scheduleBake(s);
  }

  void _duplicateSnip(int i) {
    if (i < 0 || i >= _snips.length) return;
    final _Snip s = _snips[i].clone(_nextId++);
    s.px = (s.px + 0.05).clamp(0.0, 1.0);
    s.py = (s.py + 0.05).clamp(0.0, 1.0);
    setState(() {
      _snips.insert(i + 1, s);
      _sel = i + 1;
    });
    _scheduleBake(s);
  }

  void _removeSnip(int i) {
    if (i < 0 || i >= _snips.length) return;
    final int id = _snips[i].id;
    setState(() {
      _snips.removeAt(i);
      _pieces.remove(id);
      _sel = _snips.isEmpty ? 0 : _sel.clamp(0, _snips.length - 1);
    });
  }

  String? _firstBaseFor(AppState app, String? source) {
    final List<String> bases = _basesForSource(app, source);
    return bases.isNotEmpty ? bases.first : null;
  }

  List<String> _basesForSource(AppState app, String? source) {
    if (source == null) return app.spriteBases();
    return app.mixSources
            .firstWhereOrNull((MixSource m) => m.label == source)
            ?.bases ??
        const <String>[];
  }

  String? _overlayRel(AppState app, _Snip s) {
    if (s.base == null) return null;
    return s.source == null
        ? app.relForBase(s.base!)
        : app.relForMixBase(s.source!, s.base!);
  }

  // ---- baking ---------------------------------------------------------------

  Future<void> _loadBody(AppState app) async {
    final String? rel = _base == null ? null : app.relForBase(_base!);
    if (rel == null) {
      setState(() {
        _bodyW = _bodyH = 0;
        _bodyPng = null;
      });
      return;
    }
    final img.Image? body = await app.decodeFirstFrame(rel);
    if (body == null) return;
    final img.Image bg = _downscale(body, 720);
    if (!mounted) return;
    setState(() {
      _bodyW = body.width;
      _bodyH = body.height;
      _bodyPng = Codecs.encodePng(bg);
    });
  }

  void _scheduleBake(_Snip s) {
    _bakeDebounce?.cancel();
    _bakeDebounce = Timer(const Duration(milliseconds: 90), () => _bakePiece(s));
  }

  Future<void> _rebakeAll(AppState app) async {
    for (final _Snip s in _snips) {
      await _bakePiece(s);
    }
  }

  Future<void> _bakePiece(_Snip s) async {
    final AppState app = context.read<AppState>();
    final String? rel = _overlayRel(app, s);
    if (rel == null) {
      setState(() => _pieces.remove(s.id));
      return;
    }
    final img.Image? ov = await app.decodeFirstFrame(rel);
    if (ov == null) {
      setState(() => _pieces.remove(s.id));
      return;
    }
    final img.Image piece = _makePiece(s, ov);
    if (!mounted) return;
    setState(() {
      _pieces[s.id] = _Piece(Codecs.encodePng(piece), piece.width, piece.height);
    });
  }

  /// Cut + flip + feather + recolour the snip's region out of [ov].
  img.Image _makePiece(_Snip s, img.Image ov) {
    final IntRect rect = IntRect(
      (s.cx * ov.width).round().clamp(0, ov.width - 1),
      (s.cy * ov.height).round().clamp(0, ov.height - 1),
      (s.cw * ov.width).round().clamp(1, ov.width),
      (s.ch * ov.height).round().clamp(1, ov.height),
    );
    final CutResult cut =
        s.ellipse ? Compositor.cutEllipse(ov, rect) : Compositor.cutRect(ov, rect);
    img.Image piece = cut.image;
    if (s.flipH) piece = _flip(piece, horizontal: true);
    if (s.flipV) piece = _flip(piece, horizontal: false);
    if (s.feather > 0.5) piece = _featherEdges(piece, s.feather.round());
    final List<ColorOp> ops = <ColorOp>[
      if (s.hue.abs() > 0.5)
        ColorOp('hueShift', nums: <String, double>{'degrees': s.hue}),
      if ((s.sat - 1).abs() > 0.01)
        ColorOp('saturation', nums: <String, double>{'amount': s.sat}),
      if ((s.bri - 1).abs() > 0.01)
        ColorOp('brightness', nums: <String, double>{'amount': s.bri}),
    ];
    if (ops.isNotEmpty) ImageOps.applyAll(piece, ops);
    return piece;
  }

  /// Full-resolution composite for **Save**: body + every snip, then output crop.
  Future<Uint8List?> _composite(AppState app) async {
    final String? baseRel = _base == null ? null : app.relForBase(_base!);
    if (baseRel == null) return null;
    final img.Image? body = await app.decodeFirstFrame(baseRel);
    if (body == null) return null;

    img.Image result = body;
    for (final _Snip s in _snips) {
      final String? rel = _overlayRel(app, s);
      if (rel == null) continue;
      final img.Image? ov = await app.decodeFirstFrame(rel);
      if (ov == null) continue;
      final img.Image piece = _makePiece(s, ov);
      result = Compositor.placeCentered(
        result,
        piece,
        cx: s.px * result.width,
        cy: s.py * result.height,
        scale: s.scale,
        angle: s.angle,
        opacity: s.opacity,
      );
    }

    if (_cropL > 0 || _cropT > 0 || _cropR > 0 || _cropB > 0) {
      final int x0 = (_cropL * result.width).round();
      final int y0 = (_cropT * result.height).round();
      final int x1 = result.width - (_cropR * result.width).round();
      final int y1 = result.height - (_cropB * result.height).round();
      final int w = x1 - x0, h = y1 - y0;
      if (w >= 1 && h >= 1) {
        result = img.copyCrop(result, x: x0, y: y0, width: w, height: h);
      }
    }
    return Codecs.encodePng(result);
  }

  Future<void> _ensureSourceView(AppState app, String rel) async {
    if (_sourceViews.containsKey(rel)) return;
    final img.Image? src = await app.decodeFirstFrame(rel);
    if (src == null) return;
    final img.Image small = _downscale(src, 600);
    if (!mounted) return;
    setState(() => _sourceViews[rel] =
        _SourceView(Codecs.encodePng(small), src.width, src.height));
  }

  // ---- image helpers (own copies; never mutate the decode cache) ------------

  img.Image _downscale(img.Image im, int maxEdge) {
    final int longest = im.width > im.height ? im.width : im.height;
    if (longest <= maxEdge) return im.clone();
    final double s = maxEdge / longest;
    return img.copyResize(im,
        width: (im.width * s).round(),
        height: (im.height * s).round(),
        interpolation: img.Interpolation.average);
  }

  img.Image _flip(img.Image im, {required bool horizontal}) {
    final img.Image out = img.Image(width: im.width, height: im.height, numChannels: 4);
    for (int y = 0; y < im.height; y++) {
      for (int x = 0; x < im.width; x++) {
        final img.Pixel p = im.getPixel(
            horizontal ? im.width - 1 - x : x, horizontal ? y : im.height - 1 - y);
        out.setPixelRgba(x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(), p.a.toInt());
      }
    }
    return out;
  }

  img.Image _featherEdges(img.Image im, int radius) {
    if (radius <= 0) return im;
    final img.Image src = im.clone();
    for (int y = 0; y < im.height; y++) {
      for (int x = 0; x < im.width; x++) {
        final img.Pixel p = src.getPixel(x, y);
        if (p.a.toInt() == 0) continue;
        int opaque = 0, total = 0;
        for (int dy = -radius; dy <= radius; dy++) {
          for (int dx = -radius; dx <= radius; dx++) {
            total++;
            final int xx = x + dx, yy = y + dy;
            if (xx < 0 || yy < 0 || xx >= im.width || yy >= im.height) continue;
            if (src.getPixel(xx, yy).a.toInt() > 8) opaque++;
          }
        }
        final int na = (p.a.toInt() * (opaque / total)).round().clamp(0, 255);
        im.setPixelRgba(x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(), na);
      }
    }
    return im;
  }

  Future<void> _loadPartsFolder(AppState app) async {
    final PickedFolder? picked = await pickFolderFiles();
    if (picked == null || picked.files.isEmpty) return;
    await app.importMixParts(<PickedFile>[
      for (final PickedFolderFile f in picked.files) PickedFile(f.name, f.bytes),
    ]);
    if (app.mixSources.isEmpty) return;
    final String label = app.mixSources.last.label;
    setState(() {
      // Layers mode pulls from "Add all from"; point it at the new folder.
      _addAllSource = label;
      // Snip modes graft onto the selected snip; point it at the new folder too.
      if (_selSnip != null) {
        _selSnip!.source = label;
        _selSnip!.base = _firstBaseFor(app, label);
      }
    });
    if (_selSnip != null) _scheduleBake(_selSnip!);
  }

  void _resetSnip() {
    final _Snip? s = _selSnip;
    if (s == null) return;
    setState(() => s.resetTransform());
    _scheduleBake(s);
  }

  // ---- geometry -------------------------------------------------------------

  Rect _containRect(Size size, int cw, int ch) {
    if (cw <= 0 || ch <= 0) return Offset.zero & size;
    final double ar = cw / ch;
    double w = size.width, h = w / ar;
    if (h > size.height) {
      h = size.height;
      w = h * ar;
    }
    return Rect.fromLTWH((size.width - w) / 2, (size.height - h) / 2, w, h);
  }

  Offset _toLocal(Offset global) {
    final RenderBox? box =
        _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global) ?? global;
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final List<String> bases = app.spriteBases();
    if (_base != null && !bases.contains(_base)) _base = bases.isNotEmpty ? bases.first : null;

    return Row(
      children: <Widget>[
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: bases.isEmpty
                ? const Center(child: Text('Import sprites first.'))
                : _canvas(app),
          ),
        ),
        const VerticalDivider(width: 1),
        SizedBox(width: 380, child: _controls(app, bases)),
      ],
    );
  }

  // ---- canvas ---------------------------------------------------------------

  Widget _canvas(AppState app) {
    return Column(
      children: <Widget>[
        SegmentedButton<_Mode>(
          segments: const <ButtonSegment<_Mode>>[
            ButtonSegment<_Mode>(
                value: _Mode.arrange,
                icon: Icon(Icons.open_with_rounded),
                label: Text('Arrange')),
            ButtonSegment<_Mode>(
                value: _Mode.snip,
                icon: Icon(Icons.crop_rounded),
                label: Text('Snip')),
            ButtonSegment<_Mode>(
                value: _Mode.layers,
                icon: Icon(Icons.layers_rounded),
                label: Text('Layers')),
          ],
          selected: <_Mode>{_mode},
          onSelectionChanged: (Set<_Mode> s) => setState(() => _mode = s.first),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: switch (_mode) {
              _Mode.arrange => _arrangeCanvas(app),
              _Mode.snip => _snipCanvas(app),
              _Mode.layers => _layersCanvas(app),
            },
          ),
        ),
        const SizedBox(height: 4),
        Text(
          switch (_mode) {
            _Mode.arrange =>
              'Drag a part to move · corner to scale (or scroll) · round handle to rotate.',
            _Mode.snip => 'Drag the box to move the snip · drag a corner to resize.',
            _Mode.layers =>
              'Stack whole, pre-aligned sprite files (eyes, brows, body…) into one.',
          },
          style: const TextStyle(fontSize: 11, color: Colors.white60),
        ),
      ],
    );
  }

  Widget _arrangeCanvas(AppState app) {
    if (_bodyPng == null || _bodyW == 0) {
      return const Center(child: CircularProgressIndicator());
    }
    return Listener(
      onPointerSignal: (PointerSignalEvent e) {
        if (e is PointerScrollEvent && _selSnip != null) {
          setState(() {
            _selSnip!.scale =
                (_selSnip!.scale * (e.scrollDelta.dy < 0 ? 1.06 : 0.94))
                    .clamp(0.1, 4.0);
          });
        }
      },
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints cons) {
          final Rect rect = _containRect(cons.biggest, _bodyW, _bodyH);
          final double k = rect.width / _bodyW;
          return Stack(
            key: _canvasKey,
            children: <Widget>[
              const Positioned.fill(child: CheckerImage(bytes: null)),
              Positioned.fromRect(
                rect: rect,
                child: Image.memory(_bodyPng!, fit: BoxFit.fill, gaplessPlayback: true),
              ),
              for (int i = 0; i < _snips.length; i++)
                ..._pieceWidgets(i, rect, k),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _pieceWidgets(int i, Rect rect, double k) {
    final _Snip s = _snips[i];
    final _Piece? piece = _pieces[s.id];
    if (piece == null) {
      _scheduleBake(s);
      return const <Widget>[];
    }
    final double dispW = piece.w * s.scale * k;
    final double dispH = piece.h * s.scale * k;
    final Offset center =
        Offset(rect.left + s.px * rect.width, rect.top + s.py * rect.height);
    final bool selected = i == _sel;

    return <Widget>[
      Positioned(
        left: center.dx - dispW / 2,
        top: center.dy - dispH / 2,
        width: math.max(1.0, dispW),
        height: math.max(1.0, dispH),
        child: Transform.rotate(
          angle: s.angle * math.pi / 180,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _sel = i),
            onPanStart: (_) => setState(() => _sel = i),
            onPanUpdate: (DragUpdateDetails d) {
              setState(() {
                s.px = (s.px + d.delta.dx / rect.width).clamp(0.0, 1.0);
                s.py = (s.py + d.delta.dy / rect.height).clamp(0.0, 1.0);
              });
            },
            child: Opacity(
              opacity: s.opacity,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Positioned.fill(
                    child: Image.memory(piece.png,
                        fit: BoxFit.fill, gaplessPlayback: true),
                  ),
                  if (selected)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: const Color(0xFFB58CFF), width: 1.5),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      // Handles live OUTSIDE the rotation so their drag math is in canvas space.
      if (selected) ..._handles(s, center, dispW, dispH, rect),
    ];
  }

  List<Widget> _handles(_Snip s, Offset center, double dispW, double dispH, Rect rect) {
    // Place the scale handle near the (rotated) bottom-right corner and the
    // rotate handle above the (rotated) top-centre.
    final double a = s.angle * math.pi / 180;
    Offset rotated(Offset local) {
      final double dx = local.dx, dy = local.dy;
      return Offset(
        center.dx + dx * math.cos(a) - dy * math.sin(a),
        center.dy + dx * math.sin(a) + dy * math.cos(a),
      );
    }

    final Offset scalePos = rotated(Offset(dispW / 2, dispH / 2));
    final Offset rotatePos = rotated(Offset(0, -dispH / 2 - 22));

    return <Widget>[
      _handle(
        scalePos,
        Icons.open_in_full_rounded,
        onStart: (Offset p) {
          _dragCenter = center;
          _dragStartScale = s.scale;
          _dragStartDist = math.max(1.0, (p - center).distance);
        },
        onUpdate: (Offset p) {
          setState(() {
            s.scale = (_dragStartScale * ((p - _dragCenter).distance / _dragStartDist))
                .clamp(0.1, 4.0);
          });
        },
      ),
      _handle(
        rotatePos,
        Icons.rotate_right_rounded,
        onStart: (Offset p) {
          _dragCenter = center;
          _dragStartAngle = s.angle;
          _dragStartAngleDeg = _angleDeg(p - center);
        },
        onUpdate: (Offset p) {
          setState(() {
            final double now = _angleDeg(p - _dragCenter);
            double a = _dragStartAngle + (now - _dragStartAngleDeg);
            while (a > 180) {
              a -= 360;
            }
            while (a < -180) {
              a += 360;
            }
            s.angle = a;
          });
        },
      ),
    ];
  }

  double _angleDeg(Offset v) => math.atan2(v.dy, v.dx) * 180 / math.pi;

  Widget _handle(Offset pos, IconData icon,
      {required void Function(Offset) onStart, required void Function(Offset) onUpdate}) {
    const double size = 22;
    return Positioned(
      left: pos.dx - size / 2,
      top: pos.dy - size / 2,
      width: size,
      height: size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (DragStartDetails d) => onStart(_toLocal(d.globalPosition)),
        onPanUpdate: (DragUpdateDetails d) => onUpdate(_toLocal(d.globalPosition)),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFFB58CFF),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 14, color: Colors.white),
        ),
      ),
    );
  }

  Widget _snipCanvas(AppState app) {
    final _Snip? s = _selSnip;
    if (s == null) {
      return const Center(child: Text('Add a snip to crop it.'));
    }
    final String? rel = _overlayRel(app, s);
    if (rel == null) {
      return const Center(child: Text('Pick a sprite to snip from.'));
    }
    final _SourceView? view = _sourceViews[rel];
    if (view == null) {
      _ensureSourceView(app, rel);
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints cons) {
        final Rect rect = _containRect(cons.biggest, view.w, view.h);
        final Rect cropRect = Rect.fromLTWH(
          rect.left + s.cx * rect.width,
          rect.top + s.cy * rect.height,
          s.cw * rect.width,
          s.ch * rect.height,
        );
        return Stack(
          key: _canvasKey,
          children: <Widget>[
            const Positioned.fill(child: CheckerImage(bytes: null)),
            Positioned.fromRect(
              rect: rect,
              child: Image.memory(view.png, fit: BoxFit.fill, gaplessPlayback: true),
            ),
            // Move the crop box.
            Positioned.fromRect(
              rect: cropRect,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (DragUpdateDetails d) {
                  setState(() {
                    s.cx = (s.cx + d.delta.dx / rect.width).clamp(0.0, 1 - s.cw);
                    s.cy = (s.cy + d.delta.dy / rect.height).clamp(0.0, 1 - s.ch);
                  });
                  _scheduleBake(s);
                },
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFB58CFF), width: 1.5),
                    shape: s.ellipse ? BoxShape.circle : BoxShape.rectangle,
                  ),
                ),
              ),
            ),
            // Top-left resize handle.
            _cropHandle(
              Offset(cropRect.left, cropRect.top),
              onUpdate: (Offset p) {
                setState(() {
                  final double nx = ((p.dx - rect.left) / rect.width).clamp(0.0, s.cx + s.cw - 0.02);
                  final double ny = ((p.dy - rect.top) / rect.height).clamp(0.0, s.cy + s.ch - 0.02);
                  s.cw = (s.cx + s.cw) - nx;
                  s.ch = (s.cy + s.ch) - ny;
                  s.cx = nx;
                  s.cy = ny;
                });
                _scheduleBake(s);
              },
            ),
            // Bottom-right resize handle.
            _cropHandle(
              Offset(cropRect.right, cropRect.bottom),
              onUpdate: (Offset p) {
                setState(() {
                  final double right = ((p.dx - rect.left) / rect.width).clamp(s.cx + 0.02, 1.0);
                  final double bottom = ((p.dy - rect.top) / rect.height).clamp(s.cy + 0.02, 1.0);
                  s.cw = right - s.cx;
                  s.ch = bottom - s.cy;
                });
                _scheduleBake(s);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _cropHandle(Offset pos, {required void Function(Offset) onUpdate}) {
    const double size = 20;
    return Positioned(
      left: pos.dx - size / 2,
      top: pos.dy - size / 2,
      width: size,
      height: size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (DragUpdateDetails d) => onUpdate(_toLocal(d.globalPosition)),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFB58CFF),
            border: Border.all(color: Colors.white, width: 1),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }

  // ---- layers (link whole, pre-aligned sprites) -----------------------------

  String? _layerRel(AppState app, _Layer l) {
    if (l.base == null) return null;
    return l.source == null
        ? app.relForBase(l.base!)
        : app.relForMixBase(l.source!, l.base!);
  }

  void _addLayer({String? source, String? base}) {
    final AppState app = context.read<AppState>();
    final _Layer l = _Layer(_layerNextId++)
      ..source = source
      ..base = base ?? _firstBaseFor(app, source);
    setState(() => _layers.add(l));
  }

  /// One-click "link everything": add every sprite in [source] as a layer.
  void _addAllLayers(AppState app, String? source) {
    final List<String> bases = _basesForSource(app, source);
    setState(() {
      for (final String b in bases) {
        _layers.add(_Layer(_layerNextId++)
          ..source = source
          ..base = b);
      }
    });
  }

  void _moveLayer(int i, int delta) {
    final int j = i + delta;
    if (i < 0 || i >= _layers.length || j < 0 || j >= _layers.length) return;
    setState(() => _layers.insert(j, _layers.removeAt(i)));
  }

  /// Full-resolution stack of every visible layer at its native position.
  Future<Uint8List?> _compositeLayers(AppState app) async {
    final List<Layer> stack = <Layer>[];
    int w = 0, h = 0;
    for (final _Layer l in _layers) {
      if (!l.visible) continue;
      final String? rel = _layerRel(app, l);
      if (rel == null) continue;
      final img.Image? im = await app.decodeFirstFrame(rel);
      if (im == null) continue;
      w = math.max(w, im.width);
      h = math.max(h, im.height);
      stack.add(Layer(im, opacity: l.opacity));
    }
    if (stack.isEmpty || w == 0 || h == 0) return null;
    img.Image result = Compositor.flatten(w, h, stack);
    if (_cropL > 0 || _cropT > 0 || _cropR > 0 || _cropB > 0) {
      final int x0 = (_cropL * result.width).round();
      final int y0 = (_cropT * result.height).round();
      final int x1 = result.width - (_cropR * result.width).round();
      final int y1 = result.height - (_cropB * result.height).round();
      if (x1 - x0 >= 1 && y1 - y0 >= 1) {
        result = img.copyCrop(result, x: x0, y: y0, width: x1 - x0, height: y1 - y0);
      }
    }
    return Codecs.encodePng(result);
  }

  Widget _layersCanvas(AppState app) {
    final List<_Layer> visible =
        _layers.where((_Layer l) => l.visible).toList();
    if (visible.isEmpty) {
      return const Center(child: Text('Add layers to stack them here.'));
    }
    final Map<_Layer, String> rels = <_Layer, String>{};
    for (final _Layer l in visible) {
      final String? rel = _layerRel(app, l);
      if (rel != null) {
        rels[l] = rel;
        _ensureSourceView(app, rel);
      }
    }
    _SourceView? first;
    for (final _Layer l in visible) {
      final String? rel = rels[l];
      if (rel != null && _sourceViews[rel] != null) {
        first = _sourceViews[rel];
        break;
      }
    }
    if (first == null) return const Center(child: CircularProgressIndicator());
    final _SourceView baseView = first;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints cons) {
        final Rect rect = _containRect(cons.biggest, baseView.w, baseView.h);
        return Stack(
          children: <Widget>[
            const Positioned.fill(child: CheckerImage(bytes: null)),
            for (final _Layer l in visible)
              if (rels[l] != null && _sourceViews[rels[l]] != null)
                Positioned.fromRect(
                  rect: rect,
                  child: Opacity(
                    opacity: l.opacity,
                    child: Image.memory(_sourceViews[rels[l]]!.png,
                        fit: BoxFit.fill, gaplessPlayback: true),
                  ),
                ),
          ],
        );
      },
    );
  }

  // ---- controls -------------------------------------------------------------

  Widget _controls(AppState app, List<String> bases) {
    if (_mode == _Mode.layers) return _layersControls(app, bases);
    return _snipControls(app, bases);
  }

  Widget _layersControls(AppState app, List<String> bases) {
    final List<String?> sources = <String?>[
      null,
      for (final MixSource m in app.mixSources) m.label,
    ];
    if (!sources.contains(_addAllSource)) _addAllSource = null;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        Text('Link layers', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'For art where every feature is a separate, already-aligned file '
            '(eyes, eyebrows, body, an arm…). Add them all and they stack into '
            'one finished sprite — no cropping or positioning needed.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _loadPartsFolder(app),
          icon: const Icon(Icons.create_new_folder_outlined),
          label: const Text('Load a sprite folder…'),
        ),
        const SizedBox(height: 8),
        Row(children: <Widget>[
          Expanded(
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Add ALL from', isDense: true),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  isExpanded: true,
                  value: _addAllSource,
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('This project')),
                    for (final MixSource m in app.mixSources)
                      DropdownMenuItem<String?>(
                          value: m.label, child: Text('📁 ${m.label}')),
                  ],
                  onChanged: (String? v) => setState(() => _addAllSource = v),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: () => _addAllLayers(app, _addAllSource),
            child: const Text('Add all'),
          ),
        ]),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _addLayer(source: _addAllSource),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add one layer'),
        ),
        const Divider(),
        Text('Stack (top of list = on top)',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        if (_layers.isEmpty)
          const Text('No layers yet.',
              style: TextStyle(fontSize: 12, color: Colors.orange)),
        for (int i = 0; i < _layers.length; i++) _layerCard(app, i),
        const Divider(),
        Text('Crop output', style: Theme.of(context).textTheme.labelLarge),
        _slider('Left', _cropL, (double v) => _cropL = v, min: 0, max: 0.45),
        _slider('Top', _cropT, (double v) => _cropT = v, min: 0, max: 0.45),
        _slider('Right', _cropR, (double v) => _cropR = v, min: 0, max: 0.45),
        _slider('Bottom', _cropB, (double v) => _cropB = v, min: 0, max: 0.45),
        const Divider(),
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'New sprite name'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () async {
            final Uint8List? png = await _compositeLayers(app);
            if (png != null) await app.addCompositeSprite(_name.text, png);
          },
          icon: const Icon(Icons.save_rounded),
          label: const Text('Combine & save as new emote'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _layerCard(AppState app, int i) {
    final _Layer l = _layers[i];
    final List<String> bases = _basesForSource(app, l.source);
    if (l.base != null && !bases.contains(l.base)) {
      l.base = bases.isNotEmpty ? bases.first : null;
    }
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          children: <Widget>[
            Row(children: <Widget>[
              Checkbox(
                value: l.visible,
                visualDensity: VisualDensity.compact,
                onChanged: (bool? v) => setState(() => l.visible = v ?? true),
              ),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: bases.contains(l.base) ? l.base : null,
                    hint: const Text('(pick sprite)'),
                    items: <DropdownMenuItem<String>>[
                      for (final String b in bases)
                        DropdownMenuItem<String>(
                            value: b,
                            child: Text(b, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (String? v) => setState(() => l.base = v),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Up',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                onPressed: i == 0 ? null : () => _moveLayer(i, -1),
              ),
              IconButton(
                tooltip: 'Down',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                onPressed: i == _layers.length - 1 ? null : () => _moveLayer(i, 1),
              ),
              IconButton(
                tooltip: 'Remove',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => setState(() => _layers.removeAt(i)),
              ),
            ]),
            if (app.mixSources.isNotEmpty)
              Row(children: <Widget>[
                const SizedBox(width: 4),
                const Text('From', style: TextStyle(fontSize: 11)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      isExpanded: true,
                      value: app.mixSources.any((MixSource m) => m.label == l.source)
                          ? l.source
                          : null,
                      items: <DropdownMenuItem<String?>>[
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('This project')),
                        for (final MixSource m in app.mixSources)
                          DropdownMenuItem<String?>(
                              value: m.label,
                              child: Text('📁 ${m.label}',
                                  overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (String? v) => setState(() {
                        l.source = v;
                        l.base = _firstBaseFor(app, v);
                      }),
                    ),
                  ),
                ),
              ]),
            Row(children: <Widget>[
              const Text('Opacity', style: TextStyle(fontSize: 11)),
              Expanded(
                child: Slider(
                  value: l.opacity,
                  onChanged: (double v) => setState(() => l.opacity = v),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _snipControls(AppState app, List<String> bases) {
    final _Snip? s = _selSnip;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        Row(children: <Widget>[
          Expanded(
            child: Text('Frankensprite mixer',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          TextButton(onPressed: _resetSnip, child: const Text('Reset snip')),
        ]),
        const SizedBox(height: 8),
        _howItWorks(),
        const SizedBox(height: 12),

        // ---- Body ----
        Text('Body', style: Theme.of(context).textTheme.labelLarge),
        _picker('Body (from your project)', _base, bases, (String? v) {
          setState(() => _base = v);
          _loadBody(app);
        }),
        const Divider(),

        // ---- Snips list ----
        Row(children: <Widget>[
          Expanded(
              child: Text('Snips (${_snips.length})',
                  style: Theme.of(context).textTheme.labelLarge)),
          IconButton(
            tooltip: 'Add a snip',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _addSnip(),
          ),
        ]),
        _snipList(app),
        const SizedBox(height: 8),

        if (s == null)
          const Text('Add a snip to start grafting parts on.',
              style: TextStyle(fontSize: 12, color: Colors.orange))
        else
          ..._snipEditor(app, s),
        const Divider(),

        // ---- Output crop ----
        Text('Crop output', style: Theme.of(context).textTheme.labelLarge),
        _slider('Left', _cropL, (double v) => _cropL = v, min: 0, max: 0.45),
        _slider('Top', _cropT, (double v) => _cropT = v, min: 0, max: 0.45),
        _slider('Right', _cropR, (double v) => _cropR = v, min: 0, max: 0.45),
        _slider('Bottom', _cropB, (double v) => _cropB = v, min: 0, max: 0.45),
        const Divider(),

        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'New sprite name'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () async {
            final Uint8List? png = await _composite(app);
            if (png != null) await app.addCompositeSprite(_name.text, png);
          },
          icon: const Icon(Icons.save_rounded),
          label: const Text('Save as new emote'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _snipList(AppState app) {
    if (_snips.isEmpty) return const SizedBox.shrink();
    return Column(
      children: <Widget>[
        for (int i = 0; i < _snips.length; i++)
          Card(
            color: i == _sel ? const Color(0x33B58CFF) : null,
            margin: const EdgeInsets.symmetric(vertical: 2),
            child: ListTile(
              dense: true,
              onTap: () => setState(() => _sel = i),
              leading: _pieces[_snips[i].id]?.png == null
                  ? const Icon(Icons.crop_rounded, size: 20)
                  : SizedBox(
                      width: 28,
                      height: 28,
                      child: Image.memory(_pieces[_snips[i].id]!.png,
                          fit: BoxFit.contain, gaplessPlayback: true),
                    ),
              title: Text('Snip ${i + 1}: ${_snips[i].base ?? '—'}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(_snips[i].source ?? 'this project',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                IconButton(
                  tooltip: 'Duplicate',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () => _duplicateSnip(i),
                ),
                IconButton(
                  tooltip: 'Remove',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => _removeSnip(i),
                ),
              ]),
            ),
          ),
      ],
    );
  }

  List<Widget> _snipEditor(AppState app, _Snip s) {
    final List<String> overlayBases = _basesForSource(app, s.source);
    if (s.base != null && !overlayBases.contains(s.base)) {
      s.base = overlayBases.isNotEmpty ? overlayBases.first : null;
    }
    return <Widget>[
      Text('Editing snip ${_sel + 1}',
          style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 4),
      _partsSourcePicker(app, s),
      const SizedBox(height: 6),
      OutlinedButton.icon(
        onPressed: () => _loadPartsFolder(app),
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('Load a 2nd sprite folder…'),
      ),
      const SizedBox(height: 6),
      overlayBases.isEmpty
          ? const Text('That source has no sprites yet.',
              style: TextStyle(fontSize: 12, color: Colors.orange))
          : _picker('Snip from', s.base, overlayBases, (String? v) {
              setState(() => s.base = v);
              _scheduleBake(s);
            }),
      _switch('Ellipse snip (good for heads)', s.ellipse, (bool v) {
        s.ellipse = v;
        _scheduleBake(s);
      }),
      const SizedBox(height: 6),
      Text('Snip region (or drag the box in Snip mode)',
          style: Theme.of(context).textTheme.labelMedium),
      _slider('X', s.cx, (double v) => s.cx = v, bake: s),
      _slider('Y', s.cy, (double v) => s.cy = v, bake: s),
      _slider('Width', s.cw, (double v) => s.cw = v, min: 0.02, max: 1, bake: s),
      _slider('Height', s.ch, (double v) => s.ch = v, min: 0.02, max: 1, bake: s),
      Row(children: <Widget>[
        Expanded(child: _switch('Flip H', s.flipH, (bool v) { s.flipH = v; _scheduleBake(s); })),
        Expanded(child: _switch('Flip V', s.flipV, (bool v) { s.flipV = v; _scheduleBake(s); })),
      ]),
      _slider('Feather', s.feather, (double v) => s.feather = v, min: 0, max: 6, bake: s),
      const SizedBox(height: 6),
      Text('Recolour the snip (match the body)',
          style: Theme.of(context).textTheme.labelMedium),
      _slider('Hue', s.hue, (double v) => s.hue = v, min: -180, max: 180, bake: s),
      _slider('Saturation', s.sat, (double v) => s.sat = v, min: 0, max: 2, bake: s),
      _slider('Brightness', s.bri, (double v) => s.bri = v, min: 0, max: 2, bake: s),
      const SizedBox(height: 6),
      Row(children: <Widget>[
        Expanded(
            child: Text('Placement (drag on the canvas too)',
                style: Theme.of(context).textTheme.labelMedium)),
        TextButton(
          onPressed: () {
            setState(() {
              s.px = 0.5;
              s.py = 0.5;
            });
          },
          child: const Text('Center'),
        ),
      ]),
      _slider('Pos X', s.px, (double v) => s.px = v),
      _slider('Pos Y', s.py, (double v) => s.py = v),
      _slider('Scale', s.scale, (double v) => s.scale = v, min: 0.1, max: 4),
      _slider('Rotate', s.angle, (double v) => s.angle = v, min: -180, max: 180),
      _slider('Opacity', s.opacity, (double v) => s.opacity = v),
    ];
  }

  Widget _howItWorks() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.lightbulb_outline, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Stack ANY number of snips on a body — heads, hats, accessories.\n'
              '• Body = a sprite from your project.\n'
              '• Each snip = your project, or a 2nd folder you load.\n'
              '• Drag on the canvas (Arrange/Snip modes) or use the sliders.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _partsSourcePicker(AppState app, _Snip s) {
    final List<DropdownMenuItem<String?>> items = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(value: null, child: Text('This project')),
      for (final MixSource m in app.mixSources)
        DropdownMenuItem<String?>(
          value: m.label,
          child: Text('📁 ${m.label}  (${m.groups.length})',
              overflow: TextOverflow.ellipsis),
        ),
    ];
    return Row(
      children: <Widget>[
        Expanded(
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'Snip parts from'),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                isExpanded: true,
                value: app.mixSources.any((MixSource m) => m.label == s.source)
                    ? s.source
                    : null,
                items: items,
                onChanged: (String? v) {
                  setState(() {
                    s.source = v;
                    s.base = _firstBaseFor(app, v);
                  });
                  _scheduleBake(s);
                },
              ),
            ),
          ),
        ),
        if (s.source != null)
          IconButton(
            tooltip: 'Remove this loaded folder',
            icon: const Icon(Icons.close_rounded),
            onPressed: () {
              final String label = s.source!;
              setState(() {
                for (final _Snip sn in _snips) {
                  if (sn.source == label) {
                    sn.source = null;
                    sn.base = _firstBaseFor(app, null);
                  }
                }
              });
              app.removeMixSource(label);
              _rebakeAll(app);
            },
          ),
      ],
    );
  }

  Widget _picker(String label, String? value, List<String> items,
          ValueChanged<String?> onChanged) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: InputDecorator(
          decoration: InputDecoration(labelText: label),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: items.contains(value) ? value : null,
              items: <DropdownMenuItem<String>>[
                for (final String s in items)
                  DropdownMenuItem<String>(
                      value: s, child: Text(s, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: onChanged,
            ),
          ),
        ),
      );

  Widget _switch(String label, bool value, ValueChanged<bool> assign) =>
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: const TextStyle(fontSize: 13)),
        value: value,
        onChanged: (bool v) => setState(() => assign(v)),
      );

  Widget _slider(String label, double v, void Function(double) assign,
          {double min = 0, double max = 1, _Snip? bake}) =>
      Row(
        children: <Widget>[
          SizedBox(width: 64, child: Text(label, style: const TextStyle(fontSize: 12))),
          Expanded(
            child: Slider(
              value: v.clamp(min, max),
              min: min,
              max: max,
              onChanged: (double nv) {
                setState(() => assign(nv));
                if (bake != null) _scheduleBake(bake);
              },
            ),
          ),
        ],
      );
}

/// One grafted part: where it's cut from, how it's cut, and how it's placed.
class _Snip {
  _Snip(this.id);
  final int id;

  String? source; // null = this project, else a MixSource label
  String? base;
  bool ellipse = true;

  // crop of the source (fractions 0..1)
  double cx = 0.25, cy = 0.0, cw = 0.5, ch = 0.45;
  // placement on the body (fractions) + transform
  double px = 0.5, py = 0.22, scale = 1.0, angle = 0, opacity = 1.0;
  // post-processing
  bool flipH = false, flipV = false;
  double feather = 0, hue = 0, sat = 1, bri = 1;

  void resetTransform() {
    cx = 0.25;
    cy = 0;
    cw = 0.5;
    ch = 0.45;
    px = 0.5;
    py = 0.22;
    scale = 1;
    angle = 0;
    opacity = 1;
    flipH = false;
    flipV = false;
    feather = 0;
    hue = 0;
    sat = 1;
    bri = 1;
  }

  _Snip clone(int newId) {
    final _Snip s = _Snip(newId)
      ..source = source
      ..base = base
      ..ellipse = ellipse
      ..cx = cx
      ..cy = cy
      ..cw = cw
      ..ch = ch
      ..px = px
      ..py = py
      ..scale = scale
      ..angle = angle
      ..opacity = opacity
      ..flipH = flipH
      ..flipV = flipV
      ..feather = feather
      ..hue = hue
      ..sat = sat
      ..bri = bri;
    return s;
  }
}

/// A baked cut piece: PNG bytes + its full-resolution pixel size (for canvas
/// sizing — the piece sits 1:1 on body pixels, scaled by [_Snip.scale]).
class _Piece {
  _Piece(this.png, this.w, this.h);
  final Uint8List png;
  final int w, h;
}

/// A decoded source sprite for the Snip-mode crop view.
class _SourceView {
  _SourceView(this.png, this.w, this.h);
  final Uint8List png;
  final int w, h;
}

/// One whole-sprite layer in **Layers** mode: composited at its native position
/// (0,0) with [opacity]; [visible] toggles it without removing it.
class _Layer {
  _Layer(this.id);
  final int id;
  String? source; // null = this project, else a MixSource label
  String? base;
  double opacity = 1;
  bool visible = true;
}
