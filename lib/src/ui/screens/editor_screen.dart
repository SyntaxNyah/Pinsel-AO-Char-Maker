import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ao_constants.dart';
import '../../core/emote.dart';
import '../app_state.dart';
import '../widgets/zoom_canvas.dart';

/// Emotes screen.
///
/// Performance: typing in a field updates the emote **model + its own
/// controller only** — it does NOT call `notifyListeners` per keystroke, so the
/// big sprite preview (a 1024px decode/encode) no longer re-bakes on every
/// character you type. The edit is committed (undo snapshot + list refresh) when
/// the field loses focus or you submit it. The preview is a cached, stateful
/// widget keyed on the sprite path + [AppState.spriteRevision], so it only
/// reloads when the actual sprite changes.
class EditorScreen extends StatelessWidget {
  const EditorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: <Widget>[
        SizedBox(width: 280, child: _EmoteList()),
        VerticalDivider(width: 1),
        Expanded(child: _DetailPane()),
      ],
    );
  }
}

/// The emote list. Supports **multi-select** (tick the boxes → delete many at
/// once) and **auto-scrolls** to the selected emote when you move with the
/// keyboard (Ctrl+↑/↓), so navigating a 100-emote cast isn't blind.
class _EmoteList extends StatefulWidget {
  const _EmoteList();

  @override
  State<_EmoteList> createState() => _EmoteListState();
}

class _EmoteListState extends State<_EmoteList> {
  /// Indices ticked for multi-select (transient: cleared after a bulk delete).
  final Set<int> _selected = <int>{};
  final ScrollController _scroll = ScrollController();
  int _lastSelected = -1;

  /// Approximate dense-row height, only used to scroll a keyboard-selected
  /// (possibly off-screen) emote into view.
  static const double _rowExtent = 56;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toggle(int i) => setState(() {
        if (!_selected.remove(i)) _selected.add(i);
      });

  void _scrollToSelected(int i) {
    if (!_scroll.hasClients || i < 0) return;
    final ScrollPosition pos = _scroll.position;
    final double rowTop = i * _rowExtent;
    // Only scroll when the row is off-screen, so tapping a visible row (which
    // also changes the selection) doesn't make the list jump.
    if (rowTop >= pos.pixels &&
        rowTop + _rowExtent <= pos.pixels + pos.viewportDimension) {
      return;
    }
    _scroll.animateTo(
      (rowTop - 96).clamp(0.0, pos.maxScrollExtent), // a little context above
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (BuildContext context, AppState app, _) {
        final List<Emote> emotes = app.character?.emotes ?? <Emote>[];
        // Drop any ticked indices that no longer exist (after a delete/reset).
        _selected.removeWhere((int i) => i >= emotes.length);
        // Auto-scroll to the selected emote when it changes externally
        // (keyboard nav). Scheduled post-frame — can't scroll during build.
        if (app.selectedEmote != _lastSelected) {
          _lastSelected = app.selectedEmote;
          final int target = app.selectedEmote;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _scrollToSelected(target);
          });
        }
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: <Widget>[
                  const Text('Emotes'),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Undo',
                    onPressed: app.canUndo ? app.undo : null,
                    icon: const Icon(Icons.undo_rounded),
                  ),
                  IconButton(
                    tooltip: 'Redo',
                    onPressed: app.canRedo ? app.redo : null,
                    icon: const Icon(Icons.redo_rounded),
                  ),
                  IconButton(
                    tooltip: 'Add emote',
                    onPressed: app.addEmote,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ),
            if (emotes.isNotEmpty) _selectionBar(app, emotes.length),
            Expanded(
              child: ReorderableListView.builder(
                scrollController: _scroll,
                itemCount: emotes.length,
                onReorder: (int from, int to) {
                  // Dragging one of several ticked rows moves the WHOLE selection
                  // as a block (so you can reorder multiple at once); otherwise
                  // it's a normal single-row move.
                  if (_selected.length > 1 && _selected.contains(from)) {
                    final int count =
                        _selected.where((int i) => i < emotes.length).length;
                    final int first = app.moveEmotes(_selected, to);
                    if (first >= 0) {
                      setState(() {
                        _selected
                          ..clear()
                          ..addAll(
                              List<int>.generate(count, (int k) => first + k));
                      });
                    }
                  } else {
                    app.moveEmote(from, to > from ? to - 1 : to);
                  }
                },
                itemBuilder: (BuildContext context, int i) {
                  final Emote e = emotes[i];
                  return ListTile(
                    key: ValueKey<int>(i),
                    selected: i == app.selectedEmote,
                    dense: true,
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Checkbox(
                          value: _selected.contains(i),
                          visualDensity: VisualDensity.compact,
                          onChanged: (_) => _toggle(i),
                        ),
                        CircleAvatar(radius: 12, child: Text('${i + 1}')),
                      ],
                    ),
                    title: Text(e.comment,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(e.sprite,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: 'Delete',
                      onPressed: () => app.deleteEmote(i),
                    ),
                    onTap: () => app.selectEmote(i),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// A compact bar to select-all / clear / delete the ticked emotes. Always
  /// shown (with a hint) so multi-select is discoverable; the actions light up
  /// once something is ticked.
  Widget _selectionBar(AppState app, int count) {
    final bool any = _selected.isNotEmpty;
    return Material(
      color: any ? Theme.of(context).colorScheme.surfaceContainerHighest : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                any ? '${_selected.length} selected' : 'Tick to select',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: _selected.length == count
                  ? () => setState(_selected.clear)
                  : () => setState(() {
                        _selected
                          ..clear()
                          ..addAll(List<int>.generate(count, (int i) => i));
                      }),
              child: Text(_selected.length == count ? 'None' : 'All'),
            ),
            TextButton.icon(
              onPressed: any
                  ? () {
                      app.deleteEmotes(_selected);
                      setState(_selected.clear);
                    }
                  : null,
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: Text('Delete${any ? ' (${_selected.length})' : ''}'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailPane extends StatelessWidget {
  const _DetailPane();

  @override
  Widget build(BuildContext context) {
    // Rebuild only when the selection or the sprite pixels/paths change — NOT on
    // every keystroke (typing doesn't notify) and NOT on dropdown commits.
    return Selector<AppState, (int, int)>(
      selector: (_, AppState a) => (a.selectedEmote, a.spriteRevision),
      builder: (BuildContext context, (int, int) _, __) {
        final AppState app = context.read<AppState>();
        final Emote? e = app.current;
        if (e == null) {
          return const Center(child: Text('Select an emote to edit it.'));
        }
        final String? rel = app.spriteRelFor(e);
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: _SpritePreview(rel: rel, revision: app.spriteRevision),
              ),
              const SizedBox(height: 8),
              _Fields(key: ValueKey<int>(app.selectedEmote), app: app, emote: e),
            ],
          ),
        );
      },
    );
  }
}

/// Caches the decoded/encoded sprite preview; only reloads when [rel] or
/// [revision] changes. Decoupled from text editing entirely.
class _SpritePreview extends StatefulWidget {
  const _SpritePreview({required this.rel, required this.revision});
  final String? rel;
  final int revision;

  @override
  State<_SpritePreview> createState() => _SpritePreviewState();
}

class _SpritePreviewState extends State<_SpritePreview> {
  Uint8List? _bytes;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_SpritePreview old) {
    super.didUpdateWidget(old);
    if (old.rel != widget.rel || old.revision != widget.revision) _load();
  }

  Future<void> _load() async {
    final String? rel = widget.rel;
    if (rel == null) {
      if (mounted) setState(() => _bytes = null);
      return;
    }
    _loading = true;
    final Uint8List? b = await context.read<AppState>().previewSprite(rel);
    _loading = false;
    if (mounted) setState(() => _bytes = b);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rel == null) {
      return const Center(child: Text('No sprite file found for this emote.'));
    }
    if (_bytes == null && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ZoomCanvas(bytes: _bytes);
  }
}

/// The editable fields. Owns its [TextEditingController]s so typing never goes
/// through [AppState.notifyListeners]; the change is written to the [emote]
/// model live (so nothing is lost) and *committed* (undo snapshot + list
/// refresh) when the field group loses focus or a field is submitted.
class _Fields extends StatefulWidget {
  const _Fields({super.key, required this.app, required this.emote});
  final AppState app;
  final Emote emote;

  @override
  State<_Fields> createState() => _FieldsState();
}

class _FieldsState extends State<_Fields> {
  late final TextEditingController _name =
      TextEditingController(text: widget.emote.comment);
  late final TextEditingController _sprite =
      TextEditingController(text: widget.emote.sprite);
  late final TextEditingController _preanim =
      TextEditingController(text: widget.emote.preanim);
  late final TextEditingController _sound =
      TextEditingController(text: widget.emote.soundName ?? '');
  late final TextEditingController _delay = TextEditingController(
      text: '${widget.emote.soundDelayTicks ?? 0}');

  bool _dirty = false;

  @override
  void dispose() {
    _name.dispose();
    _sprite.dispose();
    _preanim.dispose();
    _sound.dispose();
    _delay.dispose();
    super.dispose();
  }

  void _commit() {
    if (!_dirty) return;
    _dirty = false;
    widget.app.commitEdit();
  }

  @override
  Widget build(BuildContext context) {
    final Emote e = widget.emote;
    // Commit when focus leaves the whole field group (e.g. click the preview or
    // another emote), not when moving between fields inside it.
    return Focus(
      onFocusChange: (bool hasFocus) {
        if (!hasFocus) _commit();
      },
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: <Widget>[
          _text('Name', _name, (String v) => e.comment = v, width: 200),
          _text('Sprite', _sprite, (String v) => e.sprite = v, width: 220),
          _text('Preanim', _preanim, (String v) => e.preanim = v, width: 160),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<EmoteModifier>(
              decoration: const InputDecoration(labelText: 'Modifier'),
              value: e.modifier,
              items: <DropdownMenuItem<EmoteModifier>>[
                for (final EmoteModifier m in EmoteModifier.values)
                  DropdownMenuItem<EmoteModifier>(value: m, child: Text(m.label)),
              ],
              onChanged: (EmoteModifier? m) {
                if (m == null) return;
                setState(() => e.modifier = m);
                widget.app.commitEdit();
              },
            ),
          ),
          SizedBox(
            width: 240,
            child: DropdownButtonFormField<DeskModifier>(
              decoration: const InputDecoration(labelText: 'Desk'),
              value: e.deskMod ?? DeskModifier.show,
              items: <DropdownMenuItem<DeskModifier>>[
                for (final DeskModifier d in DeskModifier.values)
                  DropdownMenuItem<DeskModifier>(value: d, child: Text(d.label)),
              ],
              onChanged: (DeskModifier? d) {
                setState(() => e.deskMod = d);
                widget.app.commitEdit();
              },
            ),
          ),
          _text('Sound (SoundN)', _sound,
              (String v) => e.soundName = v.isEmpty ? null : v, width: 200),
          _text('Delay ticks', _delay,
              (String v) => e.soundDelayTicks = int.tryParse(v), width: 110),
          Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Checkbox(
              value: e.soundLoop ?? false,
              onChanged: (bool? v) {
                setState(() => e.soundLoop = v);
                widget.app.commitEdit();
              },
            ),
            const Text('Loop sound'),
          ]),
        ],
      ),
    );
  }

  Widget _text(String label, TextEditingController controller,
          ValueChanged<String> apply, {double width = 180}) =>
      SizedBox(
        width: width,
        child: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: label),
          onChanged: (String v) {
            apply(v); // write to the model live; no notify → no rebuild/re-bake
            _dirty = true;
          },
          onSubmitted: (_) => _commit(),
        ),
      );
}
