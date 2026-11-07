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

**How these numbers were taken.** On the same Windows PC (NVIDIA laptop GPU), in a window, vsync off, 120 frames per screen after 40 settling frames, with `tools/drawcost.gd`. The "before" is a copy of the commit just before the glass UI (`20fc2aa`) and the "after" is this checkout, both run with `--mode=plain`, two rounds each (the rounds agreed within about 0.1 ms). Combat is level 33 with the simulation running and the ship kept alive. The boss is the Ember Tyrant. These are **desktop** numbers. Nothing here was measured on a phone.

| Screen | Before | After | Draw calls before to after |
|---|---|---|---|
| Title | 1.37 ms | 1.81 ms | 69 to 111 |
| Hangar, ships | 1.54 ms | 1.99 ms | 80 to 128 |
| Hangar, gear (busiest) | 2.47 ms | 3.24 ms | 110 to 181 |
| Hangar, tech | 1.38 ms | 1.81 ms | 65 to 104 |
| Ops | 1.47 ms | 1.99 ms | 67 to 112 |
| Settings | 1.84 ms | 2.43 ms | 92 to 139 |
| Map | 1.13 ms | 1.68 ms | 40 to 124 |
| Combat | 1.17 ms | 1.37 ms | 32 to 47 |
| Boss fight | 1.13 ms | 1.29 ms | 36 to about 100 |

So the glass costs between 0.15 and 0.8 ms per frame on this PC, and the number of draw calls is 1.5 to 3 times higher on menus. The map is the biggest jump in relative terms (every node is now several shapes). The boss figure is the least reliable, because draw calls depend on which attack the boss is in; a flat-panel run of the same fight was already about 85, so the glass itself added roughly 15.

How the cost was kept down: depth is one gradient polygon, all fine lines are one multi-line call, small panels and chips skip the bottom shade and inner highlight, plain information panels never draw brackets, and the bar ticks are one call. That cut the busiest screen from 223 draw calls to 181.

**Not known:** how a budget phone copes. A menu frame is about 0.5 ms heavier on a fast desktop, and draw calls and polygon triangulation are CPU work that weighs more on a phone. Check it with the device list in `docs/DEVICE_TESTING.md`.

**`UI.classic`.** Setting `UI.classic = true` makes `UI.panel`, `UI.glass`, `UI.bar` and `UI.chip` draw one flat style box (chips draw only their text) and turns off `rule`, `shine` and `enter_veil`. It isolates what the glass layers cost. It does not undo layout changes (the title pad, the mission card, the node shapes), so it is not a "before" picture. For that, run the tool in a copy of the old commit:

```powershell
git archive 20fc2aa "Mobile game development capabilities" | tar -x -C C:/temp/old
# copy .godot into the copy, copy tools/drawcost.gd into it, then in each project folder:
& $godot --path . --script tools/drawcost.gd -- --test --mode=plain
```

`--mode=both` (the default) runs flat panels and then glass panels in one checkout.

## Touch targets

The layout is always 720 units wide, so a control's real size depends on the phone: one unit is `width in dp / 720` dp. A typical 1080 px phone (411 dp wide, 65 mm) gives 0.57 dp or 0.09 mm per unit. A compact 720 px phone (360 dp, 57 mm) gives 0.50 dp or 0.08 mm per unit.

`tools/touch_audit.gd` lists the smallest controls on every screen and in every combat phase. Findings, 492 controls checked:

- 314 of 492 controls are drawn smaller than 84 units (48 dp on a typical phone). The smallest are the Settings segments and Gear filter chips, 54 units tall (31 dp typical, 27 dp compact), then tabs and the Abandon button at 56 to 62 units (32 to 35 dp). The map's level nodes are 84 to 112 units across (48 to 64 dp).
- To fix that without redrawing anything, every control now gets an invisible touch margin up to `UILayer.MIN_TOUCH` = 84 units (**48 dp on a typical phone, 42 dp on a compact one, about 7.6 mm and 6.7 mm**). A touch on a control or its 6-unit slop always wins. A touch that misses everything goes to the nearest control whose enlarged area contains it, so a margin never steals a touch from a neighbour.
- `_test_touch_targets` fails the suite if any control on those screens has a smaller effective touch area, and checks both rules above on a real settings segment. A 40-unit check would prove nothing about a thumb, which is why the test is in layout units with the dp conversion printed next to it.
- Still to confirm by hand on a real phone: that the visible 54-unit segments feel right to hit, and that the margin does not make a mistap more likely in the dense Gear filter row.

## Combat HUD

Covered by `_test_glass_hud`: pause by touch, the pause menu's buttons, the music toggle, resume and the countdown, the Nova disc (pressable only when full), the upgrade cards and picking one by touch, the boss fight's HUD, and the victory and defeat screens' buttons inside the safe area. The same five combat screens are also drawn under reduced motion, reduced flashes, larger interface size and the colour-blind palette. (The colour-blind palette only recolours enemy shots, so the HUD itself looks the same under it.)

The glass in combat is deliberately small. The largest piece is the score plate, about 230 by 82 units, drawn at 34% opacity, which covers about 2% of the screen. The boss name plate is about 40 units tall. Pause and Nova are the existing size. No panel sits on the middle of the battlefield. On a narrow screen (larger interface size) the shield gauge shortens so it never runs under the score plate.

## Using it

- Prefer `UI.glass` with a kind for new panels, and `UI.panel` where a colour already says what it is.
- A toggle or tab is `selected`, the one main action is `primary`, a destructive one is `warning`.
- Never pass `primary` for a toggle: it would compete with the real action.
- Gate any new ambient animation with `UI.motion_ok()`, and any pulse or flash with `UI.flash_ok()`.

## Tests and screenshots

`_test_glass_ui` in `tools/test_game.gd` checks the accessibility switches, that every button id on the title, Hangar, Ops, Settings, map, briefing and Expedition screens is still present with a touch-sized hit area, that scrolling carries hit areas with it, a real touch on a settings segment, and that every screen paints under four combinations of motion, flash, interface size and colour-blind settings.

Screenshots are in `screenshots/glass-ui/` (the previous look is in `screenshots/glass-ui/before/`; other phone sizes, large interface size and reduced motion are in `screenshots/glass-ui/sizes/`; every combat phase under each accessibility setting is in `screenshots/glass-ui/hud/`).
