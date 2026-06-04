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
