# Keyboard shortcuts

Global shortcuts work from anywhere in the app. **Control** and **⌘ (Command)**
are both bound, so the same keys work on Windows/Linux and macOS. Press **F1**
in-app to pop up this list, and find the same actions as buttons on the **top
toolbar** (undo / redo / import / export / **Start over ↻**).

> **Rebinding.** The two contextual single-key sets — **Buttons → Manual
> framing** and **Theme Maker → Arrange nudge** — are **rebindable** right in the
> **F1** dialog: press **Set** next to an action and tap the key you want.
> Rebound keys are **saved and restored next time you open the app**. The global
> `Ctrl/⌘` shortcuts above are fixed (they're already plain modifier combos).

| Shortcut | Action |
|----------|--------|
| `Ctrl/⌘ + Z` | Undo |
| `Ctrl/⌘ + Y` *or* `Ctrl/⌘ + Shift + Z` | Redo |
| `Ctrl/⌘ + O` | Import a folder of sprites |
| `Ctrl/⌘ + S` | Export the character as a `.zip` |
| `Ctrl/⌘ + Shift + S` | **Save the character as a plain folder** (no zip) |
| `Ctrl/⌘ + E` | Export just `char.ini` |
| `Ctrl/⌘ + N` | Add a new emote |
| `Ctrl/⌘ + ↑` / `Ctrl/⌘ + ↓` | Select the previous / next emote (the list auto-scrolls to it) |
| `Ctrl/⌘ + 1 … 9` | Jump to a screen (1 = Home, 2 = Character, … 9 = Bulk) |
| `F1` | Show the shortcuts cheat-sheet |

> Inside a text field, `Ctrl+Z` is handled by the field (text undo). Click
> anywhere outside the field first to use the global undo/redo.

## Screen numbers (`Ctrl/⌘ + 1…9`)

1. Home · 2. Character · 3. Emotes · 4. Colour Lab · 5. Animate · 6. Buttons ·
7. Edit · 8. Mixer · 9. Bulk

> Screens past the 9th — **Plugins**, **Ripper**, **Theme**, **Paint** and
> **Zoom** — have no number shortcut (there are only nine digits); click them in
> the rail.

## Direct manipulation (mouse + arrow keys)

Some editors are mouse-driven **and** keyboard-nudgeable — drag with the mouse for
speed, then fine-tune with the keyboard:

- **Theme Maker → Arrange.** Click a widget box to select it, then the **arrow
  keys** move it 1px, **Shift + arrow** moves 10px, and **Ctrl/Alt + arrow**
  resizes it. Set a **Grid** (5–50px) to **snap** mouse drags for pixel-perfect
  alignment. The four direction keys are **rebindable** — click the **⌨ keyboard
  button** in Arrange and assign any key to up / down / left / right (Reset
  restores the arrows).
- **Any slider.** Tab to a slider (or click it) and **←/→/↑/↓** adjust it,
  **Home/End** jump to min/max. The Ripper's sliders step by 1.
- **Sprite Ripper → Manual** and the **Mixer.** Drag boxes/snips to move, drag a
  corner to resize.
- **Emotes list.** Tick the per-row **checkboxes** (or **All**) to multi-select,
  then **Delete (N)** to remove many at once. Drag a row to reorder — and dragging
  any **ticked** row moves the **whole selection** together (as one block), so you
  can reorder several emotes at once instead of one at a time.
- **Buttons → pick any sprite from the list.** The Buttons screen now has a
  left-hand **sprite list** (just like the Emotes screen) showing a **tiny
  preview of each *button*** (the framed result, not the raw sprite) — click any
  one to frame it. A pink tick marks sprites you've given a custom (Manual) box.
- **Buttons → Manual (frame the whole cast from the keyboard).** Click the sprite
  once to focus the big framing canvas, then (these are the **default**, plain
  keys — **no `[`/`]`** — and every one is **rebindable in the F1 dialog**):

  | Key (default) | Action |
  |---------------|--------|
  | `←` / `→` | Previous / next sprite to frame |
  | `Enter` | "Make it & go to the next sprite" (boxes save as you go) |
  | `R` | Reset this sprite to its auto face crop |
  | `A` | Apply the current box to **all** sprites |
  | `F` | Cycle framing **Face → Full → Manual** |
  | `Shift` + `←/→/↑/↓` | **Nudge the crop box** precisely (add `Ctrl/⌘` for a bigger step) |

  Drag the box to move it, the corner to resize. These only fire while the
  framing area is focused — typing in a value box never triggers them. Rebind any
  of them (and they persist) from the **F1** keyboard-shortcuts dialog.
- **Buttons → the BIG framing editor.** In Manual mode, **“Open the BIG framing
  editor”** gives a full-screen DRO-style workspace: **scroll** to zoom, **drag
  the sprite** to pan, **drag the box / its corner** to frame, **Shift + arrows**
  to nudge the box precisely, and the same ←/→/Enter/R/A keyboard flow.
  +/−/Reset-view buttons sit bottom-right, and the side panel has the **border /
  background overlay** controls so you can skin the buttons without leaving.
  **Advancing keeps your framing:** pressing `Enter`/`→` (or clicking a later
  sprite) **carries your current box** onto the next sprite if it hasn't been
  framed yet — so the box doesn't reset to that sprite's auto face. Already-framed
  sprites keep their own box; press `R` to snap one back to auto.

- **Zoom Studio → the canvas.** Click the canvas to focus it, then frame the
  character with the mouse + keys (these are fixed, plain keys — the canvas is its
  own focused area, so they never clash with anything global):

  | Key / input | Action |
  |-------------|--------|
  | **Mouse wheel** | Zoom toward the cursor |
  | **Drag** | Pan the camera |
  | `+` / `-` | Zoom in / out |
  | `←/→/↑/↓` | Recenter (nudge the focus point) |
  | `R` or `0` | Reset the camera |
  | `G` | Toggle the rule-of-thirds grid |
  | `F` | Auto-frame the character |

These are **contextual** — they act on the focused/selected widget, not globally.

## Undo / redo scope

Undo/redo cover **character/emote model** edits (names, sprite fields, order,
add/delete, sound, etc.). Baked **pixel** changes (recolour / crop / animation
saves) write straight to the sprite files and aren't on the undo stack — re-run
the tool or re-import to change them.

## Adding your own

Shortcuts live in `lib/src/app.dart` (`_HomeShellState._bindings`), a
`CallbackShortcuts` map of `SingleActivator` → callback. Add a `bind(key, cb)`
line (it registers both the Control and ⌘ variants) and document it here.
