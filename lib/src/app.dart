import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'platform/folder_picker.dart';
import 'ui/app_state.dart';
import 'ui/credits.dart';
import 'ui/screens/animation_studio_screen.dart';
import 'ui/screens/bulk_screen.dart';
import 'ui/screens/button_studio_screen.dart';
import 'ui/screens/color_lab_screen.dart';
import 'ui/screens/edit_screen.dart';
import 'ui/screens/editor_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/ini_builder_screen.dart';
import 'ui/screens/mixer_screen.dart';
import 'ui/screens/paint_studio_screen.dart';
import 'ui/screens/plugins_screen.dart';
import 'ui/screens/sprite_ripper_screen.dart';
import 'ui/screens/theme_maker_screen.dart';
import 'ui/screens/zoom_studio_screen.dart';
import 'ui/theme.dart';
import 'ui/widgets/confirm_replace.dart';
import 'ui/widgets/key_capture.dart';

class PinselApp extends StatelessWidget {
  const PinselApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pinsel AO Char Maker',
      debugShowCheckedModeBanner: false,
      theme: PinselTheme.dark(),
      home: const HomeShell(),
    );
  }
}

const List<({IconData icon, String label})> _dests =
    <({IconData icon, String label})>[
  (icon: Icons.home_rounded, label: 'Home'),
  (icon: Icons.badge_rounded, label: 'Character'),
  (icon: Icons.grid_view_rounded, label: 'Emotes'),
  (icon: Icons.palette_rounded, label: 'Colour Lab'),
  (icon: Icons.movie_filter_rounded, label: 'Animate'),
  (icon: Icons.crop_square_rounded, label: 'Buttons'),
  (icon: Icons.content_cut_rounded, label: 'Edit'),
  (icon: Icons.auto_fix_high_rounded, label: 'Mixer'),
  (icon: Icons.dynamic_feed_rounded, label: 'Bulk'),
  (icon: Icons.extension_rounded, label: 'Plugins'),
  (icon: Icons.grid_on_rounded, label: 'Ripper'),
  (icon: Icons.brush_rounded, label: 'Theme'),
  (icon: Icons.format_paint_rounded, label: 'Paint'),
  (icon: Icons.zoom_in_rounded, label: 'Zoom'),
];

/// Screens that work without a loaded character: Home, Plugins, the Sprite
/// Sheet Ripper and the AO2 Theme Maker. Kept as named constants + a set so the
/// no-project guard doesn't go stale when destinations are reordered.
const int _pluginsIndex = 9;
const int _ripperIndex = 10;
const int _themeIndex = 11;
const Set<int> _projectFreeIndices = <int>{0, _pluginsIndex, _ripperIndex, _themeIndex};

/// Persistent navigation rail + status bar around the active screen.
///
/// Performance: only the *active* screen is built (not all eight via an
/// IndexedStack), and the shell/rail do NOT subscribe to [AppState], so a
/// slider drag no longer rebuilds the whole UI — only the screen that needs it.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  Widget _screenFor(int i) {
    switch (i) {
      case 1:
        return const IniBuilderScreen();
      case 2:
        return const EditorScreen();
      case 3:
        return const ColorLabScreen();
      case 4:
        return const AnimationStudioScreen();
      case 5:
        return const ButtonStudioScreen();
      case 6:
        return const EditScreen();
      case 7:
        return const MixerScreen();
      case 8:
        return const BulkScreen();
      case 9:
        return const PluginsScreen();
      case 10:
        return const SpriteRipperScreen();
      case 11:
        return const ThemeMakerScreen();
      case 12:
        return const PaintStudioScreen();
      case 13:
        return const ZoomStudioScreen();
      case 0:
      default:
        return const HomeScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState app = context.read<AppState>();
    return CallbackShortcuts(
      bindings: _bindings(context, app),
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            children: <Widget>[
              _NavRail(
                index: _index,
                onSelect: (int i) => setState(() => _index = i),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  children: <Widget>[
                    _TopBar(
                      onImport: () => _importFolder(context),
                      onShortcuts: () => _showShortcuts(context),
                      onAbout: () => showAboutCreditsDialog(context),
                      onReset: () => _resetProject(context),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      // Only rebuilds when project presence flips (rare), not on
                      // every AppState change.
                      child: Selector<AppState, bool>(
                        selector: (_, AppState a) => a.hasProject,
                        builder: (BuildContext context, bool hasProject, _) {
                          final bool needsProject =
                              !_projectFreeIndices.contains(_index) && !hasProject;
                          if (needsProject) {
                            return _NoProject(
                                onGoHome: () => setState(() => _index = 0));
                          }
                          return KeyedSubtree(
                            key: ValueKey<int>(_index),
                            child: _screenFor(_index),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: const _StatusBar(),
        ),
      ),
    );
  }

  /// All global keyboard shortcuts. Control **and** ⌘ (meta) are both bound so
  /// the same keys work on Windows/Linux and macOS.
  Map<ShortcutActivator, VoidCallback> _bindings(BuildContext context, AppState app) {
    final Map<ShortcutActivator, VoidCallback> m = <ShortcutActivator, VoidCallback>{};
    void bind(LogicalKeyboardKey key, VoidCallback cb, {bool shift = false}) {
      m[SingleActivator(key, control: true, shift: shift)] = cb;
      m[SingleActivator(key, meta: true, shift: shift)] = cb;
    }

    bind(LogicalKeyboardKey.keyZ, app.undo);
    bind(LogicalKeyboardKey.keyY, app.redo);
    bind(LogicalKeyboardKey.keyZ, app.redo, shift: true); // Ctrl+Shift+Z
    bind(LogicalKeyboardKey.keyS, () => app.exportZip());
    bind(
        LogicalKeyboardKey.keyS,
        () => app.exportFolder(
            confirmReplace: (String name) =>
                confirmReplaceFolder(context, name)),
        shift: true); // Ctrl+Shift+S
    bind(LogicalKeyboardKey.keyE, () => app.exportIni());
    bind(LogicalKeyboardKey.keyO, () => _importFolder(context));
    bind(LogicalKeyboardKey.keyN, () {
      if (app.hasProject) app.addEmote();
    });
    bind(LogicalKeyboardKey.arrowDown, () => _selectRelative(app, 1));
    bind(LogicalKeyboardKey.arrowUp, () => _selectRelative(app, -1));

    const List<LogicalKeyboardKey> digits = <LogicalKeyboardKey>[
      LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5, LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit8, LogicalKeyboardKey.digit9,
    ];
    for (int i = 0; i < digits.length && i < _dests.length; i++) {
      final int idx = i;
      bind(digits[i], () => setState(() => _index = idx));
    }
    m[const SingleActivator(LogicalKeyboardKey.f1)] = () => _showShortcuts(context);
    return m;
  }

  void _selectRelative(AppState app, int delta) {
    final int count = app.character?.emotes.length ?? 0;
    if (count == 0) return;
    app.selectEmote((app.selectedEmote + delta).clamp(0, count - 1));
  }

  Future<void> _importFolder(BuildContext context) async {
    final AppState app = context.read<AppState>();
    final PickedFolder? picked = await pickFolderFiles();
    if (picked == null || picked.files.isEmpty) return;
    // Fresh import — name the character after the picked folder.
    await app.importFiles(<PickedFile>[
      for (final PickedFolderFile f in picked.files) PickedFile(f.name, f.bytes),
    ], projectName: picked.folderName);
  }

  /// Confirm, then wipe the project back to empty (also on the Home screen's
  /// "Start over"). Destructive, so it asks first.
  Future<void> _resetProject(BuildContext context) async {
    final AppState app = context.read<AppState>();
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Start over?'),
        content: const Text(
            'Clear the current character, all imported sprites and edits, and '
            'reset to an empty project? Your Button/Studio settings are kept. '
            'This can\'t be undone.'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reset')),
        ],
      ),
    );
    if (go == true) app.resetProject();
  }

  void _showShortcuts(BuildContext context) {
    final AppState app = context.read<AppState>();
    // The global Ctrl/⌘ shortcuts are fixed (and already plain). The two
    // contextual single-key sets — Button-Studio framing and Theme-Maker nudge —
    // are **rebindable** here, and the choice **persists across sessions**.
    const List<List<String>> rows = <List<String>>[
      <String>['Ctrl/⌘ + Z', 'Undo'],
      <String>['Ctrl/⌘ + Y  ·  Ctrl/⌘ + Shift + Z', 'Redo'],
      <String>['Ctrl/⌘ + O', 'Import a folder of sprites'],
      <String>['Ctrl/⌘ + S', 'Export character .zip'],
      <String>['Ctrl/⌘ + Shift + S', 'Save character as a folder (no zip)'],
      <String>['Ctrl/⌘ + E', 'Export char.ini'],
      <String>['Ctrl/⌘ + N', 'Add a new emote'],
      <String>['Ctrl/⌘ + ↑ / ↓', 'Previous / next emote'],
      <String>['Ctrl/⌘ + 1 … 9', 'Jump to a screen (Home, Character … Bulk)'],
      <String>['F1', 'Show this list'],
    ];
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setD) {
          Future<void> rebind(String action) async {
            final LogicalKeyboardKey? nk = await captureKey(ctx);
            if (nk != null) {
              app.setFramingKey(action, nk);
              setD(() {});
            }
          }

          Future<void> rebindNudge(String dir) async {
            final LogicalKeyboardKey? nk = await captureKey(ctx);
            if (nk != null) {
              app.setNudgeKey(dir, nk);
              setD(() {});
            }
          }

          Widget bindableRow(String label, String keyLbl, VoidCallback onSet) =>
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: <Widget>[
                    Expanded(child: Text(label)),
                    Container(
                      constraints: const BoxConstraints(minWidth: 56),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white24),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(keyLbl,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(onPressed: onSet, child: const Text('Set')),
                  ],
                ),
              );

          return AlertDialog(
            title: const Text('Keyboard shortcuts'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Global',
                        style: Theme.of(ctx).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    for (final List<String> r in rows)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: <Widget>[
                            SizedBox(
                              width: 230,
                              child: Text(r[0],
                                  style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.w600)),
                            ),
                            Expanded(child: Text(r[1])),
                          ],
                        ),
                      ),
                    const Divider(height: 24),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text('Buttons → Manual framing  (rebindable)',
                              style: Theme.of(ctx).textTheme.titleSmall),
                        ),
                        TextButton(
                          onPressed: () {
                            app.resetFramingKeys();
                            setD(() {});
                          },
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                    const Text(
                      'Click the sprite in the Buttons screen to focus it, then '
                      '(plus Shift + arrows to nudge the crop box precisely):',
                      style: TextStyle(fontSize: 12, color: Colors.white60),
                    ),
                    const SizedBox(height: 4),
                    for (final ({String id, String label}) a
                        in AppState.framingActions)
                      bindableRow(a.label, keyLabel(app.framingKeys[a.id]!),
                          () => rebind(a.id)),
                    const Divider(height: 24),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                              'Theme Maker → Arrange nudge  (rebindable)',
                              style: Theme.of(ctx).textTheme.titleSmall),
                        ),
                        TextButton(
                          onPressed: () {
                            app.resetNudgeKeys();
                            setD(() {});
                          },
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    bindableRow('Move up', keyLabel(app.nudgeKeys['up']!),
                        () => rebindNudge('up')),
                    bindableRow('Move down', keyLabel(app.nudgeKeys['down']!),
                        () => rebindNudge('down')),
                    bindableRow('Move left', keyLabel(app.nudgeKeys['left']!),
                        () => rebindNudge('left')),
                    bindableRow('Move right', keyLabel(app.nudgeKeys['right']!),
                        () => rebindNudge('right')),
                    const SizedBox(height: 8),
                    const Text(
                      'Rebound keys are saved and restored next time you open '
                      'the app.',
                      style: TextStyle(fontSize: 11, color: Colors.white38),
                    ),
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close')),
            ],
          );
        },
      ),
    );
  }
}

/// Slim toolbar above the active screen: undo/redo + quick import/export + the
/// shortcuts cheatsheet. Only repaints when the relevant state flips (not on
/// every slider drag).
class _TopBar extends StatelessWidget {
  const _TopBar(
      {required this.onImport,
      required this.onShortcuts,
      required this.onAbout,
      required this.onReset});

  final VoidCallback onImport;
  final VoidCallback onShortcuts;
  final VoidCallback onAbout;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final AppState app = context.read<AppState>();
    return Selector<AppState, (bool, bool, bool)>(
      selector: (_, AppState a) => (a.canUndo, a.canRedo, a.hasProject),
      builder: (BuildContext context, (bool, bool, bool) s, _) {
        final bool canUndo = s.$1, canRedo = s.$2, hasProject = s.$3;
        return Material(
          color: PinselTheme.surface,
          child: SizedBox(
            height: 44,
            child: Row(
              children: <Widget>[
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Undo (Ctrl+Z)',
                  onPressed: canUndo ? app.undo : null,
                  icon: const Icon(Icons.undo_rounded),
                ),
                IconButton(
                  tooltip: 'Redo (Ctrl+Y)',
                  onPressed: canRedo ? app.redo : null,
                  icon: const Icon(Icons.redo_rounded),
                ),
                const VerticalDivider(width: 16, indent: 10, endIndent: 10),
                IconButton(
                  tooltip: 'Import folder (Ctrl+O)',
                  onPressed: onImport,
                  icon: const Icon(Icons.folder_open_rounded),
                ),
                IconButton(
                  tooltip: 'Save as a folder — no zip (Ctrl+Shift+S)',
                  onPressed: hasProject
                      ? () => app.exportFolder(
                          confirmReplace: (String name) =>
                              confirmReplaceFolder(context, name))
                      : null,
                  icon: const Icon(Icons.drive_folder_upload_rounded),
                ),
                IconButton(
                  tooltip: 'Export .zip (Ctrl+S)',
                  onPressed: hasProject ? () => app.exportZip() : null,
                  icon: const Icon(Icons.archive_outlined),
                ),
                IconButton(
                  tooltip: 'Export char.ini (Ctrl+E)',
                  onPressed: hasProject ? () => app.exportIni() : null,
                  icon: const Icon(Icons.description_outlined),
                ),
                IconButton(
                  tooltip: 'Start over (reset project)',
                  onPressed: hasProject ? onReset : null,
                  icon: const Icon(Icons.restart_alt_rounded),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'About / credits',
                  onPressed: onAbout,
                  icon: const Icon(Icons.info_outline_rounded),
                ),
                IconButton(
                  tooltip: 'Keyboard shortcuts (F1)',
                  onPressed: onShortcuts,
                  icon: const Icon(Icons.keyboard_rounded),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Scrollable navigation rail (NavigationRail itself doesn't scroll, so a short
/// window would overflow with this many destinations).
class _NavRail extends StatelessWidget {
  const _NavRail({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: NavigationRail(
                selectedIndex: index,
                onDestinationSelected: onSelect,
                labelType: NavigationRailLabelType.all,
                leading: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text('🐾', style: TextStyle(fontSize: 24)),
                ),
                destinations: <NavigationRailDestination>[
                  for (final ({IconData icon, String label}) d in _dests)
                    NavigationRailDestination(
                      icon: Icon(d.icon),
                      label: Text(d.label),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NoProject extends StatelessWidget {
  const _NoProject({required this.onGoHome});
  final VoidCallback onGoHome;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text('No project yet', style: TextStyle(fontSize: 20)),
          const SizedBox(height: 8),
          const Text('Import a folder of sprites to unlock this screen.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onGoHome,
            icon: const Icon(Icons.home_rounded),
            label: const Text('Go to Home'),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PinselTheme.surface,
      child: Consumer<AppState>(
        builder: (BuildContext context, AppState app, _) {
          final double? progress = app.progress;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // A thin per-job progress bar: determinate when the job reports a
              // count, otherwise an indeterminate sweep while busy.
              if (app.busy)
                LinearProgressIndicator(
                  minHeight: 2,
                  value: progress,
                ),
              SizedBox(
                height: 30,
                child: Row(
                  children: <Widget>[
                    const SizedBox(width: 12),
                    if (app.busy)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        progress != null
                            ? '${app.status}  ·  ${(progress * 100).round()}%'
                            : app.status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    // Cancel a long bulk job mid-run (stops at the next
                    // chunk/group boundary; nothing already saved is undone).
                    if (app.canCancel)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: TextButton.icon(
                          onPressed: app.requestCancel,
                          icon: const Icon(Icons.stop_circle_outlined, size: 16),
                          label: const Text('Cancel'),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: Colors.redAccent,
                          ),
                        ),
                      ),
                    if (app.character != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('${app.character!.emotes.length} emotes',
                            style: const TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
