# Roadmap

Legend: ✅ done · 🟡 partial · ⬜ planned

## Core engine
- ✅ Tolerant `char.ini` reader/writer with run-on-line repair
- ✅ Lossless `Character` model (preserves unknown sections/keys)
- ✅ Emotes, SoundN/T/L/B, Videos, OptionsN, Options2–5, Shouts, Time
- ✅ Frame effects (`_FrameSFX` / `_FrameRealization` / `_FrameScreenshake`)
- ✅ Validator / linter with suggested fixes
- ✅ Snapshot undo/redo
- ⬜ Per-emote `[Options*]` editing UI (model already preserves it)

## Automation
- ✅ Sprite scanner (a/b/c, statics, subfolders, preanims, extension priority)
- ✅ Auto character builder (names, preanim detection, sound guesses)
- ✅ Organizer (folders, file copy/move, auto buttons, ini)
- ✅ Auto `char_icon.png` generation (head/face framing, size 40–128, choose the
  source emote, optional border/background overlay)
- ✅ **⚡ One-click character** (`autoMagicExport`) — folder/project → ini +
  buttons + char_icon → exported `.zip`, in one action (WebP convert is opt-in:
  forcing it via native FFI was hard-crashing, see PERFORMANCE/FAQ)
- ✅ **Manual button/icon crop** (`CropFraming.manual` + `CropBox`) — KFO/DRO-style
  draggable/resizable crop box + X/Y/Size sliders, seeded from the auto head-square.
  **Per-sprite**: buttons keep one box *per sprite* (`AppState.buttonCrops`,
  keyed by sprite base) with an **Emotes-style sprite list** (tiny per-sprite
  preview of the **rendered button**, click any pose; a ◀ ▶ navigator too), a
  "k of N customised" caption, **Reset this sprite to auto** + **Apply this box to
  all sprites**; untouched sprites auto-frame their own face, so you only
  hand-place the poses the auto crop gets wrong. **Advancing carries your framing
  forward** (`arriveButtonCrop`) so pressing Enter/→ keeps your box instead of
  re-detecting the next sprite's face. **Keyboard-driven, KFO-style**: a big
  framing canvas + a plain single-key flow (defaults **← / →** prev/next,
  **Enter** make-&-next, **R** reset, **A** apply-all, **F** cycle framing — no
  `[`/`]`) so you frame a 100-sprite cast without reaching for the rail. **Every
  framing key (and the Theme-Maker Arrange nudge keys) is rebindable from the F1
  dialog and persists across sessions** (`AppState.framingKeys`/`nudgeKeys` →
  `platform/settings_store`). **DRO-style BIG framing editor**
  (`openButtonFramingEditor` → full-screen route): large **zoom + pan** canvas
  (single-GestureDetector hit-test over a one-origin Transform-free layout, scroll
  to zoom about the cursor) + sprite list + box sliders as an independent safety
  net, so the sprite shows up big and you frame precisely
- ✅ **Save as a plain folder (no zip)** (`AppState.exportFolder` →
  `platform/folder_export` seam) — writes the finished character folder straight
  to a picked directory so it just *appears* on disk (DRO/KFO-style), `Ctrl/⌘
  +Shift+S` / toolbar folder icon; web has no filesystem so it falls back to the
  `.zip`. Sits alongside `exportZip`/`exportIni`
- ✅ **`pinselcredits.txt`** stamped into every exported character (attribution +
  bug-report URL), written by the Organizer (single + bulk)
- ⬜ Auto `credits.txt` scaffolding

## Imaging & colour
- ✅ Decode webp/apng/gif/png (+ jpg/bmp/tga/tiff/…)
- ✅ ~25 composable colour ops + pipeline
- ✅ Hundreds of presets / palettes / gradients
- ✅ Region/outfit editor (magic wand, masks, feather, recolour/erase/fill)
- ✅ 43 colour ops incl. split-tone, vignette, scanlines, grain, chroma shift,
  pixelate, solarize, dither, cross-process, bleach-bypass, sharpen, blur
- ✅ Custom colour wheel/picker → recolour / tint / solid / gradient (blendable)
- ✅ Crop, **grow**, **resize** (width/height — slider + −/+ + typeable px box,
  lock-aspect; `SpriteEditSpec.scaleX/scaleY` → `SpriteEdit.resize`), auto-trim &
  background removal (frame-aware; uniform across (a)/(b))
- ✅ Sprite compositor / mixer (snip + stack layers; head-on-body) with a
  two-folder workflow (load a 2nd character's folder to graft parts from),
  **multiple snips at once**, **mouse drag/scale/rotate**, and a **Layers mode**
  that links separated part-files (eyes/brows/body/…) into one sprite
- ✅ Bulk recolour, convert, crop/trim & rename (recolour/edit re-encode WebP
  sprites in place — no more phantom `.apng` that left the original untouched)
- ✅ WebP encode: web (canvas) + native (libwebp via FFI), bundled in CI builds
- ✅ Animated WebP export (native via libwebpmux); **WebP is the default output**,
  auto-falling back to APNG where WebP isn't available (web build, or native
  without libwebpmux) — and the fallback now **reports why** (no more silent APNG)
- ✅ Bulk "animate all sprites" — one effect stack baked onto every sprite at
  once, each saved as an animated WebP `(b)` talk sprite (`bulkAnimateAll`),
  rendered+encoded **off the UI isolate** (`compute`) and **across all CPU cores**
  (`mapParallel`), while staying **lossless** (no quality loss)
- ✅ **Multi-core baking** — `imaging/parallel.dart` windowed scheduler runs up to
  `maxConcurrency` (`min(cores,8)`) encode jobs at once; "Use all CPU cores"
  toggle on Home (see docs/PERFORMANCE.md)
- ✅ Update an existing character — **Add sprites / Add sprite folder**
  (`addSprites`) appends an emote per *new* sprite group without touching the
  existing ini, emotes or edits
- ✅ **Sprite sheet ripper** (`imaging/sprite_sheet.dart`) — auto-detect
  (border-background flood + connected components), uniform grid, or **manual**
  (draw/move/resize/delete your own boxes); tap-to-toggle, background removal,
  add-to-character or zip
- ✅ **AO2 Theme Maker** (`theme/`) — full client theme editor: drag widgets in a
  live courtroom (real art, **labelled + tooltipped** boxes, **snap-to-grid**,
  **rebindable arrow-key nudge**), edit every position/colour/font/image/sound/
  CSS/scalar, **resize** to 1080p/720p/custom (proportional `resize`), a
  **real-client preview**, import a real theme, random palette generator, lossless
  `.zip` export for `base/themes/`
- ✅ `scripts/build_all.ps1` bundles the libwebp DLLs into local Windows builds
  too (best-effort via vcpkg), so a locally-built app gets working animated WebP
- 🟡 GPU real-time preview — ✅ exact colour-**matrix** path on the compositor
  (`ColorMatrix`/`liveColorMatrix`; brightness/contrast/exposure/invert/grayscale/
  sepia/temperature/tint/solid/opacity), with a CPU fallback for HSV/curve/spatial
  ops; ⬜ fragment-shader path to cover the non-linear ops too
- ⬜ Palette-swap (exact indexed remap) op
- ✅ Outline / drop-shadow / glow image ops (spatial ops that draw into the halo)

## Animation
- ✅ ~88 stackable recipes with easing (incl. outline/glow/shadow effect recipes)
- ✅ **Frame-by-frame** assembler (pick/reorder existing sprites → one animation;
  fps, reverse, ping-pong, canvas alignment)
- ✅ Region-targeted animation (wave a hand, spin a limb)
- ✅ Manual keyframe timeline
- ✅ Lip-sync / **talking mouths** — the **Mouth** tab fakes a natural, looping
  talking `(b)` from ONE drawing (`LipSync.talk`, face-placed adjustable mouth box
  + live preview), plus two-state/multi-viseme for real mouth art; **all-sprites**
  variant baked across cores (`bulkMouthTalkAll`) — see docs/LIPSYNC.md
- ✅ **VN talk styles** — hundreds of named "ways of talking" (`TalkStyle` /
  `LipSync.styleCatalogue`: Calm/Energetic/Loud/Soft/Emotional/Stylised, ~60
  archetypes × {base,Soft,Intense,Fast,Slow}) with a searchable picker in the
  Mouth tab; `LipSync.talkStyled` bakes a seamless VN-style loop (speech-like
  syllabic cadence + pauses + subtle head bob) onto any static sprite
- ✅ **Real open/close mouth + anime mouth presets + mesh** — the lips actually
  part (feathered cavity, not a stretched chin); ~112 drawn **anime mouth shapes**
  (`LipSync.mouthShapes`); and a **mesh** path (`cutMouthPiece` + `talkMeshed`)
  that cuts a real open mouth from another sprite and blends it in. Auto/Anime/
  Mesh toggle in the Mouth tab; a **drag/resize box** on the live preview
- ✅ **Jiggle physics** — bounce any region (chest/body/hair) in **any direction**
  with amount/speed/bounciness/squash/sway (`JiggleSpec` + the `jigglePhysics`
  recipe; ~140 presets), a draggable box, preview + Save as `(a)` idle +
  all-sprites — see docs/JIGGLE.md
- ✅ **Soft-body jiggle warp + twin lobes** — `jigglePhysics` now renders as a
  **per-pixel feathered/anchored displacement warp** (`AnimEngine.warpJiggle`)
  instead of a sliding cut-out rectangle (the "looks like a cropped PNG" fix), and
  **`twin`** splits a box into two opposite-phase lobes (the **Bust**/"boobs"
  presets) — i.e. multiple regions per box
- ✅ **Pro soft-body jiggle realism** — `anchor` (pinned point), `gravity`
  (asymmetric weighty fall), `organic` (natural harmonic), `followThrough` (tip
  lags base = the jiggle ripples through the flesh as a wave), and **`lobes`** N
  (a UI slider; generalises twin) with `spread`. All loop-seamless, all neutral
  by default. Premium **Bust** + **Physics** presets; sliders in the Jiggle tab
- ✅ **Smeary/blocky jiggle fix** — radial (elliptical) influence mask instead of
  a box (no rectangular edge), and the bounce is mostly a uniform translation of
  the mass with low shear (so the art stays crisp instead of melting).
- ✅ **Multiple jiggle boxes + sprite picker** — the Jiggle tab holds a list of
  boxes (Add/select/Remove chips; active = editable, others = outlines; every box
  bounces with its own settings) and a sprite dropdown to jiggle any sprite.
- ✅ **Freeform "draw-around" jiggle region** — a lasso in the Jiggle tab traces a
  polygon (`JiggleSpec.poly` / `AnimRecipe.poly`); `warpJiggle` masks to that exact
  shape with a feathered edge (inside + edges jiggle, blends into the body). Tested.
- ✅ **Mobile crash/lag fix** — bulk render concurrency capped to 2 on Android/iOS
  (`maxConcurrency`) so a big bulk job (e.g. ~500 sprites) doesn't OOM-kill the app
  or starve the UI on a phone/tablet.
- ✅ **Ripper zoom** — `InteractiveViewer` pinch/wheel zoom + pan on the sheet
  canvas (pan off in Manual mode where drag draws boxes).
- ✅ **Button/icon crop shapes (engine)** — `imaging/crop_shape.dart`: circle /
  rounded / polygon / star / heart presets + an AA `mask(size)`; `renderFramed`
  clips a button to the shape (real round buttons, transparent corners) behind a
  clip toggle. ⬜ Next: the Button Studio shape-picker UI + custom generator +
  import-PNG-as-mask + `AppState` wiring
- ⬜ Onion-skinning + scrubbable timeline UI
- ⬜ Per-frame SFX/realization/screenshake authoring UI (model supports it)

## Plugins & sharing
- ✅ JSON content packs (presets/palettes/gradients/animations/name sets)
- ✅ Pack install/remove (works on web)
- ✅ Native code hooks (ops/recipes/easings)
- ⬜ Pack browser / online registry
- ⬜ Export current project's custom presets as a pack

## Platforms
- ✅ Single codebase: Windows / Linux / macOS / Android / iOS / Web
- ✅ In-memory workspace + zip export for uniform behaviour
- ✅ Folder import on every platform (native dir dialog / web `webkitdirectory`)
- 🟡 Direct folder write on desktop (currently zip export; folder write planned)
- ⬜ Android SAF / `MANAGE_EXTERNAL_STORAGE` flow for in-place folder editing
- ⬜ Recent projects / autosave

## UI polish
- ✅ Button & Icon Studio: head/face vs full-body framing (face default), size
  (**defaults to the classic 40×40** so the theme shows it 1:1 = crisp in-game;
  the on-screen preview renders larger so small buttons still frame sharply),
  zoom, crop-position offsets, and **image overlays** (KFO-style borders +
  backgrounds) for both buttons and the char_icon
- ✅ **Edit screen grows as well as crops**: each side is one bidirectional
  slider (crop in / pad out with transparency) with `−`/`+` 1% steppers, plus a
  This-sprite / All-sprites toggle
- ✅ **Emotes sound picker**: the Sound (SoundN) field has a working ▾ that lists
  used names + sfx guesses + bundled audio files (free typing still allowed)
- ✅ Dedicated **char.ini builder** screen (the full `[Options]` block: name,
  showname, blips, chat, side, category, scaling, …)
- ✅ About / credits (maintainer + repo) in the toolbar and on Home
- ✅ Performance: lazy active-screen build, decoupled/debounced previews
  (incl. the Mixer), cached chip lists, smooth (non-pixelated) scaling
- ✅ Performance: field editing (Emotes/Character) is no longer re-rendered per
  keystroke — it commits on blur, and the preview is cached per sprite revision
- ✅ Emote list fixes for big casts: tapping a row no longer auto-scrolls the
  list and selects the wrong (upper) emote (tap syncs `_lastSelected`); the
  number badge scales to fit so 3+ digit emote numbers (100+ sprites) aren't
  clipped
- ✅ Performance: allocation-free per-pixel op core (sequential pixel cursor),
  bulk/recolour/edit loops yield so the UI stays responsive
- ✅ Keyboard shortcuts (undo/redo, import/export, screen jumps, F1 help) + a
  top toolbar with undo/redo + quick actions
- ✅ Mixer tools: snip-crop/ellipse, flip H/V, feather, recolour the snip,
  output crop, center/reset
- 🟡 Home, Character (char.ini), Editor, Colour Lab, Animate, Buttons, Edit,
  Mixer, Bulk, Plugins screens
- 🟡 App icon: `flutter_launcher_icons` pipeline wired (`assets/icon/app_icon.png`,
  `dart run flutter_launcher_icons`) — placeholder art, swap in the Pinsel mascot
- ⬜ Drag-and-drop import
- ⬜ Move heavy bakes (bulk/animation export) into isolates
- ✅ Button overlay/border + background system (auto buttons + char_icon): **dozens
  of built-in presets** (Umineko, Danganronpa, Limbus, kawaii, colours) **and an
  in-app builder** (editable `OverlaySpec`: style + colour-wheel + gradients +
  thickness/radius/inset, live preview, start-from-preset). **Save your own built
  overlays as reusable presets** (`OverlaySpec.toJson` → `AppState.userOverlayPresets`
  via `settings_store`; shown under **★ Saved** in the picker, persist across sessions)
- ✅ **Per-sprite button overlays** — putting a border/background on a button
  affects only **that sprite** by default (`buttonFgBySprite`/`buttonBgBySprite`,
  mirrors per-sprite crops), with an **"Apply to all sprites"** action; the
  char_icon keeps its own single overlay
- ⬜ Full mask/crop button compositor UI (engine: `ButtonMaker.renderComposite`)
- 🟡 Region picker overlay (drag a box) — done in the Mixer (snip/arrange canvas);
  still planned for region animation/outfit edits
- ⬜ Theming / accessibility pass
