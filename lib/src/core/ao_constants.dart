/// Single source of truth for every Attorney Online / webAO constant the app
/// relies on. No magic numbers or magic strings should appear anywhere else in
/// the codebase — if the AO format defines it, it lives here.
///
/// References (all verified against the user's local repos):
///  * Official spec: docs/Content Creation/characters/Overview.md
///  * Reference client: AO2-Client/src/animationlayer.cpp, text_file_functions.cpp
///  * webAO compatibility notes (no `(a)/`,`(b)/` subfolder mode on web)
library;

/// Image file extensions AO treats as *animated*, in the exact priority order
/// the engine resolves them (highest priority first).
const List<String> kAnimatedExtensions = <String>['webp', 'apng', 'gif'];

/// Image file extension AO treats as *static*. Always checked last.
const String kStaticExtension = 'png';

/// Full resolution order: animated formats first, then the static PNG fallback.
/// Mirrors `AOApplication::get_image_suffix`.
const List<String> kSpriteExtensionPriority = <String>[
  ...kAnimatedExtensions,
  kStaticExtension,
];

/// Every image extension the *maker* will happily import (a superset of what AO
/// itself renders — we can convert anything down to an AO-compatible format).
const List<String> kImportableImageExtensions = <String>[
  'webp', 'apng', 'gif', 'png', 'jpg', 'jpeg', 'bmp', 'tga', 'tiff', 'tif',
  'ico', 'pnm', 'ppm', 'pgm', 'pbm', 'psd', 'exr', 'pvr', 'pvrtc',
];

/// Sprite-state prefixes used on the filesystem.
class SpritePrefix {
  const SpritePrefix._();

  /// Idle / blinking animation, played while not speaking. `(a)foo`.
  static const String idle = '(a)';

  /// Talking animation, played while speaking. `(b)foo`.
  static const String talk = '(b)';

  /// Post / transition animation, played speaking -> idle. `(c)foo`.
  static const String post = '(c)';

  /// Subfolder variants (e.g. `(a)/foo`). Not supported by webAO.
  static const String idleFolder = '(a)/';
  static const String talkFolder = '(b)/';
  static const String postFolder = '(c)/';

  /// All bare prefixes, longest-first so trimming is unambiguous.
  static const List<String> all = <String>[idle, talk, post];
}

/// The `<modifier>` field of an emote line.
enum EmoteModifier {
  /// 0 — never plays the preanimation or its sound. Pure idle/talk.
  idle(0, 'Idle (no preanim)'),

  /// 1 — plays the preanimation and its associated sound.
  preanim(1, 'Play preanim + sound'),

  /// 5 — zoom: desk/stand hidden, background replaced with speed lines.
  /// Never plays a preanimation.
  zoom(5, 'Zoom (speed lines, no preanim)'),

  /// 6 — zoom that *always* plays the preanimation.
  zoomPreanim(6, 'Zoom + preanim');

  const EmoteModifier(this.value, this.label);

  /// The integer written to / read from the ini.
  final int value;

  /// Human-friendly label for the UI.
  final String label;

  static EmoteModifier fromValue(int value) {
    for (final EmoteModifier m in EmoteModifier.values) {
      if (m.value == value) return m;
    }
    // Unknown modifiers degrade gracefully to "idle" rather than throwing,
    // because real-world inis contain all sorts of junk.
    return EmoteModifier.idle;
  }
}

/// The optional `<deskmod>` field of an emote line.
enum DeskModifier {
  /// 0 — forcibly hide the desk/stand/overlay.
  hide(0, 'Always hide desk'),

  /// 1 — forcibly show the desk/stand/overlay (the usual default).
  show(1, 'Always show desk'),

  /// 2 — hide during preanim, show once it finishes.
  hideDuringPre(2, 'Hide during preanim'),

  /// 3 — show only during preanim, hide afterwards.
  showDuringPre(3, 'Show only during preanim'),

  /// 4 — like 2 but the preanim ignores X/Y offsets and hides paired chars.
  hideDuringPreCentered(4, 'Hide during preanim (centered)'),

  /// 5 — like 3 but the preanim ignores X/Y offsets and hides paired chars.
  showDuringPreCentered(5, 'Show only during preanim (centered)');

  const DeskModifier(this.value, this.label);

  final int value;
  final String label;

  /// AO's effective default when the deskmod field is omitted entirely.
  static const DeskModifier defaultValue = DeskModifier.show;

  static DeskModifier fromValue(int value) {
    for (final DeskModifier d in DeskModifier.values) {
      if (d.value == value) return d;
    }
    return DeskModifier.defaultValue;
  }
}

/// Valid courtroom positions for `[Options] side`.
enum CourtSide {
  defense('def', 'Defense'),
  prosecution('pro', 'Prosecution'),
  helperDefense('hld', 'Helper (defense)'),
  helperProsecution('hlp', 'Helper (prosecution)'),
  judge('jud', 'Judge'),
  witness('wit', 'Witness'),
  juror('jur', 'Juror'),
  seance('sea', 'Seance');

  const CourtSide(this.id, this.label);

  final String id;
  final String label;

  static const CourtSide defaultValue = CourtSide.witness;

  static CourtSide? fromId(String id) {
    final String norm = id.trim().toLowerCase();
    for (final CourtSide s in CourtSide.values) {
      if (s.id == norm) return s;
    }
    return null;
  }
}

/// Scaling/resize modes for `[Options] scaling` and per-emote `scaling`.
enum ScalingMode {
  smooth('smooth', 'Smooth (bilinear)'),
  pixel('pixel', 'Pixel (nearest)');

  const ScalingMode(this.id, this.label);

  final String id;
  final String label;

  static ScalingMode? fromId(String id) {
    final String norm = id.trim().toLowerCase();
    for (final ScalingMode m in ScalingMode.values) {
      if (m.id == norm) return m;
    }
    return null;
  }
}

/// How an auto-generated **button** or **char_icon** frames the sprite.
///
/// AO emote buttons and the character-select icon look best showing the
/// character's *expression* (their face), not their whole body — so [head] is
/// the default. [full] keeps the legacy "square around the whole sprite".
enum CropFraming {
  /// Crop to the character's head/face (detected from the alpha silhouette).
  /// The default for both buttons and the char icon.
  head('head', 'Head / face'),

  /// Square around the whole (auto-trimmed) sprite — the legacy framing.
  full('full', 'Full body'),

  /// A hand-placed crop box you drag/resize yourself (KFO/DRO style). See
  /// `CropBox` in `imaging/button_maker.dart`.
  manual('manual', 'Manual box');

  const CropFraming(this.id, this.label);

  final String id;
  final String label;

  /// The default framing used everywhere a button/icon is auto-generated.
  static const CropFraming defaultValue = CropFraming.head;

  static CropFraming fromId(String id) {
    final String norm = id.trim().toLowerCase();
    for (final CropFraming f in CropFraming.values) {
      if (f.id == norm) return f;
    }
    return defaultValue;
  }
}

/// Per-frame effect categories that live in `[<emote>_Frame*]` sections.
enum FrameEffectKind {
  sfx('FrameSFX'),
  realization('FrameRealization'),
  screenshake('FrameScreenshake');

  const FrameEffectKind(this.suffix);

  /// The ini section suffix, e.g. `_FrameSFX` is `'_' + suffix`.
  final String suffix;

  String sectionSuffix(String emoteSprite) => '${emoteSprite}_$suffix';
}

/// Canonical `char.ini` section names (lower-cased for case-insensitive lookup).
class IniSection {
  const IniSection._();

  static const String options = 'options';
  static const String shouts = 'shouts';
  static const String time = 'time';
  static const String emotions = 'emotions';
  static const String soundN = 'soundn';
  static const String soundT = 'soundt';
  static const String soundL = 'soundl';
  static const String soundB = 'soundb';
  static const String videos = 'videos';
  static const String optionsN = 'optionsn';

  /// Numbered alternate option blocks: `[Options2]`..`[Options5]`.
  static const int maxAlternateOptionBlocks = 5;
}

/// Timing constants.
class AoTiming {
  const AoTiming._();

  /// One `[SoundT]` tick equals this many milliseconds.
  static const int soundTickMs = 60;

  /// Animated-image frame delays in AO are expressed in centiseconds
  /// (hundredths of a second), matching GIF/APNG/WebP frame metadata.
  static const double frameDelayUnitSeconds = 0.01;

  /// A sensible default frame delay (≈100 ms) when none is known.
  static const int defaultFrameDelayCentis = 10;
}

/// Filesystem layout constants for a character folder.
class CharFolder {
  const CharFolder._();

  static const String iniName = 'char.ini';
  static const String charIcon = 'char_icon.png';
  static const String creditsFile = 'credits.txt';

  /// Attribution file written into every exported character (see
  /// [kPinselCreditsText]). Separate from the user's own `credits.txt`.
  static const String pinselCreditsFile = 'pinselcredits.txt';
  static const String emotionsDir = 'emotions';
  static const String backupEmotionsDir = '_old_emotions';
  static const String preanimDir = 'anim';
  static const String customObjectionsDir = 'custom_objections';

  /// Button file name template; `{n}` is the 1-based emote number and
  /// `{state}` is `off` or `on`.
  static const String buttonTemplate = 'button{n}_{state}.png';

  static String buttonName(int oneBasedIndex, {required bool on}) =>
      buttonTemplate
          .replaceFirst('{n}', '$oneBasedIndex')
          .replaceFirst('{state}', on ? 'on' : 'off');

  /// Recommended minimum button edge in pixels (1:1).
  static const int recommendedButtonSize = 40;

  /// Default button edge the app generates at. **40 is the classic AO emote-
  /// button size**: exporting at the size the theme actually displays means the
  /// client shows the button 1:1 with no theme-side resampling — which is what
  /// keeps it crisp in-game (a larger image the theme downscales with a cheap
  /// filter is what looked "low quality"). The renderer area-averages the
  /// downscale from the full-res sprite, so 40px is as clean as 40px can be;
  /// raise the slider (up to [maxButtonSize]) for HiDPI/KFO themes that want
  /// bigger art.
  static const int defaultButtonSize = 40;

  /// Allowed button edge range for the Button Studio slider. The renderer never
  /// upscales past the source crop, so a high value just means "as crisp as the
  /// source allows" for high-res art.
  static const int minButtonSize = 24;
  static const int maxButtonSize = 512;

  /// Resolution the Button/Icon Studio renders its on-screen *preview* at,
  /// independent of the exported [defaultButtonSize]. A 40px button shown in a
  /// ~168px preview box would otherwise be blown up and look pixelated/blurry;
  /// rendering the preview large (then letting Flutter fit it down) shows a
  /// crisp framing preview while the exported file stays the chosen size.
  static const int buttonPreviewRenderPx = 320;

  /// Recommended minimum char_icon edge in pixels (1:1).
  static const int recommendedIconSize = 60;

  /// Default char_icon edge the app generates at. AO themes render the icon
  /// small, so 40 keeps files tiny by default; raise it (up to [maxIconSize])
  /// for crisp HiDPI icons.
  static const int defaultIconSize = 40;

  /// Allowed char_icon edge range (40–128) for the customiser.
  static const int minIconSize = 40;
  static const int maxIconSize = 128;

  /// Folders that should never be treated as emote sprite sources when scanning.
  static const List<String> ignoredScanDirs = <String>[
    emotionsDir,
    backupEmotionsDir,
    customObjectionsDir,
  ];

  /// File base-names that are character chrome, not emotes.
  static const List<String> ignoredScanBaseNames = <String>[
    'char_icon',
    'custom',
    'holdit',
    'holdit_bubble',
    'objection',
    'objection_bubble',
    'takethat',
    'takethat_bubble',
    'defense_speedlines',
    'prosecution_speedlines',
    'placeholder',
    'showname',
  ];
}

/// Field separator inside an `[Emotions]` value line.
const String kEmoteFieldSeparator = '#';

/// Placeholder used for "no preanimation".
const String kNoPreanim = '-';

/// Audio file extensions AO/webAO plays (SFX, blips). Used by the Emotes-tab
/// **sound picker** to offer the audio files bundled with an imported character
/// as pickable `[SoundN]` names (AO references a sound by name, without the
/// extension), alongside the names already used elsewhere in the character.
const List<String> kAudioExtensions = <String>['opus', 'ogg', 'wav', 'mp3'];

/// Limits + step for the Edit screen's per-side crop / grow sliders. A single
/// slider per side is **bidirectional**: positive crops that edge *in*, negative
/// pads (grows) the canvas *out* with transparency. Kept here so the slider
/// range and the engine clamp never drift apart.
class CropLimits {
  const CropLimits._();

  /// Largest fraction of a side that may be cropped away (in, positive).
  static const double maxCropFraction = 0.45;

  /// Largest fraction of a side the canvas may grow by (out, negative). 0.5 =
  /// add half the width/height of transparent margin to that edge.
  static const double maxPadFraction = 0.5;

  /// How much one tap of a `−` / `+` stepper button nudges a side (1%).
  static const double stepFraction = 0.01;
}

/// Project identity + attribution. Kept here (pure Dart) so the exporter can
/// stamp every character with credits without depending on the Flutter UI.
/// **Keep in sync with `ui/credits.dart`** (`kAppName`/`kMaintainer`/`kRepoUrl`).
const String kPinselAppName = 'Pinsel AO Char Maker';
const String kPinselMaintainer = 'SyntaxNyah';
const String kPinselRepoUrl =
    'https://github.com/SyntaxNyah/Pinsel-AO-Char-Maker';

/// Contents of the [CharFolder.pinselCreditsFile] written into every export.
const String kPinselCreditsText =
    'This Attorney Online character was generated with $kPinselAppName.\n'
    '\n'
    'Pinsel is a free, open-source AO / webAO character & button maker —\n'
    'drop in a folder of sprites and get a finished, ready-to-use character\n'
    '(auto char.ini, emote buttons, char_icon), then recolour, animate and\n'
    'customise everything.\n'
    '\n'
    'Created and maintained by $kPinselMaintainer.\n'
    'Project, source code and bug reports:\n'
    '$kPinselRepoUrl\n'
    '\n'
    'This file is just attribution — you can delete it.\n';
