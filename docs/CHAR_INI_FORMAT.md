# `char.ini` reference

This is the format Pinsel reads and writes. It is compatible with the AO2
reference client and webAO. Verified against the official AO content-creation
docs and `AO2-Client` source.

A character is a folder (named after `[Options] name`) containing `char.ini`,
sprite images, an `emotions/` folder of button icons, and optional extras
(`char_icon.png`, `credits.txt`, `sounds`, `custom_objections/`, …).

## Sprite naming & resolution

For an emote whose `sprite` field is `foo`, the engine looks for, in order:

| Role | Lookup order |
|------|--------------|
| Idle (not talking) | `(a)foo`, `(a)/foo`, `foo`, then placeholder |
| Talking | `(b)foo`, `(b)/foo`, `foo`, then placeholder |
| Post (talk→idle) | `(c)foo`, `(c)/foo`, `foo` |
| Preanimation | the `preanim` name directly (e.g. `anim/deskslam`) |

**Sub-folder mode:** a sprite of `/def/thinking` resolves to
`(a)/def/thinking`, `(b)/def/thinking`, etc. (webAO does **not** support the
`(a)/`,`(b)/` folder form.)

**Extension priority** (highest first): `.webp` → `.apng` → `.gif` → `.png`.
Animated formats are tried before the static `.png`. Avoid having two formats
with the same base name.

**Case-insensitive matching.** AO resolves these files case-insensitively, and so
does Pinsel: an emote whose `sprite` field is `Normal` still finds `(a)normal.webp`
(and the optional subfolder leading `/` may be present or omitted). An **exact**
match always wins first, so a correctly-cased character is unaffected; the folded
match is only a fallback. This matters when **importing** an existing `char.ini`
whose casing doesn't match the on-disk file names — without it, the previews,
buttons and `char_icon` for every mismatched emote silently disappear (only the
exactly-matching emote would export a button). See
[FAQ.md](FAQ.md) → *"Only one emote button shows up after export."*

## Sections

> Edit all of `[Options]` in the app's **Character** tab (the dedicated char.ini
> builder) — see [USER_GUIDE.md → Character](USER_GUIDE.md#character--the-charini).

### `[Options]`
| Key | Meaning |
|-----|---------|
| `name` | folder name / asset lookup name (required) |
| `showname` | nameplate text (optional) |
| `needs_showname` | `false` → blank nameplate |
| `side` | `def`, `pro`, `hld`, `hlp`, `jud`, `wit` (default), `jur`, `sea` |
| `blips` | talking blip sound (formerly `gender`) |
| `chat` | custom chatbox folder under `misc/` |
| `effects` | overlay effects folder (default `default/effects`) |
| `realization` | custom realization sound |
| `category` | character-list category |
| `scaling` | `smooth` or `pixel` |
| `stretch` | `true`/`false` |

`[Options2]`–`[Options5]` may override `showname`/`blips`; `[OptionsN]` maps an
emote number to which options block it uses. Pinsel preserves all of these.

### `[Shouts]`
Custom interjection text, e.g. `custom_name`, `custom_message`,
`holdit_message`. You do **not** need to define the default holdit/objection/
takethat.

### `[Time]`
Legacy preanimation durations (mostly redundant since AO 2.8.4). Preserved.

### `[Emotions]`
```
number = N
<n> = <comment>#<preanim>#<sprite>#<modifier>[#<deskmod>]
```
- **comment** — the label shown on the button/dropdown.
- **preanim** — preanimation name, or `-` for none.
- **sprite** — the `(a)`/`(b)` base name.
- **modifier**:
  - `0` idle — never plays preanim/sound
  - `1` play preanim + sound
  - `5` zoom (desk hidden, speed lines; never plays preanim)
  - `6` zoom **and** always play preanim
- **deskmod** (optional):
  - `0` hide desk · `1` show desk · `2` hide during preanim · `3` show only
    during preanim · `4`/`5` = `2`/`3` but center & hide pairs

Pinsel round-trips the exact field count, so `N#-#n#0` (4 fields),
`N#-#n#0#` (trailing empty deskmod), and `N#-#n#0#1` all preserve precisely.

### Sound sections (indexed by emote number)
- `[SoundN]` — sound effect name (omit / `0` / `1` / `-1` = none)
- `[SoundT]` — delay in **ticks** (60 ms each)
- `[SoundL]` — `1` to loop (by emote number, or by sound name)
- `[SoundB]` — per-emote blip override
- `[Videos]` — per-emote associated video

### Frame effects (per sprite)
Sections named `[<sprite>_FrameSFX]`, `[<sprite>_FrameRealization]`,
`[<sprite>_FrameScreenshake]`, keyed by **frame number**. The sprite reference
may be prefixed (`(a)/`, `(b)/`).
```ini
[(b)point_FrameSFX]
2 = sfx-point

[pre-salute_FrameRealization]
32 = 1
```

## Sample
```ini
[Options]
name = Phoenix
showname = Wright
side = def
blips = male
chat = aa
scaling = smooth

[Emotions]
number = 4
1 = normal#-#normal#0#
2 = pointing#-#pointing#0#
3 = slam#deskslam#handsondesk#1#
4 = zoom#-#zoom#5

[SoundN]
3 = sfx-deskslam

[SoundT]
3 = 4
```

## Buttons & icons
- Buttons live in `emotions/buttonN_off.png` (and optional `buttonN_on.png`),
  1:1, ≥ 40×40. Pinsel auto-generates `_off` icons on export.
- The character icon is `char_icon.png`, 1:1, ≥ 60×60.
