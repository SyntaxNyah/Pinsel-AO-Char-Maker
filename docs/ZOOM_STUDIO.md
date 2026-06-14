# Zoom Studio

The dead-simple **"this sprite is too far away — pull it in"** screen.

Some character art sits tiny in a big, mostly-empty frame. In-game that means a
small character lost in the AO viewport. The Zoom Studio lets you **frame the
character with a virtual camera** — mouse-wheel to zoom, drag to pan — and bake
that framing into the sprite (or the whole cast at once) so it fills the screen.

> Open it from the **Zoom** tab (the magnifier icon). It needs a character
> loaded (it edits real sprites).

---

## 1. The idea: a normalized camera

The framing is just a tiny **camera** over the sprite:

- **zoom** — `1×` shows the whole sprite, `>1` zooms in (crops to the focus and
  scales up), `<1` zooms out (shrinks the character, transparent margin appears).
- **focus** — the point of the sprite (0..1 in each axis) that lands in the
  centre of the result.

Because the camera is *normalized*, the **same** camera applied to every sprite
produces the **same** transform — so the whole cast stays aligned in-game (AO
anchors and rescales sprites; mismatched framing makes poses visibly jump when
you switch emotes or talk). That's why **"Whole cast"** is the default Apply
target.

The maths is a crop to the camera's region followed by one high-quality resize
(`imaging/sprite_zoom.dart` → `SpriteZoom.apply`). It runs **per frame on an
isolated single-frame copy** of each frame, so every frame of an animation (and
every `(a)/(b)/(c)` of an emote) round-trips with its frame count + timing
intact.

---

## 2. The canvas (WYSIWYG)

The big canvas shows **exactly what AO will display** — a live, instant preview
(it's a pure widget-layer transform of the sprite, so wheel/drag never lag and
nothing is re-encoded until you press Apply).

| Input | Does |
|-------|------|
| **Mouse wheel** | Zoom toward the cursor |
| **Drag** | Pan the camera |
| **+ / −** | Zoom in / out |
| **Arrow keys** | Recenter (nudge the focus) |
| **R** or **0** | Reset the camera |
| **G** | Toggle the rule-of-thirds grid |
| **F** | Auto-frame |

A **rule-of-thirds grid** with a centre crosshair overlays the canvas as a
framing guide (toggle it with the grid button or **G**). The transparent
checkerboard behind the sprite shows where margin will be when you zoom out.

Across the bottom is a **strip of every pose** — click a thumbnail to switch
which sprite the camera is framing without leaving the screen.

---

## 3. Auto-frame

Don't want to fiddle? Press **Auto-frame** (or **F**). It finds the character by
its visible pixels and frames it automatically, leaving a little breathing room.

When the Apply target is **Whole cast**, auto-frame computes **one** framing from
the **union** of every sprite's content — so the result still keeps the cast
aligned (it never frames each pose independently, which would desync them). It
only ever zooms *in*; if the character already fills the frame it leaves it
alone.

Auto-frame only **sets the sliders** — review it on the canvas, tweak if you
like, then Apply.

---

## 4. Apply

- **Whole cast** *(default, recommended)* — bakes the same framing into every
  sprite, so the character is consistently sized across all poses.
- **This sprite** — only the selected emote's sprite group `(a)/(b)/(c)`.

The framing is applied to **every frame** of animated sprites and to all sprite
states of an emote, so animations and idle/talk stay in sync. Files are
re-encoded **in place** in their own format (WebP stays lossless WebP; APNG/PNG
fallback when the WebP encoder is unavailable) — your sprites' quality is never
traded away.

### Export resolution

Leave it at **1×** for AO (keeps the sprite's pixel size, the character just
appears bigger because it fills more of the frame). Bake at **2×** to render the
zoom at twice the resolution for a crisper result on big HD themes — uniform, so
alignment is unchanged.

---

## 5. For developers

- Engine: `lib/src/imaging/sprite_zoom.dart` — `SpriteZoomSpec` (zoom / focus /
  outputScale, JSON round-trip) + `SpriteZoom.apply` (frame-aware bake) +
  `SpriteZoom.fitToContent` (the union auto-frame). Pure Dart, tested in
  `test/sprite_zoom_test.dart`.
- Constants: `ZoomLimits` in `lib/src/core/ao_constants.dart`.
- State: `AppState.applyZoom(spec, {allSprites})` and
  `AppState.computeAutoFrame({allSprites})` (mirror `applyEdit`/the Edit screen;
  reuse `_writeSpriteInPlace` for lossless in-place writes).
- UI: `lib/src/ui/screens/zoom_studio_screen.dart`. The live canvas is a
  widget-layer transform (no re-bake on wheel ticks) — keep heavy work on the
  Apply path only.
