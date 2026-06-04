# 🐾 Pinsel AO Char Maker

**The most customizable, most automated Attorney Online / webAO character & button maker — on every platform from one codebase.**

Drop in a folder of sprites → get a finished, AO2- **and** webAO-compatible
character: an auto-generated `char.ini`, the right folder layout, and
auto-generated emote buttons. Then recolour, animate, lip-sync, and customise
everything — or don't, because every powerful feature has a sensible default.

Runs natively on **Windows, Linux, macOS, Android, iOS**, and as a **website**
(Flutter Web) so people can use and share it straight from a browser.

> Built from scratch with [KFO-CharMaker](https://github.com/Crystalwarrior/KFO-CharMaker) and
> [DROButtonMaker](https://github.com/Chrezm/DROButtonMaker) as inspiration —
> aiming to be vastly more expansive than both. Format details were verified
> against the official AO docs and the AO2 reference client. AGPL-3.0.

---

## ✨ What it does

### Automate everything (optional)
- **⚡ One-click character.** The headline shortcut: pick a folder and get a
  ready-to-drop `.zip` — auto `char.ini`, sprites converted to **WebP**, emote
  **buttons** + **char_icon**, all in one go. (Already have a project open?
  **Finish & export everything** does the same without re-importing.)
  ([docs](docs/ONE_CLICK.md))
- **Folder → character.** Scans a folder of images, detects `(a)`/`(b)`/`(c)`
  idle/talk/post sprites, static sprites, sub-folder sprites, preanimations, and
  animation formats — then writes a correct `char.ini`, **named after the folder**.
  **Import starts fresh** (it clears the previous project — no more old emotes
  sneaking back in), and **Start over** wipes everything when you want a clean slate.
- **Update an existing character.** Already have a character (or one you
  imported)? **Add sprites / Add sprite folder** drops new images straight in and
  turns each new sprite into a new emote — keeping your existing `char.ini`,
  emotes and edits. Grow a character instead of rebuilding it. Trim a big cast
  fast with **multi-select** in the Emotes tab (tick rows → delete many at once).
- **Auto folders + file moving.** Builds the character folder, an `emotions/`
  folder, and lays everything out the way AO expects.
- **Auto buttons + char_icon.** Generates `buttonN_off.png` for every emote
  **and** the character-select `char_icon.png`. They frame the character's
  **face by default** (AO buttons show expressions, not whole bodies); switch to
  full-body, tune the size/zoom/position, or lay a **border on top** (KFO-style)
  — import your own, pick from **dozens of built-in border & background presets**
  (Umineko, Danganronpa, Limbus, kawaii pastels, hearts/sparkles, and a big colour
  palette), *or* **build your own in-app** (style + **colour-wheel** + gradients +
  thickness/radius, with a live preview — start from any preset and tweak it). Rendered **crisp** (lossless PNG, never upscaled). Drop your
  own button in to override.
- **Smart guesses.** Friendly emote names, preanimation detection, and optional
  sound-effect guesses (keyword → SFX, e.g. *slam* → desk-slam) — all adjustable.

### Customize everything
- **Real-time Colour Lab** — hue / saturation / brightness / contrast with live
  preview, plus **hundreds of presets**, palettes, gradient maps, and
  "Make it `<colour>`" recolours that **preserve shading** (perfect for OCs —
  turn a sprite pink without flattening it).
- **Custom colour wheel** — pick *any* colour (wheel / area / sliders / hex) and
  blend it in as a recolour, tint, solid fill, or gradient — stack as many as
  you like on top of the presets.
- **Effects** — add an **outline**, **outer glow** or **drop shadow** around a
  sprite, **sharpen**/**blur**, or film looks (cross-process, bleach-bypass,
  solarize, dither) — all blendable like any other preset.
- **Region / outfit editing** — magic-wand colour selection, rectangle/ellipse
  masks, feathering, grow/shrink; then recolour just the clothes, erase a
  region, or paint a fill.
- **Crop, auto-trim & background removal** — crop sprites (uniform across all
  frames + (a)/(b)), trim transparent margins, or knock out a flat background by
  flood-filling from the corners.
- **Full char.ini editor** — a dedicated **Character** tab for the `[Options]`
  block: name, showname, `needs_showname`, side, **blips**, **chat**, category,
  scaling, stretch, and more. The auto-builder fills defaults; tweak any of them
  here (imported custom keys are preserved).
- **Sprite mixer ("frankensprite")** — **mouse-driven**: drag parts to move,
  drag a corner / scroll to scale, drag a handle to rotate (sliders too). Snip a
  region from one sprite (e.g. a head) and drop it onto a body — **stack as many
  snips as you want** — then save it as a new emote. Combine **two characters**
  by loading a **second sprite folder** in the Mixer (kept out of your project +
  export). A **Layers** mode "links everything" for art that ships each feature
  as a separate, pre-aligned file (eyes, brows, body, an arm…). Tools: snip-crop
  + ellipse, **flip H/V**, **feather**, **recolour the snip**, **crop output**.
- **Bulk operations** — recolour, convert, **crop/trim**, or **rename** *every*
  sprite/emote at once (find/replace, prefix/suffix, numbering, case).
- **Format conversion** — import webp/apng/gif/png (and jpg/bmp/tga/tiff/…),
  export PNG/APNG/GIF, and **WebP (lossy + lossless)** — instantly in the web
  build, or via the bundled libwebp on desktop/mobile.

### Animate everything (so anyone can)
- **One-click animation recipes** — sway, bob, bounce, breathe, shake, spin,
  nod, head-shake, swing, drift, orbit, heartbeat, glow, flash, rainbow, pulse,
  neon, hologram, glitch, fade, throb, sparkle, drop-in, spring-in, outline-pulse,
  aura-glow… **stack them** ("move + glow + rainbow") with **easing curves**.
- **Frame-by-frame** — already drew the frames? The **Frames** mode stitches
  chosen sprites into one animation (fps, reverse, ping-pong, auto-aligned
  canvas) and exports it — no procedural effect required.
- **Animate ALL sprites at once** — one button bakes your effect stack onto
  *every* sprite, saving each as an animated WebP `(b)` talk sprite. Give a whole
  character the same idle sway/breathe in a single click. Baked across **all CPU
  cores**.
- **Animate just a part** — pick a region to wave a hand or spin a limb.
- **Talking mouths (lip-sync), zero extra art** — the **Mouth** tab fakes a
  natural, looping talking `(b)` animation from a *single* drawing: a face-placed
  mouth box drops the jaw with a speech-like cadence. **Preview it live and drag
  the box onto the lips**, tune the open amount/speed, then save — or give your
  **whole cast** talking mouths in one click. Already drew mouth shapes? Feed it a
  closed+open sprite (or several visemes) instead. ([docs](docs/LIPSYNC.md))
- **~88 stackable effects** and a **custom keyframe timeline** for full control.
- Exports as **animated WebP** by default (bundled libwebp on desktop/mobile;
  browser-native on web), auto-falling back to APNG where WebP isn't available —
  and the status line tells you *why* it fell back, so a stray APNG is fixable
  rather than a mystery.

### Rip & theme everything
- **Sprite sheet ripper** — drop in a sheet/collage of VN sprites and it slices
  out each one as a transparent sprite. **Auto-detect** any layout (it flood-fills
  the background inward from the edges, so even white-clothing-on-white works) or
  a **uniform grid**. Tap boxes to include/exclude, then **add them straight to
  your character** or download a zip. See
  [docs/SPRITE_RIPPER.md](docs/SPRITE_RIPPER.md).
- **AO2 Theme Maker** — design a full **Attorney Online 2 / webAO** client theme:
  every widget position (**drag them around the courtroom**), every colour, every
  font, every image (PNG/GIF/WebP), sounds and Qt CSS. **Import a real theme** to
  edit, **roll a random** one, **resize** to 1080p / 720p / any custom size
  (scaling the whole layout), see a **real-client preview** before you use it, then
  **export a `.zip`** ready for `base/themes/`. ~95 known widgets, a full image
  catalogue and every design option — all customizable, with lossless
  round-trips. See [docs/THEME_MAKER.md](docs/THEME_MAKER.md).

### Extend everything
- **Plugin packs** — plain JSON adding presets, palettes, gradients, animations
  and name sets. No install, no recompile, and they work on the **web** too.
- **Native code hooks** — register new colour ops, animation recipes, and easing
  curves.

### Never lose data
- The `char.ini` parser is **lossless**: unknown sections/keys are preserved,
  and it even **repairs** mangled run-on lines found in real-world inis.
- **Undo/redo** and a **validator/linter** that flags missing sprites, count
  mismatches, and preanim mistakes — with plain-language fixes.

### Fast & comfortable
- **Keyboard shortcuts** for everything — `Ctrl/⌘+Z`/`Y` undo/redo, `Ctrl/⌘+S/E`
  export, `Ctrl/⌘+1…9` to jump screens, `F1` for the cheat-sheet — plus a top
  **toolbar** with undo/redo + import/export buttons. See
  [docs/SHORTCUTS.md](docs/SHORTCUTS.md).
- **Tuned for speed** — an allocation-free per-pixel core, downscaled/debounced
  live previews, and bulk jobs that keep the UI responsive (progress instead of
  a freeze). Editing fields (Emotes, Character) writes to the model and commits
  on blur — **no per-keystroke re-render**, so typing stays smooth even with a
  big sprite in the preview.

---

## 🚀 Quick start

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install)
(3.22+). The platform project folders are generated on first run.

```bash
# 1. Get the code
cd Pinsel-AO-Char-Maker

# 2. Generate the platform folders (android/ios/linux/macos/windows/web)
flutter create .

# 3. Install dependencies
flutter pub get

# 4. Run it
flutter run -d windows      # or linux / macos / chrome / <android|ios device>
```

**Make the website:**
```bash
flutter build web --release
# Serve build/web/ from any static host (GitHub Pages, Netlify, itch.io, …)
```

See **[docs/BUILD_AND_RUN.md](docs/BUILD_AND_RUN.md)** for per-platform details
(Android/iOS signing, native libwebp, web hosting).

---

## ⬇️ Prebuilt binaries FOR DOWNLOADS. (let GitHub build them)

You don't need to compile anything yourself — GitHub Actions does it for every
platform via [`.github/workflows/build.yml`](.github/workflows/build.yml).

**For the download links, Open the *Actions* tab → the latest "Build binaries" run.** Each platform's
   output is under **Artifacts** (`pinsel-windows`, `-linux`, `-macos`,
   `-android-apk`, `-web`). Download and unzip.

> Builds run **independently of the tests**, so you still get binaries even if a
> test fails. iOS isn't auto-built (it needs your signing certificate); build it
> locally with `flutter build ios`.

## 📖 Documentation

| Doc | What's inside |
|-----|---------------|
| [docs/USER_GUIDE.md](docs/USER_GUIDE.md) | **Click-by-click guide to every feature (start here)** |
| [docs/BUILD_AND_RUN.md](docs/BUILD_AND_RUN.md) | Build & run on every platform + the web |
| [docs/WEBSITE.md](docs/WEBSITE.md) | Host it as a website (GitHub Pages, Netlify, …) |
| [docs/CHAR_INI_FORMAT.md](docs/CHAR_INI_FORMAT.md) | Complete AO `char.ini` reference |
| [docs/AUTO_BUILD.md](docs/AUTO_BUILD.md) | How folder → character works |
| [docs/ONE_CLICK.md](docs/ONE_CLICK.md) | ⚡ One-click: folder → finished, exported character |
| [docs/COLOR_OPS.md](docs/COLOR_OPS.md) | Every colour operation + parameters |
| [docs/ANIMATION.md](docs/ANIMATION.md) | Recipes, easing, timeline, lip-sync, regions |
| [docs/LIPSYNC.md](docs/LIPSYNC.md) | Talking mouths from one drawing (preview + adjust) |
| [docs/PERFORMANCE.md](docs/PERFORMANCE.md) | GPU previews + multi-core baking |
| [docs/MIXER.md](docs/MIXER.md) | Snip, stack & link sprites (mouse-driven; multi-snip + layers) |
| [docs/SPRITE_RIPPER.md](docs/SPRITE_RIPPER.md) | Slice sprite sheets into sprites (auto-detect / grid) |
| [docs/THEME_MAKER.md](docs/THEME_MAKER.md) | Design & export an AO2 client theme (drag layout, random, custom images) |
| [docs/SHORTCUTS.md](docs/SHORTCUTS.md) | Keyboard shortcuts + the top toolbar |
| [docs/PLUGINS.md](docs/PLUGINS.md) | Pack JSON schema + native plugins + libwebp |
| [ARCHITECTURE.md](ARCHITECTURE.md) | How the code is organised |
| [ROADMAP.md](ROADMAP.md) | What's done and what's next |
| [docs/FAQ.md](docs/FAQ.md) | Common questions & troubleshooting |

The source is documented heavily — almost every public type and method has a
doc comment explaining what it does and why.

---

## 🧭 Status

This is **v0.1** — a deep, tested engine plus a working cross-platform UI. The
core (INI model, scanner/auto-builder, organiser, image/colour engine,
animation engine, presets, plugins) is complete and unit-tested. Some UI screens
are first-pass and the roadmap lists what's growing next. See
[ROADMAP.md](ROADMAP.md).

## 📜 License

AGPL-3.0. See [LICENSE](LICENSE). Credit to the Attorney Online dev team and the
authors of KFO-CharMaker and DROButtonMaker for format references and
inspiration.
