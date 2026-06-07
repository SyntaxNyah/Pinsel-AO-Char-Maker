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
   * **Lobes** — split the box into N side-by-side lobes that bounce out of
     phase. **2 = boobs** (two breasts alternating, the natural look); 1 = a
     single region; 3–6 for rows of jiggling parts.
   * **Lobe spread** — phase offset between lobes (0.5 = exactly opposite).
   * **Realism (soft-body physics):**
     * **Gravity** — a heavier, quicker fall and a gentler rise (weighty flesh).
     * **Follow-through** — the swinging end lags the base, so the jiggle ripples
       *through* the flesh as a wave. This is the biggest "pro animation" tell.
     * **Organic** — a touch of extra harmonic so it isn't a robotic sine.
     * **Anchor** — where the pinned point sits: 0 = pinned at the top (hangs and
       swings below — boobs/hair), 0.5 = centre-pinned (both ends free).
   * **Motion styles (more ways to move):**
     * **Circular (2D ellipse)** — adds a perpendicular wobble 90° out of phase so
       the tip traces a little **ellipse** instead of straight up/down (natural).
     * **Swirl** — a back-and-forth **rotation** of the region about its centre.
     * **Pulse** — the jiggle **swells and fades** once per loop (breathing
       intensity). See the **Motion** preset group (Circular/Swirl/Pulse/Orbit/
       Hypnotic). All default to off and add no real cost.
   * **Preset** — pick from **180+ presets** (the **Bust** group leads — premium
     twin chest physics with gravity + follow-through; then a **Physics** group
     and subtle/bouncy/jelly/sway/wild…) as a starting point; it keeps the box
     you placed and adopts its physics.
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

* The displacement is **zero at the influence boundary** (an **elliptical/radial**
  falloff that feathers out to ~1.35× the box radius — not a rectangle, so there's
  no visible box edge), so the warped flesh joins the static body with
  **no seam** — this is the whole reason it stops looking like a cut-out.
* Motion is largest at the **free end** of the region and ~zero at the
  attachment (the anchored "hang"), so it swings rather than slides.
* **Squash & stretch** is coupled to velocity (tallest whipping through centre),
  and **sway** adds a lateral, free-end-weighted wobble.

Per frame `t ∈ [0,1)` the time-varying drive is:

```
w      = 2π · frequency · t + phase
osc(a) = sin(a) + bounciness·0.4·sin(2a+0.6)        // base + springy overshoot
         − gravity·0.28·cos(2a)                      // asymmetric fall vs rise
         + organic·0.22·sin(3a+1.7)                  // less-robotic harmonic
weight = 0 at the pinned point (anchor) → 1 at the swinging end
osc_p  = lerp(osc(w), osc(w − followThrough·0.9), weight)  // tip lags = wave
disp   = direction·(amplitude·osc_p·weight)          // anchored bounce
       + squash·velocity stretch (along) / squeeze (across)
       + sway·(lateral, ×weight)
sample = (x,y) − disp · mask                          // inverse map, bilinear
```

Every `osc` harmonic is an **integer** multiple of `w`, so the whole thing is
periodic — `t=0` equals `t=1` and the loop is seamless (the unit test asserts
this). `gravity`, `organic`, `followThrough` and `anchor` all default to 0, which
reproduces the original motion exactly, so existing presets are unchanged.

`frequency` is a whole number so the oscillators are periodic and `t=0 == t=1`
(seamless loop). Amplitude is a fraction of the region height
(resolution-independent), so the **preview** (downscaled) and the **export**
(full-res) deform by the same relative amount. On a flat sprite there is no data
hidden behind the region, so a continuous warp is the most natural jiggle
achievable.

### Lobes (boobs)

`lobes: N` splits the drawn box into N side-by-side lobes (with a ~10% gap)
that warp **out of phase** by `spread` (0.5 = opposite). **`lobes: 2`** is two
breasts bouncing alternately — far more convincing than one symmetric block — so
the **Bust** presets ship with it and the Jiggle tab defaults to a bust preset.
`twin: true` is kept as the back-compat shorthand for `lobes: 2`.

### Draw-around (freeform lasso)

Instead of a box, hit **Draw region ✏️** in the Jiggle tab and **trace a shape**
around exactly what should jiggle (e.g. the breasts). The outline is stored on
`JiggleSpec.poly` (fractions); `warpJiggle` then masks to that **exact polygon
with a feathered edge** — the inside *and* edges jiggle and blend into the body,
no rectangle. A drawn region is one shape (lobe-splitting is skipped); "Back to
box" clears it. You can mix multiple boxes and drawn shapes via the **Boxes**
chips. (Multiple boxes/shapes + a per-box sprite picker live in the same tab.)

## In code

```dart
import 'package:pinsel/src/animation/jiggle.dart';
import 'package:pinsel/src/animation/anim_engine.dart';

final j = const JiggleSpec(
  x: 0.27, y: 0.34, w: 0.46, h: 0.21,   // region (fractions)
  amplitude: 0.18, frequency: 2, bounciness: 0.62, squash: 0.7,
  sway: 3, direction: 0,                 // 0° = up/down
  lobes: 2, spread: 0.5,                 // two out-of-phase lobes (boobs)
  gravity: 0.5, organic: 0.4, followThrough: 0.65, // soft-body realism
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
