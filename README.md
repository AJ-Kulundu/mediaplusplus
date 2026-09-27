# Media++

An Omarchy shell media plugin. It does everything `omarchy.media` does, plus
seeking, shuffle and repeat, a settings panel, hotkeys, and two ways of drawing
the artwork and the progress bar.

![Media++](preview.png)

## What it adds over the stock media plugin

| | Stock | Media++ |
|---|---|---|
| Seeking | — | Scrub bar, ±10s buttons, `seekTo`/`seekPercent` over IPC |
| Shuffle / repeat | — | Both, with per-player support detection |
| Artwork | Fixed square thumbnail | Aspect-driven frame, or a spinning vinyl |
| Progress bar | — | Plain, Material 3 Expressive wiggle, or barber-pole stripes |
| Settings | — | In-popup panel: bar position, artwork, progress style |
| Hotkeys | — | Global summon, plus transport keys while the popup is open |
| Bar label | Resizes with the title | Fixed width, continuous carousel |
| Source list | Title only | App icon per source |

It also fixes two things the stock plugin gets wrong: the bar label can strand
itself off-screen and vanish, and secondary text inverts its contrast on light
themes, ending up louder than the title above it.

## Install

```bash
omarchy plugin add <repo-url>
omarchy plugin enable ajkulundu.mediaplusplus
```

Requires a Nerd Font for the transport glyphs — Omarchy ships one.

## Bar widget

Cover thumbnail plus track and artist, at a fixed width so the bar does not
reflow on every track change. Long titles scroll as a continuous carousel with
a pause between passes. The thumbnail dims while paused. Left click opens the
popup; nothing else on the bar is clickable, so a stray scroll cannot skip a
track.

## Popup

Artwork, track metadata, a scrub bar with elapsed and total time, and a
transport row: shuffle · previous · −10s · play/pause · +10s · next · repeat.
Controls a player does not support are dimmed rather than hidden. When more
than one player is running, each appears in a list below with its app icon.

## Settings

Gear icon, top right of the popup.

| Setting | Options | Default |
|---|---|---|
| Position on bar (`m`) | Left · Center · Right | Left |
| Popup artwork (`v`) | Square · Vinyl | Square |
| Progress animation (`y`) | Plain · Wiggle · Stripes | Plain |

**Square** keeps the cover's own aspect ratio; **Vinyl** fills a record that
turns while playing. **Wiggle** is Material 3 Expressive's wave, flattening
when playback pauses; **Stripes** is a barber-pole sweep.

Anything not exposed in the panel is an inline field on the widget's entry in
`~/.config/omarchy/shell.json`:

```json
{ "id": "ajkulundu.mediaplusplus",
  "labelWidth": 136, "scrollSpeed": 0.6, "scrollPause": 5,
  "artworkStyle": "square", "progressAnimation": "default" }
```

`labelWidth` is the bar label width, `scrollSpeed` multiplies the carousel pace
(below 1 is slower), `scrollPause` is the hold between passes in seconds.

## Hotkeys

Bind the summon key yourself, in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + M", "Media controls", "omarchy-shell shell toggle ajkulundu.mediaplusplus")
```

The rest work while the popup is open:

| Key | |
|---|---|
| `space` | Play / pause |
| `b` / `f` | Back / forward 10s |
| `p` / `n` | Previous / next track |
| `m` | Cycle bar position |
| `v` | Square ⇄ vinyl |
| `y` | Cycle progress style |
| `s` | Settings |
| `esc` | Close |

Keys are matched on the character, so they follow your keyboard layout.

**Known limitation.** Hotkeys work from when the popup opens until keyboard
focus drifts elsewhere — under `focus_follows_mouse` that is any window the
pointer crosses. The popup is an xdg popup, and only a full-screen layer
surface can hold focus the way the stock panels do. Reopening restores them.

## IPC

```bash
omarchy-shell media status        # JSON: track, position, length, shuffle, loop
omarchy-shell media playPause
omarchy-shell media seek -10      # relative seconds
omarchy-shell media seekTo 90     # absolute seconds
omarchy-shell media seekPercent 50
omarchy-shell media shuffle
omarchy-shell media loop          # off -> all -> track
omarchy-shell media sourceNext
```

## Dismissal

The popup closes on `esc`, on clicking the bar widget, on the summon hotkey,
or shortly after the pointer leaves it — but only once the pointer has actually
been on it, so opening by hotkey with the mouse elsewhere stays put.

## Credit

Cloned from Omarchy's first-party `omarchy.media` and extended from there.

## License

MIT
