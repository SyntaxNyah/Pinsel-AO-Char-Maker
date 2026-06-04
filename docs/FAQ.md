# FAQ & troubleshooting

**Is the output really AO-compatible?**
Yes — Pinsel writes the same `char.ini` format and sprite/button layout the
AO2 reference client and webAO read. The parser/writer are unit-tested against
real-world inis, and the format was verified against the official docs and AO2
source. See [CHAR_INI_FORMAT.md](CHAR_INI_FORMAT.md).

**Will it wreck my existing char.ini?**
No. The model is lossless — unknown sections and keys are preserved, and the
reader even repairs corrupted run-on lines. Re-opening and re-saving a character
keeps everything it doesn't understand.

**What image formats can I import?**
webp, apng, gif, png, plus jpg/jpeg, bmp, tga, tiff, ico, pnm, psd, exr, and
more. Output is PNG/APNG/GIF everywhere, and WebP (lossy + lossless) on the web
build or with libwebp on native.

**Why is WebP export unavailable on my desktop build?**
Pure-Dart can't encode WebP yet, so native builds use `libwebp` via FFI. Install
or bundle it (see [PLUGINS.md](PLUGINS.md#native-libwebp)). The **web** build
encodes WebP with the browser's own codec, no setup needed.

**Animated WebP**
WebP (including **animated** WebP) is the default export. Native builds produce
animated WebP via `libwebpmux`; if it (or libwebp) isn't present, or you're on
the web build, the tool **automatically falls back to APNG** so you always get a
working animated sprite — and the status line now tells you **why** it fell back
(e.g. "libwebpmux not found"), so a stray APNG is fixable instead of a mystery.
To guarantee WebP on desktop, ship the DLLs next to the `.exe`: the CI release
artifact already does, and `scripts/build_all.ps1` bundles them into local
Windows builds too (best-effort, via vcpkg). See
[PLUGINS.md](PLUGINS.md#native-libwebp) to install/bundle libwebp + libwebpmux.

**My animation keeps exporting as APNG, not WebP — why?**
WebP encoding needs the native `libwebp` **and** `libwebpmux` libraries loaded at
runtime. The most common cause is running a build that doesn't have them next to
the executable — e.g. a plain `flutter run` (debug) or a hand-built Release that
skipped the bundling step. Fixes: use the **web** build (WebP always works
there), grab a **CI release artifact**, or run `scripts/build_all.ps1` (which
bundles the DLLs via vcpkg). The save status line names the exact reason for the
fallback, so check it after saving.

**How do I recolour just the clothes / hair?**
Use the region editor: magic-wand select the colour, feather it, then apply a
`colorize`/`hueShift` pipeline through the mask. See
[COLOR_OPS.md](COLOR_OPS.md#region--outfit-editing).

**How do I crop a sprite or remove its background?**
Open the **Edit** tab: toggle **Auto-trim**, **Remove background** (corner flood
fill, with a tolerance slider), and/or drag the **crop** sliders, then **Apply**
(this emote) or **All sprites**. Crop/trim stay aligned across all frames and an
emote's (a)/(b)/(c).

**How do I pick a custom colour (not just presets)?**
In the **Colour Lab**, tap **Pick colour…** for the colour wheel, then blend it
in as Recolour / Tint / Solid / Gradient. They stack with the presets and
sliders.

**Can I import a whole folder?**
Yes — **Home → Import folder**. On desktop/mobile it's a directory picker; on the
website it's a folder upload. Sub-folder structure is preserved, and an existing
`char.ini` in the folder is loaded as-is.

**How do I put one character's head on another's body?**
Open the **Mixer**. Your **body** is a sprite from the loaded project; for the
head, click **Load a 2nd sprite folder…** and dump the other character's folder
in — it's added as a "parts" source you can snip from, but stays out of your
project and export. Add a snip, frame it (drag the box in **Snip** mode), then
**drag it into place** on the canvas in **Arrange** mode (corner = scale, scroll
= scale, round handle = rotate) and **Save as new emote**. You can add **several
snips** (head + hat + accessory). See [MIXER.md](MIXER.md).

**My character is split into separate part files (eyes, brows, body, an arm…) —
how do I combine them?**
Open the **Mixer → Layers** mode. **Load a sprite folder** of the parts, click
**Add all**, and they stack into one finished sprite at their native positions
(no cropping or positioning needed). Reorder/hide/fade per layer, then **Combine
& save as new emote**. See [MIXER.md](MIXER.md#layers--for-art-where-everything-is-separated).

**What does "Guess sound effects" do?**
It's an auto-build helper. When on, the builder scans each emote's name for
keywords (e.g. *slam*, *point*, *object*, *shout*) and fills in a matching
`SoundN` sound effect (and sets the emote to play its preanimation). Off = it
leaves sounds blank for you to set in the **Emotes** tab.

**My buttons show the whole body — can they just show the face?**
They already do by default. Buttons (and the `char_icon`) frame the character's
**head/face** (detected from the silhouette). The **Buttons** tab framing picker
has **Face**, **Full** (whole sprite) and **Manual** — plus **Face zoom** and
**Move X/Y** to fine-tune the auto crop.

**Can I crop the button myself instead of the auto-detect (like KFO / DRO)?**
Yes — **Buttons** tab → framing → **Manual**. A crop box appears over the sprite
(seeded on the detected face): **drag the box to move it**, **drag the corner to
resize**, or use the **Box X / Y / Size** sliders for exact values. The one box
crops every emote button (and the char_icon has its own). The live preview beside
it updates as you drag. (The auto **Face**/**Full** modes are still there.)

**What's the `pinselcredits.txt` in my exported character?**
It's a small attribution file Pinsel adds to every exported character noting it
was made with Pinsel, who maintains it, and where to file bug reports
(github.com/SyntaxNyah/Pinsel-AO-Char-Maker). It's harmless — delete it if you
don't want it; it doesn't affect the character in-game.

**How do I make the char_icon? Can I move it or add a border?**
The **Buttons** tab generates `char_icon.png` automatically on export. There you
can pick its **framing** (face by default), **size** (40–128, default 40),
**zoom**, **Move X/Y** position, the **emote it's made from**, and an **overlay
border/background**. **Save char_icon.png now** bakes it straight into your
project.

**Can I put a border/frame on my buttons (like KFO CharMaker)?**
Yes — **Buttons** tab → **Overlays → Border (on top)**. Three ways:
- **Presets** — dozens of built-in frames (Umineko, Danganronpa/Monokuma, Limbus,
  kawaii sakura/hearts/sparkles, classic gold, a full colour palette).
- **Build…** — make your own: pick a style (frame, double, corners, heart
  corners, gradient/rainbow/split), set colours with a **colour wheel**, and drag
  thickness/corner-radius/inset, with a live preview. You can **start from any
  preset** and tweak it (recolour it, change the gradient…).
- **Import…** — your own PNG.

It's composited over every generated button. The **Background** slot works the
same (solid, gradients, dots/hearts/sparkles, diagonal split, rainbow…), and the
char_icon has its own overlays. Everything's generated in-app and scales crisply
to any size.

**My buttons look blurry / low quality.**
Buttons are **lossless PNG** — PNG can't lose quality to compression, so
blurriness is always from *resizing*. Pinsel now renders them crisp: it
**area-averages** when downscaling from your full-res sprite and **never
upscales** a small crop (the old bicubic path softened both up- and big
down-scales). If they still look soft:
1. **Raise Button size** (Buttons tab, up to 512). It won't upscale past the
   source, so big, sharp buttons need high-res sprites.
2. **Don't feed it degraded sprites.** If you converted to WebP with **lossy**
   quality, the button is cut from an already-degraded image — re-do the convert
   with **Lossless** (Bulk → WebP → Lossless) and regenerate.
Buttons stay PNG because it's the most universally AO-compatible button format
(lossless WebP buttons work in current AO2 but not everywhere).

**Where do I set blips, chat, showname, or the side?**
The **Character** tab — it's the full `char.ini` `[Options]` editor (name,
showname, `needs_showname`, side, **blips**, **chat**, category, scaling,
stretch, …). The auto-builder sets defaults; change anything here. Imported
custom keys are preserved.

**Typing in a field is laggy.**
Fixed — editing fields (Emotes, Character) no longer re-renders the big sprite
preview on every keystroke; the change is written immediately and committed when
you click away. Update to the current build if you still see it.

**I recoloured/edited "All sprites" but nothing changed — why?**
That was a bug with **WebP** sprites (the default format): the edit was written to
a stray `.apng` while the original `.webp` was left in place. It's fixed — recolour
and crop/trim now re-encode each sprite **in place** in its own format. Re-run the
action.

**Is there keyboard control / undo buttons?**
Yes. Every screen has a top **toolbar** with **undo/redo** (and import/export)
buttons, and there are global shortcuts: `Ctrl/⌘+Z` undo, `Ctrl/⌘+Y` (or
`Ctrl/⌘+Shift+Z`) redo, `Ctrl/⌘+S`/`E` export, `Ctrl/⌘+O` import, `Ctrl/⌘+1…9`
to switch screens, `F1` for the full list. See [SHORTCUTS.md](SHORTCUTS.md).

**Recolour / bulk / animation feel slow or freeze — anything I can do?**
It's a lot faster now: the per-pixel engine is allocation-free, live previews
run on a downscaled copy (the GPU even renders tonal previews), and
bulk/recolour/edit/**button** jobs yield so the **progress bar updates** instead
of the window freezing. Animate-all and talking-mouth-all bake across **all CPU
cores** (toggle on Home → Performance). The big one-off **bakes** still take a
moment on large sprite sets — watch the status bar. Tips: recolour the
**selected emote** (just `Apply`) while dialling in a look, then do **All
sprites** once; keep sprite dimensions reasonable; the native WebP encoder
(desktop release / web) is much faster than the APNG fallback. See
[PERFORMANCE.md](PERFORMANCE.md).

**The app froze / "not responding" / crashed when exporting a big character (or
bulk folders).** Generating buttons for a large cast (e.g. 100 emotes, or many
characters at once) used to render every button back-to-back on the UI thread
and could make the OS mark the window "not responding" — reopening it "fixed" it.
That's fixed: button rendering now yields between buttons so the UI stays alive,
folder scanning skips unreadable/huge files and symlink loops, and a global
crash logger writes a stack trace to **`pinsel_crash.log`** (next to the `.exe`,
or your temp folder) plus the browser console on web. If it still crashes, send
that log — it turns "it crashes sometimes" into something fixable.

**The app didn't freeze — the window *just closed* (during One-Click).** That's a
*hard* crash (out-of-memory or a native-library crash) which the in-app logger
can't catch as a Dart error. The culprit was One-Click **force-converting every
sprite to WebP** through the native encoder. So **One-Click no longer converts**
— it copies sprites in their existing format (still AO-compatible) and is now the
same reliable path as **Export .zip**. Convert to WebP deliberately via **Bulk →
Convert → WebP** when you want it (if *that* crashes, it's clearly the WebP
encoder — tell us, with the build details). One-Click also drops **phase
breadcrumbs** into `pinsel_crash.log` ("one-click start / building+zipping /
done"), so if it ever closes again the last line says which phase did it.

**I imported another folder and the previous character's emotes came back!**
Fixed. **Import** now starts a *fresh* project (the old sprites are cleared
first) — it no longer accumulates onto the last import. Use **Add sprites / Add
sprite folder** when you *want* to grow the current character, and **Start over**
to wipe everything explicitly.

**How do I reset / start over?**
**Home → Start over** (or the ↻ button in the top toolbar). It clears the
character, all imported sprites and edits back to an empty project (your
Button/Studio settings are kept). It asks first — it can't be undone.

**Can I delete lots of emotes at once?**
Yes — in the **Emotes** tab, tick the checkboxes on the rows you want (or **All**),
then **Delete (N)**. One undo step. Single rows still have their own trash icon.

**The character name defaults to "newchar".**
Import via **Import folder** (or **One-Click**) and the character is named after
the folder automatically. You can still rename it in the **Character** tab. (Note:
the export always reflects the name shown there — if an exported `char.ini` looks
stale, make sure you're opening the freshly-exported file, not an older copy.)

**Can it just play my frames in order (real frame-by-frame), not only effects?**
Yes. **Animate → Frames**: tap sprites to add them as ordered frames, set
**fps**, and optionally **Reverse** / **Ping-pong**; differently-sized frames are
auto-aligned onto a shared canvas. **Save as (b)/(a)** exports them as one
animated WebP (APNG fallback). Need ≥2 frames. (The **Effects** mode is the
procedural one.) See [ANIMATION.md](ANIMATION.md#frame-by-frame-assemble-given-frames).

**How do I change the app icon?**
Drop a 1024×1024 PNG at `assets/icon/app_icon.png` and run
`dart run flutter_launcher_icons` — see `assets/icon/README.md`.

**How do I make a sprite move if I can't animate?**
Open the **Animate** screen, click a preset (e.g. "Happy Bounce" or "Magical"),
maybe drag the intensity, and **Save**. That's it — see
[ANIMATION.md](ANIMATION.md).

**Can I use it without installing anything?**
Use the web build in a browser — import images, edit, and download a `.zip`. Host
`build/web/` anywhere static (see [BUILD_AND_RUN.md](BUILD_AND_RUN.md#the-website)).

**`flutter create .` — is that safe?**
Yes. It only generates the missing platform folders and standard config; your
`lib/`, `test/`, `assets/`, and docs are untouched. The platform folders are
gitignored on purpose so the repo stays lean.

**The "Emotes/Colour/Animate" tabs say "no project".**
Import sprites first (Home → Import sprite files / Import folder). Those screens
need a loaded character.

**Where are my edits stored?**
In an in-memory project (uniform across platforms). Use **Export .zip** (full
character with buttons) or **Export char.ini** to write them out. Autosave /
recent-projects are on the roadmap.

**How do I add my own presets/animations for others to use?**
Author a JSON pack (see [PLUGINS.md](PLUGINS.md)) — it works on desktop, mobile
**and** the web with no code.

**It runs slowly on a huge sprite while dragging sliders.**
The live preview is computed on a downscaled copy for speed (tonal adjustments
preview on the GPU); "Apply" then bakes at full resolution. Big bulk bakes
(animate-all, talking-mouth-all) now fan out across **all CPU cores** — see
[PERFORMANCE.md](PERFORMANCE.md).
