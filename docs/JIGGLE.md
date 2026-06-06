# Jiggle physics

Bounce a **part** of a sprite — chest, hair, belly, anything — by dragging a box
over it and dialing in how it moves. The result is baked as a looping animated
sprite, so it plays in-game with no extra work.

> **What it is (and isn't):** this is a **looping oscillation tuned to feel
> springy**, not an impulse/settle physics simulation. A true damped spring
> decays and wouldn't loop seamlessly, so instead the motion is a periodic bounce
> with an overshoot harmonic that *reads* as jiggle and loops forever.

## In the app: **Animate → Jiggle**

1. Open **Animate** and pick the **Jiggle** tab, then select an emote.
2. **Drag the box** in the preview over what should jiggle (corner/edge handles
   resize it — same as the mouth box).
3. Tune it (every knob is live):
   * **Direction** — the **angle** the bounce travels along: `0°` = up/down,
     `90°` = left/right, anything between = diagonal. Jiggle in *any* direction.
   * **Bounce amount** — how far it travels (as a % of the box height).
   * **Speed (bounces per loop)** — how fast it bounces.
   * **Bounciness** — how much springy overshoot rides on top.
   * **Softness (squash & stretch)** — how much it squashes as it moves.
   * **Sway (rotation)** — a little rotational wobble.
   * **Preset** — pick from **100+ presets** (subtle, bouncy, jelly, sway, wild…)
     as a starting point; it keeps the box you placed and adopts its physics.
4. **Save as (a) idle** — jiggle is an idle motion, so it saves as the `(a)`
   sprite (plays while the character is just standing there). WebP, APNG
   fallback.
5. **Jiggle ALL sprites** applies the same box + settings to every sprite, baked
   across all CPU cores (see [PERFORMANCE.md](PERFORMANCE.md)).

## How it works

A `JiggleSpec` is the region (as **fractions** of the sprite) plus the physics
knobs. It becomes an [`AnimEngine`](ANIMATION.md) `jigglePhysics` recipe on that
region (`JiggleSpec.toRecipe`), so it reuses the tested region-as-layer
compositing, looping and WebP/APNG encode. The region is cut, transformed
(translate along the direction + squash/stretch + sway) per frame, and
composited back over the otherwise-static sprite.

Per frame `t ∈ [0,1)`:

```
w   = 2π · frequency · t + phase
osc = sin(w) + bounciness · 0.45 · sin(2w + 0.5)   // base + overshoot
dx  = amplitude · osc · sin(direction)
dy  = amplitude · osc · cos(direction)
scaleY = 1 + squash · 0.16 · cos(w)                // tallest at peak velocity
scaleX = 1 − 0.6 · (that)
angle  = sway · sin(w)
```

`frequency` is a whole number so frame *n‑1 → 0* is seamless. Amplitude is a
fraction of the region height (resolution-independent), so the **preview**
(downscaled) and the **export** (full-res) bounce by the same relative amount.

Center-anchored motion reads well for chest/body at sensible amplitudes; the
default amplitude is kept modest because very large travel reveals the
rectangular region's edges.

## In code

```dart
import 'package:pinsel/src/animation/jiggle.dart';
import 'package:pinsel/src/animation/anim_engine.dart';

final j = const JiggleSpec(
  x: 0.30, y: 0.33, w: 0.40, h: 0.18,   // region (fractions)
  amplitude: 0.18, frequency: 3, bounciness: 0.7, squash: 0.6,
  sway: 0, direction: 0,                 // 0° = up/down
);
final clip = AnimEngine.render(sprite, <AnimRecipe>[j.toRecipe(sprite.width, sprite.height)],
    frames: 18, fps: 16);
```

`JiggleSpec` JSON-round-trips (`toJson`/`fromJson`) and is isolate-safe; the
catalogue is `jigglePresets` / `jiggleCategories` / `jiggleByName(name)`.

`AppState`:

* `previewJiggle(specs, {frames, fps})` — looping preview frames.
* `saveJiggle(specs, {prefix = '(a)', frames, fps})` — bake the selected sprite.
* `bulkJiggleAll(specs, {prefix = '(a)', frames, fps})` — every sprite, across all
  CPU cores.

See also [ANIMATION.md](ANIMATION.md) and [LIPSYNC.md](LIPSYNC.md).
