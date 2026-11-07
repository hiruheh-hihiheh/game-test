# Glass interface

The whole game uses one visual language: dark translucent glass with thin accent edges, tactical corner brackets on emphasised pieces, and light that is used sparingly. It is drawn with the existing immediate-mode UI (`src/ui.gd`, `src/ui_layer.gd`). There is no blur, no SubViewport and no shader, so it is cheap on the GL Compatibility renderer.

## The parts

| Part | Where | What it does |
|---|---|---|
| `UI.glass(canvas, rect, kind, accent, options)` | `src/ui.gd` | The one panel. Layers: tinted translucent fill, a thin border, a top sheen, a soft bottom shade, an inner highlight, an accent edge light, and corner brackets on emphasised kinds |
| `UI.panel(...)` | `src/ui.gd` | The old call, kept so every existing screen changes at once. The border colour becomes the accent, a thick border or glow means selected |
| `UI.Kind` | `src/ui.gd` | `INFO`, `CARD`, `SELECTED`, `PRIMARY`, `DISABLED`, `REWARD`, `WARNING` |
| `UILayer.button` | `src/ui_layer.gd` | Same ids, hit areas and press scale as before. `primary` is the one illuminated action on a screen, `selected` marks a tab or option, `warning` marks a destructive action, `disabled` is flat and grey |
| `UI.bar` | `src/ui.gd` | A thin glass gauge with a gradient fill, a bright leading edge and quarter ticks |
| `UI.chip`, `UI.rule` | `src/ui.gd` | A small glass label, and a fading divider |
| `UI.enter_veil`, `UI.shine`, `UI.breathe` | `src/ui.gd` | Cards fade in from the dark in turn, rewards get one glint, primary actions breathe slowly |

Panel types in use: information (plain glass), interactive card (brighter border and a lit top edge), selected card (accent border, glow, brackets), primary action (accent-tinted glass that breathes), disabled and locked (flat grey), reward and rarity (gold edge, glint), warning and destructive (red edge with a bar on the left).

## What changed on each screen

- **Title:** the selected ship stands on a holographic pad with a light cone and a scanning ring, with its name and role in a chip. PLAY is the single illuminated action. Pilot, salvage, stars and season are glass chips.
- **Hangar:** tabs ease their selection (a light grows under the active one). Ship cards have a landing pad and an ACTIVE tag. Cards fade in one after another.
- **Map:** level nodes are glass octagons. Cleared nodes show stars, the current node pulses, locked nodes are dark with a padlock, bosses have a double edge and elites a marker. Cleared stretches of the route glow, the rest is dashed.
- **Briefing:** the level name and star goals sit on one mission card.
- **Expedition:** each node type has its own shape and symbol: battle (circle, crossed blades), elite (diamond, star), depot (square, plus), signal (triangle, mark), boss (large octagon, crown). The path you walked is lit. Signal events sit on a gold card.
- **Ops:** challenge and contract cards, fade-in, long contract names shrink to fit.
- **Settings:** each option is a glass segmented control with a lit segment that slides to your choice. Section headers have an accent bar and a rule.
- **In flight:** a thin see-through plate behind the score, a glass boss bar with a name plate, a glass Nova disc with a bright charge tip, glass upgrade cards (plain, lit, or gold by rarity), a glass pause menu, reward rows with a glint.

## Accessibility

- **Reduce motion:** no card fade-ins, no sliding selections, no breathing, no sweeps, no ship bob or ring spin on the title.
- **Reduce flashes:** also no pulses, glints or light sweeps. Pulsing glow is replaced by a steady one.
- **Larger interface size** and the **colour-blind palette** are unchanged and tested with the new layout.

## Cost

Measured in a window on a desktop GPU with vsync off, 90 frames per screen, old flat panels against the glass ones:

| Screen | Flat | Glass | Draw calls flat to glass |
|---|---|---|---|
| Title | 1.87 ms | 1.82 ms | 123 to 121 |
| Hangar, ships | 1.78 ms | 2.03 ms | 117 to 144 |
| Hangar, gear (busiest) | 3.32 ms | 3.49 ms | 199 to 223 |
| Hangar, tech | 1.70 ms | 1.80 ms | 101 to 113 |
| Ops | 2.00 ms | 2.11 ms | 112 to 134 |
| Settings | 2.51 ms | 2.69 ms | 155 to 166 |
| Map | 1.73 ms | 1.80 ms | 128 to 127 |

That is about 0.1 to 0.25 ms more on this PC and at most 24 extra draw calls on the busiest screen. It has not been measured on a phone. `UI.classic = true` switches back to flat panels for repeating the measurement.

To keep it cheap: small panels and chips skip the bottom shade and inner highlight, plain information panels never draw brackets, and the sheen is one polygon with per-vertex colours.

## Using it

- Prefer `UI.glass` with a kind for new panels, and `UI.panel` where a colour already says what it is.
- A toggle or tab is `selected`, the one main action is `primary`, a destructive one is `warning`.
- Never pass `primary` for a toggle: it would compete with the real action.
- Gate any new ambient animation with `UI.motion_ok()`, and any pulse or flash with `UI.flash_ok()`.

## Tests and screenshots

`_test_glass_ui` in `tools/test_game.gd` checks the accessibility switches, that every button id on the title, Hangar, Ops, Settings, map, briefing and Expedition screens is still present with a touch-sized hit area, that scrolling carries hit areas with it, a real touch on a settings segment, and that every screen paints under four combinations of motion, flash, interface size and colour-blind settings.

Screenshots are in `screenshots/glass-ui/` (the previous look is in `screenshots/glass-ui/before/`; other phone sizes, large interface size and reduced motion are in `screenshots/glass-ui/sizes/`).
