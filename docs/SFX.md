# Adding a sound effect (SFX) to a character

Want an emote to **play a sound** — a jumpscare scream, a desk slam, a sting?
Here's the whole flow. Three parts: **import** the sound, **attach** it to an
emote, and set the emote up so AO actually **plays** it.

## 1. Import the sound

**Home → "Add sound (SFX)"** (shown once a character is loaded). Pick your audio
file(s) — AO uses **`.opus`** (preferred), `.ogg`, `.wav` or `.mp3`. They're
dropped into the project so they **ship inside the exported character folder**
and show up in the Emotes Sound picker.

> Add sounds **after** importing your sprites — starting a fresh sprite import
> clears the project. (Use the same "Add sound" button any time after that.)

## 2. Attach it to an emote

Go to **Emotes**, pick the emote that should make the sound (e.g. your jumpscare
pose), and set the **Sound (SoundN)** field to the sound's **name without the
extension** — so `scream.opus` → type `scream` (the ▾ picker lists your imported
sounds). Optionally:

- **SoundT** (delay) — how long after the emote starts the sound plays, in
  **ticks** (1 tick = 60 ms). `0` = immediately. For a jumpscare you usually want
  it to hit a specific frame of the animation, so bump this until it lines up.
- **SoundL** (loop) — turn on only for ambient/looping sounds, not a one-shot SFX.

## 3. Make AO play it (the part people miss)

In AO, a sound plays **with a preanimation**. So the emote needs:

1. a **preanim** (the `preanim` field) — the animation that plays before the
   talking sprite (for a jumpscare, this is your jumpscare animation), and
2. the modifier set to **"Play preanim + sound"** (modifier `1`) — the Emotes tab
   has this dropdown.

If an emote has no preanim, AO has nothing to "play the sound over." A common
trick for a sound with no real preanim is to point `preanim` at a 1-frame/looping
animation. Set **SoundT** so the scream lands on the scary frame.

```ini
[Emotions]
5 = jumpscare#foxy_pre#foxy#1#      ; preanim "foxy_pre", modifier 1

[SoundN]
5 = scream                          ; plays scream.opus

[SoundT]
5 = 8                               ; 8 ticks (~480 ms) in
```

## Where the sound file goes

AO looks for an emote's SFX in **`base/sounds/general/<name>`** (trying
`.opus`/`.ogg`/`.wav`/`.mp3`). Pinsel **bundles your imported sounds inside the
exported character** so they travel with it and never get lost — but depending on
your AO build, you may need to **copy the sound file into `base/sounds/general/`**
(or wherever your server keeps sounds) so the client can find it by name. Share
the file alongside the character so others can do the same.

## In the app / in code

- **Home → Add sound (SFX)** → `AppState.addSoundFiles(files)` (imports audio into
  the project; bundled on export by the organizer).
- **Emotes tab** → the **Sound (SoundN)** field (with a ▾ picker over
  `AppState.availableSoundNames()`), **SoundT** delay, and **SoundL** loop — these
  edit the `Emote.soundName` / `soundDelayTicks` / `soundLoop` fields that
  serialise to `[SoundN]` / `[SoundT]` / `[SoundL]`.
- Frame-accurate SFX (a sound on a *specific animation frame*) use the
  `[<sprite>_FrameSFX]` sections — see [CHAR_INI_FORMAT.md](CHAR_INI_FORMAT.md).

## Related

- [CHAR_INI_FORMAT.md](CHAR_INI_FORMAT.md) — the `[SoundN/T/L/B]` + `_FrameSFX`
  reference.
- [USER_GUIDE.md](USER_GUIDE.md) — the Emotes tab walkthrough.
