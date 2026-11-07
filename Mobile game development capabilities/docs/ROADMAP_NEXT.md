# What comes after Danger Contracts

These five features are designed, not built. They are ordered by value and by what each one needs from the one before it. None adds an energy gate, a countdown, or anything that can be bought.

How the current game is built, since every proposal leans on it:

- A run is `session -> game.gd`. Modifiers (Dials, tiers, Danger Contracts) change how a run plays, and loot, parts and pilot XP are paid when it ends.
- Gear is three slots with random affixes and 13 Legendary perks. Each perk is tied to a boss through `Gear.PERKS[...].boss`, and the perks reuse the Module card stat keys (`ricochet`, `drones`, `phoenix`...).
- Ships have a trait, mastery levels and paints. Nova modes are chosen in the Hangar.
- Meta already has daily contracts, achievements, the codex, a season table that does not change play yet, and cloud saves (`Cloud`, `CloudSave.Backend`; see `docs/CLOUD_SAVE.md`).

Suggested order: Build Report, then Weekly Boss Bounties, then Gear sets, then Faction reputation, then Daily rankings. The first two need no new systems and tell us what the rest should be.

---

## 1. Post-run Build Report cards

**Why players return.** A run ends and the player wants to know what they just made. A card that names their best combo, the build they assembled and the one stat that stood out turns a forgettable loss into a story they can compare, screenshot and improve on. It is also the only feature here that makes every single run feel more meaningful, with no new content.

**How it connects.** Everything it needs already exists during a run: `held` (module cards and evolutions), `best_combo`, `kills`, `score`, `hull_lost`, the equipped gear and its perks, `Save.nova_mode`, the ship and its mastery, `danger` and `mutators`. Nothing needs to be invented, only gathered when the run ends.

**Minimum viable version.**
- One card on the results screen, collapsed by default under the existing rewards, opened with a single tap.
- Shows: ship, Nova mode, the build as its module icons (evolutions highlighted), gear icons with rarity, contracts and dials, best combo, damage taken, and one "standout" line chosen from a small fixed list (for example "Never lost shield", "Nova fired 6 times", "Evolved Prism").
- Saved as a small dictionary in the last few runs (keep 10), viewable from the Records tab. Sharing is a screenshot of the card, drawn on a SubViewport. Do not build a server.

**Economy and balance risks.** None, because it pays nothing. The risk is clutter: the results screen is already dense, so the card must stay behind a tap. A second risk is the "standout" line praising nothing in particular, which makes it feel fake, so each line needs a real threshold.

**What to measure.**
- Share of runs where the card is opened, and where it is shared.
- Whether opening it changes the next action (retry, Hangar, quit).
- Which standout lines show up. If one line is above 40% of cards it is too easy to earn.

---

## 2. Weekly Boss Bounties

**Why players return.** The weekly boss today is one fight with one reward. A bounty gives each week a reason to come back on a particular day and a goal that is not "get a higher number": special objectives (kill the boss without using Nova, break all weak points before the third phase, finish with full shield) and a collectible that stays when the week ends.

**How it connects.** `Meta.weekly_challenge()` already picks a boss sector from the bosses the player has beaten. Bosses have weak points, phases and a Legendary perk tied to them. Danger Contracts are the natural way to make an objective harder: a bounty can feature one contract, as the daily and weekly cards do today. The reward is a boss trophy (see below), plus the usual gear roll.

**Minimum viable version.**
- Each week offers three bounties on the same boss with different objectives, worth 1, 2 and 3 marks. Objectives come from a fixed list of about ten, all checkable from data the game already tracks.
- Marks buy nothing consumable. Each boss has a **trophy**: a cosmetic shown in the Codex and on the ship's paint page (a boss-themed hue and a small emblem on the title screen). Three marks in one week complete the trophy track for that boss. Collecting all six is the long goal.
- One extra, optional drop per week: a Legendary of that boss's perk, once, so the bounty is a good moment to be there but never a requirement.

**Economy and balance risks.**
- Perk drops make bosses the best farm. A weekly guaranteed Legendary is generous, so cap it at one per week and keep the existing farm odds unchanged.
- Objectives that reward hiding (never moving, never shooting) must be avoided. Test each objective for a degenerate way to complete it.
- Trophies must be cosmetic only. If a trophy ever changes a stat it becomes pay-to-win in spirit and a wall for new players.

**What to measure.**
- Share of active players who attempt a bounty each week, and how many objectives they attempt per week.
- Completion rate per objective. An objective under 15% is probably unfair or unclear, and one over 85% is not a challenge.
- Whether players who finish a bounty return for the next week more than those who do not.

---

## 3. Gear-set synergies that change how you play

**Why players return.** Today gear is stats, and an Epic plating with better numbers is a straight upgrade. A set is a reason to keep a worse item because of what it makes the ship do, which is the difference between a stat treadmill and a build. It also gives every drop a second question: does this belong to a set I am chasing?

**How it connects.** There are 13 Legendary perks and each already ties to a boss sector, so the natural unit is the **boss set**: items carrying the same boss mark. Equipping two or three marks from one boss activates a set effect, built from effects the card system already implements (ricochet, burn, drones, phoenix, graze). The set bonus changes behaviour, not numbers. Ship traits give a second hook: a set can be written to pair with a trait.

**Minimum viable version.**
- Two sets only, built on bosses 1 and 2, whose effects are easy to read: for example "Warden set: shots stop at the first boulder but ricochet twice; plating blasts nearby shots on a shield hit." The set tag appears on the gear card and the Gear tab shows `2/3` progress.
- Items gain a `set` field that is only rolled on Epic and Legendary drops, and only from that boss, so the set is a place to go and not a random lottery.
- Add a lock on gear so a set piece is never scrapped by mistake. This was already in the grind plan.

**Economy and balance risks.**
- The largest risk. A set that is strictly strongest becomes the only build. Each set needs a real trade-off, and the first two should be tested against the best non-set loadout, with the goal of "equal at best on raw damage, different in play".
- Set pieces make the bag fuller, and the bag is capped at 80. Sets need a dedicated way to hold pieces or the cap will quietly punish people for collecting.
- Stacking with Legendary perks that use the same stat key must be capped.

**What to measure.**
- Share of players wearing 2 or more set pieces by pilot level.
- Win rates and clear times of set loadouts against non-set at the same rating, using the bot simulation first, then real players.
- How often set pieces are scrapped. A high number means the sets are not understood.

---

## 4. Faction reputation: three salvager groups

**Why players return.** Reputation gives a long arc that is separate from power: a place to put a particular way of playing. A player who likes risk, one who likes loot, and one who likes careful play each get a home, with rewards that suit them and visible ranks.

**How it connects.** Each faction maps onto a system the game already has:
- **The Breakers** (risk): rank rises from completing Danger Contracts.
- **The Reclaimers** (collecting): rank rises from gear found, parts and Black Box missions.
- **The Wardens of the Belt** (mastery): rank rises from flawless clears, boss objectives and ship mastery.

Reputation is earned from actions the game already counts, so there is nothing to grind separately. Rewards are cosmetics (ship paints, title-screen emblems, a pilot title) plus **gameplay flavour**: each faction offers a choice of one small, sideways perk to carry (for example the Breakers let the player pick which Danger Contract is featured on the daily).

**Minimum viable version.**
- One screen with three ranked bars. Ranks 1 to 5 each. Rank 5 gives one cosmetic and one flavour choice each, for three of each in total. No store, no currency.
- Reputation is a sum of existing stats with weights, so it can be rebuilt from the save at any time. No new stored state except the chosen flavour.

**Economy and balance risks.**
- Flavour perks are where it could become power. Rule: a flavour choice must widen options (extra contract choice, a gear lock slot, a second featured daily) and never raise damage, shield or drop odds.
- Players can feel forced to play the faction they do not enjoy. Because ranks come from what they already do, no faction should ever require something else.
- Three factions means three sets of cosmetics to make. Start with palette swaps and emblems.

**What to measure.**
- Distribution of rank across the three factions. If one is far ahead, its action is too easy.
- Whether players who choose a flavour perk change which modes they play.
- Share of players who open the faction screen at all.

---

## 5. Asynchronous daily challenge rankings

**Why players return.** Daily play is where players compare. Ranking identical conditions turns the daily challenge from "clear it once" into "do it better than yesterday", and is the clearest long-term reason to return for a competitive player.

**How it connects.** `Meta.daily_challenge()` already fixes the level and dials from the date, and now the featured Danger Contract is fixed the same way, so everyone who opts in faces the same rules. Scores are already recorded per day in `Save.daily_best`. The `CloudSave.Backend` seam exists for a Play Games plugin.

**Minimum viable version.**
- Keep play identical for everyone: seed every random source in the daily run (enemy spawns, module offers, loot) from the date, so two players with the same inputs see the same run. Module offers use a fresh `rng.randomize()` today and must change for this.
- Rank by one number, the existing score, within a fixed ship (the daily ship is set, or players are ranked per ship).
- Start with a **friends-and-self** board and a personal history before any global one. Then use Play Games leaderboards, so there is no server to run.

**Economy and balance risks.**
- Cheating: a leaderboard without a server check will fill with edited scores. Plan from the start for plausibility limits on score per second, and treat global rankings as unverified until there is a replay check.
- Gear creates unfair advantage. Either run the daily with a standard loadout (preferred) or rank by gear band.
- A visible rank can discourage newer players. Show their percentile and their own best, not the top of the board.
- No rewards that depend on rank. Rewards should depend on taking part.

**What to measure.**
- Daily participation, and the share of players who play more than once in a day to improve.
- Spread of scores. A tight spread means the challenge is solved, and a very wide one means skill or gear is dominating.
- Whether players with a visible rank return more often than those without. Test this before building the global board.

---

## Order and gates

| Step | Needs | Done when |
|---|---|---|
| Build Report | nothing new | cards open from every run's results and from Records |
| Weekly Bounties | Build Report data helps | 3 objectives checked from tracked stats, trophy cosmetics shown |
| Gear sets | gear lock | 2 sets tested against non-set loadouts by simulation |
| Faction reputation | Danger Contracts, bounties | reputation rebuilds from the save and nothing is power |
| Daily rankings | seeded runs | the same inputs give the same run |

Do not start a later step because an earlier one looks finished. Start it when the numbers from the earlier step say players use it.
