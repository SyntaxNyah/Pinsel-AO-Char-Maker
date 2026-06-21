# Merge characters into one

Combine two (or more) **complete, correct** Attorney Online characters into a
**single** character — one `char.ini`, one cast of emotes, buttons that still
point at the right sprites, and **no file-name collisions**. The classic use is
"I have two characters and I want them as one big character with all the poses."

> Engine: [`lib/src/discovery/character_merge.dart`](../lib/src/discovery/character_merge.dart)
> · tests: [`test/character_merge_test.dart`](../test/character_merge_test.dart)
> · driver: `AppState.mergeCharactersInFolder`.

## In the app

On **Home**, click **"Merge characters into one"** and pick a *parent* folder
that contains the character sub-folders you want to combine, e.g.:

```
ToMerge/                 ← pick THIS folder
  Phoenix/
    char.ini
    (a)normal.webp  (b)normal.webp  point.png
    emotions/button1_off.png …
    char_icon.png
  Edgeworth/
    char.ini
    (a)normal.webp  (b)normal.webp  (a)smug.webp
    emotions/button1_off.png …
    char_icon.png
```

You get a **`<name>_merged.zip`** holding one finished character folder, ready to
unzip into AO's `characters/`. The project you currently have open is **not
touched** — if you want to keep editing the result, import the zip.

It merges **every** `char.ini` it finds in the folder (and subfolders), not just
two. The **primary** — the *alphabetically-first* character folder — keeps the
identity (its `[Options]`, name, side, shouts, timing and its `char_icon.png`).
The status line tells you which character became the primary and exactly what
happened.

## What the merge does

| Part | Rule |
|------|------|
| **Emotes** | Concatenated in folder order. `char.ini` `number` and every `SoundN/SoundT/SoundL/SoundB/Videos/OptionsN` line are renumbered automatically. |
| **Buttons** (`emotions/buttonN_*.png`) | **Renumbered positionally** so each button stays glued to its emote. The second character's `button1` becomes `button{primary_count+1}`, etc. |
| **Sprites** | A sprite **base** whose files would overwrite an existing file **with different bytes** is renamed (`normal` → `normal_2`). *All* of that base's files (`(a)`/`(b)`/`(c)`/static) are renamed together, and the emote `sprite` field is updated to match. |
| **Identical files** | If two characters share a byte-for-byte identical sprite, it's kept once (no rename, no duplication). |
| **Preanims** (`anim/…`) & **bundled sounds** | Same byte-collision rename, with the emote `preanim` / `SoundN` reference updated to follow. |
| **`char_icon.png` & other chrome** | One per character, so the **primary's wins**. A different secondary file at the same path is reported (kept the primary's), never silently swapped. |

### Why rename instead of overwrite?

Two correct characters very often both contain `(a)normal.webp` (different art).
If you just dropped both into one folder, one would clobber the other and an
emote would show the wrong sprite. Renaming the colliding base **and rewriting
the `char.ini` reference** is what keeps every emote pointing at its own art —
"restructure the names and the ini so it doesn't conflict."

## What a merge can't carry (and tells you about)

A single character has **one** of each of these, so only the **primary's** are
kept. Each non-empty section dropped from a *secondary* character is listed in
the result (status line + crash-log breadcrumb) so the loss is **never silent**:

- a second `[Shouts]` (custom objection/hold-it/take-that),
- `[Options2]`–`[Options5]` alternate-option blocks (a secondary emote that used
  one falls back to the default options),
- `[Time]` legacy timings, named `[SoundL]` loops, custom `[Options]` keys, and
  any unknown/custom sections.

If you need a secondary's custom shouts or alt-options, set them up by hand on
the merged character afterwards.

## Re-exporting the merged character

The merged zip already contains correctly-numbered `emotions/` buttons. If you
import it and then **Export** with **"Regenerate buttons on export"** *on* (the
default), the Button Studio will re-render buttons from the sprites and **drop
the imported `emotions/` folder** — which is usually what you want (consistent
framing), but it replaces the hand-made buttons the merge just renumbered. Turn
that toggle **off** to keep the original buttons.

## In code

```dart
// Pure engine — operates on in-memory folders, no filesystem.
final MergeResult r = CharacterMerge.merge(<MergeSource>[
  MergeSource('Phoenix',  phoenixChar,  phoenixFiles),  // primary (kept identity)
  MergeSource('Edgeworth', edgeworthChar, edgeworthFiles),
]);
r.files;          // merged folder: relPath → bytes (incl. the rewritten char.ini)
r.character;      // the merged Character model
r.report.summary; // "Merged 2 characters into "Phoenix" → 9 emote(s); 2 sprite(s) renamed; …"
r.report.losses;  // human-readable list of secondary sections not carried
```

`AppState.mergeCharactersInFolder(files)` wires this to the Home button: it uses
`IniRepair.findCharFolders` to split the picked folder into per-character file
lists, sorts them (alphabetical → deterministic primary), merges, and saves the
zip.

## Related

- [AUTO_BUILD.md](AUTO_BUILD.md) — **Bulk folders → characters** does the
  *opposite*: a parent folder of sub-folders → **many** separate characters.
- [CHAR_INI_FORMAT.md](CHAR_INI_FORMAT.md) — the `char.ini` sections the merge
  renumbers and re-keys.
