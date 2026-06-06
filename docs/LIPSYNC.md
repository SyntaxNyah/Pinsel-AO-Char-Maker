# Talking mouths — VN-style lip-sync

Make a character **talk like a visual-novel sprite** — without drawing a single
extra frame. Give Pinsel one static drawing (a Danganronpa / Umineko / DR-style
bust, anything) and it fakes a talking `(b)` sprite by dropping the jaw inside a
small mouth box with a chosen **"way of talking"** — a natural, irregular,
**seamless-looping** speech cadence (so AO can loop it forever with no visible
seam).

> In Attorney Online, `(a)foo` is the idle sprite and `(b)foo` is the *talking*
> sprite played while the character speaks. A talking mouth is just an animated
> `(b)` sprite.

## Hundreds of ways of talking

This is the headline feature. Instead of one generic flap, Pinsel ships a
**catalogue of hundreds of named talk styles** (`LipSync.styleCatalogue`),
generated from ~60 expressive archetypes × {base, Soft, Intense, Fast, Slow}
across categories:

| Category    | Examples |
|-------------|----------|
| **Calm**      | Natural, Narration, Monotone, Gentle, Formal, Deadpan, Confident |
| **Energetic** | Excited, Cheerful, Hyper, Bubbly, Peppy, Chattering, Rambling |
| **Loud**      | Shouting, Angry, Furious, Commanding, Booming, Menacing, Villainous |
| **Soft**      | Whisper, Shy, Timid, Sleepy, Tired, Mumbling, Breathy, Hesitant |
| **Emotional** | Sobbing, Crying, Trembling, Nervous, Panicked, Anxious, Pleading |
| **Stylised**  | Robotic, Glitchy, Singing, Chanting, Stuttering, Laughing, Smug, Dramatic, Tsundere, Yandere, Cute… |

Each style is a small set of numbers describing *how* the mouth moves over one
loop:

* **rate (`syllables`)** — mouth-opens per loop (fast chatter ↔ slow speech).
* **openAmount** — peak jaw drop.
* **jitter** — rhythm irregularity (metronomic ↔ uneven/chattery).
* **pause** — gaps between words/phrases (the mouth falls quiet).
* **tension** — resting openness (a mumbler never fully closes).
* **bob** — a subtle head bob (a few px), like a Live2D sway, for extra life.

This mirrors how VN / Live2D engines drive a `0..1` "mouth open" parameter from a
voice line — except here the curve is *generated* to read like speech, so you
don't need any audio or extra art.

## In the app: **Animate → Mouth**

1. Open the **Animate** screen and pick the **Mouth** tab.
2. Select an emote (Emotes tab) — its sprite loads with a **pink mouth box**
   already placed on the face.
3. Tap **Way of talking** and pick a style (search by name — "excited",
   "whisper", "robotic" — or filter by category). The preview **loops, talking**
   in that style straight away.
4. **Place the box on the lips by dragging it right in the preview** (sliders are
   optional now):
   * **Drag the pink box** — move it anywhere.
   * **Drag the bottom-right corner** handle — resize (width + height).
   * **Drag the right edge** handle — stretch the width; **bottom edge** — the
     height.
   * **Auto-place on face** — snap the box back onto the detected face.
   * **Openness / jaw drop** — fine-tune how far the jaw drops on top of the
     chosen style.
   * **Frames / Speed (fps)** — length and pace of the talk loop (more frames =
     smoother fast styles).
   * The **Mouth X/Y/Width/Height sliders** are still there for precise nudging.
5. **Choose how the mouth opens** with the **Auto / Anime / Mesh** toggle (see
   the next section).
6. **Save as (b) talk** (or the moon icon for **(a) idle**). The animated WebP is
   dropped into your project *and* downloaded.
7. **Talking mouth on ALL sprites** gives every expression its own face-placed
   talking mouth — in the chosen style — in one action (baked across all CPU
   cores; see [PERFORMANCE.md](PERFORMANCE.md)).

Everything saves as **animated WebP** (the default here), falling back to **APNG**
if WebP isn't available on the platform — so you always get a working sprite.

## Three ways to open the mouth

The **Mouth opening** toggle in the Mouth tab picks how the lips actually part:

### Auto (procedural) — works on any sprite
The lip line drops and a **soft, feathered dark cavity** opens between the lips —
the mouth genuinely opens and closes, not the chin stretching. The cavity is
clipped to the silhouette and feathered at the sides so it melts into the lips on
any art style. Nothing to draw.

### Anime mouths (drawn shapes) — preset open mouths
Pick from **100+ drawn open-mouth shapes** (`LipSync.mouthShapes`): round, small
o, wide, tall gasp, agape, soft, pout, smile/grin/beam (with teeth), tongue
out/lick, each in Small/Big/Wide/Narrow/Teeth/Tongue/Smiley variants. The chosen
shape is drawn into the mouth box and grows/shrinks on the talk cadence. Each
shape is a few numbers (width, height, curve, fill, teeth, tongue) so it scales
crisp to any size.

### Mesh (cut a real open mouth) — the most accurate
Have art of the **same character with their mouth open**? Pick **Mesh →
open-mouth sprite**. Pinsel cuts the mouth out of it at your box, **feathers the
edges** (an elliptical alpha fade) so the seams blend, and **cross-fades** that
real open mouth in and out on the talk cadence. Position the box on the mouth
first — the same box is cut from the open-mouth sprite. This is the quality path
when you have the art.

In all three, the **timing** comes from the chosen [talk style](#hundreds-of-ways-of-talking):
the openness over one loop (`styleOpenness`) is built from per-syllable Gaussian
pulses — placed evenly, then **jittered and occasionally silenced**
(deterministically, from the style's name) — times a slow "breath" dip for phrase
pauses. It's periodic (frame *n‑1 → 0* is continuous) but irregular enough to
read as real talking. A style's **bob** also nudges the whole frame a couple of
px in sync (capped to a few px), which sells "alive" without fighting AO's fixed
desk.

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

// Pick a style by name (or browse LipSync.styleCatalogue / styleCategories).
final style = LipSync.styleByName('Excited');       // or LipSync.defaultStyle

// One sprite → a natural VN talking loop in that style. `mouth` defaults to the
// face-derived box; `openAmount` overrides the style's jaw drop when given.
final clip = LipSync.talkStyled(
  sprite,
  style,
  mouth: LipSync.defaultMouthRegion(sprite),         // or your own IntRect
  frames: 10,
  fps: 12,
);
final out = await clip.encodePreferWebp();           // (bytes, ext, webpError)
```

`LipSync.talk(...)` is still available (the original default cadence) for
back-compat; `talkStyled` is the styled superset.

**Drawn anime mouth** — pass a `MouthShape` to `talkStyled`:

```dart
final shape = LipSync.mouthShapes.firstWhere((s) => s.name == 'Grin');
final clip = LipSync.talkStyled(sprite, style, shape: shape);
```

**Mesh a real open mouth** — cut it from another sprite and blend it in:

```dart
final region = LipSync.defaultMouthRegion(closedSprite);
final piece  = LipSync.cutMouthPiece(openMouthSprite, region); // feathered
final clip   = LipSync.talkMeshed(closedSprite, piece, region, style);
```

`MouthRegion` expresses the box as **fractions** (`0..1`) of the sprite, so it
survives downscaled previews and maps onto any sprite size:

```dart
const m = MouthRegion(0.32, 0.40, 0.36, 0.07); // x, y, w, h
final px = m.toPixels(image.width, image.height);
final auto = MouthRegion.defaultFor(image);     // face-derived default
```

`AppState` ties it to the UI (each method takes an optional `style`, `shape`,
and a `mesh` flag):

* `previewMouthTalk(mouth, {frames, fps, openAmount, style, shape, mesh})` —
  looping preview.
* `saveMouthTalk(mouth, {prefix, frames, fps, openAmount, style, shape, mesh})` —
  bake one.
* `bulkMouthTalkAll({frames, fps, openAmount, style, shape, prefix})` — every
  sprite, each with its own face-placed mouth, across all CPU cores (mesh is
  single-sprite, so bulk uses the cavity or the drawn shape).
* `setMeshSprite(bytes, {ext})` / `hasMeshSprite` — load the open-mouth sprite
  to mesh from.
* `defaultMouthRegionFor(rel)` / `currentSpriteAspect()` — seed + size the editor.

`TalkStyle` is plain data (numbers + name + category), so it JSON-round-trips
(`toJson` / `fromJson`) and is **sendable to a background isolate** — the bulk
bake carries the chosen style into each `compute` worker unchanged.

See also [ANIMATION.md](ANIMATION.md) for the full animation system.
