import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';

import '../../platform/folder_picker.dart';
import '../../theme/ao2_theme.dart';
import '../../theme/ao2_theme_defaults.dart';
import '../app_state.dart';

/// **AO2 Theme Maker** — design a complete Attorney Online 2 / webAO client
/// theme: every widget position/size, every colour, every font, every image
/// (PNG/GIF/WebP), sounds and Qt stylesheets — then export a `.zip` ready to
/// drop into AO2's `base/themes/`. Import a real theme as a starting point,
/// or roll a random one.
class ThemeMakerScreen extends StatefulWidget {
  const ThemeMakerScreen({super.key});

  @override
  State<ThemeMakerScreen> createState() => _ThemeMakerScreenState();
}

class _ThemeMakerScreenState extends State<ThemeMakerScreen> {
  /// Bumped on import/new/randomise so field widgets pick up fresh values.
  int _rev = 0;
  bool _editLobby = false;
  bool _showArt = true;
  String _filter = '';

  /// Arrange-canvas snap grid in theme px (0 = off). Drags/resizes snap to it.
  int _gridSize = 0;

  void _bump() => setState(() => _rev++);

  Future<void> _import() async {
    final PickedFolder? picked = await pickFolderFiles();
    if (picked == null || picked.files.isEmpty || !mounted) return;
    await context.read<AppState>().importThemeFiles(<String, Uint8List>{
      for (final PickedFolderFile f in picked.files) f.name: f.bytes,
    });
    if (mounted) _bump();
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final Ao2Theme? theme = app.theme;
    if (theme == null) return _empty(app);

    return DefaultTabController(
      length: 7,
      child: Column(
        children: <Widget>[
          _header(app, theme),
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: <Widget>[
              Tab(text: 'Layout'),
              Tab(text: 'Colours'),
              Tab(text: 'Fonts'),
              Tab(text: 'Images'),
              Tab(text: 'Style'),
              Tab(text: 'Arrange'),
              Tab(text: 'Preview'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                _layoutTab(app, theme),
                _coloursTab(app, theme),
                _fontsTab(app, theme),
                _imagesTab(app, theme),
                _styleTab(app, theme),
                _previewTab(app, theme),
                _clientPreviewTab(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header + empty state
  // ---------------------------------------------------------------------------

  Widget _empty(AppState app) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.brush_rounded, size: 48, color: Colors.white24),
          const SizedBox(height: 12),
          const Text('Design an Attorney Online 2 theme.',
              style: TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          const Text('Import an existing theme to edit, or start a fresh one.',
              style: TextStyle(color: Colors.white60)),
          const SizedBox(height: 16),
          Wrap(spacing: 12, children: <Widget>[
            FilledButton.icon(
              onPressed: _import,
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Import theme folder'),
            ),
            FilledButton.tonalIcon(
              onPressed: () {
                app.newTheme();
                _bump();
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('New theme'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _header(AppState app, Ao2Theme theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 220,
            child: TextFormField(
              key: ValueKey<String>('themeName$_rev'),
              initialValue: theme.name,
              decoration: const InputDecoration(
                  labelText: 'Theme name', isDense: true),
              onFieldSubmitted: (String s) {
                theme.name = s.trim().isEmpty ? 'theme' : s.trim();
                app.touchTheme();
              },
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => _sizeDialog(app, theme),
            icon: const Icon(Icons.aspect_ratio_rounded, size: 18),
            label: Text('${theme.width}×${theme.height}'),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _import,
            icon: const Icon(Icons.folder_open_rounded, size: 18),
            label: const Text('Import'),
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            onPressed: () => _randomDialog(app),
            icon: const Icon(Icons.casino_rounded, size: 18),
            label: const Text('Random'),
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            onPressed: () => app.exportTheme(),
            icon: const Icon(Icons.archive_rounded, size: 18),
            label: const Text('Export .zip'),
          ),
        ],
      ),
    );
  }

  Future<void> _randomDialog(AppState app) async {
    bool colors = true, fonts = true, jitter = false;
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setD) => AlertDialog(
          title: const Text('Random theme'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CheckboxListTile(
                value: colors,
                title: const Text('Randomise colours'),
                onChanged: (bool? v) => setD(() => colors = v ?? true),
              ),
              CheckboxListTile(
                value: fonts,
                title: const Text('Randomise fonts'),
                onChanged: (bool? v) => setD(() => fonts = v ?? true),
              ),
              CheckboxListTile(
                value: jitter,
                title: const Text('Nudge positions (±5px)'),
                onChanged: (bool? v) => setD(() => jitter = v ?? false),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Roll')),
          ],
        ),
      ),
    );
    if (go != true || !mounted) return;
    app.randomizeTheme(colors: colors, fonts: fonts, jitter: jitter);
    _bump();
  }

  // ---------------------------------------------------------------------------
  // Layout tab
  // ---------------------------------------------------------------------------

  Widget _layoutTab(AppState app, Ao2Theme theme) {
    final ThemeDesign d = _editLobby ? theme.lobby : theme.courtroom;
    final List<ThemeElement> elems = <ThemeElement>[
      for (final ThemeElement e in d.elements)
        if (_filter.isEmpty || e.name.toLowerCase().contains(_filter)) e,
    ];
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: <Widget>[
            _courtroomLobbyToggle(),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 18),
                    hintText: 'Filter widgets…'),
                onChanged: (String s) => setState(() => _filter = s.trim().toLowerCase()),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: () => _addElement(app, d),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
          ]),
        ),
        _modeCaption(),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            itemCount: elems.length,
            itemBuilder: (BuildContext context, int i) => _elementRow(app, d, elems[i]),
          ),
        ),
      ],
    );
  }

  Widget _elementRow(AppState app, ThemeDesign d, ThemeElement e) {
    Widget numField(String label, int value, ValueChanged<int> set) => SizedBox(
          width: 60,
          child: TextFormField(
            key: ValueKey<String>('${e.name}-$label-$value-$_rev'),
            initialValue: value.toString(),
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: label, isDense: true),
            onFieldSubmitted: (String s) {
              final int? v = int.tryParse(s.trim());
              if (v != null) {
                set(v);
                app.touchTheme();
              }
            },
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(e.name,
                style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 6),
          numField('X', e.x, (int v) => e.x = v),
          const SizedBox(width: 4),
          numField('Y', e.y, (int v) => e.y = v),
          const SizedBox(width: 4),
          numField('W', e.w, (int v) => e.w = v),
          const SizedBox(width: 4),
          numField('H', e.h, (int v) => e.h = v),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close, size: 16),
            onPressed: () {
              d.elements.remove(e);
              app.touchTheme();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _addElement(AppState app, ThemeDesign d) async {
    final String? name =
        await _pickKnown('Add a widget', <({String name, String hint})>[
      for (final ThemeWidgetDef w in kCourtroomWidgets)
        (name: w.name, hint: '${w.category} · ${w.hint}'),
    ]);
    if (name == null || name.isEmpty) return;
    ThemeWidgetDef? def;
    for (final ThemeWidgetDef w in kCourtroomWidgets) {
      if (w.name == name) {
        def = w;
        break;
      }
    }
    d.upsertElement(name, 20, 20, def?.w ?? 100, def?.h ?? 30);
    app.touchTheme();
    _bump();
  }

  // ---------------------------------------------------------------------------
  // Colours tab
  // ---------------------------------------------------------------------------

  Widget _coloursTab(AppState app, Ao2Theme theme) {
    final List<ThemeColor> all = <ThemeColor>[
      ...theme.courtroom.colors,
      ...theme.lobby.colors,
    ];
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: <Widget>[
            Expanded(
              child: Text('${all.length} colours',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _addColour(app, theme.courtroom),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add colour'),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: <Widget>[
              for (final ThemeColor c in all) _colourRow(app, theme, c),
            ],
          ),
        ),
      ],
    );
  }

  Widget _colourRow(AppState app, Ao2Theme theme, ThemeColor c) {
    return ListTile(
      dense: true,
      leading: GestureDetector(
        onTap: () async {
          final int? argb = await _pickColour(c.argb);
          if (argb != null) {
            c.argb = argb;
            app.touchTheme();
          }
        },
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Color(c.argb),
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
      title: Text(c.name, style: const TextStyle(fontSize: 13)),
      subtitle: Text('${c.r}, ${c.g}, ${c.b}', style: const TextStyle(fontSize: 11)),
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 16),
        onPressed: () {
          theme.courtroom.colors.remove(c);
          theme.lobby.colors.remove(c);
          app.touchTheme();
        },
      ),
    );
  }

  Future<void> _addColour(AppState app, ThemeDesign d) async {
    final String? name =
        await _pickKnown('Add a colour', <({String name, String hint})>[
      for (final String k in kThemeColorKeys) (name: k, hint: ''),
    ]);
    if (name == null || name.isEmpty) return;
    d.upsertColor(name, 255, 255, 255);
    app.touchTheme();
    _bump();
  }

  // ---------------------------------------------------------------------------
  // Fonts tab
  // ---------------------------------------------------------------------------

  Widget _fontsTab(AppState app, Ao2Theme theme) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: <Widget>[
            Expanded(
              child: Text('${theme.fonts.length} fonts',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _addFont(app, theme),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add font'),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: <Widget>[
              for (final ThemeFont f in theme.fonts) _fontRow(app, theme, f),
            ],
          ),
        ),
      ],
    );
  }

  Widget _fontRow(AppState app, Ao2Theme theme, ThemeFont f) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 120,
              child: Text(f.name,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
            ),
            SizedBox(
              width: 56,
              child: TextFormField(
                key: ValueKey<String>('fs-${f.name}-${f.size}-$_rev'),
                initialValue: f.size.toString(),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Size', isDense: true),
                onFieldSubmitted: (String s) {
                  final int? v = int.tryParse(s.trim());
                  if (v != null) {
                    f.size = v;
                    app.touchTheme();
                  }
                },
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextFormField(
                key: ValueKey<String>('ff-${f.name}-$_rev'),
                initialValue: f.font,
                decoration: const InputDecoration(labelText: 'Font family', isDense: true),
                onFieldSubmitted: (String s) {
                  f.font = s.trim();
                  app.touchTheme();
                },
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () async {
                final int? argb = await _pickColour(f.argb);
                if (argb != null) {
                  f.argb = argb;
                  app.touchTheme();
                }
              },
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Color(f.argb),
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
            _flag('B', f.bold, (bool v) {
              f.bold = v;
              app.touchTheme();
            }),
            _flag('Aa', f.sharp, (bool v) {
              f.sharp = v;
              app.touchTheme();
            }, tip: 'Sharp (no anti-alias)'),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: () {
                theme.fonts.remove(f);
                app.touchTheme();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _flag(String label, bool value, ValueChanged<bool> onChanged, {String? tip}) {
    final Widget chip = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: value,
        visualDensity: VisualDensity.compact,
        onSelected: onChanged,
      ),
    );
    return tip == null ? chip : Tooltip(message: tip, child: chip);
  }

  Future<void> _addFont(AppState app, Ao2Theme theme) async {
    final String? name =
        await _pickKnown('Add a font', <({String name, String hint})>[
      for (final String k in kFontWidgets) (name: k, hint: ''),
    ]);
    if (name == null || name.isEmpty) return;
    theme.fonts.add(ThemeFont(name, size: 12, font: 'Sans'));
    app.touchTheme();
    _bump();
  }

  // ---------------------------------------------------------------------------
  // Images tab
  // ---------------------------------------------------------------------------

  String _baseOf(String fileName) {
    final int dot = fileName.lastIndexOf('.');
    return dot < 0 ? fileName : fileName.substring(0, dot);
  }

  ThemeImage? _imageForBase(Ao2Theme theme, String base) {
    for (final ThemeImage im in theme.images.values) {
      if (_baseOf(im.fileName) == base) return im;
    }
    return null;
  }

  Widget _imagesTab(AppState app, Ao2Theme theme) {
    // Custom (imported) images not in the catalogue.
    final Set<String> known = <String>{
      for (final ThemeImageSlot s in kThemeImageSlots) _baseOf(s.fileName)
    };
    final List<ThemeImage> extra = <ThemeImage>[
      for (final ThemeImage im in theme.images.values)
        if (!known.contains(_baseOf(im.fileName))) im,
    ];
    return ListView(
      padding: const EdgeInsets.all(10),
      children: <Widget>[
        Row(children: <Widget>[
          Expanded(
            child: Text(
              'Replace any asset with your own PNG / GIF / WebP. The client picks '
              'webp → apng → gif → png by name.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: () => _addCustomImage(app),
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: const Text('Add custom'),
          ),
        ]),
        const SizedBox(height: 8),
        for (final String cat in kThemeImageCategories) ...<Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(cat, style: Theme.of(context).textTheme.titleSmall),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final ThemeImageSlot s in kThemeImageSlots)
                if (s.category == cat) _imageSlot(app, theme, s.fileName, s.hint),
            ],
          ),
        ],
        if (extra.isNotEmpty) ...<Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 8, bottom: 4),
            child: Text('Imported / custom', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final ThemeImage im in extra) _imageSlot(app, theme, im.fileName, ''),
            ],
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _imageSlot(AppState app, Ao2Theme theme, String fileName, String hint) {
    final ThemeImage? im = _imageForBase(theme, _baseOf(fileName));
    return SizedBox(
      width: 120,
      child: Column(
        children: <Widget>[
          GestureDetector(
            onTap: () => _replaceImage(app, theme, fileName),
            child: Container(
              width: 120,
              height: 90,
              decoration: BoxDecoration(
                color: Colors.black26,
                border: Border.all(
                    color: im?.bytes != null ? Colors.tealAccent : Colors.white24),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: im?.bytes != null
                  ? Image.memory(im!.bytes!, fit: BoxFit.contain, gaplessPlayback: true)
                  : const Center(
                      child: Icon(Icons.add_photo_alternate_outlined,
                          color: Colors.white38)),
            ),
          ),
          const SizedBox(height: 2),
          Text(im?.fileName ?? fileName,
              style: const TextStyle(fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          if (hint.isNotEmpty)
            Text(hint,
                style: const TextStyle(fontSize: 9, color: Colors.white54),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          if (im?.bytes != null)
            TextButton(
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
              onPressed: () {
                theme.images.removeWhere(
                    (String k, ThemeImage v) => _baseOf(k) == _baseOf(fileName));
                app.touchTheme();
              },
              child: const Text('Clear', style: TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
  }

  Future<void> _replaceImage(AppState app, Ao2Theme theme, String defaultName) async {
    final FilePickerResult? res = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const <String>['png', 'webp', 'gif', 'apng', 'jpg', 'jpeg', 'bmp'],
    );
    if (res == null || res.files.isEmpty || res.files.first.bytes == null) return;
    final PlatformFile f = res.files.first;
    final String ext = (f.extension ?? 'png').toLowerCase();
    final String base = _baseOf(defaultName);
    final String newName = '$base.$ext';
    // Drop any other-extension variant of the same asset so the client can't
    // pick a stale one.
    theme.images.removeWhere((String k, ThemeImage v) => _baseOf(k) == base);
    app.setThemeImage(newName, f.bytes, ext: ext);
  }

  Future<void> _addCustomImage(AppState app) async {
    final String? name = await _promptName('Asset file name (e.g. background.png)');
    if (name == null || name.isEmpty || !mounted) return;
    await _replaceImage(app, app.theme!, name.contains('.') ? name : '$name.png');
  }

  // ---------------------------------------------------------------------------
  // Style tab (CSS + sounds)
  // ---------------------------------------------------------------------------

  Widget _styleTab(AppState app, Ao2Theme theme) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        Text('Courtroom stylesheet (Qt CSS)',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        TextFormField(
          key: ValueKey<String>('css$_rev'),
          initialValue: theme.courtroomCss,
          maxLines: 12,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: const InputDecoration(
              border: OutlineInputBorder(), hintText: 'QWidget { color: white; } …'),
          onChanged: (String s) => theme.courtroomCss = s,
        ),
        const SizedBox(height: 16),
        Text('Lobby stylesheet', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        TextFormField(
          key: ValueKey<String>('lcss$_rev'),
          initialValue: theme.lobbyCss,
          maxLines: 6,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onChanged: (String s) => theme.lobbyCss = s,
        ),
        const Divider(height: 28),
        Row(children: <Widget>[
          Expanded(
            child: Text('Sounds (${theme.sounds.length})',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          FilledButton.tonalIcon(
            onPressed: () async {
              final String? name = await _promptName('Sound key (e.g. objection)');
              if (name == null || name.isEmpty) return;
              theme.sounds.add(ThemeSound(name, ''));
              app.touchTheme();
              _bump();
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add'),
          ),
        ]),
        for (final ThemeSound snd in theme.sounds)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: <Widget>[
              SizedBox(width: 130, child: Text(snd.name, style: const TextStyle(fontSize: 12))),
              Expanded(
                child: TextFormField(
                  key: ValueKey<String>('snd-${snd.name}-$_rev'),
                  initialValue: snd.path,
                  decoration: const InputDecoration(isDense: true, hintText: 'sfx/objection.opus'),
                  onFieldSubmitted: (String s) {
                    snd.path = s.trim();
                    app.touchTheme();
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () {
                  theme.sounds.remove(snd);
                  app.touchTheme();
                },
              ),
            ]),
          ),
        const Divider(height: 28),
        Row(children: <Widget>[
          Expanded(
            child: Text('Design options (${theme.courtroom.scalars.length})',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          FilledButton.tonalIcon(
            onPressed: () => _addScalar(app, theme),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add'),
          ),
        ]),
        const Text(
          'Alignment, spacing and flags — every non-position design key '
          '(e.g. showname_align, emote_button_spacing, music_list_animated).',
          style: TextStyle(fontSize: 12, color: Colors.white60),
        ),
        for (final MapEntry<String, String> sc in theme.courtroom.scalars)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: <Widget>[
              SizedBox(
                  width: 170,
                  child: Text(sc.key, style: const TextStyle(fontSize: 12))),
              Expanded(
                child: TextFormField(
                  key: ValueKey<String>('sc-${sc.key}-${sc.value}-$_rev'),
                  initialValue: sc.value,
                  decoration: const InputDecoration(isDense: true),
                  onFieldSubmitted: (String s) {
                    theme.courtroom.setScalar(sc.key, s.trim());
                    app.touchTheme();
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () {
                  theme.courtroom.scalars
                      .removeWhere((MapEntry<String, String> x) => x.key == sc.key);
                  app.touchTheme();
                },
              ),
            ]),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _addScalar(AppState app, Ao2Theme theme) async {
    final String? name =
        await _pickKnown('Add a design option', <({String name, String hint})>[
      for (final ({String key, String hint}) s in kThemeScalars)
        (name: s.key, hint: s.hint),
    ]);
    if (name == null || name.isEmpty) return;
    theme.courtroom.setScalar(name, '');
    app.touchTheme();
    _bump();
  }

  // ---------------------------------------------------------------------------
  // Preview tab (schematic layout)
  // ---------------------------------------------------------------------------

  Widget _previewTab(AppState app, Ao2Theme theme) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Every box is labelled — hover for what it does. Drag to move, '
                  'corner to resize, arrows to nudge. Use Grid to snap.',
                  style: TextStyle(fontSize: 12, color: Colors.white60),
                ),
              ),
              Tooltip(
                message: 'Snap dragging/resizing to a pixel grid (great for '
                    'pixel-perfect alignment)',
                child: DropdownButton<int>(
                  value: _gridSize,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  items: const <DropdownMenuItem<int>>[
                    DropdownMenuItem<int>(value: 0, child: Text('Grid: off')),
                    DropdownMenuItem<int>(value: 5, child: Text('Grid: 5px')),
                    DropdownMenuItem<int>(value: 10, child: Text('Grid: 10px')),
                    DropdownMenuItem<int>(value: 20, child: Text('Grid: 20px')),
                    DropdownMenuItem<int>(value: 25, child: Text('Grid: 25px')),
                    DropdownMenuItem<int>(value: 50, child: Text('Grid: 50px')),
                  ],
                  onChanged: (int? v) => setState(() => _gridSize = v ?? 0),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Show each widget\'s real image instead of a coloured box',
                child: FilterChip(
                  label: const Text('Show art'),
                  selected: _showArt,
                  visualDensity: VisualDensity.compact,
                  onSelected: (bool v) => setState(() => _showArt = v),
                ),
              ),
              const SizedBox(width: 8),
              _courtroomLobbyToggle(),
              IconButton(
                tooltip: 'Rebind the nudge keys',
                icon: const Icon(Icons.keyboard_rounded),
                onPressed: () => _rebindDialog(app),
              ),
            ],
          ),
        ),
        _modeCaption(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _LayoutCanvas(
              key: ValueKey<String>('canvas-$_rev-$_editLobby-$_showArt'),
              design: _editLobby ? theme.lobby : theme.courtroom,
              theme: theme,
              showArt: _showArt,
              gridSize: _gridSize,
              keys: app.nudgeKeys,
              themeW: theme.width,
              themeH: theme.height,
              onCommit: app.touchTheme,
            ),
          ),
        ),
      ],
    );
  }

  /// Realistic "what it looks like in the client" preview tab.
  Widget _clientPreviewTab(Ao2Theme theme) {
    return Column(
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'Approximate real-client look — your theme\'s images at their '
            'positions with sample text in your fonts. The scene/character '
            'background comes from a background pack (shown here as a placeholder).',
            style: TextStyle(fontSize: 12, color: Colors.white60),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _ClientPreview(theme),
          ),
        ),
      ],
    );
  }

  Future<void> _sizeDialog(AppState app, Ao2Theme theme) async {
    final TextEditingController wCtl =
        TextEditingController(text: theme.width.toString());
    final TextEditingController hCtl =
        TextEditingController(text: theme.height.toString());
    bool scaleEls = true, scaleFonts = true;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setD) => AlertDialog(
          title: const Text('Theme size'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    for (final ({String label, int w, int h}) p in _sizePresets)
                      ActionChip(
                        label: Text(p.label, style: const TextStyle(fontSize: 11)),
                        onPressed: () => setD(() {
                          wCtl.text = p.w.toString();
                          hCtl.text = p.h.toString();
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: wCtl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Width', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: hCtl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Height', isDense: true),
                    ),
                  ),
                ]),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: scaleEls,
                  title: const Text('Scale all widgets to fit the new size'),
                  onChanged: (bool? v) => setD(() => scaleEls = v ?? true),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: scaleFonts && scaleEls,
                  title: const Text('Scale font sizes too'),
                  onChanged: scaleEls
                      ? (bool? v) => setD(() => scaleFonts = v ?? true)
                      : null,
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Apply')),
          ],
        ),
      ),
    );
    final int w = int.tryParse(wCtl.text.trim()) ?? theme.width;
    final int h = int.tryParse(hCtl.text.trim()) ?? theme.height;
    wCtl.dispose();
    hCtl.dispose();
    if (ok != true || !mounted) return;
    theme.resize(w.clamp(64, 8000), h.clamp(64, 8000),
        scaleElements: scaleEls, scaleFonts: scaleFonts && scaleEls);
    app.touchTheme();
    _bump();
  }

  // ---------------------------------------------------------------------------
  // shared helpers
  // ---------------------------------------------------------------------------

  /// Courtroom vs Lobby selector — with icons + tooltips so it's clear each is a
  /// separate AO2 screen (trial vs server-select). Shared by Layout and Arrange.
  Widget _courtroomLobbyToggle() {
    return SegmentedButton<bool>(
      showSelectedIcon: false,
      segments: const <ButtonSegment<bool>>[
        ButtonSegment<bool>(
          value: false,
          label: Text('Courtroom'),
          icon: Icon(Icons.gavel_rounded),
          tooltip: 'The in-trial screen — viewport, chatbox, buttons, penalty '
              'bars (courtroom_design.ini)',
        ),
        ButtonSegment<bool>(
          value: true,
          label: Text('Lobby'),
          icon: Icon(Icons.dns_rounded),
          tooltip: 'The server-select screen you see before joining — server '
              'list, connect, player count (lobby_design.ini)',
        ),
      ],
      selected: <bool>{_editLobby},
      onSelectionChanged: (Set<bool> s) => setState(() => _editLobby = s.first),
    );
  }

  /// Rebind the Arrange nudge keys — click **Set** on a direction, then press the
  /// key you want. Stored on [AppState.nudgeKeys] so it sticks across navigation.
  Future<void> _rebindDialog(AppState app) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setD) {
          Widget row(String dir, String label) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: <Widget>[
                  SizedBox(width: 90, child: Text(label)),
                  Expanded(
                    child: Text(_keyLabel(app.nudgeKeys[dir]!),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      final LogicalKeyboardKey? nk = await _captureKey();
                      if (nk != null) {
                        app.setNudgeKey(dir, nk);
                        setD(() {});
                      }
                    },
                    child: const Text('Set'),
                  ),
                ]),
              );
          return AlertDialog(
            title: const Text('Arrange nudge keys'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  row('up', 'Move up'),
                  row('down', 'Move down'),
                  row('left', 'Move left'),
                  row('right', 'Move right'),
                  const SizedBox(height: 8),
                  const Text(
                    'Click Set, then press any key. While nudging, hold Shift for '
                    '10px steps and Ctrl/Alt to resize instead of move.',
                    style: TextStyle(fontSize: 11, color: Colors.white60),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  app.resetNudgeKeys();
                  setD(() {});
                },
                child: const Text('Reset to arrows'),
              ),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
            ],
          );
        },
      ),
    );
  }

  Future<LogicalKeyboardKey?> _captureKey() => showDialog<LogicalKeyboardKey>(
        context: context,
        builder: (BuildContext ctx) => const _KeyCaptureDialog(),
      );

  String _keyLabel(LogicalKeyboardKey key) {
    if (key.keyLabel.isNotEmpty) return key.keyLabel;
    return key.debugName ?? '0x${key.keyId.toRadixString(16)}';
  }

  /// One-line caption spelling out which screen is being edited.
  Widget _modeCaption() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      child: Text(
        _editLobby
            ? 'Editing the Lobby — the server browser you see before joining a game.'
            : 'Editing the Courtroom — the main in-trial screen (sprites, chatbox, buttons).',
        style: const TextStyle(fontSize: 11, color: Colors.white60),
      ),
    );
  }

  Future<int?> _pickColour(int argb) async {
    Color picked = Color(argb);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Pick a colour'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: picked,
            enableAlpha: false,
            paletteType: PaletteType.hueWheel,
            hexInputBar: true,
            labelTypes: const <ColorLabelType>[ColorLabelType.hex, ColorLabelType.rgb],
            onColorChanged: (Color c) => picked = c,
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
    if (ok != true) return null;
    return 0xFF000000 | (picked.red << 16) | (picked.green << 8) | picked.blue;
  }

  /// A searchable picker over a list of known names (with hints) that also lets
  /// you type a custom one — so you can add *any* widget/colour/font/option.
  Future<String?> _pickKnown(
      String title, List<({String name, String hint})> options) {
    final TextEditingController custom = TextEditingController();
    String search = '';
    return showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setD) {
          final List<({String name, String hint})> filtered =
              <({String name, String hint})>[
            for (final ({String name, String hint}) o in options)
              if (search.isEmpty ||
                  o.name.toLowerCase().contains(search) ||
                  o.hint.toLowerCase().contains(search))
                o,
          ];
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 440,
              height: 460,
              child: Column(
                children: <Widget>[
                  TextField(
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search, size: 18),
                        hintText: 'Search…',
                        isDense: true),
                    onChanged: (String s) =>
                        setD(() => search = s.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: custom,
                    decoration: const InputDecoration(
                        labelText: 'Or type a custom name', isDense: true),
                    onSubmitted: (String s) => Navigator.pop(ctx, s.trim()),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ListView(
                      children: <Widget>[
                        for (final ({String name, String hint}) o in filtered)
                          ListTile(
                            dense: true,
                            title: Text(o.name),
                            subtitle: o.hint.isEmpty
                                ? null
                                : Text(o.hint, style: const TextStyle(fontSize: 11)),
                            onTap: () => Navigator.pop(ctx, o.name),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, custom.text.trim()),
                  child: const Text('Add custom')),
            ],
          );
        },
      ),
    ).whenComplete(custom.dispose);
  }

  Future<String?> _promptName(String title) async {
    final TextEditingController c = TextEditingController();
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          onSubmitted: (String s) => Navigator.pop(ctx, s.trim()),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('OK')),
        ],
      ),
    );
    c.dispose();
    return result;
  }
}

/// Interactive layout canvas: every widget is a draggable box (drag to move,
/// drag the bottom-right corner to resize). Mutates the [ThemeElement]s live and
/// calls [onCommit] on release. Mouse deltas are divided by the fit scale so a
/// drag maps 1:1 to theme pixels regardless of zoom.
class _LayoutCanvas extends StatefulWidget {
  const _LayoutCanvas({
    super.key,
    required this.design,
    required this.theme,
    required this.showArt,
    required this.gridSize,
    required this.keys,
    required this.themeW,
    required this.themeH,
    required this.onCommit,
  });

  final ThemeDesign design;
  final Ao2Theme theme;
  final bool showArt;
  final int gridSize;
  final Map<String, LogicalKeyboardKey> keys;
  final int themeW;
  final int themeH;
  final VoidCallback onCommit;

  @override
  State<_LayoutCanvas> createState() => _LayoutCanvasState();
}

class _LayoutCanvasState extends State<_LayoutCanvas> {
  ThemeElement? _sel;
  bool _resizing = false;
  double _accX = 0, _accY = 0;
  int _startX = 0, _startY = 0, _startW = 0, _startH = 0;
  final FocusNode _focus = FocusNode(debugLabel: 'theme layout canvas');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Keyboard nudging of the selected widget: **arrows** move 1px, **Shift+arrow**
  /// 10px, **Ctrl/Alt+arrow** resizes instead of moving.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final ThemeElement? e = _sel;
    if (e == null) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    int dx = 0, dy = 0;
    final LogicalKeyboardKey k = event.logicalKey;
    if (k == widget.keys['left']) {
      dx = -1;
    } else if (k == widget.keys['right']) {
      dx = 1;
    } else if (k == widget.keys['up']) {
      dy = -1;
    } else if (k == widget.keys['down']) {
      dy = 1;
    } else {
      return KeyEventResult.ignored;
    }
    final int step = HardwareKeyboard.instance.isShiftPressed ? 10 : 1;
    dx *= step;
    dy *= step;
    final bool resize = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed;
    setState(() {
      if (resize) {
        e.w = (e.w + dx).clamp(1, 1 << 20);
        e.h = (e.h + dy).clamp(1, 1 << 20);
      } else {
        e.x += dx;
        e.y += dy;
      }
    });
    widget.onCommit();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final int tw = widget.themeW, th = widget.themeH;
    if (tw <= 0 || th <= 0) {
      return const Center(child: Text('Set the courtroom size first.'));
    }
    return Focus(
      focusNode: _focus,
      onKeyEvent: _handleKey,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints cons) {
          final double scale = (cons.maxWidth / tw).clamp(0.0, cons.maxHeight / th);
          if (scale <= 0) return const SizedBox.shrink();
          final double dw = tw * scale, dh = th * scale;
          return Center(
            child: GestureDetector(
              onTap: () {
                _focus.requestFocus();
                setState(() => _sel = null);
              },
              child: Container(
              width: dw,
              height: dh,
              decoration: BoxDecoration(
                color: const Color(0xFF15101F),
                border: Border.all(color: Colors.white24),
              ),
              child: Stack(
                children: <Widget>[
                  if (widget.gridSize > 0)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _GridPainter(widget.gridSize * scale),
                        ),
                      ),
                    ),
                  for (final ThemeElement e in widget.design.elements)
                    if (e.name != 'courtroom' && e.w > 0 && e.h > 0) _box(e, scale),
                ],
              ),
            ),
          ),
        );
      },
      ),
    );
  }

  Widget _box(ThemeElement e, double scale) {
    final bool selected = identical(e, _sel);
    final Color col = _hueFor(e.name);
    final double bw = (e.w * scale).clamp(6.0, double.infinity);
    final double bh = (e.h * scale).clamp(6.0, double.infinity);
    const double handle = 16;
    final bool resizable = bw >= 28 && bh >= 28;

    Widget? art;
    if (widget.showArt) {
      final String? base = _widgetImageBase[e.name];
      final ThemeImage? im =
          base == null ? null : _themeImageForBase(widget.theme, base);
      if (im?.bytes != null) {
        art = Image.memory(im!.bytes!, fit: BoxFit.fill, gaplessPlayback: true);
      }
    }

    final String hint = _widgetHint(e.name) ?? '';
    final String tip = hint.isEmpty ? e.name : '${e.name} — $hint';

    return Positioned(
      left: e.x * scale,
      top: e.y * scale,
      width: bw,
      height: bh,
      child: Tooltip(
        message: tip,
        waitDuration: const Duration(milliseconds: 350),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _focus.requestFocus();
            setState(() => _sel = e);
          },
          onPanStart: (DragStartDetails d) {
            _focus.requestFocus();
            _accX = 0;
            _accY = 0;
            _resizing = resizable &&
                d.localPosition.dx > bw - handle &&
                d.localPosition.dy > bh - handle;
            _startX = e.x;
            _startY = e.y;
            _startW = e.w;
            _startH = e.h;
            setState(() => _sel = e);
          },
          onPanUpdate: (DragUpdateDetails d) {
            _accX += d.delta.dx;
            _accY += d.delta.dy;
            setState(() {
              if (_resizing) {
                e.w = _snap(_startW + (_accX / scale).round()).clamp(1, 1 << 20);
                e.h = _snap(_startH + (_accY / scale).round()).clamp(1, 1 << 20);
              } else {
                e.x = _snap(_startX + (_accX / scale).round());
                e.y = _snap(_startY + (_accY / scale).round());
              }
            });
          },
          onPanEnd: (_) => widget.onCommit(),
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: selected
                            ? Colors.white
                            : (art != null ? Colors.white24 : col.withOpacity(0.9)),
                        width: selected ? 2 : 1),
                    color: art != null ? null : col.withOpacity(selected ? 0.22 : 0.12),
                  ),
                  child: art,
                ),
              ),
              // Always-visible widget label (readable over art or colour).
              Positioned(
                left: 0,
                top: 0,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: bw),
                  child: Container(
                    color: Colors.black.withOpacity(0.55),
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                    child: Text(e.name,
                        style: const TextStyle(fontSize: 8, color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
              if (selected && resizable)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: handle,
                    height: handle,
                    color: Colors.white,
                    child: const Icon(Icons.open_in_full, size: 10, color: Colors.black),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Snap a theme-pixel value to the canvas grid (no-op when the grid is off).
  int _snap(int v) {
    final int g = widget.gridSize;
    if (g <= 0) return v;
    return (v / g).round() * g;
  }

  Color _hueFor(String name) {
    final int h = name.hashCode % 360;
    return HSVColor.fromAHSV(1, (h < 0 ? h + 360 : h).toDouble(), 0.55, 0.95).toColor();
  }
}

/// Faint grid overlay for the Arrange canvas (lines every [step] display px).
class _GridPainter extends CustomPainter {
  _GridPainter(this.step);

  final double step;

  @override
  void paint(Canvas canvas, Size size) {
    if (step < 3) return; // too dense to be useful
    final Paint p = Paint()
      ..color = Colors.white.withOpacity(0.10)
      ..strokeWidth = 1;
    for (double x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.step != step;
}

/// A read-only **approximate-real-client** render: the theme's images drawn at
/// their courtroom positions, with sample text in the theme's fonts/colours, so
/// you can see what it'll look like before exporting. The scene/character
/// background is external (a background pack), shown as a placeholder.
class _ClientPreview extends StatelessWidget {
  const _ClientPreview(this.theme);

  final Ao2Theme theme;

  @override
  Widget build(BuildContext context) {
    final int tw = theme.width, th = theme.height;
    if (tw <= 0 || th <= 0) {
      return const Center(child: Text('Set the courtroom size first.'));
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints cons) {
        final double scale = (cons.maxWidth / tw).clamp(0.0, cons.maxHeight / th);
        if (scale <= 0) return const SizedBox.shrink();
        return Center(
          child: Container(
            width: tw * scale,
            height: th * scale,
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: const Color(0xFF0B0B12),
              border: Border.all(color: Colors.white24),
            ),
            child: Stack(
              children: <Widget>[
                // viewport first (it's the backdrop), then everything on top.
                for (final ThemeElement e in theme.courtroom.elements)
                  if (e.name == 'viewport' && e.w > 0 && e.h > 0)
                    ..._render(e, scale),
                for (final ThemeElement e in theme.courtroom.elements)
                  if (e.name != 'courtroom' && e.name != 'viewport' && e.w > 0 && e.h > 0)
                    ..._render(e, scale),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _render(ThemeElement e, double scale) {
    final Widget? content = _contentFor(e, scale);
    if (content == null) return const <Widget>[];
    return <Widget>[
      Positioned(
        left: e.x * scale,
        top: e.y * scale,
        width: e.w * scale,
        height: e.h * scale,
        child: content,
      ),
    ];
  }

  Widget? _contentFor(ThemeElement e, double scale) {
    if (e.name == 'viewport') {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xFF2A3550), Color(0xFF141A2A)],
          ),
        ),
        alignment: Alignment.center,
        child: Text('viewport\n(background pack)',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: (9 * scale).clamp(8.0, 18.0), color: Colors.white24)),
      );
    }
    final String? base = _widgetImageBase[e.name];
    if (base != null) {
      final ThemeImage? im = _themeImageForBase(theme, base);
      if (im?.bytes != null) {
        return Image.memory(im!.bytes!, fit: BoxFit.fill, gaplessPlayback: true);
      }
      return null; // known image widget but unset — draw nothing
    }
    final String? sample = _widgetSampleText[e.name];
    if (sample != null) {
      final ThemeFont? f = theme.font(e.name);
      final double fontSize = ((f?.size ?? 12) * scale).clamp(6.0, 64.0);
      return Container(
        alignment: Alignment.topLeft,
        child: Text(sample,
            style: TextStyle(
              fontFamily: (f?.font.isNotEmpty ?? false) ? f!.font : null,
              fontSize: fontSize,
              color: f != null ? Color(f.argb) : Colors.white,
              fontWeight: (f?.bold ?? false) ? FontWeight.bold : FontWeight.normal,
            ),
            maxLines: e.name == 'ic_chatlog' ? 6 : 2,
            overflow: TextOverflow.ellipsis),
      );
    }
    return null;
  }
}

String _baseOfFile(String fileName) {
  final int dot = fileName.lastIndexOf('.');
  return dot < 0 ? fileName : fileName.substring(0, dot);
}

/// Find a theme image by its base name (ignoring extension).
ThemeImage? _themeImageForBase(Ao2Theme theme, String base) {
  for (final ThemeImage im in theme.images.values) {
    if (_baseOfFile(im.fileName) == base) return im;
  }
  return null;
}

/// Friendly "what this widget does" description (from the widget catalogue), for
/// the Arrange-canvas box tooltips. Null for unknown/custom names.
String? _widgetHint(String name) {
  for (final ThemeWidgetDef w in kCourtroomWidgets) {
    if (w.name == name) return w.hint;
  }
  return null;
}

/// Common theme sizes (incl. 1080p/720p and the AOHD family).
const List<({String label, int w, int h})> _sizePresets =
    <({String label, int w, int h})>[
  (label: '1920×1080 (1080p)', w: 1920, h: 1080),
  (label: '1280×720 (720p)', w: 1280, h: 720),
  (label: '960×544', w: 960, h: 544),
  (label: '1021×705 (AOHD Mini)', w: 1021, h: 705),
  (label: '1363×705 (AOHD)', w: 1363, h: 705),
  (label: '1918×982 (AOHD Ultra)', w: 1918, h: 982),
  (label: '714×688 (FullChar)', w: 714, h: 688),
  (label: '256×192 (classic)', w: 256, h: 192),
];

/// Which image asset (by base name) stands in for a widget in the previews.
const Map<String, String> _widgetImageBase = <String, String>{
  'ao2_chatbox': 'chatbox',
  'hold_it': 'holdit',
  'objection': 'objection',
  'take_that': 'takethat',
  'custom_objection': 'custom',
  'witness_testimony': 'witnesstestimony',
  'cross_examination': 'crossexamination',
  'guilty': 'guilty',
  'not_guilty': 'notguilty',
  'defense_bar': 'defensebar10',
  'prosecution_bar': 'prosecutionbar10',
  'change_character': 'change_character',
  'call_mod': 'call_mod',
  'reload_theme': 'reload_theme',
  'settings': 'settings',
  'pair_button': 'pair_button',
  'mute_button': 'mute',
  'evidence_button': 'evidence_button',
  'evidence_background': 'evidence_background',
  'switch_area_music': 'switch_area_music',
  'emote_left': 'arrow_left',
  'emote_right': 'arrow_right',
  'chat_arrow': 'chat_arrow',
};

/// Sample strings shown for text widgets in the real-client preview.
const Map<String, String> _widgetSampleText = <String, String>{
  'showname': 'Phoenix',
  'message': "OBJECTION! That testimony doesn't add up.",
  'ic_chatlog': 'Phoenix: Hold it!\nEdgeworth: ...what?\nJudge: Order!',
  'music_name': '♪ Pursuit ~ Cornered',
  'ms_chatlog': '[Server] Welcome to the courtroom.',
  'server_chatlog': '[Server] Welcome to the courtroom.',
};

/// Captures the next key press (for rebinding the nudge keys). Cancels on
/// **Escape** and ignores bare modifier keys (Shift/Ctrl/Alt/Meta) so a
/// direction can't be bound to a modifier that already means something.
class _KeyCaptureDialog extends StatelessWidget {
  const _KeyCaptureDialog();

  // Not `const`: LogicalKeyboardKey overrides ==, which Dart forbids in a const
  // set (const_set_element_not_primitive_equality).
  static final Set<LogicalKeyboardKey> _modifiers = <LogicalKeyboardKey>{
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Press a key'),
      content: Focus(
        autofocus: true,
        onKeyEvent: (FocusNode node, KeyEvent event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.pop(context);
            return KeyEventResult.handled;
          }
          if (_modifiers.contains(event.logicalKey)) {
            return KeyEventResult.ignored;
          }
          Navigator.pop(context, event.logicalKey);
          return KeyEventResult.handled;
        },
        child: const SizedBox(
          height: 44,
          child: Center(child: Text('Press any key…  (Esc to cancel)')),
        ),
      ),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ],
    );
  }
}
