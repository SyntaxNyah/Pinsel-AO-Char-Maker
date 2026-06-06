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
- `enum CropFraming { head, full, manual }` — how buttons / the char_icon frame a
  sprite (auto face, whole-body, or a hand-placed `CropBox`). `.id`, `.label`,
  `.fromId`, `.defaultValue` (= **head**). No exhaustive `switch`es on it (safe to
  extend); `ButtonMaker.renderFramed` keys off it.
- `enum FrameEffectKind { sfx, realization, screenshake }` — `.suffix`,
  `.sectionSuffix(spriteRef)`.
- `IniSection` — canonical lower-case section names.
- `AoTiming` — `soundTickMs`=60, `frameDelayUnitSeconds`=0.01, defaults.
- `CharFolder` — `iniName`, `charIcon`, `emotionsDir`, `buttonName(n,{on})`,
  `recommendedButtonSize`=40, **`defaultButtonSize`=40** (classic AO size →
  exported 1:1 so the theme doesn't rescale = crisp in-game; was 128, user asked
  for 40), `min/maxButtonSize`(24–512), **`buttonPreviewRenderPx`=320** (the
  Button/Icon Studio renders its on-screen *preview* at ≥ this, decoupled from
  the export size, so a 40px button still frames sharply on screen),
  `recommendedIconSize`=60, `defaultIconSize`=40, `min/maxIconSize`(40–128),
  `ignoredScanDirs`, `ignoredScanBaseNames`, …
- `kEmoteFieldSeparator`='#', `kNoPreanim`='-'.
- `kAudioExtensions` (opus/ogg/wav/mp3) — feeds the Emotes-tab **sound picker**.
- `CropLimits` — `maxCropFraction`=0.45, `maxPadFraction`=0.5, `stepFraction`=0.01
  for the Edit screen's bidirectional crop/grow sliders + their −/+ steppers.

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
  `.redo()`→Character?, `.canUndo`, `.canRedo`, `.depth`, **`.clear()`** (reset).
  Snapshot-based (stores serialised ini strings).

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
  framing, zoom, spriteBase)` — framing/zoom let the renderer head-crop;
  overlays/offsets + the **per-sprite manual crop** are captured by the injected
  closure (see `AppState.buildOutput`). `spriteBase` is the emote's `sprite`
  base name so the closure can pick that sprite's own manual box; it's `null`
  for the char_icon. `ButtonJob` carries the `spriteBase` from `plan`.
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
  kept unless `overwriteExistingButtons`. **`execute` yields (`await
  Future.delayed(Duration.zero)`) between buttons** — button rendering is sync
  CPU on the UI isolate, so a big cast (100 emotes, or bulk-folders) would
  otherwise block long enough that the OS marks the app "not responding" and the
  user force-quits (looked like a crash). `execute` also stamps every character
  with `CharFolder.pinselCreditsFile` (`pinselcredits.txt` = `kPinselCreditsText`,
  attribution + repo/bug-report URL) — so single + bulk export both get it.

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

### imaging/color_matrix.dart  ← GPU live-preview matrix
- `ColorMatrix.tryBuild(List<ColorOp>)` → 20-value `ColorFilter.matrix` list
  (row-major 4×5, 0–255 channels) **or `null`** if any op isn't an exact linear
  transform. Powers the Colour Lab GPU preview (the UI lays a `ColorFilter` over
  the base sprite; falls back to the CPU bake when null). `supportedTypes`:
  brightness, contrast, exposure, invert, grayscale, sepia, temperature, tint,
  solidColor, opacity. Exact (luma weights match `ImageOps._luma`), so the
  preview equals what "Apply" bakes. `identity`, `supports(op)`. Exposed via
  `AppState.liveColorMatrix(pipeline)`. See docs/PERFORMANCE.md.

### imaging/parallel.dart  ← multi-core scheduler
- `mapParallel<T,R>(items, task, {concurrency, onProgress})` — pure-Dart windowed
  runner: keeps `concurrency` `task` futures in flight, **preserves input order**.
  Doesn't spawn isolates itself (the `task` chooses `compute` vs inline), so it's
  web-safe + unit-tested. Drives `bulkAnimateAll`/`bulkMouthTalkAll` (one
  `compute` per in-flight sprite = true multi-core). See docs/PERFORMANCE.md.

### imaging/region_edit.dart  ← outfit/region editing
- `class SelectionMask(w,h)` / `.full(w,h)` — `.get/.set`, `.invert`,
  `.combine(other,mode)`, `.selectedCount`.
- `class RegionEditor` — `rectangle`, `ellipse`, `selectByColor(image,x,y,{
  tolerance,contiguous,ignoreTransparent})` (magic wand/flood fill),
  `selectByLuminance`, `feather`, `grow`, `shrink`, `applyOps(image,mask,ops)`,
  `erase(image,mask)`, `fill(image,mask,argb)`,
  `removeBackgroundFromCorners(image,{tolerance,feather})`,
  `eraseColor(image,argb,{tolerance})`.

### imaging/sprite_edit.dart  ← crop / **grow** / **resize** / trim / bg removal
- `class SpriteEditSpec({cropLeft,cropTop,cropRight,cropBottom,
  **padLeft,padTop,padRight,padBottom** (all fractions), autoTrim, removeBgCorners,
  eraseColorEnabled, eraseColorValue, bgTolerance, **scaleX, scaleY** (resize
  factors, 1.0 = unchanged)})` — `.isNoop` (now also requires scale == 1).
  **crop\* reduce a side; pad\* grow (extend) it with transparency; scale\* resize
  the whole image.** A side is never both crop+pad (the Edit UI maps one
  bidirectional slider per side to exactly one).
- `class SpriteEdit` — `computeRect(images, spec)` (one shared box for a whole
  emote group: inward crop + union auto-trim, **then grows outward by pad\*** so
  the returned `IntRect` may have a **negative origin / exceed the image**),
  `removeBg(image, spec)` (in place, no size change), `cropTo(image, rect)`
  (frame-aware; when `rect` is inside it crops, when it overflows it paints each
  frame onto a transparent canvas = the pad/grow), **`resize(image, sx, sy)`**
  (frame-aware `copyResize` by factors — cubic up / average down — preserving
  frame durations; 1×1 returns the same instance), `apply(image, spec, {rect})`
  (preview: removeBg → crop/grow → **resize**). Geometry/scale are uniform across
  frames and across an emote's (a)/(b)/(c) so animations/idle-talk stay aligned.
  See `test/sprite_edit_test.dart`.

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
- `class CropBox(x,y,side)` — **manual** crop as fractions (x/y top-left, side =
  edge as a frac of width → square in px). `toPixels(w,h)` returns a square
  **clamped** fully inside the image (the safety net for the draggable editor);
  `fromPixels(rect,w,h)` (seed from `headSquare`), `initial`, `copyWith`. Used by
  `CropFraming.manual` (Button Studio "Manual" mode). **Buttons keep one box per
  sprite** (`AppState.buttonCrops`, keyed by sprite base); the icon has its own.
- `renderFramed`/`renderAutoOverlaid` take **`CropBox? manualCrop`**: when
  `framing == manual` and the box is non-null the square is
  `manualCrop.toPixels(...)`; when `framing == manual` and the box is **null**
  (a sprite the user never hand-placed) it **falls back to `headSquare`** so
  every button still frames a face. Auto offsets are skipped in manual. Threaded
  from `AppState` (`buttonCropRaw(spriteBase)`/`iconCrop`) via the preview calls
  + the `_studioOrganizer` renderer closures (the closures capture it like the
  overlays/offsets; the typedef passes `spriteBase` so the closure can resolve
  the right box per button).
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
  `.kind`, **`.toJson()` / `static fromJson(map)`** (style by enum *name*, colours
  as ints, doubles; for persisting user-saved presets). `_buildSpec` dispatches to
  the drawing primitives (`_ring`/`_corners`/`_gradientRing`/`_rainbowRing`/
  `_splitFrame`/`_solid`/`_linear`/`_radial`/`_diagSplit`/`_dots`/`_hearts`/
  `_sparkles`/`_hsv`…). No asset files; scales to any size.
- `class OverlayPreset(name, category, spec)` — `.build(size)`/`.kind` delegate to
  the (editable) `spec`. `class OverlayPresets` — `borders`, `backgrounds`,
  `forKind(kind)`, `defaultSpec(kind)`. Categories: **Umineko, Danganronpa, Limbus,
  Kawaii, Classic, Vibes, Colours** (~40 borders + ~40 backgrounds). Surfaced in
  the Button Studio: a **Presets** grid (with your **★ Saved** user presets first),
  an **Import…** path, **Build…** (the `overlay_builder.dart` editor) and **Save**
  (store the built spec as a reusable user preset — `AppState.saveOverlayPreset`,
  persists). Applied via `AppState.setOverlay(..., spec:)` (baked to PNG at 256,
  then `_fit` by `ButtonMaker.renderFramed`).

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

### animation/lipsync.dart  ← talking mouths (see docs/LIPSYNC.md)
- **`LipSync.talk(base,{mouth,openAmount,frames,fps})`** — the headline path: a
  natural, **seamless-looping** talking clip faked from ONE sprite by dropping
  the jaw inside `mouth` with a harmonic, speech-like cadence
  (`talkOpenness(t)`). Clones internally (never mutates the source).
- `LipSync.defaultMouthRegion(image)` — face-derived mouth box (uses
  `ButtonMaker.headSquare`, lower-third of the head). `defaultOpenAmount`=0.32.
- `LipSync.twoState(closed,open,...)`, `.fromVisemes(list,...)` (real mouth art),
  `.auto(base,...)` (original single-pulse jaw-drop, kept for back-compat).
- `class MouthRegion(x,y,w,h)` — the box as **fractions** 0..1; `.toPixels(w,h)`,
  `.copyWith`, `MouthRegion.defaultFor(image)`. Surfaced in the Animation
  Studio's **Mouth** tab (live preview + adjustable box) and `AppState`
  (`previewMouthTalk`/`saveMouthTalk`/`bulkMouthTalkAll`/`defaultMouthRegionFor`).

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
- `cpuCount` (`cpu.dart`) — logical core count (native `Platform.numberOfProcessors`
  / web `navigator.hardwareConcurrency`); seam behind `cpu_io`/`cpu_web`. Feeds
  `AppState.maxConcurrency` for multi-core bulk baking.
- `pickFolderFiles()` (`folder_picker.dart`) — pick a whole folder (recursive);
  native dir dialog, web `<input webkitdirectory>`. Returns a **`PickedFolder`**
  record `({String? folderName, List<PickedFolderFile> files})` — `folderName`
  (basename on native / first path segment on web) is used to auto-name the
  character. **Hardened** against folder-scan crashes: `followLinks: false`
  (no symlink/junction-cycle hangs), per-file try/catch (skip unreadable), and a
  64 MB per-file size cap (skip videos/PSDs) — **no extension filter** (char.ini
  + audio must survive). Callers use `picked.files` / `picked.folderName`.
- `logCrash(text)` / `crashLogPath` (`error_log.dart`) — append to
  `pinsel_crash.log` next to the exe (native; falls back to temp/cwd) or the dev
  console (web). Wired in `main.dart` via `runZonedGuarded` + `FlutterError.onError`
  so an unreproducible crash in a built app becomes a sendable stack trace
  (can't catch a hard OOM/native segfault, but catches every Dart exception).
- `loadSettings()` / `saveSettings(map)` (`settings_store.dart`, `_io`/`_web`
  seam) — **dependency-free** key→value persistence for UI prefs that must
  survive a restart. Native writes `pinsel_settings.json` next to the exe (same
  candidate-dir logic as the crash log so read/write agree); web uses
  `localStorage`. Both best-effort + **never throw**. Used by `AppState` to
  persist the rebindable framing/nudge keys **and user overlay presets** (one
  `_persistSettings()` writes them all together — add new keys there, don't write
  the file from two places or they clobber). Values must be JSON-encodable;
  `LogicalKeyboardKey`s are stored as integer `keyId`s, overlays via
  `OverlaySpec.toJson`.
- `exportToFolder(files)` (`folder_export.dart`, `_io`/`_web` seam) — native: pick
  a directory (`FilePicker.getDirectoryPath`) then write every `relPath → bytes`
  under it (splits the `/`-keyed rel + re-joins with the platform separator), so
  the built character folder just *appears* on disk (no zip). Returns the chosen
  dir or null (cancelled / web, where it's unsupported → caller falls back to the
  `.zip`). Drives `AppState.exportFolder`.
- `MemoryWorkspace.clear()` — drop all files (used by fresh import + reset).

### ui/
- `AppState extends ChangeNotifier` (`ui/app_state.dart`) — the hub the screens
  use: import (files/folder), **addSprites** (grow an existing character without
  losing emotes/edits — appends an emote per *new* sprite group), scan/build,
  edit, undo/redo, previews, live pipeline, apply/bulk, **bulkRename**,
  **crop/grow/resize/trim/bg via previewEdit/applyEdit** (`SpriteEditSpec` now
  carries `scaleX/scaleY`; `currentSpriteSize()` feeds the Edit screen's px
  fields), animation render/save (WebP
  default) + **bulkAnimateAll** (one effect stack baked onto every sprite, each
  saved as animated WebP; renders+encodes **off the UI isolate via `compute`** so
  it stays responsive, **lossless** — bulk must not degrade quality),
  **sprite-sheet ripping** (`loadSheet`/`exportSheetCells`), **AO2 theme** state +
  export (`theme`, `importThemeFiles`, `newTheme`, `randomizeTheme`,
  `setThemeImage`, `touchTheme`, `exportTheme`) + **rebindable keys** (the Theme
  Maker Arrange nudge keys `nudgeKeys`/`setNudgeKey`/`resetNudgeKeys` **and** the
  Button Studio Manual framing keys `framingKeys`/`setFramingKey`/
  `resetFramingKeys` + `framingActions` label list). Both are seeded with plain
  defaults (nudge = arrows; framing = ←/→ prev/next, Enter make-&-next, R/A/F),
  **persist across sessions** via `settings_store` (loaded in the `AppState()`
  ctor through `_loadPersistedSettings`, saved on every rebind through
  `_persistKeybinds`; `LogicalKeyboardKey` ↔ `keyId`). Also: mixer save, export
  zip/ini, and
  **bulkBuildCharacters** (parent folder → many characters in one `.zip` — groups
  via `BulkFolders.split`, builds/organises each in a throwaway workspace using
  the studio settings, never touching the open project). Read it before adding a
  screen.
  - **Talking mouths**: `previewMouthTalk(mouth,…)` (live loop), `saveMouthTalk(mouth,
    {prefix,…})` (one sprite), **`bulkMouthTalkAll({…})`** (every sprite, auto mouth
    per face), `defaultMouthRegionFor(rel)` + `currentSpriteAspect()` seed the Mouth
    tab. `MouthRegion` (fractions). See docs/LIPSYNC.md.
  - **One-click `autoMagicExport({convertToWebp = false})`**: ini + buttons + icon
    → export `.zip`, via the same path as `exportZip` (reliable). `convertToWebp`
    is **off by default** — force-converting every sprite through the native
    libwebp FFI was *hard-crashing* (window closes = OOM/segfault, uncatchable in
    Dart) so One-Click copies sprites as-is; convert via Bulk→WebP instead. Writes
    phase **breadcrumbs** to `pinsel_crash.log` (`logCrash`) so a hard crash is
    localisable. Home: "One-Click: folder → finished character" / "Finish &
    export everything". See docs/ONE_CLICK.md.
  - **Performance**: `useAllCores`/`setUseAllCores`, `cpuCores`, `maxConcurrency`
    (`min(cores,8)`, or 1). `bulkAnimateAll`/`bulkMouthTalkAll` fan out via
    `mapParallel` (one `compute` per in-flight sprite). `liveColorMatrix(pipeline)`
    → GPU `ColorFilter` for the Colour Lab. See docs/PERFORMANCE.md.
  - **Fresh import / reset / multi-delete**: `importFiles({projectName})` now
    **clears the workspace first** (`_clearWorkspaceFiles`) so a second import
    doesn't accumulate the previous character's sprites (the "Ebina emotes
    returned" bug), and names the auto-built character after the picked folder
    (`projectName` → `_buildConfigNamed`, sanitised by `_cleanProjectName`).
    `resetProject()` wipes everything (workspace/character/scan/history/previews/
    mix parts) — settings kept; surfaced as Home "Start over" + the toolbar ↻.
    `deleteEmotes(Set<int>)` removes many emotes in one undo step + `moveEmotes(
    Set<int>, newIndex)` reorders a multi-selection as a block (Emotes-tab
    multi-select drag). `addSprites` still *grows* the current character.
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
    + `iconBg/Fg` (`OverlaySlot`, set via `setOverlay`). **User overlay presets**:
    `userOverlayPresets` (`[{name, OverlaySpec}]`), `userOverlaysFor(kind)`,
    `saveOverlayPreset(name, spec)` / `deleteOverlayPreset(name)` — a built overlay
    can be **Saved** and reused; persisted via `settings_store`. `previewAutoButton(size)`
    (= `previewButtonForEmote(current, size)`) / **`previewButtonForEmote(e, size)`**
    (any emote — drives the sprite list's tiny **button** thumbnails) /
    **`previewCharIcon([int? size])`** use `renderFramed` (the studio passes a
    large preview size; `size` omitted = real `iconSize`); `availableSoundNames()`
    (async) feeds the Emotes sound picker; `saveCharIcon()` bakes `char_icon.png`
    into the project; `buildOutput()` feeds them all into `OrganizeConfig` and wraps
    `ButtonMaker.renderAutoOverlaid` in `buttonRenderer`/`iconRenderer` closures.
    `bumpButtonStyle()` (debounced from the studio's `_computeBtn`) just
    **notifies** so the list rebuilds; which thumbnails actually re-render is
    decided **per-sprite** by **`buttonThumbKey(e)`** (a cheap hash of
    framing/zoom/offsets/overlays + *that sprite's* box, passed as each
    `_ButtonThumb`'s reload key) — so editing one sprite's box re-renders **one**
    thumbnail, not the whole visible list (the fix for the drag-stop freeze on a
    big cast). Kept separate from `spriteRevision` (pixels).
    **Export:** `exportZip()` (`.zip`), **`exportFolder()`** (writes the built
    character to a picked directory via the `folder_export` seam — no zip, falls
    back to `exportZip` on web), `exportIni()` (just `char.ini`). All three build
    through `buildOutput()`.
  - **Per-sprite manual crops**: `buttonCrops` is a `Map<spriteBase, CropBox>`
    (replaces the old single `buttonCrop`) so each sprite gets its own hand-placed
    box in Manual mode; a sprite with no entry renders with its auto head-square.
    `buttonCropRaw(base)` (stored box or null → head fallback in `renderFramed`),
    `buttonCropFor(base)` (box or `CropBox.initial`, for the editor),
    `setButtonCrop(base,box)`, `ensureButtonCropSeeded(emote)` (lazy seed from the
    sprite's own head-square on first view), **`arriveButtonCrop(to,{carryFrom})`**
    (seed-on-arrival: when you advance *forward* it **carries** the previous
    sprite's box onto the next unframed one instead of re-detecting its face — the
    "it resets when I press Enter" fix; callers pass `carryFrom` only when
    `target > selectedEmote`), `resetButtonCropFor(emote)`,
    `applyButtonCropToAll(box)`, and `buttonCropCoverage` (→ `(customised,total)`
    distinct sprite bases, for the caption). **`navigateButtonFraming(target)`**
    is the **single** framing-navigation entry point (selectEmote + carry-forward
    + notify) — the inline studio, the sprite list, AND the big editor all call it
    so prev/next/Enter behave identically (no divergent copies). The char_icon
    still uses one `iconCrop`. `buttonCrops` is cleared on
    `resetProject`/`importFiles` (via `_clearWorkspaceFiles`).
  - **Preview cache + lag fix**: `previewSprite(rel)` memoises the plain (no-op
    pipeline) PNG per `rel@maxEdge`; `_decodeButtonSource(rel)` caches a
    **≤640px downscaled** first frame used ONLY for button previews/thumbnails
    (`previewButtonForEmote`) so a manual-crop commit + 100+ list thumbnails crop
    a small image, not a full-res sprite (export still uses full res);
    `_invalidateImageCaches()` clears the decode + **button-source** + preview
    caches and bumps `spriteRevision` whenever sprite pixels/paths change (also
    cleared on fresh import/reset via `_clearWorkspaceFiles`). The Emotes screen
    watches `spriteRevision` (not every notify) so typing a field never re-bakes
    the preview.
- `screens/` — home, **ini_builder** (the `[Options]`/char.ini editor), editor,
  color_lab, animation_studio, button_studio, edit, mixer, bulk, plugins,
  **sprite_ripper** (sheet → sprites), **theme_maker** (AO2 theme editor).
  `widgets/` — `CheckerImage` (**perf**: the transparency checker is **one**
  GPU-tiled rect — a cached 2×2 `ui.Image` tile via `ImageShader` — NOT a
  `drawRect` per cell, and the whole thing is `RepaintBoundary`-wrapped, so a big
  zoom/pan canvas no longer issues thousands of draw calls per frame), `ZoomCanvas`,
  `overlay_builder` (the
  `showOverlayBuilder` dialog — style/colour-wheel/sliders for custom overlays;
  shared `_OverlayControlsPanel` + a **Big editor** full-screen route
  `_OverlayBigBuilder` with an InteractiveViewer **zoom/pan** preview + +/−/reset,
  editing the same spec),
  **`key_capture.dart`** (`keyLabel(key)` for a friendly label + `captureKey(ctx)`
  / `KeyCaptureDialog` "press a key" — shared by the F1 rebinder and the Theme
  Maker's nudge rebinder; ignores bare modifiers, cancels on Esc).
  `credits.dart` — the About dialog + Home credits card (maintainer/repo, in
  `kMaintainer`/`kRepoUrl`).
  - `color_lab`: sliders + blendable presets/gradients + a **custom colour**
    section — inline hex field and a `flutter_colorpicker` hue-wheel dialog
    (`hexInputBar`, HEX/RGB/HSV labels); picks become `colorize`/`tint`/
    `solidColor`/`gradientMap` ops on the blend stack. **GPU live preview**: when
    the whole pipeline is matrix-representable (`liveColorMatrix`), it shows the
    base sprite under a `ColorFilter.matrix` (instant, compositor-side, "GPU"
    badge) instead of the CPU bake; HSV/curve/spatial ops fall back to the CPU
    preview. `_baseBytes` is the plain sprite (reloaded after Apply); the GPU
    filter is applied to the image only (via `CheckerImage.colorFilter`), never
    the checker.
  - `animation_studio`: **three** modes via a `SegmentedButton<_StudioMode>` —
    **Effects** (procedural recipes; **Animate ALL sprites** → `bulkAnimateAll`),
    **Mouth** (talking lip-sync: a face-placed, draggable mouth box overlaid on a
    looping preview — X/Y/W/H + open amount + frames/fps; **Save (b)/(a)** →
    `saveMouthTalk`, **all sprites** → `bulkMouthTalkAll`; seeds via
    `_ensureMouthSeed`/`defaultMouthRegionFor`/`currentSpriteAspect`), and
    **Frames** (frame-by-frame: pick/reorder, fps/reverse/ping-pong/align, save).
    All share the debounced render + `ValueNotifier` playback loop.
  - `ini_builder`: dedicated **char.ini `[Options]` editor** — name, showname,
    needs_showname (tri-state), side, blips, chat, category, scaling, stretch,
    effects, realization; preserves imported `extra` keys. Same no-lag pattern as
    `editor` (controllers + commit on blur).
  - `editor` (Emotes): **typing no longer notifies per keystroke** — fields write
    to the model + commit on blur/submit; the preview is a cached `_SpritePreview`
    keyed on `rel`+`spriteRevision` (was: a 1024px re-encode on every keystroke).
    The list (`_EmoteListState`) has **multi-select** (per-row checkboxes + an
    All/None + **Delete (N)** bar → `deleteEmotes`), **multi-drag** (dragging a
    ticked row moves the whole selection as a block → `moveEmotes(selected,
    newIndex)`, which uses the raw `ReorderableListView` drop index), and
    **auto-scrolls** to the selected emote when it changes externally (keyboard
    `Ctrl+↑/↓`) via a `ScrollController` + estimated row extent (only when
    off-screen). **Tap sets `_lastSelected = i` before `selectEmote`** so the
    auto-scroll is suppressed for a tap (the row is already visible) — the row-
    extent estimate is imperfect and was jumping the list to a different emote on
    every click ("click a sprite, it selects the one above"). The number badge
    is a `FittedBox`-scaled `CircleAvatar` so 3+ digit emote numbers (100+ casts)
    stay readable instead of being clipped by the circle. The **Sound (SoundN)**
    field is now a `_SoundField`: a TextField with a working **▾ picker** (an
    `IconButton` → `showMenu`) listing `AppState.availableSoundNames()` (names
    used by other emotes + the sfx guesses + bundled audio files by base name);
    free typing still allowed. (User reported the old plain field's neighbouring
    caret "did nothing" and wanted a sound picker.)
  - `button_studio`: **Button & Icon Studio** — 3-way framing (**Face** / **Full**
    / **Manual**), size, face zoom (0.25–4×), crop **Move X/Y** offsets (±100%),
    and **overlays** (a KFO-style border on top + a background) for **both**
    buttons and the char_icon. **Manual mode** (`_CropBoxEditor` + `_cropSliders`):
    drag the box / drag the corner to resize over the base sprite (loaded via
    `spriteEditorSource`, reloads on emote/`spriteRevision`), seeded from the
    sprite's own `headCropFor` (auto head-square). **The screen is laid out like
    the Emotes screen**: a left **`_ButtonSpriteList`** (a `Consumer`-driven
    `ListView` of every emote with a **tiny `_ButtonThumb`** — the **rendered
    button** via `previewButtonForEmote(e, 96)` so you see the framed result, not
    the raw sprite; lazy per visible row, reloads on `spriteRevision +
    buttonStyleRevision` — a pink tick on sprites that have a custom box, and
    auto-scroll to the keyboard-selected sprite) + the cards on the right wrapped
    in a `Selector<AppState,(int,int)>` on `(selectedEmote, spriteRevision)` so
    they rebuild when you pick a sprite. Clicking a row calls the screen's
    `_selectSprite` (→ `app.selectEmote`, then in Manual `arriveButtonCrop`
    (carry-forward when moving to a later sprite) + `notifyButtonSettings` so the
    box shows immediately, then reschedules the button preview). **Buttons are
    per-sprite**: the list (and a `_SpriteNav` ◀ ▶ "Sprite k of N" + "customised
    k/N" caption) step `app.selectEmote` through the cast so you can frame every
    pose by hand, writing each to `app.buttonCrops[sprite]` via `setButtonCrop`;
    advancing forward (Enter/→/▶/list) **carries your box** onto the next unframed
    sprite (`_gotoEmote`/`_selectSprite` compute `carryFrom` when `target >
    selectedEmote`, else `arriveButtonCrop` seeds its own face);
    `_ManualCropActions` offers **Reset this sprite to auto** (`resetButtonCropFor`)
    and **Apply this box to all sprites** (`applyButtonCropToAll`). The char_icon
    keeps its single
    `iconCrop`. In Manual the auto controls (face zoom, Move X/Y) are hidden —
    one positioning system at a time. `toPixels` clamps so a sloppy drag still
    yields a valid square. Every numeric setting is a `_ValueSlider` (a slider + a
    **typeable value box**, kept in sync: drag, or type an exact value committed
    on Enter/blur and clamped to range) — replaces the old slider-only helpers.
    Each overlay slot offers **Presets** (a grouped grid picker over
    `OverlayPresets` via `_showOverlayPresetPicker` — a `StatefulBuilder` so it
    can refresh; your **★ Saved** user presets list first with a delete ×, then
    the built-ins; cached thumbnails in `_overlayThumbCache`, saved presets build
    fresh via `useCache:false`), **Build…** (the `overlay_builder.dart` editor —
    style + colour-wheel + thickness/radius/inset, live preview, "start from" any
    preset), **Save** (when the slot holds an editable spec → `_promptPresetName`
    → `app.saveOverlayPreset`), and **Import…** (your own PNG). The applied
    `OverlaySpec` is remembered on the slot so Build…/Save re-use it. Icon
    "made from emote" picker + "Save char_icon.png".
    Debounced `ValueNotifier` previews; settings live on `AppState` so export uses
    them. **Buttons render crisp**: `renderFramed` never upscales and area-averages
    on downscale (PNG is lossless — sharpness is purely the resample).
    **Preview vs export resolution**: `_computeBtn`/`_computeIcon` render the
    on-screen preview at `max(size, CharFolder.buttonPreviewRenderPx)` — NOT the
    export size — so the 40px default still frames sharply on screen (the user
    saw a blown-up 40px preview as "crispy/low quality"); the exported file still
    uses `app.buttonSize`/`iconSize`. `previewCharIcon([int? size])` takes the
    preview size; `saveCharIcon` calls it with none → real `iconSize`.
    **KFO-style fast framing (Manual mode)**: the `_CropBoxEditor` takes a
    `height` (buttons pass **440** = a big canvas; icon stays 240), and the whole
    manual block is wrapped in a `Focus(focusNode:_kbFocus, autofocus, onKeyEvent:
    _onKey)` with a `Listener(onPointerDown→requestFocus)` on the canvas. `_onKey`
    reads the **rebindable** `app.framingKeys` (no hard-coded keys) — only when
    `_kbFocus.hasPrimaryFocus`, so a focused `_ValueSlider` box never triggers
    them. **Plain defaults** (no `[`/`]`): **← / →** prev/next sprite, **Enter**
    (numpad Enter too) "make & next" (boxes commit live, so advancing finishes the
    current one), **R** reset this sprite to auto, **A** apply box to all, **F**
    cycle Face→Full→Manual. `_manualHint()` builds its text **from** `framingKeys`
    via `keyLabel` so it can't go stale. Rebind/persist them in the F1 dialog
    (`app.dart`, `keyLabel`/`captureKey` from `ui/widgets/key_capture.dart`).
    Mirrored in docs/SHORTCUTS.md. Bare keys are safe — the only global shortcuts
    are Ctrl/⌘-modified + F1.
    **The BIG framing editor (DRO-style)**: a button in the Manual block opens
    `openButtonFramingEditor` → a full-screen `_ButtonFramingEditor` route (its
    own `Scaffold`) = sprite list + a large **zoom/pan** canvas + a control
    sidebar, so the sprite shows up big and you frame precisely. `_FramingPane`
    (the middle+right) wraps `_ManualCanvasLoader` (loads bytes, keeps the canvas
    **mounted** across sprite switches so zoom/pan persist) → `_ManualCanvas`. The
    canvas uses **one top-left coordinate origin**: a base-fit rect drawn at
    `_pan + base·_scale`, box overlaid at the same scale, and a **single**
    `GestureDetector` hit-tests in screen space (corner→resize / inside→move
    box / else→pan) so there's no gesture-arena ambiguity; `Listener`
    onPointerSignal scroll-zooms about the cursor; +/−/reset buttons + the **Box
    X/Y/Size sliders** (sidebar) are an **independent** path that works even if a
    drag feels off (the deliberate safety net — it's an untested gesture canvas).
    **Perf (no freeze on a big cast)**: during a box drag the canvas holds a
    **local `_live` box** — it re-renders only itself (cheap) and calls `onChanged`
    to write app state **without** rebuilding the pane; the heavy refresh (slider
    sync + debounced preview) runs **once** via `onCommit` on `onPanEnd`. The
    sprite list is a sibling `Consumer` (not rebuilt mid-drag) and uses the
    per-sprite `buttonThumbKey`, so a drag re-renders at most one thumbnail.
    Keyboard `_onKey` reads the same `framingKeys` (prev/next/make/reset/all; no
    F-cycle — the editor is Manual-only) and navigates via `navigateButtonFraming`.
    The sidebar also has the **button overlay controls** (`_OverlayControls` for
    `buttonFg`/`buttonBg` — Presets / Build… / Import…) so you can **add or build
    a KFO-style border without leaving the big editor**; the live preview shows it
    and the list thumbnails refresh via `_overlayRevision` (bumped in `setOverlay`,
    folded into `buttonThumbKey` since the per-sprite key only tracks whether an
    overlay is *set*, not which one).
  - `edit`: crop / **grow** / **resize** / auto-trim / background removal (drives
    `SpriteEdit`). Each of L/T/R/B is **one bidirectional slider** (`_sideControl`):
    >0 crops the edge in, <0 grows the canvas out (mapped to `crop*`/`pad*` in
    `_spec`), with **`−`/`+` stepper `IconButton`s** (`CropLimits.stepFraction` =
    1% nudges). **Resize the whole image** (`_resizeControls` + `_ResizeAxis`):
    per-axis **Width/Height** with a **slider + −/+ steppers + a typeable exact-px
    box** (each drives a scale factor → `_spec.scaleX/scaleY`), a **Lock aspect**
    toggle (ties the axes), and 25/50/100/150/200% quick buttons; `_origW/_origH`
    come from `AppState.currentSpriteSize()` so the px boxes are exact. A **This
    sprite / All sprites** `SegmentedButton` (`_applyAll`) drives one Apply button.
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
    **rebindable** — `AppState.nudgeKeys`, `_rebindDialog` + the shared
    `captureKey`/`KeyCaptureDialog` from `ui/widgets/key_capture.dart`),
    and **Preview** (the
    read-only `_ClientPreview` — real images + sample text in the theme's fonts).
    The Courtroom/Lobby selector (`_courtroomLobbyToggle` + `_modeCaption`, shared
    by Layout/Arrange) has icons + tooltips so each AO2 screen is obvious.
    Header: Import / New / Random / **size** button (presets 1080p/720p/AOHD +
    custom, optional proportional `Ao2Theme.resize`) / Export .zip. Edits commit
    on blur; `_rev` keys refresh fields after import/randomise. See
    docs/THEME_MAKER.md.
- `app.dart` (`HomeShell`) hosts a global `CallbackShortcuts` map (undo/redo,
  import, export `.zip` `Ctrl/⌘+S`, **save-as-folder `Ctrl/⌘+Shift+S` →
  `exportFolder`**, export `char.ini` `Ctrl/⌘+E`, add emote, prev/next emote,
  `Ctrl/⌘+1..9` screen jumps, F1 help) and a `_TopBar` with undo/redo + import +
  **save-as-folder (folder icon)** + export `.zip` + export `char.ini` +
  **Start-over ↻** (reset, gated on `hasProject`, confirm dialog → `resetProject`)
  + **About/credits** (ℹ) buttons (gated on
  `AppState.canUndo`/`canRedo`/`hasProject` via a `Selector`).
  **`_showShortcuts` (F1) is also the rebinding centre**: a `StatefulBuilder`
  dialog that lists the fixed global `Ctrl/⌘` shortcuts **and** offers a **Set**
  button per Button-Studio framing action (`AppState.framingActions`/`framingKeys`)
  and per Theme-Maker nudge direction, each via the shared `captureKey`; rebinds
  persist (see `settings_store`). Reset buttons restore the plain defaults. The nav
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
