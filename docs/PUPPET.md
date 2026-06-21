# Puppet Studio — Live2D-style animated characters for AO

Turn a character that comes as **separate parts** (the way Live2D / gacha sprite
sheets ship — head, hair, eyes, mouth, body, accessories) into a gently
**animated** Attorney Online sprite: an idle `(a)` that breathes, sways and
blinks, and a talking `(b)` — **without animating any of the art by hand**.

> Engine: [`lib/src/puppet/puppet.dart`](../lib/src/puppet/puppet.dart) ·
> screen: `lib/src/ui/screens/puppet_studio_screen.dart` ·
> tests: [`test/puppet_test.dart`](../test/puppet_test.dart).

## The one constraint: AO renders sprites, not models

Attorney Online (and webAO) can't run a real Live2D/Cubism model or a 3D model —
the client only displays image sprites (animated WebP/APNG/GIF). So the Puppet
Studio **bakes** the rig down to ordinary AO sprites. You assemble + animate a
"puppet" here, and what AO ships is a normal animated `(a)`/`(b)` pair. (This is
also why a real `.moc3` importer isn't on the table — even if it parsed, it would
still have to bake to sprites, and the mesh/deformer format is proprietary.)

## In the app

Open the **Puppet** tab. Two ways to get parts in:

1. **Slice a sheet of parts** — pick a sprite sheet/atlas and it auto-detects the
   parts and loads them as layers (each placed at its position in the sheet).
2. **Add part files** — drop in separate PNG layers (e.g. a PSD exported to
   per-layer PNGs). These are assumed pre-aligned and stacked centred.

For a **tightly-packed atlas** (parts jammed together with no relation to where
they sit on the body), auto-detect can't know how to assemble them — use the
**Ripper** to box each part precisely, then **"Send to Puppet."** Either way you
finish the assembly by hand: drag the position/scale sliders so the parts line up
into a character. *Pinsel assembles the layers; it doesn't guess the pose.*

Then:

- **Layers panel** (left) — reorder z-depth (top of the list = drawn on top),
  toggle visibility, select a layer, remove one.
- **Preview** (centre) — the live animated result; flip between **Idle (a)** and
  **Talk (b)**. Name the emote and **Bake → animated emote**.
- **Controls** (right) — per-layer **Role**, position, scale, rotate, **pivot**,
  opacity, **phase**, and **idle motion**; plus global frames / fps / mouth-open.

### Roles drive the auto-animation

Each layer has a **role** (Body / Head / Hair / Eyes / Mouth / Accessory),
guessed from its file/cell name. The role seeds a sensible **pivot** and **idle
motion** so it just looks right:

| Role | Pivot | Idle motion |
|------|-------|-------------|
| Body | hips (bottom) | **breathe** (slow scale pulse) |
| Head | neck | **nod** |
| Hair | scalp (top) | **sway** (phase-offset, so it lags the body) |
| Accessory | upper | **sway** (different phase) |
| Eyes | centre | **blink** (periodic vertical squash) |
| Mouth | upper lip | still in idle; **opens** in the talk clip |

Changing a layer's role re-seeds its pivot/motion/phase to that role's defaults
(then tweak freely). Every motion is a real [Animation Studio](ANIMATION.md)
recipe under the hood, so the look matches the rest of the app.

### Talking

The **Talk (b)** clip adds a mouth open/close cadence to **every layer tagged
`Mouth`**. If no layer is a mouth, the talk clip is just the idle animation
(still a valid AO `(b)`). The **Mouth open** slider sets how far the jaw drops.

## What "bake" produces

Two clips, both rendered at the rig's canvas size (so `(a)` and `(b)` always
share dimensions and the character never jumps in-game):

- idle → `(a)<name>.webp`
- talk → `(b)<name>.webp`

They're added to the character as one new **emote** (lossless WebP; APNG
fallback). A perfectly static rig collapses to a single idle frame. From there
it's a normal emote — recolour it, frame its button, export from Home.

## Performance (it has to run on a phone)

A puppet is the heaviest thing the app renders (every layer, every frame), so:

- **The rig canvas is capped on import** (≈384 px on mobile, 768 px on desktop) —
  a sheet-sourced rig would otherwise inherit the *whole sheet's* size (often
  1024–2048 px), and rendering that × frames × layers **OOM-crashed the app on
  Android**. The whole rig (canvas + every part) is scaled by one factor, so the
  assembly is unchanged — just memory-safe. AO sprites are ~256–512 px anyway, so
  there's no real quality cost; nudge **Canvas W/H** up if you want a bigger bake.
- **The live preview renders at a reduced scale** (≤320 px, ≤240 on mobile),
  debounced, and a drag only repaints the slider — so editing stays smooth even
  though the final bake is full-res.
- The **bake** runs on the UI isolate like the other single-emote saves
  (`saveMouthTalk`); a heavy multi-layer bake briefly shows a busy indicator.

## Limitations (be honest)

- **Flat parts don't truly deform.** This is *cut-out* puppet animation (move /
  rotate / scale / squash whole parts around pivots), not mesh warping. Big
  motion on a flat part reveals there's nothing painted behind it. Keep idle
  motion subtle (the defaults are) and it reads as alive.
- **A packed atlas still needs hand-arranging** — auto-detect finds the parts but
  can't assemble the pose for you.
- **3D models aren't supported yet.** Rendering a `.glb`/`.gltf` to sprite angles
  needs an in-engine 3D renderer; it would live alongside this as a future part
  of the puppet section.

## In code

```dart
final PuppetRig rig = PuppetRig(width: 256, height: 256, layers: <PuppetLayer>[
  PuppetLayer.withRoleDefaults(bodyImg,  name: 'body',  role: PuppetRole.body),
  PuppetLayer.withRoleDefaults(hairImg,  name: 'hair',  role: PuppetRole.hair),
  PuppetLayer.withRoleDefaults(mouthImg, name: 'mouth', role: PuppetRole.mouth),
]);
final AnimClip idle = PuppetEngine.render(rig, frames: 16, fps: 12, talk: false);
final AnimClip talk = PuppetEngine.render(rig, frames: 16, fps: 12, talk: true);
```

`PuppetEngine.render` composites each visible layer per frame: it evaluates the
layer's `motion` recipes through `AnimEngine.frameSpec` (on a phase-shifted
clock), folds in the layer's static placement, then places the part by its pivot
with `AnimEngine.renderLayer` (the same verified transform the Animation Studio
uses). It reuses the **Ripper** (slice the atlas), nothing from a custom format.

`AppState` drives it: `addPuppetParts` / `puppetFromSheetCells` (Ripper handoff) /
`previewPuppet({talk})` / `bakePuppet({name})`.

## Related

- [SPRITE_RIPPER.md](SPRITE_RIPPER.md) — slice the atlas into parts first.
- [ANIMATION.md](ANIMATION.md) — the recipe library the idle motion is built on.
- [MIXER.md](MIXER.md) — the *static* "frankensprite" cousin (stack parts into one
  still sprite).
