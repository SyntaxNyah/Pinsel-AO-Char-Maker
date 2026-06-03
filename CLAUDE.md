# CLAUDE.md — developer guide for the Pinsel AO Char Maker

This file is the working manual for anyone (especially Claude) building features
in this repo. It explains the principles, the build, **every module and its
public functions**, the gotchas, and step-by-step "how to add X" recipes.

> If you're a user, read [README.md](README.md) instead. This is the dev guide.

---

## 0. Principles (follow these)

1. **Engine vs UI split.** Everything under `lib/src/{core,discovery,imaging,
   animation,presets,plugins,platform}` is **pure Dart with no `package:flutter`
   import** (platform files may use `dart:io`/`dart:html`/`dart:ffi` behind
   conditional imports). Only `lib/src/ui/**` and `lib/main.dart` import Flutter.
   Keep it that way so the engine stays testable and identical on every target.
2. **No magic numbers / strings.** AO constants live in
   `lib/src/core/ao_constants.dart`. Add new ones there; don't inline them.
3. **One model, many features.** Recolour = `ColorOp`/`OpPipeline`. Animation =
   `AnimRecipe`. Both serialise to JSON so they power preview, bulk, presets and
   plugins at once. Prefer adding to these over bespoke code paths.
4. **Lossless & tolerant.** The `char.ini` reader preserves unknown data and
   repairs malformed input. Never drop data on a round-trip.
5. **Graceful platform fallback.** WebP is the default output but must fall back
   to APNG/PNG when a platform can't encode it. Never hard-fail because an
   optional native lib is missing.
6. **Document new public APIs** with `///` doc comments, and update the relevant
   `docs/*.md` + `ROADMAP.md`.

---

## 1. Build / run / test

Flutter 3.22+ (Dart 3.4+). Platform folders are gitignored and regenerated.

```bash
flutter create .          # once: generates android/ios/linux/macos/windows/web
flutter pub get
flutter test              # run the engine tests
flutter run -d <device>   # windows|linux|macos|chrome|<android/ios id>
flutter build web --release
```
One-command everything: `scripts/build_all.ps1` (Windows) / `scripts/build_all.sh`
(Linux/macOS). CI that compiles all platforms + publishes the web build:
`.github/workflows/build.yml` (triggers on a `v*` tag).

### Key dependencies (`pubspec.yaml`)
- `image` — decode/encode + pixel ops (the engine backbone).
- `ffi` — native libwebp/libwebpmux bindings (`imaging/webp_codec_io.dart`).
- `file_picker` — file picking (folder picking lives in `platform/folder_picker*`).
- `archive` — `.zip` export. `path` / `path_provider` — paths. `collection`.
- `provider` — UI state. `flutter_colorpicker` — the Colour Lab colour wheel +
  hex bar (`ui/screens/color_lab_screen.dart`).

After pulling, run `flutter pub get` (CI does this automatically).

---

## 2. Directory map

```
lib/src/
  core/        AO data model (constants, ini, emote, character, frame effects,
               validator, history)
  discovery/   folder → character (scanner, builder, organizer, bulk rename,
               bulk folders → many characters)
  imaging/     codecs, colour ops, region edit, sprite edit (crop/trim/bg),
               compositor, buttons, bulk, webp, **sprite sheet ripper**
  animation/   clip, easing, recipe engine, keyframe timeline, lipsync
  theme/       **AO2 client theme model + defaults catalogue + randomizer**
  presets/     built-in preset library
  plugins/     JSON pack model + extension registry
  platform/    Workspace + folder picker + save/webp seams (conditional imports)
  ui/          Flutter app: app_state, theme, widgets/, screens/
```

---

## 3. Module & function reference

### core/ao_constants.dart
Constants + enums. Key items:
- `kAnimatedExtensions`, `kStaticExtension`, `kSpriteExtensionPriority`,
  `kImportableImageExtensions` — extension lists / priority.
- `SpritePrefix` — `.idle`='(a)', `.talk`='(b)', `.post`='(c)' (+ `/` folder
  variants), `.all`.
- `enum EmoteModifier { idle(0), preanim(1), zoom(5), zoomPreanim(6) }` —
  `.value`, `.label`, `EmoteModifier.fromValue(int)`.
- `enum DeskModifier { hide(0)…showDuringPreCentered(5) }` — `.value`, `.label`,
  `.fromValue`, `DeskModifier.defaultValue` (= show).
- `enum CourtSide { defense('def')…seance('sea') }` — `.id`, `.label`,
  `CourtSide.fromId`, `.defaultValue` (= witness).
- `enum ScalingMode { smooth, pixel }` — `.id`, `.fromId`.
- `enum CropFraming { head, full }` — how auto buttons / the char_icon frame a
  sprite. `.id`, `.label`, `.fromId`, `.defaultValue` (= **head**, i.e. face).
- `enum FrameEffectKind { sfx, realization, screenshake }` — `.suffix`,
  `.sectionSuffix(spriteRef)`.
- `IniSection` — canonical lower-case section names.
- `AoTiming` — `soundTickMs`=60, `frameDelayUnitSeconds`=0.01, defaults.
- `CharFolder` — `iniName`, `charIcon`, `emotionsDir`, `buttonName(n,{on})`,
  `recommendedButtonSize`=40, `defaultButtonSize`=128, `min/maxButtonSize`,
  `recommendedIconSize`=60, `defaultIconSize`=40, `min/maxIconSize`(40–128),
  `ignoredScanDirs`, `ignoredScanBaseNames`, …
- `kEmoteFieldSeparator`='#', `kNoPreanim`='-'.

### core/ao_ini.dart
Low-level tolerant INI.
- `IniEntry(key, value)`.
- `IniSectionData(name,[entries])` — `.value(k)`, `.intValue`, `.doubleValue`,
  `.boolValue`, `.set(k,v)` (in-place upsert), `.remove(k)`, `.asMap()`,
  `.numericEntries()` (sorted `List<MapEntry<int,String>>`).
- `IniDocument([sections])` — `.section(name)`, `.sectionOrCreate(name)`,
  `.hasSection`, `static parse(text,{repairMangled=true})`, `.serialize()`.
  Repairs run-on numeric lines like `1 = 02 = 0` via `_repairNumericRun`.

### core/emote.dart
- `class Emote` — fields: `comment, preanim, sprite, modifier, deskMod,
  hasDeskField, soundName, soundDelayTicks, soundLoop, blipOverride, video,
  optionsBlock`. `.hasMeaningfulSound`, `Emote.parseLine(value)`, `.toLine()`
  (round-trips field count exactly), `.copy()`.

### core/frame_effect.dart
- `FrameEffectEntry(frame,value)`.
- `FrameEffectSet({spriteRef,kind,entries})` — `.sectionName`,
  `FrameEffectSet.tryFromSection(section)` (null if not a frame section),
  `.toSection()`, `.isEmpty`.

### core/character.dart
The central model.
- `class CharacterOptions` — typed fields (`name, showname, needsShowname, side,
  blips, chat, effects, realization, category, scaling, stretch`) + `extra`
  (preserved unknown keys); `.sideEnum`, `.scalingEnum`.
- `class Character` — `options`, `alternateOptions` (Options2-5), `shouts`,
  `time`, `emotes`, `frameEffects`, `soundLoopByName`, `unknownSections`.
  - `static parse(iniText)` / `static fromIni(doc)` — lossless load.
  - `.serialize()` / `.toIni()` — canonical write (recomputes `number`, modern-
    ises `gender`→`blips`).
  - `.spriteReferences()` — set of emote sprite base names.

### core/validator.dart
- `enum LintSeverity { info, warning, error }`.
- `class LintIssue(severity,message,{emoteIndex,fix})` — `.toString()`.
- `CharacterValidator.validate(c,{scan})` → `List<LintIssue>` (missing sprites,
  count/preanim/sound mistakes, stale frame effects, with fix hints).
- `CharacterValidator.count(issues, minSeverity)`.

### core/history.dart
- `class EditHistory({limit=100})` — `.seed(c)`, `.push(c)`, `.undo()`→Character?,
  `.redo()`→Character?, `.canUndo`, `.canRedo`, `.depth`. Snapshot-based (stores
  serialised ini strings).

### discovery/sprite_scanner.dart
- `enum SpriteState { idle, talk, post, staticImage }`.
- `class SpriteFile{relPath,ext,state,base,isAnimated}`.
- `class SpriteGroup(base)` — `idle/talk/post`, `statics`, `.hasDialogPair`,
  `.hasStatic`, `.isAnimated`, `.representative`, `.suggestedComment`.
- `class ScanResult` — `groups`, `preanimCandidates`, `ignored`, `.isEmpty`.
- `class SpriteScanner` — `.scanDirectory(root)` (dart:io),
  **`.fromPaths(relPaths)`** (pure; the testable core, mirrors AO resolution).

### discovery/character_builder.dart
- `class BuildConfig({name,showname,side,blips,chat,scaling,defaultDeskMod,
  treatBareAsPreanim,guessSounds,preferredFirstNames})`.
- `soundGuesses` map (name substring → sfx).
- `class CharacterBuilder` — `.build(scan,{config})` → `Character` (names,
  preanim detection, sound guesses, preferred-first ordering).

### discovery/bulk_folders.dart  ← parent folder → many characters
- `class FolderCharacter(name)` — `.files` maps inner path (within the character
  folder) → the original picked source key.
- `class BulkFolders` — `static split(paths,{fallbackName})` → `List<FolderCharacter>`:
  groups a flat list of picker paths into one character per top-level sub-folder.
  Strips a leading **wrapper** dir (one shared by all files that holds *only*
  sub-folders — the web upload prepends the picked folder's name; native doesn't),
  then groups by next segment. A char folder (loose sprites in it) is NOT stripped;
  nested `anim/…` stays inside its character; a loose folder with no sub-folders
  collapses to one character. Drives `AppState.bulkBuildCharacters`.

### discovery/organizer.dart
- `typedef ButtonRenderer = Future<Uint8List?> Function(bytes, ext, size,
  framing, zoom)` — framing/zoom let the renderer head-crop; overlays/offsets are
  captured by the injected closure (see `AppState.buildOutput`).
- `typedef ProgressCallback = void Function(done,total,label)`.
- `class OrganizeConfig({targetCharDir,deleteOriginals,generateButtons,
  buttonSize,buttonFraming,buttonZoom,overwriteExistingButtons,generateCharIcon,
  iconSize,iconFraming,iconZoom,iconSourceEmote})`. Framing defaults to **head**;
  `iconSize` defaults to 40.
- `FileOp`, `ButtonJob`, `OrganizePlan` (now also `iconRel`/`iconSourceRel`).
- `class Organizer({buttonRenderer, iconRenderer})` — `.plan(...)`→OrganizePlan
  (adds a char_icon job from `iconSourceEmote`, falling back to the first emote
  with a sprite), `.execute(plan,{source,target,config,onProgress})`,
  `.organize(...)` (plan+execute one-shot). Copies files, writes ini, renders
  buttons + `char_icon.png`. `iconRenderer` falls back to `buttonRenderer`; set
  it when the icon needs a different (or no) border. Existing buttons/icon are
  kept unless `overwriteExistingButtons`.

### imaging/codecs.dart
- `Codecs.decode(bytes,{ext})`, `.decodeFirstFrame(...)`, `.isAnimatedExt`,
  `.frameCount(image)`, `.encodePng(image)` (APNG if multi-frame),
  `.encodeGif(image)`, `.encodeForExtension(image,ext)`,
  `.outputExtensionFor(sourceExt)` (webp/apng→apng fallback, gif→gif, else png).

### imaging/color_ops.dart  ← add recolour features here
- `class ColorOp(type,{nums,strs})` — `.n(k,[f])`, `.s(k,[f])`, `.color(k,[f])`,
  `.copyWith`, `.toJson/fromJson`.
- `class OpPipeline(name,ops,{category,description})` — `.toJson/fromJson`.
- `class ImageOps` — `static apply(image,op)`, `static applyAll(image,ops)`,
  `static register(id,fn)` (plugin hook), `registeredOps`.
- Built-in op ids (43): hueShift, saturation, vibrance, brightness, contrast,
  gamma, exposure, levels, invert, grayscale, sepia, temperature, tint,
  colorize, solidColor, gradientMap, duotone, replaceColor, selectiveHue,
  posterize, threshold, opacity, alphaThreshold, channelSwap, colorBalance,
  splitTone, selectiveSaturation, hsvAdjust, vignette, scanlines, noise,
  chromaShift, pixelate, solarize, gradientTint, dither, crossProcess,
  bleachBypass, sharpen, blur, **outline**, **dropShadow**, **glow**. (Params
  documented in docs/COLOR_OPS.md.)
- Helpers: `parseHexColor(hex)`→ARGB int?, `formatHexColor(argb)`→'#aarrggbb'.
- Implementation note: ops mutate `img.Image` frames in place; `_eachPixel`
  skips alpha==0 pixels. Ops needing neighbours (chromaShift, sharpen, blur)
  clone first. **outline/dropShadow/glow are spatial** — they clone first AND
  deliberately write into the transparent halo (they don't use `_eachPixel`).

### imaging/region_edit.dart  ← outfit/region editing
- `class SelectionMask(w,h)` / `.full(w,h)` — `.get/.set`, `.invert`,
  `.combine(other,mode)`, `.selectedCount`.
- `class RegionEditor` — `rectangle`, `ellipse`, `selectByColor(image,x,y,{
  tolerance,contiguous,ignoreTransparent})` (magic wand/flood fill),
  `selectByLuminance`, `feather`, `grow`, `shrink`, `applyOps(image,mask,ops)`,
  `erase(image,mask)`, `fill(image,mask,argb)`,
  `removeBackgroundFromCorners(image,{tolerance,feather})`,
  `eraseColor(image,argb,{tolerance})`.

### imaging/sprite_edit.dart  ← crop / trim / background removal
- `class SpriteEditSpec({cropLeft,cropTop,cropRight,cropBottom (fractions),
  autoTrim, removeBgCorners, eraseColorEnabled, eraseColorValue, bgTolerance})`
  — `.isNoop`.
- `class SpriteEdit` — `computeRect(images, spec)` (one shared crop box for a
  whole emote group, incl. union auto-trim), `removeBg(image, spec)` (in place,
  no size change), `cropTo(image, rect)` (frame-aware), `apply(image, spec,
  {rect})` (preview: removeBg → crop). Geometry is uniform across frames and
  across an emote's (a)/(b)/(c) so animations/idle-talk stay aligned.

### imaging/sprite_sheet.dart  ← rip a sheet into sprites
- `enum SheetMode { auto, grid }`; `class SheetCell(rect,{enabled,name})`.
- `class GridSpec({cols,rows,offsetX,offsetY,gutterX,gutterY,cellW,cellH})` (0
  cell size = derive to fill); `class AutoSpec({bgColor,tolerance,minSide,gap,
  padding,trim})` — `.copyWith`.
- `class SpriteSheet` — `grid(w,h,spec)`→`List<IntRect>`,
  `autoDetect(image,spec)`→`List<IntRect>` (**border-background flood-fill** so
  interior same-as-bg regions stay; 8-connected component labelling; merge boxes
  within `gap`; drop specks; trim; row-major), `extract(image,rect,{removeBg,
  bgColor,tolerance})` (crop + knock surrounding bg transparent). Drives the
  Ripper screen; export via `AppState.exportSheetCells`. See docs/SPRITE_RIPPER.md.

### imaging/compositor.dart  ← snip + combine sprites
- `class Layer(image,{x,y,scale,angle,opacity,visible,name})`.
- `class CutResult(image,offsetX,offsetY)`.
- `class Compositor` — `cut(src,mask,{trim})`, `cutRect`, `cutEllipse`,
  `place(base,piece,{x,y,scale,angle,opacity})` (top-left placement),
  `placeCentered(base,piece,{cx,cy,scale,angle,opacity})` (centre on the rotation
  pivot — rotates in place; matches the Mixer's live `Transform.rotate` preview),
  `flatten(w,h,layers)`.

### imaging/button_maker.dart
- `class IntRect(x,y,w,h)`.
- `ButtonMaker.renderAuto(bytes,ext,size,[framing,zoom])` (matches
  `ButtonRenderer`; framing defaults to **head/face**),
  `.renderAutoOverlaid(bytes,ext,size,{framing,zoom,offsetX,offsetY,background,
  foreground})` (the same with crop offsets + overlay art — buttons/icon borders),
  `.renderFramed(frame,size,{framing,zoom,offsetX,offsetY,background,foreground})`
  (from an already-decoded frame; the UI preview path),
  `.headSquare(image,{zoom})` (silhouette-based face crop — finds the shoulder
  line as the first row that widens to ~70% of the silhouette's widest row, then
  frames the head above it; floors head height so it's robust on full-body vs
  bust sprites; `zoom`>1 tightens),
  `.renderComposite({sourceFrame,crop,size,background,foreground,mask,
  selectedOverlay,on})`, `.autoTrimBounds(image)`.

### imaging/overlay_presets.dart  ← editable button/icon overlays
- `enum OverlayKind { border, background }`.
- `enum OverlayStyle { frame, doubleFrame, corners, cornerHearts, gradientFrame,
  rainbowFrame, splitFrame, solid, linearGradient, radialGradient, diagonalSplit,
  dots, hearts, sparkles, rainbow }` + `OverlayStyleInfo` extension (`.kind`,
  `.label`, `.usesColor1/Color2/Pattern/Thickness/Radius/Inset/Cell`) and
  `stylesForKind(kind)`.
- `class OverlaySpec` — the editable model: `style`, `color1/2`, `patternColor`,
  `thickness`, `radius`, `inset`, `cell`; `.build(size)`→RGBA `img.Image`, `.copy()`,
  `.kind`. `_buildSpec` dispatches to the drawing primitives (`_ring`/`_corners`/
  `_gradientRing`/`_rainbowRing`/`_splitFrame`/`_solid`/`_linear`/`_radial`/
  `_diagSplit`/`_dots`/`_hearts`/`_sparkles`/`_hsv`…). No asset files; scales to
  any size.
- `class OverlayPreset(name, category, spec)` — `.build(size)`/`.kind` delegate to
  the (editable) `spec`. `class OverlayPresets` — `borders`, `backgrounds`,
  `forKind(kind)`, `defaultSpec(kind)`. Categories: **Umineko, Danganronpa, Limbus,
  Kawaii, Classic, Vibes, Colours** (~40 borders + ~40 backgrounds). Surfaced in
  the Button Studio: a **Presets** grid, an **Import…** path, and **Build…** (the
  `overlay_builder.dart` editor). Applied via `AppState.setOverlay(..., spec:)`
  (baked to PNG at 256, then `_fit` by `ButtonMaker.renderFramed`).

### imaging/bulk_processor.dart
- `enum OutputFormat { keep, png, apng, gif, webp }`.
- `class BulkResult(sourceRel,{ok,outRel,error})`.
- `class BulkProcessor(workspace)` — `.run({files,pipeline,output,webpLossless,
  webpQuality,inPlace,nameSuffix,deleteOriginalOnConvert,onProgress})`. WebP
  output uses `encodeAnimation` for multi-frame images.

### imaging/webp_codec.dart (+ _io / _web)
- `class WebpResult.ok(bytes)` / `.fail(reason)`.
- `abstract WebpEncoder` — `supportsLossy`, `supportsLossless`,
  `encode(image,{lossless,quality})`, **`encodeAnimation(frames,durationsMs,{
  lossless,quality})`**; `WebpEncoder.instance` (active), `WebpEncoder.override(e)`.
- Native (`_io`): `NativeWebpEncoder` — libwebp via FFI (`WebPEncodeRGBA`,
  `WebPEncodeLosslessRGBA`, anim via `libwebpmux` `WebPAnimEncoder*`). ABI
  constants `_kEncoderAbi`/`_kMuxAbi` may need adjusting per libwebp version;
  every call is checked and fails to `WebpResult.fail` (never crashes), and the
  reason is surfaced to the UI status line (don't swallow it). **Only look up
  symbols a build is guaranteed to export**: the assembled-animation buffer is
  freed with `WebPFree` (always present), not `WebPDataClear` — vcpkg's
  `libwebpmux.dll` doesn't export `WebPDataClear`, and looking it up made the
  whole anim encode fall back to APNG.
- Web (`_web`): `WebWebpEncoder` — browser canvas (`toDataUrl('image/webp')`),
  still only; animation returns fail (callers fall back to APNG).

### animation/anim_clip.dart
- `class AnimFrame(image,{delayCentis})` — `.delayMs`.
- `class AnimClip(frames)` — `.toImage()`, `.encode({ext})`,
  **`.encodePreferWebp({lossless,quality})`** → `({bytes,ext,webpError})` (webp,
  else apng with `webpError` = the reason WebP wasn't produced).

### animation/easing.dart
- `class Easing` — `Easing.apply(name,t)`, `Easing.names`, `Easing.register(name,fn)`.
  ~25 curves (linear, easeInOut*, back, bounce, elastic, circ, expo, quint…).

### animation/anim_engine.dart  ← add animation effects here
- `class FrameSpec` — `dx,dy,scale,scaleX,scaleY,angle,opacity,colorOps`;
  `.add(other)` (transforms add, scales multiply, opacities multiply, colorOps
  concat).
- `class AnimRecipe(type,{p,colors,region,ease})` — `.n(k,[f])`, `.toJson/fromJson`.
  `region` (an `IntRect`) makes it animate only that area as a layer.
- `typedef RecipeFn = FrameSpec Function(double t, AnimRecipe r)`.
- `class AnimEngine` — `recipeTypes`, `register(id,fn)` (plugin hook),
  `render(base,recipes,{frames,fps,loop})`→AnimClip (global recipes sum; region
  recipes composite as layers), `renderSpec(base,specAt,{frames,fps})` (used by
  Timeline).
- Built-in recipe ids (~88): sway, bob, bounce, float, breathe, shake, spin,
  tilt, wiggle, zoomPulse, jump, glow, flash, pulse, rainbow, tintPulse, fadeIn,
  fadeOut, throb, nod, headShake, swing, drift, orbit, heartbeat, strobe,
  flicker, neon, hologram, glitch, colorCycle, wave, pendulum, vibrate, pop,
  wobble, slideIn, slideOut, squashStretch, twitch, breatheGlow, rubberBand,
  jelly, tada, rollIn, rollOut, spiralIn, levitate, recoil, lunge, duck,
  sideStep, figure8, tiltShake, zoomBounce, fadeBlink, desaturatePulse,
  colorFlash, ghostFloat, rainbowGlow, matrixGlitch, emphasisPop, breatheHeavy,
  sheen, anticipate, springIn, shiver, gallop, peek, dropIn, breatheSway, pant,
  sparkle, chromaPulse, outlinePulse, auraGlow, shadowDance, focusPull, …
  (discover at runtime via `AnimEngine.recipeTypes`). outlinePulse/auraGlow/
  shadowDance animate the spatial outline/glow/dropShadow colour ops.

### animation/timeline.dart
- `class Keyframe({time,dx,dy,scale,angle,opacity,hue,ease})` — `.toJson/fromJson`.
- `class Timeline(keyframes)` — `.specAt(t)`, `.render(base,{frames,fps})`,
  `.toJson/fromJson`.

### animation/lipsync.dart
- `LipSync.twoState(closed,open,{closedCentis,openCentis})`,
  `.fromVisemes(list,{perFrameCentis,pingPong})`,
  `.auto(base,{mouth,openAmount,frames,fps})` (procedural jaw-drop).

### theme/ao2_theme.dart  ← AO2 client theme model
- The real AO2 theme format (Qt `QSettings` flat INIs): design = `name = x,y,w,h`,
  colours = `name = r,g,b`, fonts = `name = size` + `name_font/_color/_bold/_sharp`.
- `class ThemeElement(name,x,y,w,h)`, `ThemeColor(name,r,g,b)` (`.argb`),
  `ThemeFont(name,{size,font,r,g,b,bold,sharp,extras})` (`.serialize()`),
  `ThemeSound(name,path)`, `ThemeImage(fileName,{bytes,ext})`.
- `class ThemeDesign` — ordered `elements`/`colors`/`scalars`; `upsertElement`,
  `upsertColor`, `setScalar`, `serialize(title)`, `static parse(text)`.
- `class Ao2Theme(name)` — `courtroom`/`lobby` (ThemeDesign), `fonts`/`lobbyFonts`,
  `sounds`, `courtroomCss`/`lobbyCss`, `images`, **`otherFiles`** (lossless
  passthrough). `width`/`height` from the `courtroom` element. `buildFiles()`→
  `relPath→bytes` for export; `static fromFiles(name,files)` parses a folder;
  `normalizePicked`, `starter()`, `resize(w,h,{scaleElements,scaleFonts})`,
  `parseFlatIni`, `intList`, `parseFonts`, `parseSounds`. **Lossless round-trip**
  (text is latin1 passthrough).

### theme/ao2_theme_defaults.dart
- Catalogues for the Theme Maker pickers: `kCourtroomWidgets`
  (`ThemeWidgetDef`, ~95 widgets w/ category+hint+default size), `kThemeColorKeys`,
  `kFontWidgets`, `kThemeScalars`, `kThemeImageSlots` (getter; generates the
  penalty-bar series), `kThemeImageCategories`. Append here to extend the pickers.

### theme/theme_randomizer.dart
- `ThemeRandomizer.randomize(theme,{seed,colors,fonts,jitterPositions})`→seed.
  Cohesive HSV palette (triadic accents), readable font colours; reproducible.

### presets/presets.dart
- `NamedPalette`, `NamedGradient`, `AnimPreset`, `EmoteNameSet`.
- `class PresetLibrary` — `colorPresets`, `palettes`, `gradients`, `animPresets`,
  `emoteNameSets`, `gradientMapOp(g,{strength})`, `totalCount`.

### plugins/pack.dart & extension_registry.dart
- `class PinselPack(...)` — `.fromJsonString/fromJson`, `.toJsonString/toJson`,
  `.itemCount`. Fields: colorPresets, palettes, gradients, animPresets,
  emoteNameSets.
- `ExtensionRegistry.instance` — merged getters (`colorPresets`, `palettes`,
  `gradients`, `animPresets`, `emoteNameSets`), `installPack(pack)`,
  `installPackJson(json)`, `removePack(name)`, `registerColorOp/Recipe/Easing`,
  `revision`, `installedItemCount`.

### platform/
- `abstract Workspace` — `root`, `listFiles`, `exists`, `readBytes/readString`,
  `writeBytes/writeString`, `makeDir`, `copy`, `move`, `delete`, static `norm`.
  `MemoryWorkspace` (web/tests; `.put`, `.snapshot`), `IoWorkspace` (native).
  Get one via `createLocalWorkspace(root)` from `workspace_factory.dart`.
- `saveBytes(name,bytes)` (`save_file.dart`) — native dialog / web download.
- `pickFolderFiles()` (`folder_picker.dart`) — pick a whole folder (recursive);
  native dir dialog, web `<input webkitdirectory>`. Returns `(name, bytes)` per
  file with sub-folder paths preserved.

### ui/
- `AppState extends ChangeNotifier` (`ui/app_state.dart`) — the hub the screens
  use: import (files/folder), **addSprites** (grow an existing character without
  losing emotes/edits — appends an emote per *new* sprite group), scan/build,
  edit, undo/redo, previews, live pipeline, apply/bulk, **bulkRename**,
  **crop/trim/bg via previewEdit/applyEdit**, animation render/save (WebP
  default) + **bulkAnimateAll** (one effect stack baked onto every sprite, each
  saved as animated WebP; renders+encodes **off the UI isolate via `compute`** so
  it stays responsive, **lossless** — bulk must not degrade quality),
  **sprite-sheet ripping** (`loadSheet`/`exportSheetCells`), **AO2 theme** state +
  export (`theme`, `importThemeFiles`, `newTheme`, `randomizeTheme`,
  `setThemeImage`, `touchTheme`, `exportTheme`) + rebindable Arrange nudge keys
  (`nudgeKeys`/`setNudgeKey`/`resetNudgeKeys`), mixer save, export zip/ini, and
  **bulkBuildCharacters** (parent folder → many characters in one `.zip` — groups
  via `BulkFolders.split`, builds/organises each in a throwaway workspace using
  the studio settings, never touching the open project). Read it before adding a
  screen.
  - **Export plumbing is shared**: `buildOutput` and `bulkBuildCharacters` both go
    through `_studioOrganizer()` (button/icon renderers capturing the current
    offsets+overlays) and `_studioConfig(targetCharDir:)` (size/framing/zoom/icon
    settings), so single + bulk export always render buttons identically.
    `_buildConfigNamed(name)` clones `buildConfig` with the sub-folder name.
  - **Recolour/edit write back in place** via `_writeSpriteInPlace(rel,image)`:
    re-encodes in the file's own format (WebP via the encoder, APNG/PNG/GIF
    otherwise) and only changes the path/extension on a fallback. `applyPipeline`
    and `applyEdit` both use it, then refresh `scan` from `_projectFiles()`. This
    fixes the old bug where WebP sprites (the default!) were recoloured into a
    phantom `.apng` while the original `.webp` — still referenced — was untouched.
  - **Frame-by-frame**: `spriteFiles()` lists project frames; `renderFrameSequence`
    (preview) / `saveFrameSequence(rels,{fps,reverse,pingPong,align,prefix,name})`
    assemble chosen sprites into ONE animation (normalise to a shared canvas →
    order → encode WebP/APNG). NB `AnimClip.toImage()` appends frames into the
    first frame's image, so `saveFrameSequence` **clones** each frame.
  - **Mixer parts sources**: `importMixParts(files,{label})` loads a SECOND folder
    just to snip from (`mixSources`/`MixSource`, resolved via `relForMixBase`,
    removed via `removeMixSource`). It's stashed under `_mixPrefix` in the
    workspace and excluded from every project scan (`_projectFiles`) + the export.
  - **Buttons & char_icon settings** (public fields, mutated directly by the
    studio for zero-rebuild lag): `generateButtons`, `buttonSize`, `buttonFraming`,
    `buttonZoom`, `button/iconOffsetX/Y`; `generateCharIcon`, `iconSize` (default
    40), `iconFraming`, `iconZoom`, `iconSourceEmote`; overlay slots `buttonBg/Fg`
    + `iconBg/Fg` (`OverlaySlot`, set via `setOverlay`). `previewAutoButton(size)`
    / `previewCharIcon()` use `renderFramed`; `saveCharIcon()` bakes `char_icon.png`
    into the project; `buildOutput()` feeds them all into `OrganizeConfig` and wraps
    `ButtonMaker.renderAutoOverlaid` in `buttonRenderer`/`iconRenderer` closures.
  - **Preview cache + lag fix**: `previewSprite(rel)` memoises the plain (no-op
    pipeline) PNG per `rel@maxEdge`; `_invalidateImageCaches()` clears the decode +
    preview caches and bumps `spriteRevision` whenever sprite pixels/paths change.
    The Emotes screen watches `spriteRevision` (not every notify) so typing a field
    never re-bakes the preview.
- `screens/` — home, **ini_builder** (the `[Options]`/char.ini editor), editor,
  color_lab, animation_studio, button_studio, edit, mixer, bulk, plugins,
  **sprite_ripper** (sheet → sprites), **theme_maker** (AO2 theme editor).
  `widgets/` — `CheckerImage`, `ZoomCanvas`, `overlay_builder` (the
  `showOverlayBuilder` dialog — style/colour-wheel/sliders for custom overlays).
  `credits.dart` — the About dialog + Home credits card (maintainer/repo, in
  `kMaintainer`/`kRepoUrl`).
  - `color_lab`: sliders + blendable presets/gradients + a **custom colour**
    section — inline hex field and a `flutter_colorpicker` hue-wheel dialog
    (`hexInputBar`, HEX/RGB/HSV labels); picks become `colorize`/`tint`/
    `solidColor`/`gradientMap` ops on the blend stack.
  - `animation_studio`: two modes via a `SegmentedButton` — **Effects**
    (procedural recipes; includes **Animate ALL sprites** → `bulkAnimateAll`) and
    **Frames** (frame-by-frame: pick/reorder sprite frames, fps/reverse/ping-pong/
    align, save). Both share the debounced render + `ValueNotifier` playback loop.
  - `ini_builder`: dedicated **char.ini `[Options]` editor** — name, showname,
    needs_showname (tri-state), side, blips, chat, category, scaling, stretch,
    effects, realization; preserves imported `extra` keys. Same no-lag pattern as
    `editor` (controllers + commit on blur).
  - `editor` (Emotes): **typing no longer notifies per keystroke** — fields write
    to the model + commit on blur/submit; the preview is a cached `_SpritePreview`
    keyed on `rel`+`spriteRevision` (was: a 1024px re-encode on every keystroke).
  - `button_studio`: **Button & Icon Studio** — framing (Head/face default vs Full
    body), size, face zoom (0.25–4×), crop **Move X/Y** offsets (±100%), and
    **overlays** (a KFO-style border on top + a background) for **both** buttons
    and the char_icon. Every numeric setting is a `_ValueSlider` (a slider + a
    **typeable value box**, kept in sync: drag, or type an exact value committed
    on Enter/blur and clamped to range) — replaces the old slider-only helpers.
    Each overlay slot offers **Presets** (a grouped grid picker over
    `OverlayPresets`, cached thumbnails in `_overlayThumbCache`), **Build…** (the
    `overlay_builder.dart` editor — style + colour-wheel + thickness/radius/inset,
    live preview, "start from" any preset), and **Import…** (your own PNG). The
    applied `OverlaySpec` is remembered on the slot so Build… re-opens it. Icon
    "made from emote" picker + "Save char_icon.png".
    Debounced `ValueNotifier` previews; settings live on `AppState` so export uses
    them. **Buttons render crisp**: `renderFramed` never upscales and area-averages
    on downscale (PNG is lossless — sharpness is purely the resample).
  - `edit`: crop / auto-trim / background removal (drives `SpriteEdit`).
  - `mixer`: frankensprite, **three modes** (`SegmentedButton`): **Arrange**
    (drag a snip to move, corner handle / scroll to scale, round handle to rotate),
    **Snip** (drag the crop box / corner handles on the source), **Layers** ("link
    everything" — stack whole, pre-aligned sprite files; "Add all" from a folder).
    Supports **multiple snips** (`_Snip` list, per-snip source/crop/recolour/
    placement) + whole **layers** (`_Layer` list). Body = a project sprite; parts
    come from *This project* or a **2nd folder loaded in-screen** (`importMixParts`
    → `mixSources`). Each snip's cut piece is baked **once** (debounced) into a
    cached image and moved/scaled/rotated as a live Flutter transform; only Save
    composites full-res (`placeCentered` per snip / `flatten` for layers).
  - `sprite_ripper`: load a sheet → **Auto detect** (sliders: tolerance/min
    size/gap/padding/trim), **Grid** (cols/rows/offset/gutter/cell), or **Manual**
    (`SheetMode.manual` — drag empty space to draw a box, drag a box to move,
    corner to resize, ×/Clear to delete; `_manualBox`/`_drawStart/Update/End`;
    Auto/Grid regenerate cells, Manual keeps them). Auto/grid overlay boxes are
    **tap-to-toggle**; export adds to the character (`addSprites`) or a zip. Sheet
    persists on `AppState.ripperSheetBytes`. Sliders use `divisions` (arrow-key
    friendly). See docs/SPRITE_RIPPER.md.
  - `theme_maker`: seven tabs — **Layout** (X/Y/W/H rows + add from ~95 known
    widgets, Courtroom/Lobby toggle, filter), **Colours** (swatch → hue-wheel),
    **Fonts** (size/family/colour/bold/sharp), **Images** (replace any asset with
    PNG/GIF/WebP, grouped slots), **Style** (Qt CSS + sounds + design-option
    scalars), **Arrange** (the draggable `_LayoutCanvas`: drag to move, corner to
    resize, **Show art** toggle to drag the real images; **every box is labelled +
    a hover tooltip** of what it does via `_widgetHint`; a **Grid** dropdown snaps
    drags/resizes — `_snap`/`_GridPainter`; **arrow-key nudge** via `_handleKey`
    on a `Focus` — arrows 1px, Shift 10px, Ctrl/Alt resize; the direction keys are
    **rebindable** — `AppState.nudgeKeys`, `_rebindDialog`/`_KeyCaptureDialog`),
    and **Preview** (the
    read-only `_ClientPreview` — real images + sample text in the theme's fonts).
    The Courtroom/Lobby selector (`_courtroomLobbyToggle` + `_modeCaption`, shared
    by Layout/Arrange) has icons + tooltips so each AO2 screen is obvious.
    Header: Import / New / Random / **size** button (presets 1080p/720p/AOHD +
    custom, optional proportional `Ao2Theme.resize`) / Export .zip. Edits commit
    on blur; `_rev` keys refresh fields after import/randomise. See
    docs/THEME_MAKER.md.
- `app.dart` (`HomeShell`) hosts a global `CallbackShortcuts` map (undo/redo,
  import/export, add emote, prev/next emote, `Ctrl/⌘+1..9` screen jumps, F1 help)
  and a `_TopBar` with undo/redo + import/export + **About/credits** (ℹ) buttons
  (gated on `AppState.canUndo`/`canRedo`/`hasProject` via a `Selector`). The nav
  now has a **Character** destination at index 1 (the ini builder), plus
  **Ripper** and **Theme** at the end (both project-independent). The no-project
  guard uses the `_projectFreeIndices` set (`{Home, Plugins, Ripper, Theme}`)
  instead of a hard-coded index, so adding destinations won't silently break it.
  Document new keys in `docs/SHORTCUTS.md`.

---

## 4. How to add a feature

**A colour op:** implement `static void _myOp(img.Image f, ColorOp op)` in
`color_ops.dart` (use `_eachPixel`; read params via `op.n`/`op.color`), add it to
the `_registry` map, document it in `docs/COLOR_OPS.md`, optionally add a preset.

**An animation recipe:** add `static FrameSpec _myFx(double t, AnimRecipe r)` in
`anim_engine.dart` (set transform fields and/or `colorOps`), register it in
`_registry`, document in `docs/ANIMATION.md`, optionally add an `AnimPreset`.

**An easing curve:** add to `Easing._curves` (or `Easing.register` at runtime).

**A preset / palette / gradient / name set:** add to `PresetLibrary` lists in
`presets/presets.dart`. For user-shippable content, make a JSON pack instead.

**A plugin pack:** author JSON (schema in `docs/PLUGINS.md`); load via the
Plugins screen or `ExtensionRegistry.instance.installPackJson`.

**A screen:** create `ui/screens/foo_screen.dart`, add it to `_dests` and the
`_screenFor` switch in `lib/src/app.dart`, and — if it works **without** a loaded
project — add its index to the `_projectFreeIndices` set (otherwise it's gated by
the no-project guard automatically). Talk to the engine through `AppState`.

**A new char.ini field:** add the constant/section to `ao_constants.dart`, model
it in `Character`/`Emote`, parse in `fromIni`, write in `toIni`, and add a
round-trip test. Preserve anything you don't model in `unknownSections`/`extra`.

---

## 5. Gotchas

- **`image` package (v4):** mutate frames in place via `getPixel`/`setPixelRgba`;
  iterate `image.frames` (length 1 for stills). Use `copyResize/copyCrop/
  copyRotate/compositeImage`, `encodePng` (APNG when multi-frame), `encodeGif`.
  WebP **decode** works; **encode** does not — that's why `WebpEncoder` exists.
- **WebP is the default output** but the encoder may be unavailable; always go
  through `AnimClip.encodePreferWebp` / `BulkProcessor` which fall back to APNG.
- **FFI ABI:** `webp_codec_io.dart` pokes struct fields by offset and uses ABI
  version constants. If animated WebP fails on a given libwebp build, it falls
  back; adjust `_kEncoderAbi`/`_kMuxAbi` if you need it to succeed.
- **Platform seams:** never import `*_io.dart`/`*_web.dart` directly — import the
  factory (`workspace_factory.dart`, `save_file.dart`, `webp_codec.dart`).
- **Real-time preview** runs the pipeline on a **downscaled** copy
  (`AppState.previewWithPipeline`/`previewEdit`, and the Mixer's debounced
  preview), then "Apply"/"Save" bakes at full res. Keep heavy work off the main
  path or move it into isolates.
- **Per-pixel hot path:** `ImageOps._eachPixel` iterates the frame's **sequential
  pixel cursor** and reuses one `_Rgba` (no per-pixel `getPixel/setPixelRgba`
  random access or allocation). Every colour op + animation frame funnels
  through it, so keep it allocation-free. Long bake loops (`applyPipeline`,
  `applyEdit`, `BulkProcessor.run`) `await Future.delayed(Duration.zero)`
  periodically so the progress UI repaints instead of freezing.
- **Tests:** `flutter test`. Add a test when you touch the ini model, scanner,
  colour ops, or animation engine.
```
