# Paint Studio — gradients, fills, brushes & region recolour

The **Paint** screen (nav rail → *Paint*) is the advanced pixel-editing surface:
freehand brushes, gradient fills, magic-wand region recolour, blend modes, and a
full multi-stop gradient editor. The engine lives in `lib/src/imaging/paint.dart`
(pure Dart, unit-tested in `test/paint_test.dart`); the UI is
`lib/src/ui/screens/paint_studio_screen.dart`, wired through `AppState`.

> Everything is **non-destructive until you press Apply.** Edits accumulate as a
> journal of `PaintOp`s you can undo one-by-one; the sprite is only rewritten on
> Apply, which bakes the journal into **every animation frame** losslessly.

---

## 1. The model — a journal of `PaintOp`s

Like recolour pipelines (`OpPipeline`) and animation (`AnimRecipe`), a paint edit
is a **serialisable journal**: `AppState.paintOps` is a `List<PaintOp>`. Each op
stores its geometry in **normalized 0..1 coordinates** (fractions of the sprite),
so the *same* journal replays identically onto:

- the small **preview** (frame 0, downscaled) — instant feedback, and
- the full-resolution sprite and **every animation frame** — the bake.

That's why the live preview always matches the exported result, and why an op is
resolution-independent.

### Per-frame stability
On Apply, **content-derived masks** (magic-wand, luminance) are built **once from
each sprite file's first frame** and reused across that file's animation frames —
so a magic-wand recolour can't shimmer frame-to-frame. Geometric masks
(rectangle/ellipse/lasso) and brush strokes are coordinate-based and identical on
every frame anyway. (Mirrors how `applyEdit` shares one crop rect per group.)

---

## 2. Tools

| Tool | Gesture | What it does |
|------|---------|--------------|
| **Brush** | drag (or tap = dot) | Freehand stroke in the current brush mode/colour. |
| **Bucket** | tap a part | Floods a region (magic-wand at the tap, or the whole sprite) with the chosen colour through any blend mode. |
| **Gradient** | tap a part | Floods a region with the edited multi-stop gradient. |
| **Pick** | tap | Eyedropper: grabs the colour under the cursor into the brush/fill colour. |

### Brush modes (`BrushMode`)
- **Paint** — lay the brush colour down through the brush's **blend mode** (use
  *Color* for a recolour brush that keeps shading).
- **Erase** — lower alpha (rub the sprite away).
- **Dodge** — lighten toward white (tonal; colour ignored).
- **Burn** — darken toward black (tonal).
- **Smudge** — soft smear (pulls a blurred copy along the stroke).

Brush knobs: **Size** & **Hardness** (fractions of the sprite's shorter side, so
resolution-independent), **Opacity** (max coverage of the whole stroke), **Blend**
(paint mode), and **Stay inside the sprite** (`clipToOpaque` — don't paint over
transparent pixels).

### Region (for Bucket & Gradient)
- **Whole sprite** toggle — off = tap a part (magic wand).
- **Wand tolerance** (0..200 RGB distance) and **Connected only** (flood-fill vs
  every matching pixel).
- **Feather** (soften the edge, px) and **Grow / shrink** (px).
- **Keep alpha** (`preserveAlpha`) — recolour only; don't bleed colour into
  transparent areas. Turn off for shadows/vignettes that should darken the halo.

---

## 3. Blend modes (`PaintBlend`)

`normal, multiply, screen, overlay, darken, lighten, colorDodge, colorBurn,
hardLight, softLight, difference, exclusion, add, subtract, hue, saturation,
color, luminosity`.

The HSL "creative" modes are the useful ones for character art:

- **Color** — source hue+saturation over the base's luminosity. *This is the
  recolour-keeps-shading mode*: pick the shirt with the wand, Bucket-fill a new
  colour in **Color** blend, and the folds/shading survive.
- **Hue** — only the hue changes.
- **Saturation** / **Luminosity** — swap just that channel.

`blendRgb(br,bg,bb, sr,sg,sb, mode)` is the pure building block (tested).

---

## 4. Gradients

### Model — `PaintGradient`
- `stops` — a list of `GradientStop(pos 0..1, argb)`; sampled sorted by position,
  interpolated in straight RGBA. `colorAt(t)` returns the colour at ramp position
  `t`.
- `type` — `GradientType`: **linear**, **reflected** (mirrored V), **radial**
  (ellipses), **diamond** (Manhattan), **conic** (sweep around the centre).
- `angle` — degrees for linear/reflected/conic (0 = left→right, 90 = top→bottom).
- `reverse` — flip the ramp.

A gradient fill maps its ramp across the **bounding box of the selected region**,
so "fill the hair with Fire" just works.

### The gradient editor (Gradient tool sidebar)
- A live **ramp preview**.
- Per-stop **colour** (tap the swatch → colour wheel) + **position** slider +
  remove; **Add stop**.
- **Type**, **Angle**, **Reverse**.
- **Presets** — a big built-in `GradientLibrary` (Fire / Cool / Sky / Neon /
  Pastel / Metal / Character / Neutral) plus your **Saved** gradients first.
- **Save** — store the current gradient as a reusable preset (persists across
  sessions via `settings_store`, alongside overlay presets).

`GradientLibrary.presets` / `.categories` / `.byName` / `.forCategory` expose the
catalogue; `AppState.userGradients` holds saved ones (`saveGradient` /
`deleteGradient`).

---

## 5. Engine reference (`imaging/paint.dart`)

- **`GradientStop`**, **`PaintGradient`** (`colorAt`, `copy`, `toJson/fromJson`,
  `fromColors`, `blackwhite`).
- **`PaintSelection`** — `kind` (`SelectionKind`: whole/wand/rect/ellipse/lasso/
  luminance) + normalized geometry + tolerance/feather/grow/invert; `build(frame)`
  → `SelectionMask`.
- **`BrushSpec`** — mode/colour/size/hardness/opacity/blend/clipToOpaque.
- **`PaintOp`** — `kind` (`PaintOpKind`: fillSolid/fillGradient/fillOps/brush) +
  selection/argb/gradient/ops/brush/stroke/blend/opacity/preserveAlpha;
  `buildMask(frame)`, `applyTo(frame, {mask})`, `toJson/fromJson`.
- **`Painter`** — `applyAll`, `fillSolid`, `fillGradient`, `fillOps`, `stroke`
  (all mutate the `img.Image` in place).
- **`blendRgb`** — the per-channel/HSL blend function.
- **`GradientLibrary`** — the preset catalogue.

### AppState surface
- `paintOps`, `hasPaintOps`, `addPaintOp`, `undoPaintOp`, `clearPaintOps`.
- `previewPaint(rel)` — PNG preview with the journal replayed (downscaled).
- `applyPaint({allSprites})` — bake into the emote's sprite files (or all),
  per-frame-stable, in place via `_writeSpriteInPlace`; clears the journal.
- `pickColorAt(nx, ny)` — eyedropper.
- `userGradients`, `saveGradient`, `deleteGradient`.

---

## 6. How to add to it

- **A blend mode:** add a value to `PaintBlend`, a `label` in `PaintBlendInfo`, and
  a case in `blendRgb` (HSL helpers `_rgb2hsl`/`_hsl2rgb` are there if you need
  them). It immediately works for fills and brushes.
- **A gradient type:** add to `GradientType` + `GradientTypeInfo.label`, then a
  `case` in `Painter.fillGradient`'s `tAt`.
- **A brush mode:** add to `BrushMode` + label, and a `case` in `Painter.stroke`'s
  mode switch.
- **A selection kind:** add to `SelectionKind` + label, and a `case` in
  `PaintSelection.build`.
- **A gradient preset:** add a line to `GradientLibrary._build()`.

Add a test in `test/paint_test.dart` for anything you touch (the engine is pure,
so it's cheap to cover).
