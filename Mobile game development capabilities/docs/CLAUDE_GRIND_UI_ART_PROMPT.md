# Current UI art implementation prompt — Grind update

Copy the task below to the implementation agent.

---

You are improving the visual UI of the current **Starfall Salvage** Godot mobile game. The gameplay has recently added the **Grind update**: three-slot randomized Gear loot, five rarities, legendary boss perks, replay Tiers, the Rift progression ladder, Pilot Levels, and the Overclock Lab.

The core mechanics and menu screens already work. This is a focused visual integration pass: make the new progression systems feel physical and premium by using the supplied transparent illustration assets. Do not redesign the underlying systems, alter balance, or break the immediate-mode UI architecture.

## First inspect this current project state

- `title_screen.gd`: title screen now routes to Hangar, Ops, Expedition, and **Rift** (previously Endless).
- `src/menus/menu_hangar.gd`: the Hangar now has five tabs: Ships, Gear, Lab, Tech, Nova.
- `src/menus/menu_gear.gd`: Gear is the important new screen. Every ship equips Weapon, Reactor, and Plating loot. The card renderer is `_card()`.
- `src/data/gear.gd`: defines the three slots, five rarities, and thirteen Legendary perks.
- `game.gd`: the results screen now presents Pilot XP and found Gear.
- `src/ui_layer.gd`: UI is redrawn every frame. Never load textures, create nodes, or create tweens inside the draw loop.

## Why this pass matters

The new screenshots show that the systems are strong, but the Gear screen still represents its three major equipment types with tiny generic icons. The title screen’s main destination cards are also still mostly text. Large illustrations do **not** belong on every control; add them only where they improve scanning and reward feeling.

## Supplied asset pack

All supplied assets are transparent PNGs under `assets/starfall/ui_illustrations/`.

### Destination cards

| Screen button | Asset |
|---|---|
| Hangar | `home/hangar_dock.png` |
| Ops | `home/ops_radar.png` |
| Expedition | `home/expedition_rift.png` |
| Rift | `home/endless_vortex.png` |

### Existing Hangar permanent systems

| System | Asset |
|---|---|
| Nova Pulse | `nova/pulse.png` |
| Singularity | `nova/singularity.png` |
| Overdrive | `nova/overdrive.png` |
| Aegis | `nova/aegis.png` |
| Locked Nova / unrevealed blueprint | `shared/locked_blueprint.png` |
| Cannon | `gear/cannon.png` |
| Rapid Fire | `gear/rapid.png` |
| Shield Cell | `gear/shield.png` |
| Hull Frame | `gear/hull.png` |
| Magnet | `gear/magnet.png` |
| Nova Core | `gear/core.png` |
| Loadout Slot | `tech/slot.png` |
| Reroll Bay | `tech/reroll.png` |
| Rare Scanner | `tech/lucky.png` |
| Fourth Option | `tech/extra_card.png` |
| Emergency Cell | `tech/emergency.png` |
| Salvor Contract | `tech/salvor.png` |

### New Grind assets — use these now

| Purpose | Asset |
|---|---|
| Weapon loot | `loot/weapon.png` |
| Reactor loot | `loot/reactor.png` |
| Plating loot | `loot/plating.png` |
| Pilot Level / rank reward | `pilot/rank_badge.png` |

## Required implementation

### 1. Home screen

Integrate the four destination assets beside the existing `Hangar`, `Ops`, `Expedition`, and `Rift` labels. The cards must remain full-size touch targets and retain text, subtext, badges, and current unlock states.

- Keep the current compact two-column layout viable at **405×900**.
- Draw destination art at roughly **46–60 logical pixels** on the left. Shift title/subtitle right rather than overlaying artwork and text.
- Do not put art on Play, settings, the pilot chip, salvage chip, or every navigation control.
- RIFT must use the gold/cyan vortex art, not old "Endless" wording.

### 2. Gear tab — priority one

Update `MenuGear._card()` and `_empty_slot()` with `Weapon`, `Reactor`, and `Plating` art mapped by `item.slot` / `slot`.

- Use the supplied loot art as the left-side visual in every Gear card, in the same position where the generic icon currently appears.
- Draw at around **68–80 logical pixels**, preserving the current readable name, rarity, affixes, rating, Equip/Upgrade/Scrap actions, and comparison arrow.
- Do not make random art for every individual item. Slot illustrations plus rarity treatment are the correct scalable solution for generated loot.
- Keep rarities data-driven through existing colour/glow/border treatment. Common/Uncommon should stay restrained; Rare/Epic can have stronger glows; Legendary may have a subtle gold pulse.
- For Legendary Gear, optionally draw the relevant boss texture from the existing boss art as a very faint, clipped right-side watermark (alpha around 0.08–0.14). Do not add new boss artwork or obscure the buttons.
- Use the same three images in the results-screen Gear-found tiles where space allows. If the grid is too dense, preserve its existing compact icons rather than shrinking text or touch targets.

### 3. Pilot progression

Use `pilot/rank_badge.png` as a small companion on the Pilot XP card in the results screen. It can also appear at modest size in the title-screen pilot chip only if it remains clear at phone scale.

- Size: roughly **32–44 logical pixels** in results; no larger than **26 logical pixels** in the title chip.
- Preserve level text, XP bar, reward values, and level-up readability.

### 4. Existing permanent Hangar tabs

Finish integrating the existing supplied art into the still text-led permanent Upgrade / Tech / Nova rows:

- Upgrade and Tech rows: 68–84 px companion illustration on the left.
- Nova rows: 88–104 px left illustration. Use `shared/locked_blueprint.png` for unavailable modes, dimmed and desaturated.
- Do not reveal an unavailable Nova mode by rendering its actual ability art.
- Lab rows should remain compact functional rows; use the existing small icon or a subtle glow only. Do not add large art to every endless upgrade.

### 5. What must remain simple

Do **not** add large images to:

- Hangar tabs, filter chips, back/home/settings, buy/upgrade/equip/scrap buttons
- every level-map node or tier selector
- every Ops contract, achievement, record, or menu row
- Expedition route nodes and utility decision buttons

Use icons and colour for those. The purpose is meaningful visual hierarchy, not decorating every rectangle.

## Animation rules

These assets are still PNGs. Animate them only through lightweight Godot draw transforms using the screen/menu time value.

- Gear slot art: 1–2 px float or 1–2% glow pulse.
- Reactor: slow 2–4° ring rotation / 2% core pulse.
- Weapon: soft cyan coil pulse, no continuous spinning.
- Plating: slow edge-light shimmer only.
- Pilot rank: 2% gold-star pulse on level-up/reward screen; static otherwise.
- Home destination art: subtle 2–3 px bob, 2% pulse, or up to 6° slow drift.
- Nova art: subtle mode-specific pulse/rotation. Keep the UI calm.
- Use 2.5–6 second sine/cosine cycles; no random jitter except perhaps an Overdrive afterimage alpha flicker.
- If reduced effects are enabled, draw every asset statically with no bob, rotation, pulses, added particles, or bright glow.
- Never use GIFs, video textures, animated spritesheets, heavy shaders, per-frame `load()`, or extra scene nodes for these illustrations.

## Acceptance criteria

1. The Gear screen reads as a premium loot inventory, where Weapon, Reactor, and Plating are visually identifiable before a player reads the text.
2. The home screen’s four destination cards have stronger identity while remaining clean on 405×900 portrait devices.
3. The new rank/loot art never overlaps buttons, names, price text, progress bars, rarity labels, or touch areas.
4. Current Save data, balance, navigation, and combat logic are untouched.
5. Run the quick automated test, then capture current title, Hangar Gear, Hangar Lab, Hangar Tech, Hangar Nova, and results screenshots for visual verification.

Use your judgment to make any small layout refinements necessary, but keep the existing Starfall Salvage dark-navy / cyan / magenta / gold arcade style intact.

---
