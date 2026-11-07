# UI illustrations

The Grind update art pack is wired into the menus. It is visual only: no save, balance, navigation or combat code changed.

## Where each image is used

| Screen | Art | Size |
|---|---|---|
| Title: Hangar, Ops, Expedition, Rift cards | `home/*` | 60 px, left of the label |
| Title: pilot chip | `pilot/rank_badge.png` | 26 px, still |
| Hangar Gear: every equipped and bag card | `loot/weapon`, `reactor`, `plating` by item slot | 80 px |
| Hangar Gear: empty slot | the same art, grey and faint | 66 px |
| Hangar Gear: Legendary cards | the perk's boss texture as a watermark, alpha 0.11 | behind the text |
| Hangar Lab tab: upgrade rows | `gear/*` | 84 px |
| Hangar Lab tab: Overclock rows | existing small icon, faint gold pulse once the lab is open | unchanged |
| Hangar Tech rows | `tech/*` | 84 px |
| Hangar Nova rows | `nova/*`; unfound modes show `shared/locked_blueprint.png` in grey | 100 px / 96 px |
| Results: Pilot XP card | `pilot/rank_badge.png`, pulses only when a level was gained | 44 px |
| Results: gear found tiles | slot art | 62 px, still |

Nothing else got art: tabs, filter chips, buy/equip/scrap buttons, map nodes, Ops rows and Expedition nodes stay icon-only.

## How it works

- `src/ui_art.gd` (`UIArt`) draws illustrations with `UIArt.draw(canvas, key, center, size, opts)`: one draw call plus a small transform. Painting never loads, allocates or creates nodes.
- **Nothing loads at boot.** Each page calls `UIArt.focus(active, warm)` when it opens. The groups it shows stream in on a background thread, `warm` groups follow in case the player goes there next, and everything else is released. Only the small title art (about 1.6 MB) stays resident. All the menu art together is about 5.5 MB of video memory, and the title screen alone holds 1.6 MB.
- An illustration that has not arrived yet is skipped for that frame and fades in over 0.22 s when it does, so there is no hard pop-in. In a profile of Hangar navigation the longest frame was 23.8 ms once (the first Hangar visit) and 17.4 ms everywhere else on a 60 Hz window.
- Locked and empty slots use a dim cool tint (`UIArt.GHOST`, `UIArt.LOCKED`) on the normal texture. There are no CPU image copies.
- Motion is in `UIArt.STYLE`: bob 1 to 2.5 px, tilt up to 6 degrees, pulse up to 3%, all on 3 to 6 second sine cycles. Weapon and Plating get a soft breathing outline, Overdrive a faint afterimage.
- **Reduce motion** draws everything still. **Reduce flashes** keeps motion but drops outlines and afterimages. `UIArt.pose_of` is the pure function behind this, and `tools/test_game.gd` checks it.
- `UILayer.button` accepts `art` and `art_size` options for destination cards. The art follows the button's press scale.
- Rarity stays data-driven. Common and Uncommon have no glow and slightly dimmer art, Rare and Epic have rising glow, Legendary has a slow gold pulse.

## Texture sizes

The pack arrived as about 1250 px images (39 MB on disk, roughly 6 MB of video memory each). Nothing is drawn larger than 100 logical pixels, and phones scale a 720 px wide layout by 1.5 to 2, so each group is stored at 2.4 to 4 times its drawn size:

| Group | Drawn at | Stored at |
|---|---|---|
| Title destinations | 60 px | 192 px |
| Pilot rank badge | 44 px | 160 px wide |
| Loot slots, Hangar upgrades, Tech, locked blueprint | 80 to 92 px | 224 px |
| Nova modes | 100 px | 256 px |

The images in the project are the downscaled ones (1.5 MB in total) and their import settings cap them at 256 px with mipmaps. The untouched originals are in `../.work/art_originals_1254`. The four old unused copies of the title images were removed from the art folder (they are in the same backup).

Re-import after changing art with `godot --headless --path . --import`.

## Layout rules these screens follow

- The Hangar and Ops count badge is a pill inside the card's top-right corner, so it never touches the seam, border or art. It widens for two digits and shows `99+` beyond that.
- A Pilot level-up has its own line under the XP bar (`LEVEL UP  13 > 14`), and the panel is tall from the first frame, so nothing jumps.
- Gear card text shrinks and then ends in `...` instead of running into the delta arrow, the NEW tag or the buttons (`UI.fit_text`). Tap targets are never resized.
