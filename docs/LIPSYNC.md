# Talking mouths (lip-sync)

Give a character a mouth that **moves while they talk** — without drawing a
single extra frame. Pinsel fakes a talking `(b)` sprite from one drawing by
dropping the jaw inside a small mouth box, with a natural, irregular,
**seamless-looping** cadence (so AO can loop it forever with no visible seam).

> In Attorney Online, `(a)foo` is the idle sprite and `(b)foo` is the *talking*
> sprite played while the character speaks. A talking mouth is just an animated
> `(b)` sprite.

## In the app: **Animate → Mouth**

1. Open the **Animate** screen and pick the **Mouth** tab.
2. Select an emote (Emotes tab) — its sprite loads with a **pink mouth box**
   already placed on the face.
3. The preview **loops, talking**, so you can see exactly what will be saved.
4. **Adjust** until the box sits on the lips:
   * **Mouth X / Mouth Y** — move the box.
   * **Width / Height** — resize it.
   * **Open amount** — how far the jaw drops (subtle ↔ wide).
   * **Frames / Speed (fps)** — length and pace of the talk loop.
   * **Auto-place on face** — re-centre the box on the detected face.
5. **Save as (b) talk** (or the moon icon for **(a) idle**). The animated WebP is
   dropped into your project *and* downloaded.
6. **Talking mouth on ALL sprites** gives every expression its own face-placed
   talking mouth in one action (baked across all CPU cores — see
   [PERFORMANCE.md](PERFORMANCE.md)).

Everything saves as **animated WebP** (the default here), falling back to **APNG**
if WebP isn't available on the platform — so you always get a working sprite.

## How the fake works

The lower edge of the mouth box is stretched downward (a "jaw drop") by a
speech-like amount each frame. The openness over one loop is a sum of integer
harmonics — periodic (so frame *n‑1 → 0* is continuous) but irregular enough to
read as chatter rather than a mechanical open/close. No mouth interior is
painted in, so it works on any art style.

The default mouth box is derived from the **face**: Pinsel runs the same alpha-
silhouette head detector used for buttons, then places the box across the lower-
middle of the head — roughly where a mouth sits on a bust or full-body sprite.

## Already have mouth art?

If you've drawn proper mouth shapes, use them instead of the fake:

```dart
import 'package:pinsel/src/animation/lipsync.dart';

LipSync.twoState(closedMouth, openMouth);            // closed ↔ open, loops
LipSync.fromVisemes([closed, half, open]);           // cycle several shapes
```

## In code

```dart
import 'package:pinsel/src/animation/lipsync.dart';

// One sprite → a natural talking loop. `mouth` defaults to the face-derived box.
final clip = LipSync.talk(
  sprite,
  mouth: LipSync.defaultMouthRegion(sprite), // or your own IntRect
  openAmount: LipSync.defaultOpenAmount,     // 0.32
  frames: 8,
  fps: 10,
);
final out = await clip.encodePreferWebp();   // (bytes, ext, webpError)
```

`MouthRegion` expresses the box as **fractions** (`0..1`) of the sprite, so it
survives downscaled previews and maps onto any sprite size:

```dart
const m = MouthRegion(0.32, 0.40, 0.36, 0.07); // x, y, w, h
final px = m.toPixels(image.width, image.height);
final auto = MouthRegion.defaultFor(image);     // face-derived default
```

`AppState` ties it to the UI:

* `previewMouthTalk(mouth, {frames, fps, openAmount})` — looping preview frames.
* `saveMouthTalk(mouth, {prefix, frames, fps, openAmount})` — bake one sprite.
* `bulkMouthTalkAll({frames, fps, openAmount, prefix})` — every sprite, each with
  its own face-placed mouth, across all CPU cores.
* `defaultMouthRegionFor(rel)` / `currentSpriteAspect()` — seed + size the editor.

See also [ANIMATION.md](ANIMATION.md) for the full animation system.
