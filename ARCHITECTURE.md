# Architecture

Pinsel is split into a **pure-Dart engine** (no Flutter imports, fully
unit-testable, identical on every platform) and a thin **Flutter UI** on top.
The same engine runs on desktop, mobile, and the web — only file access and a
couple of codecs differ, and those are hidden behind platform abstractions.

```
lib/
  main.dart                     app entry (wires AppState + PinselApp)
  src/
    core/                       ── the AO data model (no Flutter, no dart:io) ──
      ao_constants.dart         every AO constant: extensions, prefixes,
                                modifiers, deskmods, sides, sections, timing…
      ao_ini.dart               tolerant INI reader/writer (+ run-on repair)
      emote.dart                one emote line  (comment#pre#sprite#mod#desk)
      frame_effect.dart         [<sprite>_FrameSFX/Realization/Screenshake]
      character.dart            lossless Character model: parse() / serialize()
      validator.dart            linter → friendly issues + suggested fixes
      history.dart              snapshot-based undo/redo

    discovery/                  ── folder → character automation ──
      sprite_scanner.dart       classify files (pure fromPaths + scanDirectory)
      character_builder.dart    ScanResult → Character (auto ini, smart names)
      organizer.dart            plan + execute folders / moves / buttons + char_icon
      bulk_rename.dart          name transformer (find/replace, numbering, case)

    imaging/                    ── the image & colour engine ──
      codecs.dart               decode anything; encode png/apng/gif
      color_ops.dart            43 composable colour ops (ColorOp/OpPipeline)
      region_edit.dart          masks + magic-wand + recolour/erase/fill + bg removal
      sprite_edit.dart          crop / auto-trim / background removal (frame-aware)
      compositor.dart           snip + stack/centre layers (frankensprite mixer:
                                multi-snip, mouse, link-layers)
      button_maker.dart         buttons + char_icon: head/face vs full framing
                                (silhouette head crop), zoom/offset, overlays
      overlay_presets.dart      editable button/icon borders + backgrounds
                                (OverlaySpec/OverlayStyle; procedural presets:
                                Umineko/Danganronpa/Limbus/Kawaii/Colours…)
      bulk_processor.dart       apply pipeline / convert across many files
      sprite_sheet.dart         rip a sheet into sprites (bg flood + components / grid)
      webp_codec.dart           WebP encode interface (lossy + lossless, animated)
      webp_codec_io.dart          native: libwebp + libwebpmux via dart:ffi
      webp_codec_web.dart         web: browser canvas encoder

    animation/                  ── the animation engine ──
      anim_clip.dart            frames → encodable animated WebP (APNG/GIF fallback)
      easing.dart               easing curves (+ registry)
      anim_engine.dart          stackable recipes + region layers + render
      timeline.dart             manual keyframe interpolation
      lipsync.dart              talking-sprite generation

    puppet/                     ── Live2D-style cut-out puppet (bakes to sprites) ──
      puppet.dart               assemble part layers → animated AO sprite (idle +
                                talk); reuses the ripper + animation engine

    theme/                      ── AO2 client theme maker ──
      ao2_theme.dart            theme model + parse/serialise (lossless) + export
      ao2_theme_defaults.dart   widget/colour/font/scalar/image catalogues
      theme_randomizer.dart     cohesive random palette generator

    presets/
      presets.dart              hundreds of generated + curated presets

    plugins/
      pack.dart                 JSON content-pack model (de)serialisation
      extension_registry.dart   merges built-ins + packs; native code hooks

    platform/                   ── platform seams (conditional imports) ──
      workspace.dart            Workspace interface + MemoryWorkspace
      io_workspace.dart           native filesystem
      web_workspace.dart          web (in-memory)
      workspace_factory.dart      picks the right one at compile time
      save_file.dart / _io / _web  save (native dialog) vs download (web)
      folder_picker.* (io/web)    pick a whole folder (dir dialog / webkitdirectory)

    ui/
      app_state.dart            ChangeNotifier hub the screens talk to
      theme.dart
      credits.dart              About dialog + Home credits card (maintainer/repo)
      widgets/                  checker_image, zoom_canvas, overlay_builder
                                (custom border/background editor + colour wheel)
      screens/                  home, ini_builder (char.ini Options editor),
                                editor, color_lab, animation_studio,
                                button_studio, edit, mixer, bulk, plugins,
                                sprite_ripper (sheet → sprites),
                                theme_maker (AO2 theme editor, draggable layout),
                                puppet_studio (parts → animated AO sprite)
    app.dart                    HomeShell: nav rail + global keyboard shortcuts
                                (CallbackShortcuts) + undo/redo + About toolbar + status
```

**Performance.** The per-pixel op core (`ImageOps._eachPixel`) walks the frame's
sequential pixel cursor and reuses one struct (no per-pixel random access or
allocation); live previews (Colour Lab, Edit, Mixer, Button Studio) run
**downscaled and debounced**; field editing (Emotes, Character) writes to the
model and **commits on blur** rather than notifying per keystroke, and the
sprite preview is cached per `spriteRevision`, so typing never re-bakes it; and
the long bake loops (`applyPipeline`/`applyEdit`/`BulkProcessor.run`) yield to
the event loop so progress repaints instead of the window freezing.

## Key design decisions

**One serializable model drives many features.** A `ColorOp` (and a list of
them, `OpPipeline`) is used for the live preview, bulk processing, saved
presets, *and* plugin packs. Likewise an `AnimRecipe` powers one-click effects,
stacking, presets, and packs. Because they (de)serialise to JSON, plugins are
just data — which is why they work on the web with no native code.

**Lossless, tolerant `char.ini` handling.** `Character` models the fields it
understands and **preserves everything else verbatim** (`[Options]` extras,
`[Options2..5]`, `[Shouts]`, `[Time]`, unknown sections). The low-level reader
even repairs corrupted run-on numeric lines seen in real files.

**Platform seams, not platform forks.** `Workspace` abstracts file access;
`createLocalWorkspace`, `saveBytes`, and `makeWebpEncoder` are selected by
conditional import (`dart:io` vs `dart:html`). The UI and engine never branch on
platform.

**Everything pure where possible.** The scanner exposes a pure `fromPaths`, the
engine never imports Flutter, and the heavy logic is unit-tested. The UI is a
straightforward `provider` + `ChangeNotifier` layer.

## Data flow (typical session)

```
import files ─► MemoryWorkspace
             ─► SpriteScanner.fromPaths ─► ScanResult
             ─► CharacterBuilder.build  ─► Character  (or parse existing char.ini)
edit / recolour / animate (mutating Character + workspace bytes, with undo/redo)
export ─► Organizer (folders + buttons + char_icon + ini) ─► zip ─► saveBytes/download
```
