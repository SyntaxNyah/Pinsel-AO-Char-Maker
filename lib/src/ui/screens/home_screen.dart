import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ao_constants.dart';
import '../../core/validator.dart';
import '../../discovery/character_builder.dart';
import '../../platform/folder_picker.dart';
import '../../plugins/extension_registry.dart';
import '../app_state.dart';
import '../credits.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _importFiles(BuildContext context) async {
    final AppState app = context.read<AppState>();
    final FilePickerResult? res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: kImportableImageExtensions,
    );
    if (res == null) return;
    final List<PickedFile> files = <PickedFile>[
      for (final PlatformFile f in res.files)
        if (f.bytes != null) PickedFile(f.name, f.bytes!),
    ];
    await app.importFiles(files);
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

  /// Add more sprite files to the **current** character (keeps existing emotes
  /// and edits; only new sprite groups become new emotes). Now supports picking
  /// **multiple** files at once (it always did) — drag-select or Ctrl/Shift-click
  /// in the OS dialog.
  Future<void> _addSpriteFiles(BuildContext context) async {
    final AppState app = context.read<AppState>();
    final FilePickerResult? res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: kImportableImageExtensions,
    );
    if (res == null) return;
    await app.addSprites(<PickedFile>[
      for (final PlatformFile f in res.files)
        if (f.bytes != null) PickedFile(f.name, f.bytes!),
    ]);
  }

  /// Add a whole folder of sprites to the **current** character.
  Future<void> _addSpriteFolder(BuildContext context) async {
    final AppState app = context.read<AppState>();
    final PickedFolder? picked = await pickFolderFiles();
    if (picked == null || picked.files.isEmpty) return;
    await app.addSprites(<PickedFile>[
      for (final PickedFolderFile f in picked.files) PickedFile(f.name, f.bytes),
    ]);
  }

  /// Bulk-build many characters from one **parent** folder: each sub-folder of
  /// sprites becomes its own AO-ready character folder (char.ini, sprites,
  /// emotions/ buttons, char_icon), all packed into a single .zip. Uses the
  /// current Button & Icon Studio settings.
  Future<void> _bulkFolders(BuildContext context) async {
    final AppState app = context.read<AppState>();
    final PickedFolder? picked = await pickFolderFiles();
    if (picked == null || picked.files.isEmpty) return;
    final int n = await app.bulkBuildCharacters(<PickedFile>[
      for (final PickedFolderFile f in picked.files) PickedFile(f.name, f.bytes),
    ]);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 6),
        content: Text(n > 0
            ? 'Built $n character(s) into one .zip — unzip into AO\'s characters/.'
            // On failure show the diagnostic status (which folders were detected /
            // skipped / failed) so it's actionable, not a silent "nothing happened".
            : app.status),
      ));
    }
  }

  /// **Repair char.inis in a folder:** pick a parent folder, find every char.ini
  /// (in it and subfolders), rebuild each emote list from the sprites actually
  /// present (drop dangling refs, add an emote per orphan sprite, keep [Options]),
  /// and download the repaired inis as a .zip. Doesn't touch the open project.
  Future<void> _repairInis(BuildContext context) async {
    final AppState app = context.read<AppState>();
    final PickedFolder? picked = await pickFolderFiles();
    if (picked == null || picked.files.isEmpty) return;
    final String summary = await app.repairInisInFolder(<PickedFile>[
      for (final PickedFolderFile f in picked.files) PickedFile(f.name, f.bytes),
    ]);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 6),
        content: Text(summary),
      ));
    }
  }

  /// **Merge characters into one:** pick a parent folder that holds two (or more)
  /// complete character sub-folders and fuse them into a single character — emote
  /// lists joined, buttons renumbered to their emote, colliding file names
  /// restructured + the ini updated to match. Downloads `<name>_merged.zip`;
  /// doesn't touch the open project.
  Future<void> _mergeCharacters(BuildContext context) async {
    final AppState app = context.read<AppState>();
    final PickedFolder? picked = await pickFolderFiles();
    if (picked == null || picked.files.isEmpty) return;
    final String summary = await app.mergeCharactersInFolder(<PickedFile>[
      for (final PickedFolderFile f in picked.files) PickedFile(f.name, f.bytes),
    ]);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(summary),
      ));
    }
  }

  /// **One-click: a folder of sprites → a finished, exported character.** Picks
  /// a folder, imports it (auto char.ini + emotes), converts sprites to WebP,
  /// generates buttons + char_icon, and downloads the ready-to-drop `.zip` — the
  /// whole pipeline in a single action.
  Future<void> _oneClickFolder(BuildContext context) async {
    final AppState app = context.read<AppState>();
    final PickedFolder? picked = await pickFolderFiles();
    if (picked == null || picked.files.isEmpty) return;
    await app.importFiles(<PickedFile>[
      for (final PickedFolderFile f in picked.files) PickedFile(f.name, f.bytes),
    ], projectName: picked.folderName);
    final String? path = await app.autoMagicExport();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(path == null
            ? 'Imported, but nothing to export — were there any sprites?'
            : 'Finished character exported. Unzip into AO\'s characters/.'),
      ));
    }
  }

  /// One-click for the **already-loaded** project: convert → ini → buttons →
  /// icon → export, no re-import.
  Future<void> _finishEverything(BuildContext context) async {
    final AppState app = context.read<AppState>();
    await app.autoMagicExport();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Finished & exported — WebP sprites, buttons, icon, ini.'),
      ));
    }
  }

  /// Wipe the whole project and start over (confirmed — it's destructive).
  Future<void> _reset(BuildContext context) async {
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

  @override
  Widget build(BuildContext context) {
    final AppState app = context.watch<AppState>();
    final ExtensionRegistry reg = ExtensionRegistry.instance;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text('🐾 Pinsel AO Char Maker',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(
          'Drop in a folder of sprites → get a finished, AO/webAO-ready character '
          '(auto ini, folders, and buttons). Recolour, animate and customise '
          'everything. Runs on Windows, Linux, macOS, Android, iOS and the web.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),

        // The headline shortcut: one button, finished character.
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _oneClickFolder(context),
            icon: const Icon(Icons.bolt_rounded),
            label: const Text('One-Click: folder → finished character'),
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16)),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Pick a folder of sprites and get a ready-to-drop character .zip — auto '
          'char.ini, WebP sprites, buttons & char_icon, all in one go.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),

        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            FilledButton.icon(
              onPressed: () => _importFiles(context),
              icon: const Icon(Icons.image_outlined),
              label: const Text('Import sprite files'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _importFolder(context),
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Import folder'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _bulkFolders(context),
              icon: const Icon(Icons.folder_copy_rounded),
              label: const Text('Bulk folders → characters'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _repairInis(context),
              icon: const Icon(Icons.healing_rounded),
              label: const Text('Repair char.inis in a folder'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _mergeCharacters(context),
              icon: const Icon(Icons.merge_type),
              label: const Text('Merge characters into one'),
            ),
            if (app.hasProject) ...<Widget>[
              FilledButton.icon(
                onPressed: () => _finishEverything(context),
                icon: const Icon(Icons.bolt_rounded),
                label: const Text('Finish & export everything'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _addSpriteFiles(context),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Add sprites'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _addSpriteFolder(context),
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Add sprite folder'),
              ),
              OutlinedButton.icon(
                onPressed: () => app.exportZip(),
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Export .zip'),
              ),
              OutlinedButton.icon(
                onPressed: () => app.exportIni(),
                icon: const Icon(Icons.description_outlined),
                label: const Text('Export char.ini'),
              ),
              OutlinedButton.icon(
                onPressed: () => _reset(context),
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Start over'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
              ),
            ],
          ],
        ),
        if (app.hasProject)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Tip: “Add sprites” grows the current character (keeps your emotes '
              '& edits); “Import” starts fresh.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 20),

        const _BulkFoldersCard(),
        const SizedBox(height: 12),

        _AutoBuildCard(app: app),
        const SizedBox(height: 12),
        if (app.hasProject) _ValidatorCard(app: app),
        const SizedBox(height: 12),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                const Icon(Icons.auto_awesome_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${reg.colorPresets.length} colour presets · '
                    '${reg.palettes.length} palettes · '
                    '${reg.gradients.length} gradients · '
                    '${reg.animPresets.length} animations · '
                    '${reg.packs.length} plugin pack(s) installed',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _PerformanceCard(app: app),
        const SizedBox(height: 12),
        const CreditsCard(),
      ],
    );
  }
}

/// "Advanced" performance controls: GPU-rendered previews are automatic
/// (Flutter's compositor), and heavy bulk baking can fan out across every CPU
/// core. A simple toggle lets the user dial that back if they'd rather keep the
/// machine free.
class _PerformanceCard extends StatelessWidget {
  const _PerformanceCard({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(children: <Widget>[
              const Icon(Icons.speed_rounded),
              const SizedBox(width: 12),
              Text('Performance', style: Theme.of(context).textTheme.titleMedium),
            ]),
            const SizedBox(height: 8),
            Text(
              'Live recolour previews run on the GPU (an exact colour matrix for '
              'tonal adjustments). Heavy bulk jobs — animate-all, talking mouths, '
              'recolour-all, convert — fan out across CPU cores.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('Use all CPU cores (${app.cpuCores} detected)'),
              subtitle: Text(app.useAllCores
                  ? 'Bulk baking runs on up to ${app.maxConcurrency} cores at once.'
                  : 'Bulk baking runs one job at a time.'),
              value: app.useAllCores,
              onChanged: app.setUseAllCores,
            ),
          ],
        ),
      ),
    );
  }
}

/// Explains the "Bulk folders → characters" workflow and the folder layout it
/// expects (a parent folder of per-character sub-folders).
class _BulkFoldersCard extends StatelessWidget {
  const _BulkFoldersCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.folder_copy_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Bulk folders → many characters at once',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Make 10+ characters in one click: point “Bulk folders → '
              'characters” at a parent folder where each sub-folder holds one '
              'character\'s sprites. Every sub-folder is turned into a finished '
              'character folder and they\'re all packed into one .zip.',
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'MyCast/            ← pick this folder\n'
                '  Phoenix/         → character\n'
                '    (a)normal.png\n'
                '    (b)normal.png\n'
                '  Edgeworth/       → character\n'
                '    (a)smug.png\n'
                '\n'
                'gives →  characters.zip\n'
                '  Phoenix/char.ini · char_icon.png · emotions/button1_off.png · …\n'
                '  Edgeworth/char.ini · char_icon.png · emotions/… ',
                style: TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Buttons + char_icon use your current Button & Icon Studio '
              'settings. A sub-folder that already has a char.ini is kept as-is. '
              'Your open project isn\'t touched.',
              style: TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}

class _AutoBuildCard extends StatelessWidget {
  const _AutoBuildCard({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final BuildConfig c = app.buildConfig;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Auto-build options',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    initialValue: c.name,
                    decoration: const InputDecoration(labelText: 'Character name (folder)'),
                    onChanged: (String v) =>
                        app.updateBuildConfig(_copy(c, name: v)),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<CourtSide>(
                  value: c.side,
                  items: <DropdownMenuItem<CourtSide>>[
                    for (final CourtSide s in CourtSide.values)
                      DropdownMenuItem<CourtSide>(value: s, child: Text(s.label)),
                  ],
                  onChanged: (CourtSide? s) =>
                      app.updateBuildConfig(_copy(c, side: s)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              children: <Widget>[
                _toggle(context, 'Bare file = preanim', c.treatBareAsPreanim,
                    (bool v) => app.updateBuildConfig(_copy(c, bare: v))),
                _toggle(context, 'Guess sound effects', c.guessSounds,
                    (bool v) => app.updateBuildConfig(_copy(c, sounds: v))),
              ],
            ),
            if (app.hasProject) ...<Widget>[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => app.regenerate(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Regenerate from sprites'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _toggle(BuildContext context, String label, bool value,
          ValueChanged<bool> onChanged) =>
      Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Switch(value: value, onChanged: onChanged),
        Text(label),
      ]);

  BuildConfig _copy(BuildConfig c,
          {String? name, CourtSide? side, bool? bare, bool? sounds}) =>
      BuildConfig(
        name: name ?? c.name,
        showname: c.showname,
        side: side ?? c.side,
        blips: c.blips,
        chat: c.chat,
        scaling: c.scaling,
        defaultDeskMod: c.defaultDeskMod,
        treatBareAsPreanim: bare ?? c.treatBareAsPreanim,
        guessSounds: sounds ?? c.guessSounds,
      );
}

class _ValidatorCard extends StatelessWidget {
  const _ValidatorCard({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final List<LintIssue> issues = app.issues;
    final int errors = CharacterValidator.count(issues, LintSeverity.error);
    final int warnings =
        issues.where((LintIssue i) => i.severity == LintSeverity.warning).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(children: <Widget>[
              Icon(errors > 0
                  ? Icons.error_outline
                  : warnings > 0
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline),
              const SizedBox(width: 8),
              Text('Validation: $errors error(s), $warnings warning(s)',
                  style: Theme.of(context).textTheme.titleMedium),
            ]),
            const SizedBox(height: 8),
            ...issues.take(6).map((LintIssue i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('• ${i.toString()}',
                      style: Theme.of(context).textTheme.bodySmall),
                )),
            if (issues.length > 6) Text('…and ${issues.length - 6} more'),
            if (issues.isEmpty) const Text('No problems found. 🎉'),
          ],
        ),
      ),
    );
  }
}
