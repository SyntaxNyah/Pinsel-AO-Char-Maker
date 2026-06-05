import '../core/ao_constants.dart';
import '../core/character.dart';
import '../core/emote.dart';
import 'sprite_scanner.dart';

/// Tunable knobs for [CharacterBuilder]. Everything is optional with sensible
/// defaults — the whole point is that a user can drop images in a folder and
/// get a working character with zero configuration, yet power users can adjust
/// every heuristic.
class BuildConfig {
  const BuildConfig({
    this.name = 'newchar',
    this.showname,
    this.side = CourtSide.witness,
    this.blips,
    this.chat,
    this.scaling,
    this.defaultDeskMod = DeskModifier.show,
    this.treatBareAsPreanim = true,
    this.guessSounds = true,
    this.preferredFirstNames = const <String>[
      'normal', 'neutral', 'idle', 'default', 'stand', '1',
    ],
  });

  final String name;
  final String? showname;
  final CourtSide side;
  final String? blips;
  final String? chat;
  final ScalingMode? scaling;
  final DeskModifier defaultDeskMod;

  /// When a group has both an `(a)`/`(b)` pair *and* a bare same-named file,
  /// treat the bare file as a preanimation (sets modifier to "play preanim").
  final bool treatBareAsPreanim;

  /// Apply [soundGuesses] based on emote names.
  final bool guessSounds;

  /// Emote base names (lower-case) that should be floated to the top.
  final List<String> preferredFirstNames;
}

/// Heuristic sound-effect guesses keyed by substrings found in emote names.
/// Conservative on purpose; users can clear or extend these.
const Map<String, _SoundGuess> soundGuesses = <String, _SoundGuess>{
  'deskslam': _SoundGuess('sfx-deskslam', delayTicks: 4),
  'slam': _SoundGuess('sfx-deskslam', delayTicks: 4),
  'objection': _SoundGuess('sfx-objection'),
  'damage': _SoundGuess('sfx-stab2'),
  'hurt': _SoundGuess('sfx-stab2'),
  'point': _SoundGuess('sfx-pointing'),
  'gavel': _SoundGuess('sfx-gavel'),
  'shock': _SoundGuess('sfx-shock'),
};

class _SoundGuess {
  const _SoundGuess(this.name, {this.delayTicks = 0});
  final String name;
  final int delayTicks;
}

/// The distinct sfx names referenced by [soundGuesses] — offered as suggestions
/// by the Emotes-tab sound picker ([AppState.availableSoundNames]).
List<String> soundGuessNames() =>
    soundGuesses.values.map((_SoundGuess g) => g.name).toSet().toList();

/// Builds a fully-formed [Character] from a [ScanResult].
class CharacterBuilder {
  const CharacterBuilder();

  Character build(ScanResult scan, {BuildConfig config = const BuildConfig()}) {
    final Character c = Character();
    c.options
      ..name = config.name
      ..showname = config.showname
      ..sideEnum = config.side
      ..blips = config.blips
      ..chat = config.chat
      ..scaling = config.scaling?.id;

    final List<SpriteGroup> ordered = _ordered(scan.groups, config);

    for (final SpriteGroup g in ordered) {
      final Emote e = Emote(
        comment: g.suggestedComment,
        sprite: g.base,
        deskMod: config.defaultDeskMod,
        hasDeskField: true,
      );

      if (g.hasDialogPair) {
        final bool bareIsPreanim =
            config.treatBareAsPreanim && g.hasStatic;
        if (bareIsPreanim) {
          e.preanim = g.base;
          e.modifier = EmoteModifier.preanim;
        } else {
          e.preanim = kNoPreanim;
          e.modifier = EmoteModifier.idle;
        }
      } else {
        // Static-only emote.
        e.preanim = kNoPreanim;
        e.modifier = EmoteModifier.idle;
      }

      if (config.guessSounds) _applySoundGuess(e);
      c.emotes.add(e);
    }

    return c;
  }

  List<SpriteGroup> _ordered(List<SpriteGroup> groups, BuildConfig config) {
    final List<SpriteGroup> preferred = <SpriteGroup>[];
    final List<SpriteGroup> rest = <SpriteGroup>[];
    for (final SpriteGroup g in groups) {
      final String leaf = g.base.split('/').last.toLowerCase();
      if (config.preferredFirstNames.contains(leaf)) {
        preferred.add(g);
      } else {
        rest.add(g);
      }
    }
    // Keep the relative order among preferred names as listed in config.
    preferred.sort((SpriteGroup a, SpriteGroup b) {
      int ia = config.preferredFirstNames.indexOf(a.base.split('/').last.toLowerCase());
      int ib = config.preferredFirstNames.indexOf(b.base.split('/').last.toLowerCase());
      if (ia < 0) ia = config.preferredFirstNames.length;
      if (ib < 0) ib = config.preferredFirstNames.length;
      return ia.compareTo(ib);
    });
    return <SpriteGroup>[...preferred, ...rest];
  }

  void _applySoundGuess(Emote e) {
    final String name = '${e.comment} ${e.sprite}'.toLowerCase();
    for (final MapEntry<String, _SoundGuess> entry in soundGuesses.entries) {
      if (name.contains(entry.key)) {
        e.soundName = entry.value.name;
        if (entry.value.delayTicks > 0) {
          e.soundDelayTicks = entry.value.delayTicks;
        }
        // A sound only makes sense to auto-play with a preanim trigger.
        if (e.modifier == EmoteModifier.idle) {
          e.modifier = EmoteModifier.preanim;
        }
        return;
      }
    }
  }
}
