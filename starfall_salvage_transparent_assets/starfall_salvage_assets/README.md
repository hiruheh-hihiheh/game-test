# STARFALL // SALVAGE — Transparent Asset Pack

All individual assets are exported as **512×512 RGBA PNGs** with transparent backgrounds. Each sprite is centered and scaled proportionally; no colored canvas/background was added.

## Contents

- `ships/`: player ships, enemy fighter, boss ship
- `ui_icons/`: hull, afterburner, tri-beam, modules, boss, wave, pause, play, home, settings
- `projectiles/`: cyan player shot and orange/magenta enemy shots and laser
- `effects/`: small/large explosions and shield orb
- `environment/`: three asteroid sizes and blue salvage crystal
- `original_asset_sheet.png`: original transparent source sheet

## Sprite list

- `ships/player_nova_01.png` — `player_nova_01` (source crop 473x352)
- `ships/player_interceptor_02.png` — `player_interceptor_02` (source crop 327x280)
- `ships/enemy_fighter_01.png` — `enemy_fighter_01` (source crop 453x304)
- `ships/boss_ship_01.png` — `boss_ship_01` (source crop 653x333)
- `ui_icons/upgrade_hull_plating.png` — `upgrade_hull_plating` (source crop 166x175)
- `ui_icons/upgrade_afterburner.png` — `upgrade_afterburner` (source crop 187x142)
- `ui_icons/upgrade_tri_beam.png` — `upgrade_tri_beam` (source crop 162x185)
- `ui_icons/icon_modules.png` — `icon_modules` (source crop 173x168)
- `ui_icons/icon_boss.png` — `icon_boss` (source crop 158x170)
- `ui_icons/icon_wave_status.png` — `icon_wave_status` (source crop 195x167)
- `ui_icons/icon_pause.png` — `icon_pause` (source crop 158x161)
- `ui_icons/icon_play.png` — `icon_play` (source crop 136x153)
- `ui_icons/icon_home.png` — `icon_home` (source crop 156x144)
- `ui_icons/icon_settings.png` — `icon_settings` (source crop 154x150)
- `projectiles/projectile_player_cyan.png` — `projectile_player_cyan` (source crop 93x184)
- `projectiles/projectile_enemy_orange.png` — `projectile_enemy_orange` (source crop 90x174)
- `projectiles/projectile_enemy_magenta.png` — `projectile_enemy_magenta` (source crop 87x177)
- `projectiles/projectile_laser_magenta.png` — `projectile_laser_magenta` (source crop 136x164)
- `effects/effect_explosion_small.png` — `effect_explosion_small` (source crop 153x145)
- `effects/effect_explosion_large.png` — `effect_explosion_large` (source crop 257x210)
- `effects/effect_shield_orb.png` — `effect_shield_orb` (source crop 216x219)
- `environment/asteroid_large.png` — `asteroid_large` (source crop 219x214)
- `environment/asteroid_medium.png` — `asteroid_medium` (source crop 137x141)
- `environment/asteroid_small.png` — `asteroid_small` (source crop 87x78)
- `environment/salvage_crystal_blue.png` — `salvage_crystal_blue` (source crop 154x174)

## Implementation notes

- Use the PNGs directly as image/texture assets; the transparent pixels are preserved.
- For UI icons, use `contain`/aspect-fit so the sprite is not stretched.
- For projectiles and effects, scale according to gameplay and camera zoom.
- These are visual assets only; connect buttons, HUD values, collision, animation and gameplay behavior in code.
