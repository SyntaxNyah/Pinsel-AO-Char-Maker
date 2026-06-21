import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

import '../../core/ao_constants.dart';
import '../../imaging/button_maker.dart' show IntRect;
import '../../imaging/codecs.dart';
import '../../imaging/sprite_sheet.dart';
import '../app_state.dart';

/// **Sprite Sheet Ripper** — slice a sheet of visual-novel sprites into
/// individual transparent sprites. Two modes: **Auto** (detect each sprite from
/// the background, any layout) and **Grid** (uniform rows×columns). Overlay
/// boxes are tappable to include/exclude; export adds them to your character or
/// downloads a zip.
class SpriteRipperScreen extends StatefulWidget {
  const SpriteRipperScreen({super.key});

  @override
  State<SpriteRipperScreen> createState() => _SpriteRipperScreenState();
}

class _SpriteRipperScreenState extends State<SpriteRipperScreen> {
  img.Image? _sheet;
  Uint8List? _bytes;
  SheetMode _mode = SheetMode.auto;
  AutoSpec _auto = const AutoSpec();
  GridSpec _grid = const GridSpec();
  List<SheetCell> _cells = <SheetCell>[];
  bool _removeBg = true;
  int _bgTolerance = 24;
  final TextEditingController _prefix = TextEditingController(text: 'sprite');
  Timer? _debounce;

  // Manual-mode state: a draft rubber-band + the selected box + drag accumulators.
  int? _selManual;
  Rect? _draft;
  Offset _drawAnchor = Offset.zero;
  IntRect? _dragStartRect;
  double _accX = 0, _accY = 0;
  bool _resizingManual = false;

  @override
  void initState() {
    super.initState();
    final AppState app = context.read<AppState>();
    if (app.ripperSheetBytes != null) {
      _bytes = app.ripperSheetBytes;
      _sheet = Codecs.decode(app.ripperSheetBytes!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _detect();
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _prefix.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final FilePickerResult? res = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: kImportableImageExtensions,
    );
    if (res == null || res.files.isEmpty || res.files.first.bytes == null) return;
    final PlatformFile f = res.files.first;
    final img.Image? im = Codecs.decode(f.bytes!,
        ext: f.extension?.toLowerCase());
    if (im == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not decode that image.')));
      }
      return;
    }
    if (!mounted) return;
    context.read<AppState>().loadSheet(f.bytes!, f.name);
    setState(() {
      _bytes = f.bytes;
      _sheet = im;
    });
    _detect();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), _detect);
  }

  void _detect() {
    final img.Image? s = _sheet;
    if (s == null) return;
    if (_mode == SheetMode.manual) return; // hand-drawn boxes — keep the user's
    final List<IntRect> rects = _mode == SheetMode.auto
        ? SpriteSheet.autoDetect(s, _auto)
        : SpriteSheet.grid(s.width, s.height, _grid);
    final String prefix = _prefix.text.trim().isEmpty ? 'sprite' : _prefix.text.trim();
    setState(() {
      _cells = <SheetCell>[
        for (int i = 0; i < rects.length; i++)
          SheetCell(rects[i], name: '$prefix${i + 1}'),
      ];
    });
  }

  void _renumber() {
    final String prefix = _prefix.text.trim().isEmpty ? 'sprite' : _prefix.text.trim();
    for (int i = 0; i < _cells.length; i++) {
      _cells[i].name = '$prefix${i + 1}';
    }
    setState(() {});
  }

  int get _enabled => _cells.where((SheetCell c) => c.enabled).length;

  Future<void> _export({required bool toProject}) async {
    final img.Image? s = _sheet;
    if (s == null) return;
    await context.read<AppState>().exportSheetCells(
          s,
          _cells,
          toProject: toProject,
          removeBg: _removeBg,
          tolerance: _bgTolerance,
          namePrefix: _prefix.text.trim().isEmpty ? 'sprite' : _prefix.text.trim(),
        );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(child: _preview()),
        const VerticalDivider(width: 1),
        SizedBox(width: 360, child: _controls()),
      ],
    );
  }

  Widget _preview() {
    if (_sheet == null || _bytes == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.grid_on_rounded, size: 48, color: Colors.white24),
            const SizedBox(height: 12),
            const Text('Load a sprite sheet to rip it into sprites.'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Load sheet'),
            ),
          ],
        ),
      );
    }
    final int sw = _sheet!.width, sh = _sheet!.height;
    return Padding(
      padding: const EdgeInsets.all(12),
      // Zoom + pan the sheet so you can box tiny sprites precisely. Pinch or
      // mouse-wheel to zoom; drag to pan — except in Manual mode, where a drag
      // **draws** a box, so pan is disabled there (pinch/wheel still zooms). The
      // box gestures below read child-local coordinates, so they stay correct at
      // any zoom. minScale 1.0 ⇒ zooming all the way out returns to the fit view.
      child: InteractiveViewer(
        minScale: 1.0,
        maxScale: 10.0,
        panEnabled: _mode != SheetMode.manual,
        clipBehavior: Clip.hardEdge,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints cons) {
            final double scale =
                (cons.maxWidth / sw).clamp(0.0, cons.maxHeight / sh);
          final double dw = sw * scale, dh = sh * scale;
          final double ox = (cons.maxWidth - dw) / 2, oy = (cons.maxHeight - dh) / 2;
          return Stack(
            children: <Widget>[
              Positioned(
                left: ox,
                top: oy,
                width: dw,
                height: dh,
                child: Image.memory(_bytes!, fit: BoxFit.fill, gaplessPlayback: true),
              ),
              // Manual draw layer (under the boxes): drag empty space to draw a
              // new box; tap empty space to deselect.
              if (_mode == SheetMode.manual)
                Positioned(
                  left: ox,
                  top: oy,
                  width: dw,
                  height: dh,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _selManual = null),
                    onPanStart: (DragStartDetails d) => _drawStart(d.localPosition, scale),
                    onPanUpdate: (DragUpdateDetails d) => _drawUpdate(d.localPosition, scale),
                    onPanEnd: (_) => _drawEnd(),
                  ),
                ),
              for (int i = 0; i < _cells.length; i++)
                _mode == SheetMode.manual
                    ? _manualBox(_cells[i], i, ox, oy, scale)
                    : _box(_cells[i], i, ox, oy, scale),
              if (_draft != null)
                Positioned(
                  left: ox + _draft!.left * scale,
                  top: oy + _draft!.top * scale,
                  width: _draft!.width * scale,
                  height: _draft!.height * scale,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.amber, width: 1.5),
                        color: Colors.amber.withOpacity(0.12),
                      ),
                    ),
                  ),
                ),
            ],
          );
          },
        ),
      ),
    );
  }

  Widget _box(SheetCell c, int i, double ox, double oy, double scale) {
    final Color col = c.enabled ? Colors.tealAccent : Colors.white24;
    return Positioned(
      left: ox + c.rect.x * scale,
      top: oy + c.rect.y * scale,
      width: c.rect.w * scale,
      height: c.rect.h * scale,
      child: GestureDetector(
        onTap: () => setState(() => c.enabled = !c.enabled),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: col, width: 1.5),
            color: c.enabled ? Colors.tealAccent.withOpacity(0.08) : Colors.black26,
          ),
          alignment: Alignment.topLeft,
          child: Container(
            color: col,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text('${i + 1}',
                style: const TextStyle(fontSize: 9, color: Colors.black)),
          ),
        ),
      ),
    );
  }

  // ---- manual mode: draw / move / resize / delete boxes ----

  void _drawStart(Offset local, double scale) {
    _drawAnchor = Offset(local.dx / scale, local.dy / scale);
    setState(() {
      _selManual = null;
      _draft = Rect.fromPoints(_drawAnchor, _drawAnchor);
    });
  }

  void _drawUpdate(Offset local, double scale) {
    final Offset cur = Offset(local.dx / scale, local.dy / scale);
    setState(() => _draft = Rect.fromPoints(_drawAnchor, cur));
  }

  void _drawEnd() {
    final Rect? r = _draft;
    final img.Image? s = _sheet;
    _draft = null;
    if (r == null || s == null) {
      setState(() {});
      return;
    }
    final int x = r.left.round().clamp(0, s.width - 1);
    final int y = r.top.round().clamp(0, s.height - 1);
    final int w = r.width.round().clamp(1, s.width - x);
    final int h = r.height.round().clamp(1, s.height - y);
    if (w < 6 || h < 6) {
      setState(() {}); // ignore tiny accidental drags
      return;
    }
    final String prefix = _prefix.text.trim().isEmpty ? 'sprite' : _prefix.text.trim();
    setState(() {
      _cells.add(SheetCell(IntRect(x, y, w, h), name: '$prefix${_cells.length + 1}'));
      _selManual = _cells.length - 1;
    });
  }

  Widget _manualBox(SheetCell c, int i, double ox, double oy, double scale) {
    final bool selected = _selManual == i;
    final double bw = c.rect.w * scale, bh = c.rect.h * scale;
    const double handle = 16;
    final Color col = selected ? Colors.amber : Colors.tealAccent;
    return Positioned(
      left: ox + c.rect.x * scale,
      top: oy + c.rect.y * scale,
      width: bw,
      height: bh,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selManual = i),
        onPanStart: (DragStartDetails d) {
          _accX = 0;
          _accY = 0;
          _resizingManual =
              d.localPosition.dx > bw - handle && d.localPosition.dy > bh - handle;
          _dragStartRect = c.rect;
          setState(() => _selManual = i);
        },
        onPanUpdate: (DragUpdateDetails d) {
          _accX += d.delta.dx;
          _accY += d.delta.dy;
          final IntRect sr = _dragStartRect!;
          setState(() {
            if (_resizingManual) {
              c.rect = IntRect(
                  sr.x,
                  sr.y,
                  (sr.w + (_accX / scale).round()).clamp(4, 1 << 20),
                  (sr.h + (_accY / scale).round()).clamp(4, 1 << 20));
            } else {
              c.rect = IntRect(sr.x + (_accX / scale).round(),
                  sr.y + (_accY / scale).round(), sr.w, sr.h);
            }
          });
        },
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: col, width: selected ? 2 : 1.5),
                  color: Colors.tealAccent.withOpacity(0.08),
                ),
                alignment: Alignment.topLeft,
                child: Container(
                  color: col,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text('${i + 1}',
                      style: const TextStyle(fontSize: 9, color: Colors.black)),
                ),
              ),
            ),
            if (selected)
              Positioned(
                right: 0,
                top: 0,
                child: GestureDetector(
                  onTap: () => setState(() {
                    _cells.removeAt(i);
                    _selManual = null;
                  }),
                  child: Container(
                    color: Colors.red,
                    padding: const EdgeInsets.all(1),
                    child: const Icon(Icons.close, size: 11, color: Colors.white),
                  ),
                ),
              ),
            if (selected)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: handle,
                  height: handle,
                  color: Colors.amber,
                  child: const Icon(Icons.open_in_full, size: 9, color: Colors.black),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _manualControls() {
    return <Widget>[
      const Text(
        'Drag on the sheet to draw a sprite box. Drag a box to move it, drag its '
        'corner to resize, tap to select, then × to delete. Perfect for grouping '
        'sprites or fixing what auto-detect missed.',
        style: TextStyle(fontSize: 12, color: Colors.white70),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _cells.isEmpty
            ? null
            : () => setState(() {
                  _cells.clear();
                  _selManual = null;
                }),
        icon: const Icon(Icons.clear_all_rounded, size: 18),
        label: const Text('Clear boxes'),
      ),
    ];
  }

  Widget _controls() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        Row(children: <Widget>[
          Expanded(
            child: Text('Sprite Sheet Ripper',
                style: Theme.of(context).textTheme.titleLarge),
          ),
          IconButton(
            tooltip: 'Load a different sheet',
            onPressed: _load,
            icon: const Icon(Icons.upload_file_rounded),
          ),
        ]),
        const Text(
          'Slice a sheet of VN sprites into individual transparent sprites. '
          'Tap a box to include/exclude it.',
          style: TextStyle(fontSize: 12, color: Colors.white60),
        ),
        const SizedBox(height: 12),
        SegmentedButton<SheetMode>(
          segments: const <ButtonSegment<SheetMode>>[
            ButtonSegment<SheetMode>(
                value: SheetMode.auto, label: Text('Auto'), icon: Icon(Icons.auto_fix_high)),
            ButtonSegment<SheetMode>(
                value: SheetMode.grid, label: Text('Grid'), icon: Icon(Icons.grid_4x4)),
            ButtonSegment<SheetMode>(
                value: SheetMode.manual, label: Text('Manual'), icon: Icon(Icons.draw_outlined)),
          ],
          selected: <SheetMode>{_mode},
          onSelectionChanged: (Set<SheetMode> s) {
            setState(() => _mode = s.first);
            _detect();
          },
        ),
        const SizedBox(height: 12),
        if (_mode == SheetMode.auto)
          ..._autoControls()
        else if (_mode == SheetMode.grid)
          ..._gridControls()
        else
          ..._manualControls(),
        const Divider(height: 24),
        _removeBgControls(),
        const Divider(height: 24),
        TextField(
          controller: _prefix,
          decoration: const InputDecoration(labelText: 'Name prefix'),
          onSubmitted: (_) => _renumber(),
        ),
        const SizedBox(height: 12),
        Row(children: <Widget>[
          Expanded(
            child: Text('$_enabled / ${_cells.length} cells selected',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          TextButton(
            onPressed: _cells.isEmpty
                ? null
                : () => setState(() {
                      for (final SheetCell c in _cells) {
                        c.enabled = true;
                      }
                    }),
            child: const Text('All'),
          ),
          TextButton(
            onPressed: _cells.isEmpty
                ? null
                : () => setState(() {
                      for (final SheetCell c in _cells) {
                        c.enabled = false;
                      }
                    }),
            child: const Text('None'),
          ),
        ]),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _enabled == 0 ? null : () => _export(toProject: true),
          icon: const Icon(Icons.add_to_photos_outlined),
          label: const Text('Add to character'),
        ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: _enabled == 0 ? null : () => _export(toProject: false),
          icon: const Icon(Icons.archive_outlined),
          label: const Text('Download as .zip'),
        ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: _enabled == 0 ? null : _sendToPuppet,
          icon: const Icon(Icons.accessibility_new_rounded),
          label: const Text('Send to Puppet'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  /// Hand the boxed cells to the Puppet Studio as layers (each placed at its cell
  /// centre), then nudge the user to the Puppet tab.
  void _sendToPuppet() {
    final img.Image? s = _sheet;
    if (s == null) return;
    context.read<AppState>().puppetFromSheetCells(
          s,
          _cells,
          removeBg: _removeBg,
          tolerance: _bgTolerance,
        );
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Parts sent to the Puppet Studio — open the Puppet tab to '
            'assemble & animate them.')));
  }

  List<Widget> _autoControls() {
    return <Widget>[
      _slider('Background tolerance', _auto.tolerance.toDouble(), 0, 120, (double v) {
        setState(() => _auto = _auto.copyWith(tolerance: v.round()));
        _schedule();
      }),
      _slider('Minimum sprite size', _auto.minSide.toDouble(), 4, 200, (double v) {
        setState(() => _auto = _auto.copyWith(minSide: v.round()));
        _schedule();
      }),
      _slider('Merge gap', _auto.gap.toDouble(), 0, 60, (double v) {
        setState(() => _auto = _auto.copyWith(gap: v.round()));
        _schedule();
      }),
      _slider('Padding', _auto.padding.toDouble(), 0, 20, (double v) {
        setState(() => _auto = _auto.copyWith(padding: v.round()));
        _schedule();
      }),
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: const Text('Trim each sprite to content', style: TextStyle(fontSize: 13)),
        value: _auto.trim,
        onChanged: (bool v) {
          setState(() => _auto = _auto.copyWith(trim: v));
          _detect();
        },
      ),
    ];
  }

  List<Widget> _gridControls() {
    return <Widget>[
      Row(children: <Widget>[
        Expanded(child: _intField('Columns', _grid.cols, (int v) {
          _grid = _grid.copyWith(cols: v.clamp(1, 64));
          _detect();
        })),
        const SizedBox(width: 8),
        Expanded(child: _intField('Rows', _grid.rows, (int v) {
          _grid = _grid.copyWith(rows: v.clamp(1, 64));
          _detect();
        })),
      ]),
      Row(children: <Widget>[
        Expanded(child: _intField('Offset X', _grid.offsetX, (int v) {
          _grid = _grid.copyWith(offsetX: v);
          _detect();
        })),
        const SizedBox(width: 8),
        Expanded(child: _intField('Offset Y', _grid.offsetY, (int v) {
          _grid = _grid.copyWith(offsetY: v);
          _detect();
        })),
      ]),
      Row(children: <Widget>[
        Expanded(child: _intField('Gutter X', _grid.gutterX, (int v) {
          _grid = _grid.copyWith(gutterX: v);
          _detect();
        })),
        const SizedBox(width: 8),
        Expanded(child: _intField('Gutter Y', _grid.gutterY, (int v) {
          _grid = _grid.copyWith(gutterY: v);
          _detect();
        })),
      ]),
      Row(children: <Widget>[
        Expanded(child: _intField('Cell W (0=auto)', _grid.cellW, (int v) {
          _grid = _grid.copyWith(cellW: v);
          _detect();
        })),
        const SizedBox(width: 8),
        Expanded(child: _intField('Cell H (0=auto)', _grid.cellH, (int v) {
          _grid = _grid.copyWith(cellH: v);
          _detect();
        })),
      ]),
    ];
  }

  Widget _removeBgControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Remove background (make transparent)',
              style: TextStyle(fontSize: 13)),
          value: _removeBg,
          onChanged: (bool v) => setState(() => _removeBg = v),
        ),
        if (_removeBg)
          _slider('Removal tolerance', _bgTolerance.toDouble(), 0, 120, (double v) {
            setState(() => _bgTolerance = v.round());
          }),
      ],
    );
  }

  Widget _slider(String label, double value, double min, double max,
      ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('$label: ${value.round()}', style: const TextStyle(fontSize: 12)),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          // Integer steps so dragging snaps and ←/→/↑/↓ (when focused) nudge by 1.
          divisions: (max - min).round().clamp(1, 1000),
          label: '${value.round()}',
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _intField(String label, int value, ValueChanged<int> onChanged) {
    return TextFormField(
      key: ValueKey<String>('$label$value'),
      initialValue: value.toString(),
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, isDense: true),
      onFieldSubmitted: (String s) {
        final int? v = int.tryParse(s.trim());
        if (v != null) onChanged(v);
      },
    );
  }
}
