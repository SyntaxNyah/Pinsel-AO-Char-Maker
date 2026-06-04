# One-click character (auto-magic)

The fastest path from "a folder of sprites" to "a finished, working AO
character." One button does the whole pipeline: import → auto `char.ini` →
convert sprites to **WebP** → generate **buttons** + **char_icon** → export the
ready-to-drop **`.zip`**.

## In the app

On **Home**:

* **One-Click: folder → finished character** — pick a folder of sprites and get a
  `<name>.zip` you can unzip straight into AO's `characters/`. It:
  1. imports the folder (auto-detects `(a)`/`(b)`/`(c)` and builds emotes),
  2. converts every sprite to **lossless WebP** (deleting the originals so the
     export is clean),
  3. renders an emote **button** per emote and a **char_icon** using your current
     [Button & Icon Studio](../README.md) settings,
  4. writes a valid `char.ini`, and
  5. downloads the packaged `.zip`.

* **Finish & export everything** (shown once a project is loaded) — the same
  convert → ini → buttons → icon → export, without re-importing. Use it after
  you've recoloured, animated, added talking mouths, etc.

Your emotes and edits are **preserved**: emote sprite fields store base names
(e.g. `normal`), so converting `normal.png` → `normal.webp` keeps every reference
valid — nothing is rebuilt from scratch.

If WebP can't be encoded on the current platform, those sprites are simply kept
in their original format (the status line says how many) — you still get a
working character.

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
