# Auto-build: folder → finished character

The headline feature. **Import a whole folder** (Home → Import folder — a native
directory picker on desktop/mobile, a `webkitdirectory` upload on the web) or
pick individual images, and Pinsel produces a working character with zero
configuration — then lets you tweak any of its decisions. Sub-folder structure
is preserved, and an existing `char.ini` in the folder is loaded losslessly
instead of rebuilt.

## The pipeline

```
files ─► SpriteScanner.fromPaths ─► ScanResult
      ─► CharacterBuilder.build   ─► Character
      ─► Organizer.organize       ─► folders + char.ini + buttons + char_icon ─► .zip
```

### 1. Scanning (`SpriteScanner`)
Each image is classified by its name:
- `(a)foo` → **idle** of `foo`; `(b)foo` → **talk**; `(c)foo` → **post**.
- `foo` (no prefix) → **static** sprite `foo`.
- Sub-folders: `(a)/def/foo` → idle of `/def/foo`; a file at `extra/foo.png` →
  static `/extra/foo`.
- Files under `anim/` are collected as **preanimation candidates**, not emotes.
- Character chrome (`char_icon`, `objection`, `holdit`, `takethat`,
  speedlines, anything in `emotions/`, `_old_emotions/`, `custom_objections/`)
  is **ignored**.
- When several formats share a name, the highest-priority extension wins
  (`webp` > `apng` > `gif` > `png`).

Files that resolve to the same logical sprite are grouped (`SpriteGroup`), so
`(a)happy`, `(b)happy`, and `happy` become one emote.

### 2. Building (`CharacterBuilder`)
Each group becomes an emote:
- **Name** — a friendly Title Case of the base (`upset_look_left` → "Upset Look
  Left").
- **Modifier** — idle pair → `Idle (0)`. If a bare same-named file *also* exists
  alongside an `(a)`/`(b)` pair, the bare one is treated as a **preanimation**
  (`treatBareAsPreanim`, on by default) and the modifier becomes "play preanim".
- **Desk** — defaults to "show".
- **Sounds** — optional name-based guesses (e.g. "slam" → `sfx-deskslam` at 4
  ticks). Toggle with `guessSounds`.
- Emotes named `normal`/`neutral`/`idle`/`default`/`1` float to the front.

If the folder already contains a `char.ini`, it is parsed instead of rebuilt, so
you can re-open and keep editing existing characters losslessly.

All of this is configurable via `BuildConfig` (name, side, blips, chat, scaling,
default deskmod, the two heuristics, and the preferred-first list).

### 3. Organising (`Organizer`)
- Copies every source file into `characters/<name>/`, preserving structure.
- Writes `char.ini`.
- **Auto-generates buttons**: for each emote it takes the representative sprite's
  first frame and frames it — by **default the character's head/face** (detected
  from the silhouette), or full-body — then scales it to size →
  `emotions/buttonN_off.png`. The **Button Studio** controls framing, size, zoom,
  crop offset, and optional border/background overlays.
- **Auto-generates `char_icon.png`**: the character-select icon, from your chosen
  emote (default: the first), framed and sized the same way (default **40 px**,
  range 40–128). Both buttons and the icon are skipped if you already provide one.
- Exports the result as a `.zip` you drop straight into AO.

## Overriding decisions
Everything the auto-builder does is editable afterwards in the **Emotes** screen
(rename, reorder via drag, change sprite/preanim/modifier/desk/sound, add/delete),
and the **Button Studio** lets you drop in custom buttons. Re-run the builder any
time with **Regenerate** (it re-reads the sprites with your current options).

## Bulk folders → many characters at once

Building one character is great; building **ten in one click** is the bulk path.
Home → **Bulk folders → characters** points the same pipeline at a **parent**
folder whose sub-folders each hold one character's sprites:

```
MyCast/            ← pick this folder
  Phoenix/         → a character
    (a)normal.png
    (b)normal.png
  Edgeworth/       → a character
    (a)smug.png
  …
```

Each sub-folder runs through scan → build → organise on its own, and the results
are packed into a single `characters.zip`:

```
characters.zip
  Phoenix/   char.ini · char_icon.png · emotions/button1_off.png · …
  Edgeworth/ char.ini · char_icon.png · emotions/…
  …
```

Unzip it into AO's `characters/` and every character is ready. Notes:
- Buttons + the char_icon use your **current Button & Icon Studio** settings
  (framing, size, zoom, offsets, overlays), so style them once and they apply to
  the whole batch.
- A sub-folder that already contains a `char.ini` is **honoured** (loaded
  losslessly), not rebuilt; otherwise the auto-builder runs and names the
  character after the sub-folder.
- Sub-folders with no usable sprites (and no ini) are skipped.
- Your currently open project is **left untouched** — bulk runs in throwaway
  in-memory workspaces.
- Platform-agnostic: the web folder upload prepends the picked folder's name,
  which `BulkFolders.split` strips automatically, so the same parent folder
  behaves identically on desktop and web. A folder of loose sprites with no
  sub-folders collapses to a single character.
