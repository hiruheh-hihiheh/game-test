# Starfall Salvage Roadmap

## Done

- 60 hand-written levels in 6 sectors, each sector with its own mechanic, plus 6 Black Box side missions
- 6 multi-part bosses with weak points, three phases, intros and defeat sequences
- 5 ships with different weapons and traits, ship mastery and paints
- 32 module cards with rarities, synergy hints and 10 evolutions
- 4 Nova modes, loadouts, Hazard Dials, Hangar gear and tech
- Expedition (roguelite), Endless, daily contracts, Daily Anomaly, Weekly Boss
- 26 achievements, codex, records, season data structure
- Adaptive music with 6 sector themes, 44 sound effects
- Accessibility and comfort settings, safe-area layouts, interruption handling
- Save system with backups, migration from old saves and merge support
- Fast batched rendering, automated tests, balance simulation, stress test
- Release preset, checklist, privacy policy draft

## Next: needs a person or real hardware

1. **Listen to the audio.** None of it has been heard by a person yet.
2. **Install Android tools and build an APK.** See `docs/RELEASE_CHECKLIST.md`.
3. **Play on real phones.** Check touch feel and frame rate on a budget device. See `docs/DEVICE_TESTING.md`.
4. **Playtest with real people.** Difficulty is tuned from bots, and only humans can judge bosses and the first 10 minutes.

## Later

- Cloud save: implement `CloudSave.Backend` with a Play Games plugin. The merge logic is done.
- Leaderboards for Endless and the Weekly Boss.
- Opt-in crash reporting through `Telemetry.provider`.
- Season bonus rules. The season table exists, but it doesn't change gameplay yet.
- More art per enemy, and hand-drawn replacements for generated art if the budget allows.
- Localisation. All text is currently written directly in the data and menu files.
