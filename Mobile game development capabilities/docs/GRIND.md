# The Grind: Gear, Tiers, Rift and Pilot Level

These systems give the game a long tail. All of them are data and small functions, so every number below can be tuned without touching combat code.

## The loop

Fly a level, find gear, equip or upgrade it, then take on something harder that drops better gear. No energy timers and no waiting, and even a lost run pays out.

## Gear

Every ship has three slots: **Weapon**, **Reactor** and **Plating**. Gear belongs to you, not to a ship, and can be moved between ships.

| Rarity | Affixes | Level cap | Scrap value |
|---|---|---|---|
| Common | 1 | 4 | 3 parts |
| Uncommon | 2 | 6 | 7 |
| Rare | 2 | 8 | 15 |
| Epic | 3 | 10 | 32 |
| Legendary | 3 and a perk | 12 | 80 |

- **Affixes** are random stats such as damage, fire rate, crit, Nova charge, magnet, shield or hit immunity. Hull only rolls on Epic and better. Values scale with rarity, the drop's power and the item's upgrade level.
- **Legendary perks** reuse effects the card system already has: ricochet, burning hits, a drone, homing missiles and more. 13 exist, and each is tied to a boss, so that boss is the best place to farm it.
- **Rating** is one number for comparing two items. In the bag, a red or green triangle shows whether an item beats what you are wearing.
- **Parts** come from scrapping and from every flight. Spend them upgrading gear. Scrapping Rare or better asks you to confirm.
- **The bag** holds 80 items. When it is full, new loot is scrapped into parts automatically.
- New gear auto-equips into an empty slot, so new pilots feel it straight away.

### Where gear drops

| Source | Drops |
|---|---|
| Finishing a level | Always 1. First clear adds an Uncommon or better. Tier clears add a Rare or better |
| Heavy enemies and elites | 10% to 18% per kill |
| Bosses | A guaranteed Rare or better, plus two extra rolls with better odds for their own legendary perks |
| Black Box missions | An extra Rare or better |
| Weekly Boss | An Epic or better |
| Expedition | Elites, bosses and some battles |
| Rift | A 22% chance per floor, and every 5th floor pays once with a milestone |

**Power** decides gear strength: it rises with the level, the tier and the Rift floor. **Luck** shifts the odds toward Epic and Legendary.

## Campaign tiers

After beating level 60, the same 60 levels replay at **Veteran**, **Elite**, **Nightmare** and **Starfall**. Each tier has its own stars and progress, and beating level 60 on a tier unlocks the next.

| Tier | Enemy health | Enemy fire | Enemy count | Elite chance | Gear power | Salvage and XP |
|---|---|---|---|---|---|---|
| Normal | x1 | x1 | x1 | 0% | +0 | x1 |
| Veteran | x1.5 | x1.15 | x1.12 | 0% | +8 | x1.5 |
| Elite | x2.1 | x1.35 | x1.25 | 12% | +16 | x2.2 / x2 |
| Nightmare | x2.9 | x1.6 | x1.4 | 25% | +24 | x3.2 / x3 |
| Starfall | x4.0 | x1.9 | x1.55 | 35% | +32 | x4.5 / x4 |

Enemy fire speed also raises how often bosses attack. Tune everything in `src/data/tiers.gd`. Tier selection is the button under the salvage count on the map.

## The Rift

The old Endless mode, now a ladder of numbered floors. It shows as **RIFT** in the menus.

- Every 5th floor is a boss. The sector changes every 5 floors.
- Every 10 floors adds a Hazard Dial, up to three, chosen from a rotating list.
- Past floor 30, health, enemy fire and shot speed keep climbing, so everyone meets a wall eventually.
- **Milestones:** the first time you clear floor 5, 10, 15 and so on, you get gear and parts. Floor 15 and beyond is Epic or better. Floor 25 and beyond may be Legendary, and floor 50 is guaranteed.
- Deeper floors raise gear power and luck.

## Pilot level

Every flight earns XP, win or lose. There is no level cap.

- XP needed per level: `100 + 25 x level`.
- Every level pays salvage and parts. Every 5th level also drops a Rare or better, and every 10th an Epic or better.
- Up to level 100 each level adds +0.3% damage and +0.5 shield. After 100 the rewards continue but the bonus stops growing.

## Overclock Lab

A Hangar tab that unlocks once every standard upgrade is maxed. It has three endless upgrades: damage, shield and salvage. Each level costs 10% more than the last, so spare salvage always has somewhere to go.

## Files

| File | Purpose |
|---|---|
| `src/data/gear.gd` | Rarities, affixes, perks, generation, numbers, upgrade and scrap costs |
| `src/data/tiers.gd` | Tier table |
| `src/data/pilot.gd` | XP curve and rewards |
| `src/menus/menu_gear.gd` | The Gear tab |
| `src/save.gd` | Bag, equipment, parts and tier progress |
| `game.gd` | Drops, tiers and Rift floors in a flight (`roll_loot`, `_rift_floor_cleared`, `_commit_loot`) |

## Test options

```powershell
& $godot --headless --path . --script tools/test_game.gd -- --test --levels=1-60 --tries=3 --think=0.3 --fumble=0.25 --tier=3 --gear=legendary:30 --pilot=50
```

`--tier` picks the tier, `--gear=rarity:power` equips a full maxed set, and `--pilot` sets the pilot level.

## Next steps for the grind

These are designed but not built yet:

- **Ship ranks:** extra blueprint drops rank a ship up to five stars.
- **Hunting trophies:** kill 1,000 of an enemy type for a permanent small bonus against it.
- **Reward track:** a free 100-tier track per season, using the existing season table.
- **Login streaks** on top of the daily contracts.
- **Gear locking and sets:** a lock so nothing valuable is scrapped by mistake, and bonuses for matching sets.
- **Gear for ships' special traits:** items that interact with each ship's own trait.
