# Starfall Salvage: Design and Systems Guide

How the game fits together, and how to add to it. Everything content-related is data, so most additions are a few lines in `src/data/`.

## The loop

- **In a flight (45 to 90 seconds):** drag to dodge, the ship fires itself. Crystals and kills charge Nova Burst. Cards after each wave shape the build.
- **Between flights:** spend salvage in the Hangar, swap ships and loadouts, claim contracts.
- **Long term:** blueprints from bosses and Black Box missions unlock ships, Nova modes and modules. Mastery, achievements, the codex, Expedition, Endless and rotating challenges keep the game alive after the campaign.

## Ships

| Ship | Role | Weapon | Trait | How it plays |
|---|---|---|---|---|
| Nova | All-rounder | Pulse cannon | Capacitor: faster Nova | The honest baseline |
| Interceptor | Risk taker | Twin guns | Slipstream: near misses charge Nova and boost fire rate | Rewards flying close to shots. Smallest hitbox, least hull |
| Lancer | Sniper | Piercing beam | Steady Aim: up to 2.4x damage while holding still | Rewards committing to a lane |
| Warden | Tank | Homing missiles | Bulwark: shield hits blast nearby shots | Slow and forgiving |
| Magpie | Scavenger | Close-range scatter | Finders Keepers: crystals pay 50% more, every 10 grants a surge | Rewards getting close and looting |

Each boss drops a blueprint. Blueprint plus salvage unlocks a ship. Flying a ship earns its own mastery: stats plus paints.

## Sectors

| Sector | Mechanic | What it asks of you | Boss |
|---|---|---|---|
| Debris Belt | Cover | Use wrecks as shields, then break them | Gravity Warden: shoot through a rotating boulder ring |
| Ember Drift | Heat | Dip into ember clouds for Nova charge, use explosive tanks | Ember Tyrant: armoured until the vents open |
| Violet Nursery | Hatching | Prioritise pods before they hatch | Orbital Hydra: sever three heads to open the heart |
| Pale Graveyard | Revival | Finish what you start: shatter husks | Pale Regent: blinks, casts false images |
| Crimson Front | Crossfire | Read broadside lanes, protect haulers | Crimson Admiral: strip turrets to expose the bridge |
| Sunken Core | Gravity | Fly around wells that bend every shot | Sunken Core: fire through rotating armour rings |

## Stars

Stars are earned separately across replays. 1: clear the level. 2: lose no hull. 3: the level's own objective. Star totals gate Hangar tech.

## Adding content

**A level:** one line in `CAMPAIGN` in `src/data/levels.gd`.

```gdscript
{"n": "My Level", "obj": ["combo", 20], "tip": "Shown on first flight", "w": ["fighter vee 4; !flare 2", "gunship hold 1"]},
```

Wave language: `kind form count [delay or elite mod]`, joined by `;`. Events start with `!`.

- Forms: rain, drift, line, vee, column, sine, pincer, dive, scatter, swarm, hold, side.
- Events: storm, flare, row, ember, frost, well, spokes, treasure, escort, ambush.
- Objectives: crystals, combo, time, wrecks, ember, tanks, nohatch, husks, shield, escort.

**An enemy:** add to `DB` in `src/data/enemies.gd`. Stats, art, attack and codex text all live there.

**A card:** add to `LIST` in `src/data/cards.gd`. Its `stats` are summed automatically. Existing stat keys work with no new code. An evolution is a card with rarity `EVOLVED` and a `needs` list.

**A Hazard Dial:** add to `src/data/mutators.gd`.

**A contract or achievement:** one line in `src/data/goals.gd`. Goals count named stats, reported through `Meta.count()`.

**A season or event:** add a row to `SEASONS` in `src/data/goals.gd`. The date logic already picks the active one. Bonus rules for a season are the next step.

**A boss:** extend `BossBase` in `src/combat/bosses/`. Override `build()`, `rotation()` and `special()`. Add identity text in `src/data/bosses.gd`.

## Code map

| Path | Purpose |
|---|---|
| `game.gd` | Flow, player, enemies, waves, endings |
| `title_screen.gd` | Menu hub |
| `src/combat/` | Bullets, effects, hazards, HUD, bosses |
| `src/menus/` | Map, Hangar, Ops, Expedition, Settings |
| `src/data/` | All content |
| `src/meta/` | Progress logic, Expedition, telemetry, cloud save seam |
| `src/save.gd` | Saves, migration, merging |
| `tools/` | Art, audio and font generators, tests, benchmark |

## Performance notes

Bullets, sparks, shots and pickups draw through `SpriteBatch` (one draw call per texture) and bullets live in flat packed arrays, so hundreds of shots create no garbage. Enemy sprites are pooled. The Effects setting scales particles, and frame rate can be capped at 30.
