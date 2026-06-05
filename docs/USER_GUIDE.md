# 🐾 Pinsel — User Guide

A friendly, click-by-click guide to **every feature**. No coding needed.

If you just want to try it with nothing installed, use the **website build** (see
[WEBSITE.md](WEBSITE.md)) — import images, make your character, download a `.zip`.

---

## Contents
1. [The 60-second version](#1-the-60-second-version)
2. [A few words you'll see](#2-a-few-words-youll-see)
3. [The app layout](#3-the-app-layout)
4. [Home — import & export](#4-home--import--export)
    - [Character — the char.ini](#character--the-charini)
5. [Emotes — edit your character](#5-emotes--edit-your-character)
6. [Colour Lab — recolour sprites](#6-colour-lab--recolour-sprites)
7. [Animate — make sprites move](#7-animate--make-sprites-move)
8. [Buttons — emote buttons & char_icon](#8-buttons--emote-buttons--the-char_icon)
9. [Edit — crop, trim & remove background](#9-edit--crop-trim--remove-background)
10. [Mixer — snip & combine sprites](#10-mixer--snip--combine-sprites)
11. [Bulk — do everything at once](#11-bulk--do-everything-at-once)
12. [Plugins — add more content](#12-plugins--add-more-content)
13. [Common workflows](#13-common-workflows)
14. [Using your character in AO](#14-using-your-character-in-ao)
15. [Tips & troubleshooting](#15-tips--troubleshooting)

---

## 1. The 60-second version
1. **Home → Import sprite files** (or **Import folder** on desktop) and pick your
   images.
2. Pinsel instantly builds a character: it names your emotes, writes the
   `char.ini`, and gets everything ready.
3. (Optional) Tweak emotes, recolour, or animate using the tabs on the left.
4. **Home → Export .zip**.
5. Unzip into your AO `base/characters/` folder. Done. 🎉

---

## 2. A few words you'll see
- **Emote** — one expression/pose with a button (e.g. "Normal", "Angry").
- **Sprite** — the image file(s) for an emote.
  - `(a)name` = the **idle** animation (when not talking)
  - `(b)name` = the **talking** animation
  - `name` (no prefix) = a **static** (non-animated) sprite
- **Preanimation** — a one-time animation that plays *before* talking (e.g. a
  desk slam). `-` means "none".
- **char.ini** — the text file that tells AO about your character. Pinsel
  writes it for you.
- **Button** — the little icon for each emote in AO's emote picker.

You don't have to memorise these — Pinsel figures them out from your file
names.

---

## 3. The app layout
On the left is a **navigation rail** with these tabs:

| Tab | What it's for |
|-----|---------------|
| 🏠 **Home** | Import sprites/folders, set basics, export, credits |
| 🪪 **Character** | The full **char.ini** editor (name, showname, blips, chat, side…) |
| ▦ **Emotes** | Edit each emote's settings |
| 🎨 **Colour Lab** | Recolour sprites in real time (+ custom colour wheel) |
| 🎬 **Animate** | Make sprites move / glow / etc. |
| ▢ **Buttons** | Frame & generate emote buttons **and** the char_icon (borders too) |
| ✂️ **Edit** | Crop, auto-trim, remove background |
| ✦ **Mixer** | Snip / stack parts of sprites together (mouse-driven) |
| ⧉ **Bulk** | Recolour / convert / **rename** *all* sprites at once |
| 🧩 **Plugins** | Add preset/animation packs |
| ▩ **Ripper** | Slice a **sprite sheet** into individual sprites ([guide](SPRITE_RIPPER.md)) |
| 🖌️ **Theme** | Design a full **AO2 client theme** ([guide](THEME_MAKER.md)) |

At the very bottom is a **status bar** showing the latest action and your emote
count. A spinner there means it's working.

> Tabs other than **Home**, **Plugins**, **Ripper** and **Theme** say *"No
> project yet"* until you import sprites — those four work on their own.

---

## 4. Home — import & export

**⚡ One-Click: folder → finished character** (the big button up top)
- Pick a folder of sprites and get a **ready-to-drop `.zip`** with no other
  steps: it imports, writes the `char.ini`, converts every sprite to **WebP**,
  generates the emote **buttons** + **char_icon**, and downloads the packaged
  character. This is the whole pipeline in one action — see
  [ONE_CLICK.md](ONE_CLICK.md).
- Once a project is loaded, **Finish & export everything** does the same for what
  you've got open (after you've recoloured / animated / added talking mouths),
  without re-importing.

**Import your art**
- **Import sprite files** — pick one or many images (webp, png, gif, apng, jpg,
  bmp, …). Works everywhere, including the website.
- **Import folder** — pick a whole folder (recursively); sub-folder structure is
  kept. Works on **every** platform, including the website (it uses a folder
  upload there). If the folder already has a `char.ini`, Pinsel loads it as-is
  (nothing is lost); otherwise it auto-builds one — and **names the character
  after the folder** (no more "newchar"). **Import starts a fresh project**: the
  previous character/sprites are cleared first, so importing a second folder
  won't bring the old one's emotes back. (To *grow* a character instead, use
  **Add sprites / Add sprite folder**; to wipe everything, use **Start over**.)
- **Bulk folders → characters** — point at a **parent** folder of per-character
  sub-folders and build **all of them at once** into one `.zip` (each sub-folder
  → `Name/char.ini` + sprites + `emotions/` + `char_icon.png`). Great for making
  10 characters in one click; uses your current Button Studio settings and leaves
  your open project alone. See [Auto-build → Bulk folders](AUTO_BUILD.md).

**Update an existing character** (these appear once a project is loaded)
- **Add sprites** / **Add sprite folder** — drop *more* images into the
  character you already have. Each brand-new sprite becomes a new emote, while
  your existing `char.ini`, emotes and edits are kept untouched. Use this to grow
  a character (e.g. add a few new expressions). The difference from **Import**:
  *Import* starts fresh; *Add* grows what you've got.

The moment you import, the status bar tells you what happened (e.g. *"Auto-built
24 emotes from sprites."* or *"Added 3 new emote(s) from new sprites."*).

**Auto-build options** (set these *before* importing for best results, or change
them and press **Regenerate from sprites**):
- **Character name (folder)** — becomes the folder name and the `name` in the
  ini.
- **Side** — where the character stands (Defense, Prosecution, Witness, …).
- **Bare file = preanim** — if an emote has both an `(a)/(b)` pair *and* a plain
  same-named file, treat the plain one as a preanimation. Leave on unless your
  results look odd.
- **Guess sound effects** — auto-fills obvious SFX (e.g. a "slam" emote gets the
  desk-slam sound). Turn off if you'd rather add sounds yourself.

**Export**
- **Export .zip** — builds the full character folder (with `char.ini` *and*
  auto-generated buttons) and downloads/saves a `.zip`.
- **Export char.ini** — just the text file. It always reflects what's in the
  **Character** tab right now; if an exported file looks out of date, check
  you're opening the one you just saved (not an older copy in another folder).

**Start over** — wipes the whole project (character, sprites, edits) back to
empty so you can begin a new one. It's on Home (once a project is loaded) and as
the **↻** button in the top toolbar; it asks first and keeps your Button/Studio
settings.

**Validation card** — shows errors/warnings (e.g. "No sprite file found for X")
with a plain-language fix for each. Green = all good. 🎉

**Credits card** — who maintains Pinsel, with a link to the GitHub repo and an
**About** button (also the ℹ button in the top toolbar) for full credits.

> **"Guess sound effects" — what is it?** When on, the auto-builder reads each
> emote's name for keywords (e.g. *slam*, *point*, *object*, *shout*) and fills
> in a matching sound effect (and sets it to play the preanimation), so a
> "deskslam" emote gets the desk-slam SFX automatically. Off = sounds are left
> blank for you to set in the Emotes tab.

---

## Character — the char.ini

Open the **Character** tab. This is the full editor for the `[Options]` block of
your `char.ini` — everything the auto-builder only guessed a default for. Changes
are saved into your project automatically (use Undo/Redo), and written verbatim
on export. Any custom keys you imported are **preserved**.

- **Name** — the folder name and in-game character name.
- **Showname** — the name shown in the chatbox (blank = use Name).
- **Require a custom showname** — `needs_showname` (Unset / Yes / No).
- **Category** — groups the character in the picker (optional).
- **Side** — the courtroom position (Defense, Prosecution, Witness, Judge…).
- **Blips** — the *typing-sound* set (e.g. `male`, `female`, `typewriter`).
  Modern AO uses this where old characters used `gender` (Pinsel reads either).
- **Chat** — the chatbox / font style name.
- **Scaling** — how sprites are resized (Default / Smooth / Pixel).
- **Stretch** — stretch sprites to fill (`stretch`).
- **Effects / Realization** — advanced overrides, rarely needed.

There's an **Export char.ini** button right here, too.

---

## 5. Emotes — edit your character

**Left panel (the emote list)**
- **Drag** a row to reorder emotes (this also renumbers them).
- **+** adds a new blank emote.
- **↶ / ↷** undo / redo any change.
- The **trash** icon on a row deletes that emote.
- **Click** a row to select and edit it.
- **Multi-select / bulk delete** — tick the **checkboxes** on the rows you want
  (or **All** in the bar above the list), then **Delete (N)** to remove them all
  at once (one undo step). Great for trimming a big imported cast.
- **Drag several at once** — with rows ticked, **drag any ticked row** and the
  whole selection moves together as one block (keeping their order), so you can
  reorder a group in one drag instead of one emote at a time.
- **Keyboard navigation** — `Ctrl/⌘ + ↑ / ↓` moves to the previous/next emote and
  the list **auto-scrolls** to it (so you can step through 100 emotes without
  losing the selected one off-screen).

**Right panel (preview + settings)**
- The big preview shows the selected sprite. **Scroll / pinch to zoom**, **drag
  to pan** — handy for lining things up.
- Settings you can change:
  - **Name** — the label on the button / in the dropdown.
  - **Sprite** — the base file name (the `(a)`/`(b)` part).
  - **Preanim** — preanimation name, or `-` for none.
  - **Modifier** — *Idle* (no preanim), *Play preanim + sound*, *Zoom* (speed
    lines, hides desk), or *Zoom + preanim*.
  - **Desk** — force the desk/stand shown or hidden, with preanim variations.
  - **Sound (SoundN)** — the sound effect name. **Tap the ▾ arrow** to pick from
    a list of sounds already used in this character, the built-in sfx names, and
    any audio files (`.opus`/`.ogg`/`.wav`/`.mp3`) bundled in the folder you
    imported — or just type any name yourself.
  - **Delay ticks** — wait before the sound plays (1 tick = 60 ms).
  - **Loop sound** — repeat the sound.

Edits save into your project automatically; use **Undo/Redo** freely.

---

## 6. Colour Lab — recolour sprites

Great for tinting, themed variants, and OCs (recolour Mario to pink without
flattening his shading).

1. Pick an emote in the **Emotes** tab first (the Lab recolours the selected
   sprite).
2. In **Colour Lab**, drag the sliders — the preview updates live:
   - **Hue** (shift colours), **Saturation**, **Brightness**, **Contrast**.
   - Tonal adjustments (brightness/contrast and many presets) preview **on the
     GPU**, instantly — you'll see a small **GPU live preview** badge. Other ops
     fall back to the regular preview. Either way **Apply** bakes the same result.
3. Tap **Preset** chips (there are hundreds — "Make it Pink", "Vaporwave",
   "CRT", "Sepia", "Teal & Orange", …) and **Gradient map** chips (Fire, Ice,
   Rainbow, …). New **Effects** presets add outlines and depth: "Outline",
   "White Outline", "Outer Glow", "Drop Shadow", "Sharpen", "Soft Blur", plus
   film looks like "Cross Process", "Bleach Bypass", "Solarize" and "Dither".
   They all **blend (stack)** on top of each other and your sliders, so you can
   combine several — each one you add shows as a chip under "Blended" with an ✕
   to remove it.
4. **Custom colour** — type a **hex** code right in the panel (e.g. `FF5577`), or
   tap the wheel icon to open the colour **wheel** (hue wheel + sliders + its own
   editable hex bar + HEX/RGB/HSV readouts). Then blend that exact colour in as
   **Recolour to** (re-hue preserving shading), **Tint**, **Solid fill**, or
   **Gradient** — each adds to the blend stack like a preset.
5. Apply it:
   - **Apply** — bakes the look into **this** sprite.
   - **All sprites** — applies it to **every** sprite (great for a uniform theme).
6. **Reset** clears the sliders and the blend stack.

> "Make it `<colour>`" / "Recolour to" keep the original light/shadow, so
> recolours look natural.

For recolouring **just part** of a sprite (only the clothes/hair), see
[COLOR_OPS.md → region editing](COLOR_OPS.md#region--outfit-editing).

---

## 7. Animate — make sprites move

Anyone can animate here. AO sprites are just animated images, so the result
works natively. The **Animate** tab has three modes (toggle at the top):

- **Effects** — one-click procedural motion/effects (below).
- **Mouth** — a **talking mouth** faked from one drawing (jump to
  [Mouth](#7a-mouth)).
- **Frames** — classic **frame-by-frame**: pick existing sprites *as frames* and
  stitch them into one animation (jump to [Frame-by-frame](#7b-frame-by-frame)).

### Effects mode

1. Select an emote (Emotes tab).
2. In **Animate**, either:
   - click a **Preset** ("Idle Breathe", "Happy Bounce", "Angry Shake",
     "Magical", "Spin", "Heartbeat", "Hologram", "Glitch", …), **or**
   - click chips under **Add an effect** to stack your own (e.g. `bob` + `glow` +
     `rainbow`). Stacked effects combine.
3. Tune it:
   - **Frames** — smoothness (more = smoother, bigger file).
   - **Speed** — playback fps.
   - **Easing** — the *feel* (linear, bouncy, springy `elastic`, snappy
     `easeOutBack`, …).
   - Each added effect has its own **strength** slider (and an ✕ to remove it).
4. Save:
   - **Save (b) talk (WebP)** — saves it as the **talking** animation.
   - the **moon icon** saves it as the **(a) idle** animation.
   - It's added to your project *and* downloaded. WebP is the default; it
     automatically falls back to APNG if your platform can't make WebP — and the
     status line says **why** it fell back, so you can fix it.
5. **Animate ALL sprites (WebP)** — one button bakes the current effect stack
   onto **every** sprite at once and saves each as an animated WebP `(b)` talk
   sprite (replacing any existing talk sprite). Perfect for giving a whole
   character the same idle sway/breathe in a single click. It confirms first
   (it's a bulk write), renders each sprite **in the background** so the app
   stays responsive, and reports how many came out WebP vs APNG.

<a name="7a-mouth"></a>
### Mouth mode (talking lip-sync, no extra art)

Make a character's mouth **move while they talk** from a *single* drawing — no
mouth shapes to draw. Switch **Animate → Mouth**:

1. Select an emote (Emotes tab). Its sprite loads with a **pink mouth box**
   already placed on the face, and the preview **loops, talking**.
2. **Drag the box onto the lips** using the sliders:
   - **Mouth X / Mouth Y** — move it. **Width / Height** — resize it.
   - **Open amount** — how far the jaw drops (subtle ↔ wide).
   - **Frames / Speed** — length and pace of the talk loop.
   - **Auto-place on face** re-centres the box if you lose it.
3. Watch the preview until it looks right, then **Save as (b) talk** (or the moon
   icon for **(a) idle**). Saved as **animated WebP** (APNG fallback), added to
   your project *and* downloaded.
4. **Talking mouth on ALL sprites** gives your *whole cast* a face-placed talking
   mouth in one click (baked across all CPU cores).

Already drew real mouth shapes? You can feed a closed+open sprite or several
visemes instead — see [LIPSYNC.md](LIPSYNC.md).

<a name="7b-frame-by-frame"></a>
### Frames mode (frame-by-frame)

Already have the frames drawn? Switch **Animate → Frames** and assemble them:

1. **Add frames** — tap sprites from the list at the bottom; each tap appends it
   to the **Sequence**. Tap the same one again (or the **copy** icon) to hold it
   for longer.
2. **Reorder** — use the ▲ / ▼ on each row; **✕** removes it; **Clear** empties
   the list.
3. **Options:**
   - **Speed (fps)** — how fast the frames play.
   - **Reverse** — play the sequence backwards.
   - **Ping-pong** — play forwards then backwards (a smooth boomerang loop).
   - **Align** — frames of different sizes are padded onto a shared canvas;
     choose **Bottom** (default, sprites stand on the floor), **Center** or
     **Top**.
4. Watch it loop in the preview, name it, and **Save as (b) talk** (or the moon
   icon for **(a) idle**). It's added to your project *and* downloaded as
   **animated WebP** (APNG fallback). You need **at least 2 frames** to save.

**Move just a hand/limb or hand-author keyframes** are supported too — see
[ANIMATION.md](ANIMATION.md) (regions, the keyframe `Timeline`). For talking
mouths see [Mouth mode](#7a-mouth) above and [LIPSYNC.md](LIPSYNC.md).

---

## 8. Buttons — emote buttons & the char_icon

Buttons **and** the character-select `char_icon.png` are generated automatically
when you export. This tab — the **Button & Icon Studio** — lets you control
*how*, with a live preview of each.

### Framing (the big one)
By default Pinsel frames the character's **head / face** — AO buttons show
*expressions*, so a full-body button looks weird and tiny. The framing picker has
three modes for both the button and the icon: **Face**, **Full** (whole sprite),
and **Manual**.

- **Manual (do it yourself, KFO/DRO-style)** — pick **Manual** and a **big** crop
  box appears over the sprite (seeded on the detected face). **Drag the box to
  move it**, **drag the corner to resize**, or use the **Box X / Y / Size**
  sliders for exact values. The preview beside it updates live as you drag.
  - **Frame the whole cast from the keyboard — no mouse trip to the top.** Click
    the sprite once to focus the framing area, then fly through it: **`[` / `]`**
    previous / next sprite, **Enter** (or **Space**) "make it & go to the next",
    **R** reset this sprite to its auto face, **A** apply the current box to every
    sprite, **F** cycle Face → Full → Manual. (This is the fix for the classic
    "I had to reach for the next-sprite button every single time" gripe — boxes
    save as you go, so advancing *is* finishing the current one.)
  - **Every sprite has its own box.** The **◀ ▶** arrows ("Sprite *k* of *N*") do
    the same as `[` / `]` if you prefer the mouse; the caption shows how many
    sprites you've customised (e.g. "7 of 42").
  - **Sprites you never touch auto-frame the face**, so you only have to visit the
    poses the auto crop gets wrong — you're never forced to hand-place all 100+.
  - **Reset this sprite to auto** (key **R**) snaps the current one back to its
    detected face; **Apply this box to all sprites** (key **A**) stamps the
    current box onto every sprite at once (handy when many poses share the same
    framing).
  - The **char_icon** keeps its own single Manual box (it's one image).
- **Face zoom** (Face mode) — tighter or looser around the face (**0.25–4×**;
  >1 zooms in, <1 pulls back to head-and-shoulders).
- **Move X / Y** (Face/Full modes) — nudge the auto crop if the detected face is
  off (e.g. an off-centre or tilted head). The full **±100 %** range lets you
  shift the crop a whole crop-width/height. (In **Manual** mode the box carries
  its own position, so these are hidden — you place it directly.)
- **Size** — buttons default to the **classic 40×40 AO button** (range 24–512);
  the **char_icon** defaults to **40 px** (40–128). Output is **lossless PNG**,
  **area-averaged** down from the full-res sprite and **never upscaled**.
  Exporting at the size the theme actually shows the button means the client
  doesn't have to rescale it with a cheap filter — which is what keeps it crisp
  in-game (a big image the theme shrinks is what looked "low quality"). Bump the
  size up for HiDPI / KFO themes that display bigger art.
  - The **on-screen preview is rendered larger than the export** so a tiny 40×40
    button still *frames* sharply while you work — the saved file is still the
    size you picked (shown under the preview).

> **Slider *or* exact value.** Every setting (size, zoom, move X/Y) is a slider
> with a **typeable box** next to it — drag for a quick adjust, or type an exact
> number (it commits on Enter / when you click away, clamped to the valid range).
> Dragging the slider updates the box live.

### Borders & backgrounds (KFO-style)
Want a frame around your buttons like other makers? Under **Overlays**, each slot
has three buttons — **Presets**, **Build…**, and **Import…**:
- **Border (on top)** — laid **over** every button/icon (a frame, corner badge…).
- **Background** — sits **behind** the sprite.

**Presets** opens a picker of built-in art, grouped by theme — **Umineko**
(gilded frames, crimson/gold), **Danganronpa** (hot-pink, Monokuma split,
despair), **Limbus** (thin crimson identity frame), **Kawaii** (sakura/lavender/
mint frames, hearts, sparkles, cotton candy, pastel rainbow), **Classic**
(white/black/double-gold/corners), **Vibes** (rainbow, sunset, ocean, vaporwave),
and a big **Colours** palette (solid frames + soft radial backgrounds). They're generated in-app, so they scale crisply to
any button size.

**Build…** is the make-your-own editor. Pick a **style** (frame, double frame,
corner brackets, heart corners, gradient/rainbow frame, split frame — or, for
backgrounds: solid, linear/radial **gradient**, diagonal split, dots, hearts,
sparkles, rainbow), set the **colours** with a **colour wheel** (+ hex), and drag
**thickness / corner radius / inset / pattern size** — all with a live preview.
**Start from a preset** to edit any built-in frame (recolour it, make the
gradient yours…), then **Apply**. Build… re-opens whatever you last applied to
that slot, so you can keep tweaking.

Or **Import…** your own PNG. Buttons and the char_icon each have their own
overlays (or none).

### Char icon
- Choose which emote it's **made from** (defaults to the first).
- **Save char_icon.png now** bakes it straight into your project (and downloads
  it). Otherwise it's generated on export.

### Generate toggles & export
- Turn button or char_icon generation off entirely with the **Generate** switch.
- **Export character (.zip)** writes everything (`emotions/buttonN_off.png` +
  `char_icon.png`).

> A `buttonN_off.png` or `char_icon.png` you import (or save here) is kept as-is
> on export — only the missing ones are generated. The advanced
> background/foreground/mask compositor also exists in the engine
> (`ButtonMaker.renderComposite`).

---

## 9. Edit — crop, **grow**, trim & remove background

Open the **Edit** tab (pick an emote first).

- **Auto-trim transparent margins** — tightens the sprite to its visible pixels.
- **Remove background** — flood-fills from the four corners and makes a flat/near-
  flat background transparent. Use the **BG tolerance** slider if it removes too
  little or too much.
- **Crop *or* grow each side** — each of **Left / Top / Right / Bottom** is one
  **bidirectional** slider: **drag right to crop** that edge inward, **drag left
  to grow** the canvas outward (adding transparent margin — handy for giving a
  sprite head-room, squaring it up, or making space before a Mixer paste). The
  label tells you which way it's going ("12% crop" / "8% grow").
  - **`−` / `+` buttons** beside each slider nudge that side by **1%** per click —
    quick, exact mouse adjustments without a steady-handed drag.
- **Apply to** — a **This sprite / All sprites** toggle picks the target; then
  press **Apply**.

Crop, grow and auto-trim apply the **same box to every frame and to an emote's
`(a)`/`(b)`/`(c)` sprites**, so animations and idle/talk stay perfectly aligned.
(The result is baked into the sprite files — use Export afterwards.)

---

## 10. Mixer — snip & combine sprites

The "frankensprite" tool. It's **mouse-driven** with sliders as a precise backup,
and has **three modes** (toggle at the top of the canvas):

- **Arrange** — place snipped parts on a body. **Drag** a part to move it, drag
  its **corner** to scale (or **scroll** the wheel), drag the **round handle** to
  rotate.
- **Snip** — choose *what* to cut: **drag the box** on the source sprite, drag a
  **corner** to resize.
- **Layers** — "link everything": stack whole, pre-aligned files into one sprite.

### Snipping parts (Arrange + Snip)
1. **Body** — the sprite (from your project) that forms the bottom.
2. **Snips** — press **+** to add a snip; add **as many as you want** (a head
   *and* a hat *and* an accessory). Each row is one snip — tap to edit, **copy**
   to duplicate, **trash** to remove.
3. For the selected snip:
   - **Snip parts from** — *This project* or a **2nd folder** you load
     (**Load a 2nd sprite folder…**; it's kept separate and **never exported**).
   - **Snip from** — which sprite to take a piece of.
   - **Ellipse** (great for heads) / rectangle, **X/Y/Width/Height** (or drag in
     **Snip** mode), **Flip H/V**, **Feather**.
   - **Recolour the snip** — **Hue / Saturation / Brightness** to match the body.
   - **Placement** — drag on the canvas, or **Pos X/Y, Scale, Rotate, Opacity**.
4. **Crop output**, name it, **Save as new emote**.

### Linking separated art (Layers)
If your character is drawn as separate files (eyes, eyebrows, body, an arm…) that
already line up, switch to **Layers**:
1. **Load a sprite folder…** (or use *This project*).
2. **Add all** — every sprite becomes a layer in one click. The list is the
   stack (**top = on top**); reorder with **▲/▼**, hide with the checkbox, fade
   with **opacity**, remove with **✕**.
3. Name it and **Combine & save as new emote**.

The preview is smooth because each snipped piece is **baked once** and then just
moved/scaled as a lightweight transform — only **Save** renders at full
resolution.

Tip: animate the result in the Animate tab — a mixed sprite is just a normal
sprite.

---

## 11. Bulk — do everything at once

**Recolour ALL sprites**
1. Build a look in the **Colour Lab** (sliders/preset) — it becomes the "live
   pipeline".
2. In **Bulk**, the Recolour card shows how many ops are in it.
3. Click **Recolour ALL sprites**.

**Bulk rename emotes**
- **Find / Replace** (e.g. find `_` replace with a space), add a **Prefix** or
  **Suffix**, **Number** them with a template (`{n}` = number, `{name}` =
  current name, e.g. `Emote {n}`), and pick a **Case** (Title/lower/UPPER).
- Tick **Also rename the sprite files** to rename the underlying `(a)`/`(b)`/
  static files too (root sprites), not just the labels.
- **Apply rename to ALL emotes**. (Undo is available back in the Emotes tab.)

**Convert format**
1. Pick a **format** (default **WebP**; also PNG/APNG, GIF).
2. For **WebP**: choose **Lossless** or set a **Quality**. A note tells you if
   the WebP encoder is available on your platform (on the website it always is).
3. **Delete originals** (optional) avoids AO picking the old file by extension
   priority.
4. **Convert ALL sprites** — animation frames are preserved for PNG/APNG/GIF (and
   animated WebP on native).

---

## 12. Plugins — add more content

Packs are small JSON files that add presets, palettes, gradients, animations and
emote-name sets. They need no install and work on the website too.

- **Import pack (.json)** — pick a pack file; its content immediately appears in
  the Colour Lab / Animate tabs.
- Installed packs are listed with a **trash** icon to remove them.
- A sample pack ships at `assets/presets/example_pack.json` — copy it, edit it,
  re-import. The format is documented in [PLUGINS.md](PLUGINS.md).

---

## 12a. Ripper — slice a sprite sheet

Got a **sprite sheet** (a grid or collage of expressions in one image)? The
**Ripper** tab cuts it into individual transparent sprites.

1. **Load sheet** and pick the image.
2. Pick a mode:
   - **Auto detect** (any layout — it flood-fills the background from the edges,
     so white-on-white works). Tune the sliders until each sprite has its own box.
   - **Grid** (uniform sheets — set columns/rows/offset/gutter).
   - **Manual** — draw your own boxes: drag on the sheet to make a box, drag a box
     to move it, drag its corner to resize, tap then **×** to delete. Great for
     grouping sprites or fixing what auto-detect missed (it keeps any boxes you
     already have).
3. **Tap boxes** to include/exclude; **All / None** to bulk-toggle.
4. Keep **Remove background** on for transparent sprites.
5. **Add to character** (becomes new emotes) or **Download as .zip**.

Full details: **[SPRITE_RIPPER.md](SPRITE_RIPPER.md)**.

---

## 12b. Theme — design an AO2 client theme

The **Theme** tab is a complete **Attorney Online 2 / webAO** theme editor.

- **Import theme folder** to edit a real theme, **New** for a blank one, or
  **Random** for a fresh palette.
- Tabs: **Layout** (every widget's X/Y/W/H + add any of ~95 known widgets),
  **Colours**, **Fonts**, **Images** (replace any asset with your own PNG/GIF/
  WebP), **Style** (Qt CSS, sounds, design options), **Arrange** — a live
  courtroom where you **drag widgets around and resize them with the mouse** (flip
  on **Show art** to drag the real images) — and **Preview**, a read-only
  **real-client look** so you can see the result before using it.
- The **Courtroom / Lobby** toggle (on Layout & Arrange) picks which screen you
  edit: **⚖️ Courtroom** = the in-trial screen, **🖥️ Lobby** = the server-select
  screen you see before joining. In **Arrange**, every box is **labelled** and
  **hovering shows what it does**.
- In **Arrange**, set a **Grid** (5–50px) to **snap** drags/resizes for
  pixel-perfect alignment, and use the **arrow keys** on a selected box to nudge
  it 1px (**Shift** = 10px, **Ctrl/Alt** = resize). The **⌨ button** rebinds those
  nudge keys to anything you like. Any **slider** in the app also responds to
  arrow keys once you Tab to it.
- Click the **size** button (e.g. `1280×720`) to **resize** the theme — pick
  **1920×1080 / 720p / a custom size**, optionally scaling every widget and font.
- **Export .zip** gives you a folder ready to drop into the client's
  `base/themes/`.

Full details: **[THEME_MAKER.md](THEME_MAKER.md)**.

---

## 13. Common workflows

**Make a character from a folder of images (the fastest way)**
Home → **⚡ One-Click: folder → finished character**. Done — WebP sprites, ini,
buttons and char_icon, packaged. (Manual route: Import → check Validation →
Export .zip.)

**Make a recoloured OC variant**
Import the base → Colour Lab → "Make it `<colour>`" or sliders → **All sprites**
→ change the **Character name** on Home → Export .zip.

**Give a character a talking mouth (no extra art)**
Select the emote → **Animate → Mouth** → drag the pink box onto the lips (watch
the preview talk) → **Save as (b) talk**. Do the whole cast at once with **Talking
mouth on ALL sprites**. → Export.

**Add a talking animation to a static sprite**
Select the emote → Animate → preset like "Idle Breathe" (save as **(a)**) and/or
a talk effect (save as **(b)**) → Export.

**Convert an old character to WebP**
Import the folder → Bulk → format **WebP** → optionally **Delete originals** →
**Convert ALL** → Export.

**Frankensprite (two characters)**
Mixer → pick the **body** from your project → add a **snip** → **Load a 2nd
sprite folder** → **Snip from** the other character → frame the head (ellipse,
or drag in **Snip** mode) → recolour/feather to match → drag it into place in
**Arrange** mode → add more snips if you like → **Save as new emote** → Export.

**Combine a character that's split into separate part files**
Mixer → **Layers** mode → **Load a sprite folder** of the parts (eyes, brows,
body, arm…) → **Add all** → reorder/hide as needed → **Combine & save as new
emote** → Export.

**Add a border to your buttons**
Buttons → **Border (on top)** → **Import…** your frame PNG → it's laid over every
button (and you can do the same for the char_icon) → Export.

---

## 14. Keyboard shortcuts & the toolbar

Every screen has a slim **toolbar** at the top: **undo / redo** buttons (also
import a folder, export `.zip`, export `char.ini`, and a ⌨ button that lists the
shortcuts). The same actions have keys (Control on Windows/Linux, ⌘ on macOS):

| Shortcut | Action |
|----------|--------|
| `Ctrl/⌘ + Z` | Undo |
| `Ctrl/⌘ + Y` / `Ctrl/⌘ + Shift + Z` | Redo |
| `Ctrl/⌘ + O` | Import a folder |
| `Ctrl/⌘ + S` | Export `.zip` |
| `Ctrl/⌘ + E` | Export `char.ini` |
| `Ctrl/⌘ + N` | Add an emote |
| `Ctrl/⌘ + ↑ / ↓` | Previous / next emote |
| `Ctrl/⌘ + 1 … 9` | Jump to a screen |
| `F1` | Show the cheat-sheet |

Full reference: [SHORTCUTS.md](SHORTCUTS.md).

---

## 15. Using your character in AO
1. **Export .zip** from Home (or Buttons).
2. Unzip it into your AO install's `base/characters/` folder (so you get
   `base/characters/<YourName>/char.ini`).
3. Launch AO, pick the character. (For webAO, host the files where your server
   expects them.)

Pinsel's output matches what the AO2 client and webAO read, including buttons,
sounds, preanimations, and frame effects.

---

## 16. Tips & troubleshooting
- **A tab says "No project yet."** Import sprites on **Home** first.
- **"No sprite file found for X"** in Validation — the emote's **Sprite** name
  doesn't match a file. Fix the name in the Emotes tab, or add the file.
- **Recolour preview looks slightly soft.** The live preview uses a smaller copy
  for speed; **Apply** bakes at full resolution.
- **Animations export as APNG instead of WebP.** WebP needs `libwebp` +
  `libwebpmux` next to the `.exe`. A plain `flutter run` (debug) has neither, so
  it falls back to APNG — the save **status line names the reason**. Use the
  website build (WebP always works), a CI release artifact, or
  `scripts/build_all.ps1` (bundles the DLLs via vcpkg). See
  [PLUGINS.md](PLUGINS.md#native-libwebp).
- More answers: [FAQ.md](FAQ.md).
