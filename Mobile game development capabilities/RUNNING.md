# STARFALL // SALVAGE — Running and Testing

## Play it on this PC

Godot 4.7.2 is at `E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe`.

1. Open Godot and import `project.godot` from this folder.
2. Press **F5** to run. The game opens on the title screen.

**PC controls:** mouse drag or WASD / arrow keys to move, Space for Nova, Esc to pause, 1 to 4 to pick a module card, Enter for the next level, R to retry.

**Phone controls:** drag anywhere to move. The ship follows your thumb's movement, so your thumb never covers it. The ship fires by itself. Tap the Nova button when it's full, or turn on double-tap in Settings.

## Documentation

| Guide | What's in it |
|---|---|
| [docs/DESIGN.md](docs/DESIGN.md) | How every system works and how to add content |
| [docs/GRIND.md](docs/GRIND.md) | Gear, tiers, the Rift and pilot level: how they work and how to tune them |
| [docs/UI_ART.md](docs/UI_ART.md) | Where the menu illustrations are used and how they animate |
| [docs/DANGER_CONTRACTS.md](docs/DANGER_CONTRACTS.md) | Optional risk contracts: rules, payouts, where they work |
| [docs/ROADMAP_NEXT.md](docs/ROADMAP_NEXT.md) | Designs for the next five features |
| [docs/SAVES.md](docs/SAVES.md) | How saves load, migrate and fall back to the backup |
| [docs/BALANCE.md](docs/BALANCE.md) | Simulation results and tuning notes |
| [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md) | Steps to publish on Google Play |
| [docs/DEVICE_TESTING.md](docs/DEVICE_TESTING.md) | What to check on real phones |
| [docs/PRIVACY_POLICY.md](docs/PRIVACY_POLICY.md) | Privacy policy draft |

## Automated tests

Always pass `-- --test`. It makes the game use a throwaway save, so your real progress is safe.

```powershell
$godot = "E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
```

Every system (content, saves, menus, ships, cards, bosses, Expedition, Endless):

```powershell
& $godot --headless --path . --script tools/test_game.gd -- --test --quick
```

Full campaign with a bot that reacts like a person. Add `--ship=lancer` to try another ship, or `--tier=3 --gear=legendary:30 --pilot=50` to play a tier with maxed gear:

```powershell
& $godot --headless --path . --script tools/test_game.gd -- --test --levels=1-60 --tries=4 --think=0.3 --fumble=0.25
```

Real clicks and drags through the game window:

```powershell
& $godot --path . --script tools/input_test.gd -- --test
```

Worst-case performance:

```powershell
& $godot --headless --path . --script tools/bench.gd -- --test
```

Screenshots of every screen (opens a window). Add `--resolution 405x900` to try a tall phone:

```powershell
& $godot --path . --script tools/shots.gd -- --test --out=C:/temp/shots
```

## Regenerating art and sound

All art for the new ships, enemies and bosses, plus all music, sound effects, fonts and backgrounds, come from scripts in `tools/`, so they are original. Edit a script, rerun it, then open the project in Godot to reimport.

```powershell
node tools/gen_art.mjs
node tools/gen_audio.mjs
node tools/gen_font.mjs
node tools/gen_backgrounds.mjs
```

## Building for Android

See [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md). The short version: export templates and SDK build-tools aren't installed on this PC yet, so no APK can be built until they are.

To test on a phone once they are, turn on **USB debugging**, plug it in, and press **Remote Run Project** in Godot.

## Backups

Earlier versions of the game are in `..\.work\backup_original\` and `..\.work\backup_v2\`.
