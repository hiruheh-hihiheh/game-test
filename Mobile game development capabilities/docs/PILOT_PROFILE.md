# Pilot Profile

Tap the Pilot chip in the top-left of the title screen to open the profile. The chip looks exactly as before. Back returns to the title screen.

The page is `src/menus/menu_profile.gd`. It is registered as the `profile` page in `title_screen.gd` and scrolls like every other menu. Opening it pays nothing.

## Sections

| Section | What it shows |
|---|---|
| Hero | A large level emblem with the rank wings, total pilot XP, and the ship you fly with its role and mastery |
| Account & cloud save | Directly under the hero card. The Google Play Games / cloud state as one honest label, the account line, the last sync time, an unsynced indicator, and Sync Now / Retry / Connect. When two saves disagree it becomes the CHOOSE A SAVE screen. See [CLOUD_SAVE.md](CLOUD_SAVE.md) |
| XP progression | Level, XP into the level out of XP needed, a large bar with a percentage (it fills up when the page opens, with a soft glint), exact XP to the next level, lifetime XP, and a note that there is no level cap |
| Next level rewards | The salvage, parts and permanent bonus gains for the next level. When the next level pays gear, a gold card names the rarity and the level. If the permanent bonuses are capped, the bonus tiles say MAXED |
| Progression roadmap | The next level, the next three gear drops after it, and level 100 (the point where damage and shield bonuses stop growing). Nothing already reached is offered as upcoming, and level 100 appears once |
| Combat attributes | The current damage and shield bonuses, the cap, and progress toward level 100 |
| Career statistics | Combat record, campaign progress and collection, then achievements. Only saved figures are used |
| Current ship | The ship, its mastery with progress to the next level and the next reward, and an OPEN HANGAR button that uses the normal Hangar page |

## Where the numbers come from

Nothing is calculated twice.

- **Levels and XP:** `Pilot.level_of(Save.pilot_xp)`. The curve (`100 + 25 x level`) is untouched.
- **What a level pays:** `Pilot.reward_for(level)` returns salvage `20 + 4 x level`, parts `5 + level / 2` (whole-number division), and a guaranteed gear drop on every fifth level: Rare, or Epic on every tenth. **`Pilot.grant()` pays from this same function**, so the preview cannot drift from the payout. The gear roll itself (power, luck, minimum rarity) is as before.
- **Bonuses:** `Pilot.dmg_bonus_at(level)` and `shield_bonus_at(level)`. `Pilot.dmg_bonus()` and `shield_bonus()`, which combat applies, now call them. They give +0.3% damage and +0.5 shield per level up to `Pilot.BONUS_CAP` (100).
- **Next gain:** `Pilot.bonus_gain(level)`. It is zero and flagged `maxed` from level 101.
- **Gear milestones:** `Pilot.next_gear_level(level)`.
- **Mastery:** `Save.ship_mastery`, `Save.ship_xp` and `Ships.xp_for`.
- **Career figures:** `Meta.stat("kill")`, `"boss"` (boss fights won), `"clear"` (level victories, including replays, so the card says LEVEL CLEARS), `"best_combo"`, `"gear_found"`, `"legendary"`, plus `Save.total_stars()`, `Save.endless_best_wave`, `Save.owned_ships` and `Save.achievements`. No flight counts, playtime or win rates are shown, because they are not saved.

## Accessibility

Reduce motion switches off the XP bar fill, the orbiting emblem arcs and the card fade-ins. Reduce flashes also switches off the glints and pulses. Larger interface size is supported: nothing runs off the side.

## Tests

`_test_pilot_profile` in `tools/test_game.gd` checks the curve, `reward_for`, the bonuses before, at and after level 100, the milestone lists for many levels (no duplicates, nothing already reached), and that `grant()` pays exactly the previewed salvage, parts and gear over several levels at once. It opens the profile with a touch on the chip, returns with Back, and reads back every string the page painted to check the XP start, middle and end of a level, next-level salvage and parts, the Rare gear card at level 5, the Epic card at level 10, levels 99, 100 and 150, the career figures, and the ship. It plays a flight that gains several levels, checks the results line against the preview, and checks the profile shows the new level and next rewards afterwards, and that opening the page changes nothing. It also renders the page under Larger Interface, Reduce Motion and Reduce Flashes, scrolls it, presses OPEN HANGAR by touch, and adds the page to the touch-target audit.

Screenshots are in `screenshots/pilot-profile/` (the cloud section: `screenshots/cloud-save/`, drawn with the mock service).
