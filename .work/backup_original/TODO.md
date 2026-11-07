# Starfall Salvage

## Delivered outcomes

- **Portrait touch-first flight loop** — The player controls a bottom-anchored ship by dragging in the lower half of the screen or using left/right keys; automatic fire, shield, energy, damage, pause, retry, and main-menu navigation are implemented.
- **Wave and sector progression** — Three escalating sectors contain four asteroid waves each, with elite variants, falling threat patterns, salvage pickups, combo scoring, and a sector boss encounter.
- **Run-building upgrade cards** — Between waves, the player chooses one of three modules that change the run through spread shots, piercing rounds, orbiting drones, salvage magnetism, hull plating, afterburner movement, critical hits, or overclocking.
- **Mobile-readable presentation** — Portrait HUD, clear resource bars, boss health, tap-sized upgrade cards, telegraphed projectile colors, vector ship/asteroid/boss silhouettes, layered space scenery, particles, and branded title/result screens are included.
- **Delivery wiring** — Project identity, portrait viewport, local best score persistence, bundled fonts/audio, and the project-owned loading shell remain part of the managed Godot export.
- **Supplied asset integration** — The 25 transparent PNGs from `starfall_salvage_assets` are copied into `assets/starfall/` and wired into the live game: Nova ship, enemy fighter, boss ship, orbit drones, three asteroid sizes, salvage crystal pickups, cyan/orange/magenta projectiles, explosion effects, shield effect resource, and upgrade-card icons.
- **Visual polish pass** — Gameplay projectiles now render as oriented sprite textures with glow tinting, destroyed enemies spawn texture-backed explosion flashes, all spawned threats use real sprite art with rotation/halo feedback, the title ship uses the supplied Nova sprite with floating/rotation animation, and the module bay uses the matching Hull Plating, Afterburner, and Tri-Beam icons.
- **Dynamic space backdrop** — The playfield now has depth-scaled star drift, gentle horizontal parallax, and a pooled set of slowly drifting blue, violet, and teal nebula clouds with low-alpha pulsing layers behind gameplay.
- **Validation note** — Source and asset-reference checks pass; the repository's `npm run check -- --pack` and `check-game.mjs` entry points remain unavailable because their referenced helper modules are missing from this folder, and no Godot executable is installed on the attached desktop for a native run capture.
