# Performance & "advanced" capabilities

Pinsel is built to stay responsive on big jobs and to use the hardware you have.
Two layers do the heavy lifting: the **GPU** renders previews, and **all CPU
cores** bake the final, full-resolution output.

## GPU-rendered live previews

Flutter draws the whole UI on the GPU (the Impeller renderer). On top of that,
the **Colour Lab** previews matrix-representable adjustments **entirely on the
GPU**: instead of CPU-baking a new image on every slider tick, it lays a
`ColorFilter` colour-matrix over the already-decoded sprite, so the maths run on
the compositor. Drag Brightness/Contrast and it updates instantly with zero
work on the UI isolate — you'll see a small **GPU live preview** badge.

This path is **exact, not an approximation**: it's used only when *every* op in
the live pipeline is a true linear RGBA transform, so the preview matches what
"Apply" bakes. The representable set (`imaging/color_matrix.dart`):

> brightness, contrast, exposure, invert, grayscale, sepia, temperature, tint,
> solidColor, opacity — plus any preset built only from those.

Anything non-linear — HSV ops (hue/saturation/vibrance/colorize), tone curves
(gamma/levels/posterize) or spatial ops (blur/outline/glow) — transparently
falls back to the CPU-baked preview, so the result is always faithful.

`ColorMatrix.tryBuild(pipeline)` returns the 20-value `ColorFilter.matrix` list,
or `null` to signal "use the CPU path." It's exposed as
`AppState.liveColorMatrix(pipeline)`.

## Smooth dragging (button framing, crop boxes, the big editor)

Direct-manipulation editors (the Buttons **big framing editor** and the inline
crop-box editor, the Edit screen) are tuned so a drag never does heavy work per
frame:

- **The transparency checkerboard is one GPU-tiled draw.** `CheckerImage` paints
  a single rect filled with a cached 2×2 tile via an `ImageShader` (repeated by
  the GPU) instead of a `drawRect` per cell — a full-screen zoom/pan canvas used
  to issue *thousands* of draw calls per frame; now it's one. It's also wrapped
  in a `RepaintBoundary`, so panning/moving it just re-composites a cached layer.
- **A box drag updates only the canvas, not the whole panel.** While you drag,
  the editor renders a local "live" box and writes the value to state *without*
  rebuilding the surrounding sliders/preview/thumbnails; the one heavy refresh
  (preview re-render + thumbnail) happens **once on release**.
- **Previews & list thumbnails crop a downscaled source.** Button previews and
  the 100+ sprite-list thumbnails render from a cached **≤640px** copy of each
  sprite (`_decodeButtonSource`), not the full-res image — cropping/resizing a
  small image is an order of magnitude cheaper. The exported buttons still use
  the full-resolution sprite, so quality is unaffected.
- **Thumbnails invalidate per-sprite.** Editing one sprite's crop box re-renders
  exactly that one thumbnail (keyed by `AppState.buttonThumbKey`), not every
  visible thumbnail in the list.
- **Thumbnails are cached, so scrolling is cheap.** The sprite-list `ListView`
  recycles rows; without a cache, every thumbnail re-decoded + re-rendered the
  framed button each time it scrolled back into view (the scroll lag on a big
  cast). `AppState.buttonThumb`/`cachedButtonThumb` cache the rendered PNG per
  sprite, so a re-appearing row is an **instant, synchronous** cache hit — it only
  actually renders when that sprite's framing changes. The big editor also
  **debounces** the canvas sprite decode (70 ms) so blasting through the cast with
  the keyboard only decodes the sprite you settle on, and `headSquare` (the
  face-detect used to seed a box) runs on the ≤640px source, not full-res.
- **The overlay "Big editor" preview is debounced** (it re-draws the 512px
  overlay 60 ms after you stop, not on every slider tick).

## Multi-core baking

The expensive operations — **Animate ALL sprites**, **Talking mouth on ALL
sprites**, recolour/edit/convert across many files, and the **one-click** WebP
conversion — render and encode each sprite on a background isolate (Flutter's
`compute`). Crucially, they fan out across cores: up to **`maxConcurrency`**
sprites are processed **at once** rather than one-at-a-time.

* `cpuCores` — logical cores detected (`Platform.numberOfProcessors`; the
  browser's `navigator.hardwareConcurrency` on web).
* `maxConcurrency` — jobs kept in flight: `min(cpuCores, 8)` when multi-core is
  on, `1` when off. Capped at 8 so we never spawn an unreasonable number of
  isolates (each `compute` is one isolate).
* **Use all CPU cores** toggle (Home → Performance) flips `useAllCores`. Turn it
  off to keep the machine free for other apps; bulk jobs then run sequentially.

On **web**, `compute` runs inline (one true UI thread), so the cap is only an
upper bound — order and correctness are unchanged, there's just no real
parallelism.

### The runner

`mapParallel<T, R>(items, task, {concurrency, onProgress})`
(`imaging/parallel.dart`) is a tiny, pure-Dart windowed scheduler: it keeps
`concurrency` `task` futures in flight and **preserves input order** in the
result. It doesn't spawn isolates itself — the `task` decides whether to use
`compute` or run inline — so it's dependency-free and unit-tested
(`test/parallel_test.dart`).

```dart
final results = await mapParallel<Job, Out>(
  jobs,
  (job) => compute(worker, job),   // one isolate per in-flight job
  concurrency: maxConcurrency,
  onProgress: (done, total) => report(done, total),
);
```

## Why not a GPU compute shader for baking?

Baking has to be **byte-identical on all six targets** (Windows/Linux/macOS/
Android/iOS/Web) and feed straight into the WebP/APNG encoders. A portable
GPU compute path for the full 43-op pipeline isn't available across all of those,
so the **final** bake stays on the CPU (deterministic, identical everywhere) and
gets its speed from running on every core. The GPU is used where it's a perfect
fit and always available: **rendering** (previews + the whole UI).
