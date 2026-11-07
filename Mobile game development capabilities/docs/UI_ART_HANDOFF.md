# Menu illustration handoff

This pack adds transparent companion illustrations for the four primary destinations on the title screen. They are intended to solve the home-screen's text-heavy button grid without making every control visually busy.

## Assets

| Destination | Asset | Accent | Suggested motion |
|---|---|---|---|
| Hangar | `assets/starfall/ui_illustrations/hangar_dock.png` | mint / cyan | Float 2–4 px, slowly pulse the hologram, flicker a tiny repair spark. |
| Ops | `assets/starfall/ui_illustrations/ops_radar.png` | cyan | Rotate the radar sweep or one outer ring very slowly; add a 1.5 s scan pulse. |
| Expedition | `assets/starfall/ui_illustrations/expedition_rift.png` | magenta / violet | Pulse the portal scale 2–3%, drift particles, lightly bob the ship. |
| Endless | `assets/starfall/ui_illustrations/endless_vortex.png` | gold / cyan | Rotate orbital rings at different slow speeds; pulse the central vortex. |

## Intended layout

Use the illustrations only for the four large destination buttons on the title screen (`Hangar`, `Ops`, `Expedition`, and `Endless`). Keep small tabs, settings, back/home and contract actions icon-led; putting artwork on all of them would make the interface harder to scan.

For each destination, make the whole card the touch target. Place the illustration on the left at roughly 68–88 logical pixels; put the label and existing subtitle on the right, vertically centred. Keep 16–20 px of internal padding and never put text over the bright part of the illustration. The existing two-column cards can work with 58–68 px artwork; a later single-column card layout can use 96–128 px artwork.

## Animation rules

- Use lightweight Godot transforms and alpha/glow modulation; do not create GIFs or run full-frame texture effects.
- Respect the game's existing reduced-effects setting: show a static asset when effects are reduced.
- Movement should be subtle and loop cleanly (2–5 second cycles). It must not compete with the PLAY button or obscure text.
- Preserve aspect ratio and the PNG alpha. Do not add a rectangular background behind the artwork.
- Preload assets once and reuse them; avoid allocating textures during redraw.

## Visual direction

The artwork deliberately uses the game palette: dark navy framing, cyan instrumentation, magenta Expedition energy, gold Endless energy, and a small orange engine/alert contrast. If more destination art is made later, match this hierarchy and avoid text, logos, or overly realistic rendering.
