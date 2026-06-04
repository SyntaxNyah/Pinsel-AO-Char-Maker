# One-click character (auto-magic)

The fastest path from "a folder of sprites" to "a finished, working AO
character." One button does the whole pipeline: import → auto `char.ini` →
generate **buttons** + **char_icon** → export the ready-to-drop **`.zip`** — using
the **same export path as "Export .zip"**, so it's just as reliable.

## In the app

On **Home**:

* **One-Click: folder → finished character** — pick a folder of sprites and get a
  `<name>.zip` you can unzip straight into AO's `characters/`. It:
  1. imports the folder (auto-detects `(a)`/`(b)`/`(c)` and builds emotes, named
     after the folder),
  2. renders an emote **button** per emote and a **char_icon** using your current
     [Button & Icon Studio](../README.md) settings,
  3. writes a valid `char.ini`, and
  4. downloads the packaged `.zip` — copying sprites in their existing format.

* **Finish & export everything** (shown once a project is loaded) — the same
  ini → buttons → icon → export, without re-importing. Use it after you've
  recoloured, animated, added talking mouths, etc.

Your emotes and edits are **preserved**; nothing is rebuilt from scratch.

> **Why doesn't One-Click convert to WebP?** It used to, but force-converting
> every sprite through the native WebP encoder was the heaviest step and could
> *hard-crash* the app (the window just closing — an out-of-memory / native crash
> the in-app error handling can't catch) on some sprite sets. So One-Click leaves
> sprites in their existing format (PNG/etc. — all AO-compatible) and you convert
> deliberately via **Bulk → Convert → WebP** when you want it, where any encoder
> problem is isolated to that one step. Sprites the maker *generates*
> (animations, talking mouths) are already WebP. `autoMagicExport(convertToWebp:
> true)` still exists for callers that opt in.

## In code

```dart
// Convert to WebP, build ini + buttons + char_icon, export the .zip.
final String? zipPath = await appState.autoMagicExport();

// Skip the WebP conversion (keep whatever formats are already there):
await appState.autoMagicExport(convertToWebp: false);
```

`autoMagicExport` reuses the same export plumbing as the manual **Export .zip**
(`buildOutput` → `Organizer`), so single, one-click and **Bulk folders →
characters** all render buttons/icons identically.

## Related

* **Bulk folders → characters** (Home) — a *parent* folder of per-character
  sub-folders → many characters in one `.zip`. See [AUTO_BUILD.md](AUTO_BUILD.md).
* [PERFORMANCE.md](PERFORMANCE.md) — the conversion + bake steps use all CPU
  cores.
