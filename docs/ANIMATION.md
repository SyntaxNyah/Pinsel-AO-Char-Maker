# Animation

AO sprites are just multi-frame images, so "make the character move/glow" means
"generate an animated `(a)`/`(b)` sprite". Pinsel does that for you — pick a
recipe, tune intensity, export. No animation knowledge required, but full
keyframe control is there if you want it.

Everything exports as a standard animated sprite that works natively in AO.
**Animated WebP is the default** output (native uses `libwebpmux`); if WebP isn't
available on the current platform it transparently falls back to **APNG** (which
is also ideal for 2D visual-novel sprites), so you always get a working file.

## One-click recipes

A recipe is an `AnimRecipe(type, p: {...}, colors: {...}, ease: '...', region: ...)`.
Common params: `intensity`, `cycles`. **Stack** several to combine them.

### Movement
`sway`, `bob`, `bounce`, `float`, `breathe`, `breatheSway`, `breatheHeavy`,
`shake`, `shiver`, `spin`, `tilt`, `wiggle`, `zoomPulse`, `jump`, `gallop`,
`pant`, `nod`, `headShake`, `swing`, `drift`, `orbit`, `heartbeat`, `pendulum`,
`vibrate`, `pop`, `wobble`, `squashStretch`, `rubberBand`, `jelly`, `tada`,
`recoil`, `lunge`, `duck`, `sideStep`, `figure8`, `levitate`

### Intros / transitions
`fadeIn`, `fadeOut`, `slideIn`, `slideOut`, `rollIn`, `rollOut`, `spiralIn`,
`dropIn`, `peek`, `springIn`, `anticipate`

### Visual effects
`glow` (color), `flash`, `pulse`, `rainbow`, `tintPulse` (color), `neon`
(color), `hologram` (color), `glitch`, `colorCycle`, `strobe`, `flicker`,
`fadeBlink`, `desaturatePulse`, `colorFlash` (color), `ghostFloat`,
`rainbowGlow`, `matrixGlitch`, `sheen`, `sparkle`, `throb`, `chromaPulse`,
`focusPull`, **`outlinePulse`** (color), **`auraGlow`** (color),
**`shadowDance`**

> The bold effects animate the spatial colour ops (`outline` / `glow` /
> `dropShadow`); see [COLOR_OPS.md](COLOR_OPS.md). `none` is the identity recipe,
> and the full list is discoverable at runtime via `AnimEngine.recipeTypes`.

### Stacking example — "float + glow + rainbow"
```dart
AnimEngine.render(base, [
  AnimRecipe('float',   p: {'intensity': 3}),
  AnimRecipe('glow',    p: {'intensity': 0.6}, colors: {'color': '#FFB8E0FF'}),
  AnimRecipe('rainbow', p: {'cycles': 1}),
], frames: 24, fps: 14);
```
Transforms add, scales multiply, opacities multiply, and colour ops concatenate.

## Easing
Every recipe takes an `ease` (see `Easing.names`): `linear`, `easeInOutSine`,
`easeOutQuad`, `easeOutBack`, `easeOutBounce`, `elastic`, and more. Easing is
what makes motion feel snappy or springy instead of robotic.

## Animate just a part (wave a hand, spin a limb)
Give a recipe a `region` (a rectangle of the sprite). The rest stays still while
that region animates as a layer on top:
```dart
AnimRecipe('swing',
  p: {'intensity': 14, 'cycles': 2},
  region: IntRect(x, y, w, h));   // the hand/arm box
```

## Frame-by-frame (assemble given frames)

Already have the frames drawn? Skip the procedural effects and stitch existing
sprites together into one animation. In the app: **Animate → Frames**, tap
sprites to build an ordered **Sequence**, set **fps / reverse / ping-pong /
align**, and **Save**. Frames of different sizes are padded onto a shared canvas
(bottom-aligned by default, so sprites keep standing on the floor).

In code it's just an `AnimClip` of the frames you choose:
```dart
import 'package:pinsel/src/animation/anim_clip.dart';

final clip = AnimClip(<AnimFrame>[
  AnimFrame(frame0, delayCentis: 10), // 10 cs = 100 ms per frame (≈10 fps)
  AnimFrame(frame1, delayCentis: 10),
  AnimFrame(frame2, delayCentis: 10),
]);
// `out.ext` is 'webp' when native libwebpmux is present, else 'apng'; on a
// fallback `out.webpError` says why (so a stray APNG isn't a silent mystery).
final ({Uint8List bytes, String ext, String? webpError}) out =
    await clip.encodePreferWebp();
```
`AppState.saveFrameSequence(rels, {fps, reverse, pingPong, align, prefix, name})`
does this end-to-end (normalise → order → encode WebP/APNG → drop into the
project), with `renderFrameSequence(...)` for the live preview.

## Animate every sprite at once
The Animation Studio's **Effects** mode has an **Animate ALL sprites (WebP)**
button: it renders the current effect stack onto *every* sprite at full
resolution and saves each as an animated WebP `(b)` talk sprite (APNG fallback),
replacing any existing same-state sprite. In code:
`AppState.bulkAnimateAll(recipes, {frames, fps, prefix, lossless, quality})`
returns how many sprites it animated, and the status line reports how many came
out as WebP vs APNG (with the reason for any fallback).

The heavy render+encode for each sprite runs **off the UI isolate** (via
Flutter's `compute`, inline on web) and fans out across **all CPU cores** — up to
`maxConcurrency` sprites encode at once instead of one-at-a-time (toggle on Home,
details in [PERFORMANCE.md](PERFORMANCE.md)). It stays **lossless**
(`lossless: true` — bulk export must not degrade quality; responsiveness comes
from the background isolates, not from dropping to lossy). Bulk uses the built-in
effect recipes (plugin-registered recipe types aren't available in the worker
isolate).

## Talking mouth / lip-sync

The headline path needs **zero extra art**: from one drawing, Pinsel fakes a
talking `(b)` animation by dropping the jaw inside a mouth box with a natural,
**seamless-looping** cadence. Full guide: **[LIPSYNC.md](LIPSYNC.md)**.

In the app: **Animate → Mouth**. A pink box marks the mouth (auto-placed on the
face); the preview loops so you can **see it talking** and **adjust** the box
(Mouth X/Y, Width, Height), the **Open amount**, frames and speed. Then **Save as
(b) talk** / **(a) idle**, or **Talking mouth on ALL sprites** to do the whole
cast at once (baked across all CPU cores — see [PERFORMANCE.md](PERFORMANCE.md)).

```dart
import 'package:pinsel/src/animation/lipsync.dart';

// Zero extra art: a natural, looping talking animation from ONE sprite.
LipSync.talk(sprite, openAmount: 0.32, frames: 8, fps: 10);
// (mouth box defaults to LipSync.defaultMouthRegion(sprite) — the face's lower
// third — or pass your own IntRect.)

// Already have mouth art? Closed + open → a looping talking animation:
LipSync.twoState(closedImage, openImage);
// Several mouth shapes (visemes), cycled naturally:
LipSync.fromVisemes([closed, half, open], pingPong: true);
// The original single-pulse jaw-drop is still available as LipSync.auto(...).
```
`AppState.previewMouthTalk(mouth, ...)` drives the live preview;
`saveMouthTalk(mouth, {prefix, ...})` bakes one sprite; `bulkMouthTalkAll(...)`
does every sprite (auto mouth per face). All save as animated WebP (APNG
fallback) and drop into the project so they're exported.

## Manual keyframe timeline (advanced)
```dart
import 'package:pinsel/src/animation/timeline.dart';

final tl = Timeline([
  Keyframe(time: 0.0, dy: 0,   ease: 'easeOutQuad'),
  Keyframe(time: 0.5, dy: -12, scale: 1.05),
  Keyframe(time: 1.0, dy: 0),
]);
final clip = tl.render(base, frames: 16, fps: 12);
```
Each keyframe sets `dx, dy, scale, angle, opacity, hue` and the easing for the
segment that starts at it. Pinsel interpolates the rest.

## In the app
The **Animate** screen: pick a preset or add effects, tune intensity/frames/fps,
choose easing, watch the live looping preview, then **Save as (b) talk** or
**(a) idle** — the file is added to your project *and* downloaded.

## Adding a recipe (native plugin)
```dart
ExtensionRegistry.instance.registerRecipe('mySpin', (t, r) =>
    FrameSpec()..angle = 360 * r.n('cycles', 1) * t);
```
Packs can then reference `"type": "mySpin"` in their `animPresets`.
