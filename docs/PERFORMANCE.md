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

## Fast loading (decode only what you show)

AO's default sprites are **animated WebP**, and most of the UI only ever needs a
sprite's *first* frame — previews, the 100+ button thumbnails, the face-detect
that seeds crop/mouth boxes, the icon. Two changes keep that cheap on a big cast:

- **First-frame-only decode.** `Codecs.decodeFirstFrame` asks the decoder for
  **frame 0 only** (`decodeImage(bytes, frame: 0)`) instead of decoding the
  whole animation and discarding every frame but the first. On an 8-frame WebP
  that's roughly an 8× saving on every preview/thumbnail decode. It falls back to
  the tolerant full decode if the fast path can't handle the bytes, so nothing
  regresses.
- **Memoised face detection.** The head-square silhouette scan is a per-pixel
  hotspot during rapid framing navigation and mouth seeding. Its result is a
  resolution-independent fraction, so it's memoised per sprite path
  (`AppState._headSquareCache`) — stepping back and forth through a cast is then a
  map hit, not a re-scan. (It already ran on the ≤640px source, not full-res.)
  The cache is cleared alongside the others whenever pixels change or on
  import/reset.

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

## Memory & stability on big casts

A 200+ sprite cast of animated WebP is a lot of pixels. Two mechanisms keep a
big bulk bake from running the device out of memory (which on mobile shows up as
the OS **OOM-killing the app** — it looks like a crash):

- **Chunked, streaming bakes.** Bulk jobs (`bulkAnimateAll` / `bulkJiggleAll` /
  `bulkMouthTalkAll`) load + render + **write to disk** in batches of
  `_bulkChunk` sprites (100 on desktop, **16 on mobile**), freeing each batch
  before the next. Peak memory is bounded by the chunk, *not* by the cast size —
  the source bytes and encoded clips never all coexist. Earlier code held every
  source byte and every encoded clip at once and OOM-crashed a big mobile jiggle
  around ~70 sprites.
- **Concurrency capped (hard on mobile).** `maxConcurrency` is `min(cores, 8)` on
  desktop but **1 on Android/iOS** — each render isolate holds a full-res
  multi-frame clip, so even two at once exhausted RAM on a tablet. Mobile trades
  wall-time for staying alive.

### Cancel any long job

Every long bake — **Animate / Jiggle / Talking-mouth ALL**, **recolour /
convert all**, **apply Zoom / Edit / Paint**, and **bulk-build characters** — is
**cooperatively cancellable**. The status bar shows a real **progress bar**
(`AppState.progress`, 0..1) and a **Cancel** button (`requestCancel()`); the job
checks `_cancelled` at the next **chunk / sprite-group / file boundary** and stops
there.

This is the safety valve for a run that's heading toward an OOM kill, or that you
simply started by mistake on a huge cast. It's **safe**: work already written to
the workspace stays (nothing is rolled back), and a cancelled Paint even keeps its
op journal so you can resume. Because cancel lands at a chunk boundary, the
in-flight batch finishes first — so it's near-instant on mobile (16-sprite
chunks) and within the current batch on desktop (100).

`BulkProcessor.run` takes a `shouldCancel` callback for the same reason (the
convert path); it's checked before each file and unit-tested
(`test/bulk_processor_test.dart`).

## Audit — known opportunities & future wins

A rigorous pass over the hot paths (the per-pixel op core, region/background
editing, the export/organiser path, the "apply to all" bakes, the decode/preview
caches and the sprite-lookup paths). Each item lists **where**, **why it costs**,
rough **impact** and **effort**, and whether it's **done** or **planned**. These
are static-analysis findings (no profiler on the dev box), so they're reasoned
from the code, not measured — treat the impact ratings as estimates.

### ✅ Done this session

- **Bounded (LRU) decode/preview/thumbnail caches.** `_decodeCache`,
  `_buttonSrcCache`, `_previewCache` and `_thumbCache` were unbounded `Map`s — a
  big cast filled them with full decoded frames until the OS OOM-killed the app.
  Each is now a capacity-bounded `LruCache` (`core/lru_cache.dart`; decode 32 /
  buttonSrc 48 / preview 96 / thumb 256), so resident memory has a hard ceiling
  (a cold key just re-decodes). Consumers treat cached frames read-only, so
  eviction is safe. Tested in `test/lru_cache_test.dart`. **Impact: high** for
  memory stability on big casts; **effort: low-medium.**
- **No `pow`/`sqrt` in per-pixel colour-distance loops.** `math.pow(x, 2)` goes
  through the general power function (log/exp) and is far slower than `x*x`, and
  where the distance only feeds a threshold the `sqrt` is needless (compare
  squared distances). Replaced in `ImageOps._replaceColor` and `_vignette`
  (`pow`→multiply, `sqrt` kept where the real distance is used) and in
  `RegionEditor.selectByColor` (the magic-wand flood fill) + `RegionEditor.eraseColor`
  (drop both — squared compare; `eraseColor` also moved to the sequential pixel
  cursor). Exact-equivalent; locked by `test/region_edit_test.dart`. **Impact:
  medium-high** on recolour / magic-wand / background removal of full-res sprites;
  **effort: low.**
- **Cancellable bulk jobs + bounded, streaming bakes** — see the two sections
  above. The chunked streaming caps peak memory; Cancel is the abort valve.

### 🔴 High-impact, planned

- **O(1) sprite lookup.** `AppState.spriteRelFor` and the apply/zoom/edit/paint
  group selectors all do `scan.groups.firstWhereOrNull((g) => g.base == base)` —
  **O(groups)** each, and it's called **per emote row** on every list build, so a
  big cast is effectively **O(N²)** (list scrolling, button thumbnails, the export
  plan). *Fix:* index `scan.groups` by base into a `Map<String, SpriteGroup>` once
  per scan (e.g. behind a `scan` setter) and look up in O(1). **Effort: low-medium.**
- **Move "apply to all" bakes off the UI isolate.** `applyPipeline` (recolour),
  `applyEdit`, `applyZoom` and `applyPaint` decode → apply → **encode** on the UI
  isolate, only yielding *between* sprite groups. The WebP/APNG encode is the
  expensive part and blocks the UI. *Fix:* fan out render+encode per sprite via
  `compute` + `mapParallel`, exactly like `bulkAnimateAll`/`bulkMouthTalkAll`
  (stay lossless). **Impact: high** (responsiveness + true multi-core on the
  most-used bulk actions); **effort: medium.**
- **Parallelise export button/icon rendering.** `Organizer.execute` renders every
  button **sequentially and synchronously** on the UI isolate (a single
  `Future.delayed(zero)` yield between each — enough to avoid "not responding",
  but the decode + face-detect + encode is serial). *Fix:* render the buttons via
  `mapParallel` + `compute` (`ButtonMaker.renderFramed` is pure → isolate-safe),
  and **dedupe the decode** when several emotes share one sprite. **Impact: high**
  on exporting a big cast; **effort: medium.**
- **True isolate pool for bakes (vs `compute`-per-sprite).** The bulk bakes
  already run off the UI isolate (`compute` spawns one short-lived isolate per
  in-flight sprite) and stream to disk in chunks, so the OOM ceiling is mostly
  addressed by the chunking + the bounded caches (now done). A *persistent*
  isolate pool would cut the per-call spawn overhead, but the win is marginal next
  to the memory work and the risk (sendable-payload + lifecycle bugs) is high — so
  it's the **last** item, after the cheaper wins land and a profiler can prove it.
  **Effort: high.**
- **On-disk thumbnail cache.** The in-memory caches already avoid re-decoding
  *across screens within a session* (they live on `AppState`), and they're now
  memory-bounded. A persistent on-disk cache would additionally survive an app
  restart and free RAM — but it needs a platform seam (no filesystem on the web →
  IndexedDB) and content-hash keying/invalidation. Lower priority than the
  in-session wins above. **Effort: medium.**

### 🟡 Medium

- **Colour-op fusion.** `ImageOps.applyAll` runs **one full image pass per op** —
  an N-op preset traverses the whole buffer N times. Fusing the per-pixel ops into
  a **single pass** (one `_eachPixel` that runs the whole chain per pixel) cuts
  memory bandwidth ~N× for multi-op presets on full-res sprites. **Effort:
  medium-high** (needs a fused executor; spatial ops stay separate).
- **Cursor-based region ops.** `selectByLuminance`, `erase`, `fill` and
  `_blendByMask` (region_edit.dart) use nested `getPixel(x, y)` **random access**;
  switching to the sequential pixel cursor + indexing the mask by `p.y*w + p.x`
  (the `_eachPixel` pattern) is the documented faster path. **Impact: medium** on
  region/outfit/bg editing of big sprites; **effort: low-medium.**
- **One multi-source flood fill for background removal.**
  `removeBackgroundFromCorners` runs **four** separate `selectByColor` flood fills
  (one per corner) and unions them; seeding **one** flood fill from all four
  corners does it in a single pass. Also, the flood fill **pushes neighbours
  before checking `seen`**, so the stack can hold up to ~4×N entries — checking
  `seen` before pushing cuts that churn. **Effort: low.**
- **Skip the redundant clone in `previewWithPipeline`.** It does `src.clone()`
  *then* `copyResize` — when the sprite is larger than the preview edge (the
  common case) `copyResize` already allocates a fresh image, so the clone is a
  wasted full-image copy on every live preview. *Fix:* only clone when applying a
  pipeline at full size. **Effort: low.**
- **Spatial-op clones.** Each spatial op (`blur`/`sharpen`/`outline`/`glow`/
  `dropShadow`/`chromaShift`) clones the whole frame; stacking several clones
  repeatedly. A shared read-only snapshot per pipeline would avoid the repeats.
  **Effort: medium.**

### 🟢 Low

- **Cache `availableSoundNames`.** It re-lists the entire workspace
  (`workspace.listFiles()`) every time the Emotes sound picker opens; cache it per
  scan/`spriteRevision`.
- **`SelectionMask.selectedCount`** allocates an iterable via `.where().length`;
  a plain loop avoids it (rarely hot).

### Notes / non-goals

- **Web has no real parallelism** — `compute` runs inline on the single UI thread,
  so `mapParallel` there is ordered cooperative scheduling, not multi-core. The
  off-isolate items above still help native (the six desktop/mobile targets).
- Anything touching the **bake** stays CPU + deterministic (byte-identical on all
  targets) — see the next section.

## Why not a GPU compute shader for baking?

Baking has to be **byte-identical on all six targets** (Windows/Linux/macOS/
Android/iOS/Web) and feed straight into the WebP/APNG encoders. A portable
GPU compute path for the full 43-op pipeline isn't available across all of those,
so the **final** bake stays on the CPU (deterministic, identical everywhere) and
gets its speed from running on every core. The GPU is used where it's a perfect
fit and always available: **rendering** (previews + the whole UI).
