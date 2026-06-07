import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/error_log.dart';

/// Project identity + credits, surfaced in the About dialog and the Home card.
/// Keep this the single source of truth so both stay in sync.
const String kAppName = 'Pinsel AO Char Maker';
const String kMaintainer = 'SyntaxNyah';
const String kRepoUrl = 'https://github.com/SyntaxNyah/Pinsel-AO-Char-Maker';

/// One-line blurb about who maintains the project.
const String kMaintainerBlurb =
    'Created and maintained by $kMaintainer — ongoing bug fixes, new features '
    'and updates. Open-source on GitHub; issues and pull requests welcome.';

/// Libraries the app is built on (shown in the About dialog).
const List<String> kTechCredits = <String>[
  'Flutter & Dart',
  'image (pure-Dart codecs & pixel ops)',
  'libwebp (native WebP encode via FFI)',
  'flutter_colorpicker',
  'archive · provider · file_picker · path',
];

/// Show the About / Credits dialog.
void showAboutCreditsDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: const Row(
        children: <Widget>[
          Text('🐾  '),
          Expanded(child: Text('About $kAppName')),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'The most customizable, most automated Attorney Online / webAO '
                'character & button maker. Drop in sprites → get a finished, '
                'AO-ready character.',
              ),
              const SizedBox(height: 16),
              Text('Maintainer',
                  style: Theme.of(ctx).textTheme.titleSmall),
              const SizedBox(height: 4),
              const Text(kMaintainerBlurb),
              const SizedBox(height: 12),
              Text('Repository',
                  style: Theme.of(ctx).textTheme.titleSmall),
              const SizedBox(height: 4),
              const _RepoLink(),
              const SizedBox(height: 12),
              Text('Built with',
                  style: Theme.of(ctx).textTheme.titleSmall),
              const SizedBox(height: 4),
              for (final String t in kTechCredits)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text('• $t',
                      style: Theme.of(ctx).textTheme.bodySmall),
                ),
              const SizedBox(height: 12),
              Text('Crash logs', style: Theme.of(ctx).textTheme.titleSmall),
              const SizedBox(height: 4),
              const Text(
                'Catchable errors are logged — view them here and copy the text '
                'into a bug report. (A hard out-of-memory crash is killed by the '
                'OS before anything can be logged, so it leaves nothing here; '
                'breadcrumbs from bulk jobs still show how far it got.)',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _showCrashLogDialog(ctx),
                  icon: const Icon(Icons.bug_report_outlined, size: 18),
                  label: const Text('View crash log'),
                ),
              ),
              const SizedBox(height: 6),
              const _CrashLogLocation(),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

/// Show the crash log **inside the app** (read from the app's own file) with
/// Copy + Clear — the only way to reach it on Android 11+, where file managers
/// can't browse `Android/data`.
void _showCrashLogDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: const Text('Crash log'),
      content: SizedBox(
        width: 520,
        child: FutureBuilder<String?>(
          future: readCrashLog(),
          builder: (BuildContext c, AsyncSnapshot<String?> snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                  height: 80,
                  child: Center(child: CircularProgressIndicator()));
            }
            final String? log = snap.data;
            if (log == null) {
              return const Text(
                "Nothing logged. That's normal if the app hasn't hit a catchable "
                'error — and note that an out-of-memory crash is killed by the OS '
                'before it can write anything here.',
              );
            }
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(
                child: SelectableText(
                  log,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
            );
          },
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () async {
            final String? log = await readCrashLog();
            if (log != null) {
              await Clipboard.setData(ClipboardData(text: log));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Crash log copied')),
                );
              }
            }
          },
          child: const Text('Copy'),
        ),
        TextButton(
          onPressed: () async {
            await clearCrashLog();
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

/// A compact credits card for the Home screen.
class CreditsCard extends StatelessWidget {
  const CreditsCard({super.key});

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
                const Icon(Icons.favorite_rounded, color: Color(0xFFB58CFF)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Credits',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                TextButton.icon(
                  onPressed: () => showAboutCreditsDialog(context),
                  icon: const Icon(Icons.info_outline_rounded, size: 18),
                  label: const Text('About'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(kMaintainerBlurb),
            const SizedBox(height: 8),
            const _RepoLink(),
          ],
        ),
      ),
    );
  }
}

/// The repo URL as selectable text with a copy button (no extra dependency for
/// launching a browser — copy works on every platform including the web build).
class _RepoLink extends StatelessWidget {
  const _RepoLink();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Icon(Icons.link_rounded, size: 16),
        const SizedBox(width: 6),
        const Expanded(
          child: SelectableText(
            kRepoUrl,
            style: TextStyle(color: Color(0xFFB58CFF)),
          ),
        ),
        IconButton(
          tooltip: 'Copy link',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.copy_rounded, size: 16),
          onPressed: () {
            Clipboard.setData(const ClipboardData(text: kRepoUrl));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Repository link copied')),
            );
          },
        ),
      ],
    );
  }
}

/// Shows where the crash log is written (resolved without writing) + a copy
/// button, so any user — including on mobile — can find and send it.
class _CrashLogLocation extends StatelessWidget {
  const _CrashLogLocation();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: crashLogDir(),
      builder: (BuildContext context, AsyncSnapshot<String?> snap) {
        final String? dir = snap.data;
        if (dir == null) {
          return Text(
            snap.connectionState == ConnectionState.waiting
                ? 'Resolving location…'
                : 'Logged to the browser console (web build).',
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          );
        }
        final String full = '$dir/pinsel_crash.log';
        return Row(
          children: <Widget>[
            const Icon(Icons.bug_report_outlined, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: SelectableText(
                full,
                style: const TextStyle(fontSize: 12, color: Color(0xFFB58CFF)),
              ),
            ),
            IconButton(
              tooltip: 'Copy path',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy_rounded, size: 16),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: full));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Crash log path copied')),
                );
              },
            ),
          ],
        );
      },
    );
  }
}
