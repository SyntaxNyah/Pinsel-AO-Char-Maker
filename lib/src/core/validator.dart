import '../discovery/sprite_scanner.dart';
import 'ao_constants.dart';
import 'character.dart';
import 'emote.dart';

enum LintSeverity { info, warning, error }

/// A single problem (or note) found by the validator, with an optional, plain-
/// language suggested fix so users always know what to do next.
class LintIssue {
  LintIssue(this.severity, this.message, {this.emoteIndex, this.fix});

  final LintSeverity severity;
  final String message;
  final int? emoteIndex; // 0-based, when the issue is about a specific emote
  final String? fix;

  @override
  String toString() {
    final String where = emoteIndex == null ? '' : ' (emote ${emoteIndex! + 1})';
    final String f = fix == null ? '' : '  → $fix';
    return '[${severity.name}]$where $message$f';
  }
}

/// Validates a [Character] and (optionally) cross-checks it against the sprites
/// actually present on disk via a [ScanResult]. Surfacing these as friendly
/// warnings is a big quality-of-life win — users catch mistakes before they ever
/// load the character in AO.
class CharacterValidator {
  const CharacterValidator._();

  static List<LintIssue> validate(Character c, {ScanResult? scan}) {
    final List<LintIssue> issues = <LintIssue>[];

    if (c.options.name.trim().isEmpty) {
      issues.add(LintIssue(LintSeverity.warning,
          'Character has no name.',
          fix: 'Set [Options] name to match the character folder.'));
    }
    if (c.emotes.isEmpty) {
      issues.add(LintIssue(LintSeverity.warning, 'Character has no emotes.',
          fix: 'Add at least one emote, or run auto-scan on a folder of sprites.'));
    }

    final Set<String> seenComments = <String>{};
    // Case/slash-tolerant (mirrors AO's own resolution + the organizer/preview
    // path) so an imported char.ini whose `sprite=` casing differs from the file
    // names isn't falsely flagged "no sprite file found" for emotes that work.
    final SpriteGroupIndex? byBase =
        scan == null ? null : SpriteGroupIndex(scan.groups);

    for (int i = 0; i < c.emotes.length; i++) {
      final Emote e = c.emotes[i];

      if (e.sprite.trim().isEmpty) {
        issues.add(LintIssue(LintSeverity.error, 'Emote has no sprite name.',
            emoteIndex: i, fix: 'Set the emote\'s sprite (the (a)/(b) base name).'));
      }
      if (!seenComments.add(e.comment.toLowerCase()) && e.comment.trim().isNotEmpty) {
        issues.add(LintIssue(LintSeverity.info,
            'Duplicate emote name "${e.comment}".',
            emoteIndex: i, fix: 'Rename so buttons/tooltips stay distinct.'));
      }

      final bool wantsPre =
          e.modifier == EmoteModifier.preanim || e.modifier == EmoteModifier.zoomPreanim;
      if (wantsPre && (e.preanim.trim().isEmpty || e.preanim.trim() == kNoPreanim)) {
        issues.add(LintIssue(LintSeverity.warning,
            'Modifier "${e.modifier.label}" needs a preanimation but none is set.',
            emoteIndex: i,
            fix: 'Set a preanim name, or change the modifier to "Idle".'));
      }
      if (e.modifier == EmoteModifier.idle &&
          e.preanim.trim().isNotEmpty &&
          e.preanim.trim() != kNoPreanim) {
        issues.add(LintIssue(LintSeverity.info,
            'Preanim "${e.preanim}" is set but modifier is Idle, so it will not play.',
            emoteIndex: i,
            fix: 'Use modifier "Play preanim + sound" to play it.'));
      }
      if ((e.soundDelayTicks ?? 0) > 0 && !e.hasMeaningfulSound) {
        issues.add(LintIssue(LintSeverity.info,
            'A sound delay is set but there is no sound effect.',
            emoteIndex: i, fix: 'Add a [SoundN] name or clear the delay.'));
      }

      if (byBase != null) {
        final SpriteGroup? g = byBase.resolve(e.sprite);
        if (g == null || g.representative == null) {
          issues.add(LintIssue(LintSeverity.warning,
              'No sprite file found for "${e.sprite}".',
              emoteIndex: i,
              fix: 'Add (a)${e.sprite}/(b)${e.sprite} or ${e.sprite}.png, '
                  'or fix the sprite name.'));
        }
      }
    }

    // Frame effects referencing sprites the character does not use.
    final Set<String> sprites = c.spriteReferences();
    for (final dynamic fx in c.frameEffects) {
      final String ref = (fx.spriteRef as String);
      final String bare = ref
          .replaceAll(SpritePrefix.idleFolder, '')
          .replaceAll(SpritePrefix.talkFolder, '')
          .replaceAll(SpritePrefix.postFolder, '')
          .replaceAll(SpritePrefix.idle, '')
          .replaceAll(SpritePrefix.talk, '')
          .replaceAll(SpritePrefix.post, '');
      if (!sprites.contains(bare) && !sprites.contains(ref)) {
        issues.add(LintIssue(LintSeverity.info,
            'Frame effects target "$ref" which no emote uses.',
            fix: 'Harmless, but you can remove the stale section.'));
      }
    }

    return issues;
  }

  /// Convenience: count issues at or above [min] severity.
  static int count(List<LintIssue> issues, LintSeverity min) =>
      issues.where((LintIssue i) => i.severity.index >= min.index).length;
}
