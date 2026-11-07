# UI illustration implementation prompt

Copy everything below into the implementation agent's task.

---

You are enhancing the **Starfall Salvage** Godot mobile UI using the supplied transparent illustration pack. The game already has strong interaction, typography, and borders. Your job is to add visual companions to cards that currently feel text-only, without making the UI crowded or harming phone performance.

## Design intent

The screenshots show the key issue:

- The home screen's four destination cards (`Hangar`, `Ops`, `Expedition`, `Endless`) are clear but mostly text buttons.
- The Hangar's Nova list is completely text-led, especially the unlocked/locked ability cards.
- Gear and Tech use small symbolic icons but can feel too utility-like rather than like premium upgrades.

Use the artwork as **small, animated companion art beside text**, never as a giant wallpaper or a replacement for readable labels. Do **not** put an illustration on every small tab, settings control, back button, purchase button, or contract action. Those should remain simple and fast to scan.

## Asset mapping

All images are PNGs with transparent backgrounds under `assets/starfall/ui_illustrations/`.

### Home destination cards

| UI destination | Asset |
|---|---|
| Hangar | `hangar_dock.png` |
| Ops | `ops_radar.png` |
| Expedition | `expedition_rift.png` |
| Endless | `endless_vortex.png` |

### Nova mode cards

| Mode ID | Asset |
|---|---|
| `pulse` | `nova/pulse.png` |
| `singularity` | `nova/singularity.png` |
| `overdrive` | `nova/overdrive.png` |
| `aegis` | `nova/aegis.png` |
| locked / unrevealed | `shared/locked_blueprint.png` |

### Gear cards

| Gear ID | Asset |
|---|---|
| `cannon` | `gear/cannon.png` |
| `rapid` | `gear/rapid.png` |
| `shield` | `gear/shield.png` |
| `hull` | `gear/hull.png` |
| `magnet` | `gear/magnet.png` |
| `core` | `gear/core.png` |

### Tech cards

| Tech ID | Asset |
|---|---|
| `slot` | `tech/slot.png` |
| `reroll` | `tech/reroll.png` |
| `lucky` | `tech/lucky.png` |
| `extra_card` | `tech/extra_card.png` |
| `emergency` | `tech/emergency.png` |
| `salvor` | `tech/salvor.png` |

## Required implementation

1. Inspect the current immediate-mode UI architecture before changing it. The relevant menu code is `title_screen.gd` and `src/menus/menu_hangar.gd`; `UILayer` redraws the interface every frame.
2. Add a centralized data map from destination/item IDs to preloaded `Texture2D` assets. Do not `load()` a texture during every redraw.
3. Update the four home destination cards so the art appears to the left of the label. Keep the entire existing card as the touch target, retain every label/subtitle/badge, and keep the 2-column home layout usable on a 405 px-wide phone. Use about 54–68 logical pixels of art in the current layout; move the text right instead of overlapping it.
4. Update Nova cards so each ability gets its corresponding illustration on the left. Increase the card height only if required to retain comfortable text size. For locked abilities use the locked blueprint illustration with a dark/desaturated tint; do not reveal the actual locked mode's illustration.
5. Update Gear and Tech rows to use these companion illustrations in place of, or in a better composition with, the tiny existing icon. Keep costs, pips, star gates, and text legible. Recommended image size: 74–88 logical pixels.
6. Preserve the existing colours: cyan/mint for normal systems, magenta for Expedition/rare content, gold for Endless/rewards, red only for danger. Do not add new UI colours that fight the existing palette.
7. Do not change balance data, save behavior, touch handling, or the working navigation flow as part of this visual pass.

## Animation implementation

Do **not** create GIFs, video textures, animated spritesheets, or expensive shaders. These are still PNGs; create the motion in Godot with the existing time value (`m.t` / title screen time) using `draw_set_transform`, mild scale, rotation, alpha, and glow modulation.

Use subtle looping movement only:

| Asset group | Motion |
|---|---|
| Hangar dock | 2–3 px float and a gentle cyan glow pulse |
| Ops radar | slow 4–8° sway/rotation and a light scan pulse |
| Expedition rift | 2–3% scale pulse, small vertical bob |
| Endless vortex | slow 3–6° rotation and gold glow pulse |
| Nova Pulse | pulse scale 2%; cyan glow breathes |
| Singularity | slow reverse rotation; light inward scale pulse |
| Overdrive | small horizontal jitter/afterimage alpha pulse |
| Aegis | shield shimmer via alpha/glow pulse only |
| Gear/Tech | almost static: 1–2 px float or a 2% glow pulse |
| Locked blueprint | slow cyan scan pulse; dark tint remains |

Animation rules:

- Use 2.5–6 second cycles with sine/cosine. The art should feel alive, not distract from reading.
- Keep rotation below 8 degrees and scale changes below 3%.
- When the game's reduced-effects setting is enabled, draw the assets static with no pulse, rotation, bob, particles, or extra glow.
- Do not allocate textures, arrays, nodes, tweens, or particles inside the per-frame draw path.
- Preserve native aspect ratio and transparency. Never draw a rectangular background behind these PNGs.
- Test at 405x900 and 540x960 portrait sizes; labels, sublabels, prices, and badges must remain readable and untapped areas must not shrink.

## Quality bar

The result should make the player feel that every destination and upgrade is a physical thing in the Starfall universe. It should feel premium, clear, and responsive—not like generic icon clutter. Keep every screen more scannable than before.

After implementation, run the quick automated game test and capture updated title, Hangar Gear, Hangar Tech, and Hangar Nova screenshots for review.

---
