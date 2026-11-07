# Danger Contracts

Optional risks the player picks before a run, each with a clear effect and a payout. They are a third kind of choice next to Hazard Dials and tiers:

| | Hazard Dials | Tiers | Danger Contracts |
|---|---|---|---|
| Chosen | per run | per campaign replay | per run |
| Changes | enemy numbers | enemy numbers | your ship, the pace, the rules |
| Pays | score and level salvage | tier loot and salvage | parts, pilot XP, gear odds and extra gear drops |

Dials make a level bigger. Contracts make it different. That is why most of them change something about the player, and why the payouts are mostly gear and progression and not just more salvage.

## The seven contracts

| Contract | Effect | Pays on a win | Heat |
|---|---|---|---|
| Fragile Hull | 1 less hull (never below 1). Not offered in the Expedition | better gear odds, +1 Rare or better roll | 2 |
| Overclocked Hostiles | enemy shots 15% faster and 20% more often | +60% parts, +25% pilot XP | 2 |
| Elite Signal | a quarter of enemies are elites | +20% pilot XP, a boss cache (Rare or better gear that can carry that boss's perk) | 2 |
| Salvage Rush | waves arrive 30% sooner (no on-screen timer) | +25% salvage | 1 |
| Nova Silence | Nova Burst is sealed | +20% pilot XP, an Epic or better gear drop | 3 |
| Cold Reactor | shield refills at half speed | +15% salvage, +40% parts | 1 |
| Lean Loadout | one fewer module to pick from, no rerolls | +30% pilot XP, +1 Rare or better roll | 2 |

"Heat" is shown as bars on the card, so the risk is visible at a glance. It is a label for the player and does not enter the payout maths.

## Rules

- **Opt in only.** Nothing is chosen by default. A "Repeat last" button offers the previous pick, never applies it.
- **Unlocked** after the first boss (`Danger.UNLOCK_LEVEL`).
- **At most two** per run, and never two from the same group (your ship, enemy pressure, elites, pace, Nova, modules). Two contracts pay 15% more of the percentage rewards than the sum.
- **Compatible with Dials.** A contract and a dial that do the same thing exclude each other (Elite Signal and Elite Invasion, Fragile Hull and Brittle, Overclocked Hostiles and Overdrive Fire or Frenzy, Cold Reactor and Dry Cells). The card says why it is unavailable, and picking a dial that clashes says which contract blocks it. Anything else stacks.
- **Stacking is bounded.** Danger cannot push enemy shot speed past x2.0 or fire rate past x2.6 on its own, and elite chance uses the larger of the dial, tier and contract, never the sum.
- **Nothing is lost on a defeat.** A loss pays no bonus and records no completion. The results screen says "Nothing was lost."
- **Pay once.** Salvage, parts and pilot XP bonuses apply to what the run earned, and gear rolls are extra drops. All payouts are capped (`Danger.CAPS`): salvage +60%, parts +100%, pilot XP +60%, gear odds +4, two extra rolls.

## Where it works

| Mode | How contracts appear | When it pays |
|---|---|---|
| Campaign, boss levels, Black Box | a section in the briefing, above the Dials | on a win |
| Rift | the same section on the Rift briefing | a bonus gear roll at every 5th floor, and the percentage bonuses once 3 floors are cleared |
| Expedition | elite and boss nodes offer an overlay before the fight. Ordinary battles do not | on each node won |
| Daily and Weekly | one featured contract per day or week, the same for everyone, never in conflict with that challenge's dials. Off until switched on | on a win |

## Files

| File | What it holds |
|---|---|
| `src/data/danger.gd` | the contracts, every rule, the payout maths, daily featuring, saving |
| `src/menus/danger_picker.gd` | the illustrated cards, shared by the briefing, Expedition and Ops |
| `game.gd` | `_apply_danger`, `_pay_danger`, the Nova seal, wave pace, hull, shield, modules |
| `src/save.gd` | the `danger` key: counts per contract and the last pick per mode |

To add a contract, add an entry to `Danger.LIST` and `Danger.ORDER`. Tests cover the data, so a missing art key, an unknown effect or a payout above the caps fails the suite. The art reuses existing illustrations until dedicated art is made (`art` is a `UIArt` key).

## Tuning

Change numbers in `Danger.LIST` and the caps at the top of `danger.gd`. Check with the simulator:

```powershell
& $godot --headless --path . --script tools/test_game.gd -- --test --levels=51-60 --tries=2 --think=0.3 --fumble=0.25 --gear=rare:12 --pilot=15 --danger=rush,hostiles
```

## Tests

`_test_danger` in `tools/test_game.gd` covers: contract data, selection rules and every legal pair, payout scaling and caps, daily featuring, save and load, each contract's effect in a real run, a won run paying exactly what the card said, a lost run paying nothing, the Rift milestone and payout, and the briefing, Expedition and Ops screens.

## Balance notes (bot simulation, not people)

Levels 51 to 60 on Normal, mid gear (Rare, power 12, pilot level 15), the human-like bot, two tries per level:

| Contract | Levels beaten | Salvage per win vs none |
|---|---|---|
| none | 10 of 10 | 193 |
| Fragile Hull | 10 of 10 | 199 |
| Overclocked Hostiles | 10 of 10 | 202 |
| Elite Signal | 10 of 10 | 183 |
| Salvage Rush (before the change below) | 10 of 10 | 262 (+36%) |
| Nova Silence | 9 of 10 (one level lost twice) | 186 |
| Cold Reactor | 10 of 10 | 222 |
| Lean Loadout | 10 of 10 | 183 |

What this says and what it does not:

- The bot sees every shot, so it finds most contracts easy. Nova Silence is the only one that made it lose a level. Real players will feel them more, but that is a guess until people play.
- **Salvage Rush was free money** for a strong player (+36% salvage, no losses), so it now pays +25% and arrives 30% sooner.
- Cold Reactor (+15% salvage) is the next most generous. Watch it in playtests.
- Contracts that pay parts, XP and gear drops did not change the salvage economy. Salvage is the Hangar currency, so keep contracts' salvage bonuses small.

Measure in playtests: win rate with and without each contract at the same gear, how often each is picked (a contract nobody takes is too risky or too dull, one everybody takes is too cheap), how many players take two at once, and whether players who lose with a contract stop using them.
