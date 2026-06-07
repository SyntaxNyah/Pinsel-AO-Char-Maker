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
   * **Twin lobes (boobs)** — split the box into a **left + right lobe** that
     bounce in **opposite phase**. This is what reads as two breasts instead of
     one block; it's on by default for the **Bust** presets.
   * **Preset** — pick from **100+ presets** (the **Bust** group leads — twin
     chest physics; then subtle, bouncy, jelly, sway, wild…) as a starting point;
     it keeps the box you placed and adopts its physics.
4. **Save as (a) idle** — jiggle is an idle motion, so it saves as the `(a)`
   sprite (plays while the character is just standing there). WebP, APNG
   fallback.
5. **Jiggle ALL sprites** applies the same box + settings to every sprite, baked
   across all CPU cores (see [PERFORMANCE.md](PERFORMANCE.md)).

## How it works

A `JiggleSpec` is the region (as **fractions** of the sprite) plus the physics
knobs. It becomes an [`AnimEngine`](ANIMATION.md) `jigglePhysics` recipe on that
region (`JiggleSpec.toRecipe`); when **twin** is set, `JiggleSpec.toRecipes`
expands it into two opposite-phase lobe recipes instead.

### Soft-body warp (not a sliding rectangle)

The earlier version *cut out the rectangle and slid it* as a rigid block, which
looked like a moving cropped PNG (hard edges sliding over the body, the original
peeking out underneath). It's now a **per-pixel displacement warp**
(`AnimEngine.warpJiggle`) — the standard "puppet / liquify" technique. For each
destination pixel inside the region's influence it samples the source from a
slightly offset point (premultiplied bilinear), so the pixels that are *already
there* **stretch continuously** instead of a rectangle moving:

* The displacement is **zero at the influence boundary** (a smooth box mask that
  feathers out to 1.5× the box), so the warped flesh joins the static body with
  **no seam** — this is the whole reason it stops looking like a cut-out.
* Motion is largest at the **free end** of the region and ~zero at the
  attachment (the anchored "hang"), so it swings rather than slides.
* **Squash & stretch** is coupled to velocity (tallest whipping through centre),
  and **sway** adds a lateral, free-end-weighted wobble.

Per frame `t ∈ [0,1)` the time-varying drive is:

```
w    = 2π · frequency · t + phase
osc  = sin(w) + bounciness · 0.4 · sin(2w + 0.6)   // base + springy overshoot
hang = 0 at the anchored edge → 1 at the free end (along `direction`)
disp = direction·(amplitude·osc·hang)              // anchored bounce
     + squash·velocity stretch (along) / squeeze (across)
     + sway·(lateral, ×hang)
sample = (x,y) − disp · mask                        // inverse map, bilinear
```

`frequency` is a whole number so the oscillators are periodic and `t=0 == t=1`
(seamless loop). Amplitude is a fraction of the region height
(resolution-independent), so the **preview** (downscaled) and the **export**
(full-res) deform by the same relative amount. On a flat sprite there is no data
hidden behind the region, so a continuous warp is the most natural jiggle
achievable.

### Twin lobes (boobs)

`twin: true` splits the drawn box down the middle into a left + right lobe (with
a ~10% cleavage gap) that warp **in opposite phase**. Two breasts bouncing
alternately reads far more like real chest physics than one symmetric block — so
the **Bust** presets ship with it on, and the Jiggle tab defaults to one.

## In code

```dart
import 'package:pinsel/src/animation/jiggle.dart';
import 'package:pinsel/src/animation/anim_engine.dart';

final j = const JiggleSpec(
  x: 0.28, y: 0.34, w: 0.44, h: 0.20,   // region (fractions)
  amplitude: 0.16, frequency: 2, bounciness: 0.55, squash: 0.6,
  sway: 2, direction: 0,                 // 0° = up/down
  twin: true,                            // split into two out-of-phase lobes
);
// toRecipes() handles twin (1 or 2 recipes); toRecipe() is the single-region form.
final clip = AnimEngine.render(
    sprite, j.toRecipes(sprite.width, sprite.height),
    frames: 18, fps: 16);
```

`JiggleSpec` JSON-round-trips (`toJson`/`fromJson`, incl. `twin`) and is
isolate-safe; the catalogue is `jigglePresets` / `jiggleCategories` /
`jiggleByName(name)` (the **Bust** category leads). `AnimEngine.warpJiggle(src,
recipe, t)` is the pure, isolate-safe soft-body warp behind it all.

`AppState`:

* `previewJiggle(specs, {frames, fps})` — looping preview frames.
* `saveJiggle(specs, {prefix = '(a)', frames, fps})` — bake the selected sprite.
* `bulkJiggleAll(specs, {prefix = '(a)', frames, fps})` — every sprite, across all
  CPU cores.

See also [ANIMATION.md](ANIMATION.md) and [LIPSYNC.md](LIPSYNC.md).
