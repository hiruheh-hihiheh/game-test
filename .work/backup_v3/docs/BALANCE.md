# Balance Report

Results from `tools/test_game.gd`, using a bot set to react like a person (`--think=0.3 --fumble=0.25`: a decision every 0.3 seconds, with 1 in 4 missed). It buys gear only, picks cards at random and uses Nova when shots pile up.

**Read these as a guide, not a verdict.** The bot sees every shot perfectly, but it doesn't plan ahead or read boss patterns. Real players will take more hits on regular levels and may do better against bosses. Tune with real playtests next.

## Final campaign run (Nova, finished build)

| Sector | Attempts | Lost | Level time | Hull lost | Stars | Boss time |
|---|---|---|---|---|---|---|
| 1 Debris Belt | 10 | 0 | 43s | 0.0 | 2.3 | 83s |
| 2 Ember Drift | 10 | 0 | 35s | 0.0 | 2.5 | 65s |
| 3 Violet Nursery | 10 | 0 | 47s | 0.0 | 2.5 | 86s |
| 4 Pale Graveyard | 10 | 0 | 49s | 0.0 | 2.5 | 85s |
| 5 Crimson Front | 10 | 0 | 45s | 0.5 | 2.2 | 73s |
| 6 Sunken Core | 11 | 1 | 46s | 1.1 | 2.0 | 98s |

All 60 levels were beaten in 61 attempts. The only loss was to the final boss. Every Hangar gear upgrade was bought, with 2,399 salvage left over for tech and ships.

## Ships

Each ship flew the campaign before the last round of boss fixes. Sectors 1 to 4 are unaffected by those fixes.

| Ship | Level time (sectors 1 to 4) | Boss time (sectors 1 to 4) |
|---|---|---|
| Nova | about 43s | about 85s |
| Interceptor | about 39s | about 52s |
| Lancer | about 39s | about 70s |
| Warden | about 33s | about 68s |
| Magpie | about 40s | about 59s |

Nova is the slowest clear, which suits a starting ship: every unlock feels like a step up. The Warden is still the fastest on regular levels. Watch it in real play, because the bot makes close-range and beam ships look worse than a person would.

## What the simulations caught

- A rare crash when a hull hit cleared shots during the bullet update.
- A crash when a boss died with attacks still queued.
- The Crimson Admiral's bridge and the Sunken Core's eye could not be hit, because armour hitboxes sat in front of them. `_check_weak_points` now guards against this for every boss.
- The Tyrant's vents and the Regent's heart were partly shielded the same way.
- Homing shots aimed at boss centres, even when armoured. They now use `aim_point()`.
- The first boss was too hard and bosses took up to 200 seconds. They now take about 1 to 1.5 minutes.
- Magpie's range was too short to reach anything.
- The final boss's rings blocked about 77% of shots. They now block about half.

## Current risks to watch in playtests

- **Sectors 1 to 4 may be too easy** for skilled players. The bot rarely loses hull there. The fix is in `difficulty()` in `src/data/levels.gd`, or in the wave lines.
- **The final boss** swung a lot between test runs: from one loss to six straight losses by ship before the last spoke change. Test it by hand.
- **Beam-Lancer against rings** hasn't been tuned specifically.
- **Card balance** is untested beyond "every card works and stacks". The bot picks at random, so strong combos haven't been measured.
- **Evolutions in the campaign** depend on loadouts: a level offers only a few card picks, so evolving usually needs one half of the pair brought in a Loadout slot.
- **Expedition economy** has only been tested for flow, not for how rewarding it feels.

## Performance

`tools/bench.gd` holds 620 shots and 41 enemies on screen, far above any real level. Game logic costs 2.2 ms a frame on the development PC, against a 16.6 ms budget at 60 fps. A budget phone will be several times slower, and this doesn't include GPU time, so it needs checking on a real device.
