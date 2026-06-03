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
    final List<PickedFolderFile>? files = await pickFolderFiles();
    if (files == null || files.isEmpty) return;
    await app.importFiles(<PickedFile>[
      for (final PickedFolderFile f in files) PickedFile(f.name, f.bytes),
    ]);
  }

  /// Add more sprite files to the **current** character (keeps existing emotes
  /// and edits; only new sprite groups become new emotes).
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
    final List<PickedFolderFile>? files = await pickFolderFiles();
    if (files == null || files.isEmpty) return;
    await app.addSprites(<PickedFile>[
      for (final PickedFolderFile f in files) PickedFile(f.name, f.bytes),
    ]);
  }

  /// Bulk-build many characters from one **parent** folder: each sub-folder of
  /// sprites becomes its own AO-ready character folder (char.ini, sprites,
  /// emotions/ buttons, char_icon), all packed into a single .zip. Uses the
  /// current Button & Icon Studio settings.
  Future<void> _bulkFolders(BuildContext context) async {
    final AppState app = context.read<AppState>();
    final List<PickedFolderFile>? files = await pickFolderFiles();
    if (files == null || files.isEmpty) return;
    final int n = await app.bulkBuildCharacters(<PickedFile>[
      for (final PickedFolderFile f in files) PickedFile(f.name, f.bytes),
    ]);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(n > 0
            ? 'Built $n character(s) into one .zip — unzip into AO\'s characters/.'
            : 'No character sub-folders with sprites found in that folder.'),
      ));
    }
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
            if (app.hasProject) ...<Widget>[
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
        const CreditsCard(),
      ],
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
                Text('Bulk folders → many characters at once',
                    style: Theme.of(context).textTheme.titleMedium),
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
