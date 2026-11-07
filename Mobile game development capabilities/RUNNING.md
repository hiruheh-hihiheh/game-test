# STARFALL // SALVAGE — Running and Testing

## Where things are

The Git repository root is `E:\test game`. The Godot project is the folder inside it, `E:\test game\Mobile game development capabilities` (it holds `project.godot`). **Run every command below from the project folder.**

| Path | What it is |
|---|---|
| `E:\test game\.gitignore` | Ignore rules for the whole repository |
| `E:\test game\Mobile game development capabilities\` | The Godot project: `game.gd`, `title_screen.gd`, `src/`, `assets/`, `tools/`, `docs/` |
| `E:\test game\starfall_salvage_transparent_assets\` | The original asset sheet and manifest the first sprites came from |
| `E:\test game\.work\` | Local backups and original high-resolution art. **Not in Git**, so keep it safe |

Not in Git, and rebuilt automatically: `.godot/` (import cache). The art packs (`*.zip`) are not in Git either; every image in them is already in `assets/` (downscaled for phones) and the full-size originals are in `.work\art_originals_1254`.

## Play it on this PC

Godot 4.7.2 is at `E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe`. It is not on `PATH`.

1. Open Godot and import `project.godot` from the project folder. The first open imports the assets, which takes a minute.
2. Press **F5** to run. The game opens on the title screen.

On a fresh clone, or after deleting `.godot/`, you can import without opening the editor:

```powershell
& "E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --import
```

**PC controls:** mouse drag or WASD / arrow keys to move, Space for Nova, Esc to pause, 1 to 4 to pick a module card, Enter for the next level, R to retry.

**Phone controls:** drag anywhere to move. The ship follows your thumb's movement, so your thumb never covers it. The ship fires by itself. Tap the Nova button when it's full, or turn on double-tap in Settings.

## Documentation

| Guide | What's in it |
|---|---|
| [docs/DESIGN.md](docs/DESIGN.md) | How every system works and how to add content |
| [docs/GRIND.md](docs/GRIND.md) | Gear, tiers, the Rift and pilot level: how they work and how to tune them |
| [docs/GLASS_UI.md](docs/GLASS_UI.md) | The glass interface: parts, rules, accessibility, cost |
| [docs/UI_ART.md](docs/UI_ART.md) | Where the menu illustrations are used and how they animate |
| [docs/DANGER_CONTRACTS.md](docs/DANGER_CONTRACTS.md) | Optional risk contracts: rules, payouts, where they work |
| [docs/ROADMAP_NEXT.md](docs/ROADMAP_NEXT.md) | Designs for the next five features |
| [docs/SAVES.md](docs/SAVES.md) | How saves load, migrate and fall back to the backup |
| [docs/BALANCE.md](docs/BALANCE.md) | Simulation results and tuning notes |
| [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md) | Steps to publish on Google Play |
| [docs/DEVICE_TESTING.md](docs/DEVICE_TESTING.md) | What to check on real phones |
| [docs/PRIVACY_POLICY.md](docs/PRIVACY_POLICY.md) | Privacy policy draft |
| [docs/legacy-manus-template/](docs/legacy-manus-template/README.md) | Old starter-template files. Reference only, none of it applies |

## Automated tests

Always pass `-- --test`. It makes the game use a throwaway save, so your real progress is safe.

```powershell
$godot = "E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
```

Every system (content, saves, menus, ships, cards, bosses, Expedition, Rift, Danger Contracts, leaks). This is the quick check to run before committing. It takes about a minute and ends with `RESULT failures=0`:

```powershell
& $godot --headless --path . --script tools/test_game.gd -- --test --quick
```

If Godot is on your `PATH` as `godot`, `npm test` runs the same command. (It is not on `PATH` on this PC, so use the line above.) The headless run ends with a warning such as `3 ObjectDB instances were leaked at exit`. These are sound streams still playing when the test quits. It is a shutdown message, not a leak while playing, which the leak test in the suite checks separately.

Full campaign with a bot that reacts like a person. Add `--ship=lancer` to try another ship, `--tier=3 --gear=legendary:30 --pilot=50` to play a tier with maxed gear, or `--danger=rush,hostiles` to play with Danger Contracts:

```powershell
& $godot --headless --path . --script tools/test_game.gd -- --test --levels=1-60 --tries=4 --think=0.3 --fumble=0.25
```

Real clicks and drags through the game window:

```powershell
& $godot --path . --script tools/input_test.gd -- --test
```

Smallest touch targets, in layout units and in dp on a real phone:

```powershell
& $godot --headless --path . --script tools/touch_audit.gd -- --test
```

Menu and combat frame cost (needs a window; see `docs/GLASS_UI.md` for how to compare two commits):

```powershell
& $godot --path . --script tools/drawcost.gd -- --test
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

All art for the new ships, enemies and bosses, plus all music, sound effects, fonts and backgrounds, come from scripts in `tools/`, so they are original. They need only Node.js. **They overwrite files in `assets/`**, so commit or back up first. Then open the project in Godot to reimport.

```powershell
node tools/gen_art.mjs
node tools/gen_audio.mjs
node tools/gen_font.mjs
node tools/gen_backgrounds.mjs
```

The same four are `npm run gen:art`, `gen:audio`, `gen:font` and `gen:backgrounds`. The menu illustrations in `assets/starfall/ui_illustrations/` are not generated by these scripts.

## Building for Android

`export_presets.cfg` has three presets. Their identifiers and signing settings are set up already and should not be edited casually.

| Preset | Output | Notes |
|---|---|---|
| Windows Desktop | `outputs/StarfallSalvage-desktop.exe` | Embedded `.pck` |
| Android Debug | `outputs/StarfallSalvage-debug.apk` | Package `com.starfall.salvage`, version 0.2.0 (code 2), arm64-v8a and armeabi-v7a, portrait, Vibrate only (no internet), signed with Godot's debug key |
| Android Release | `outputs/StarfallSalvage-release.aab` | Gradle build, needs the Android build template and your own release keystore. See [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md) |

**Status on this PC: nothing can be exported yet.** A debug export attempt stops with: a valid Java SDK path is required, and the Android SDK has no `platform-tools` or `build-tools`. Install those, plus the Godot 4.7.2 export templates (see the release checklist), then from the project folder:

```powershell
New-Item -ItemType Directory -Force outputs | Out-Null
& $godot --headless --path . --export-debug "Android Debug" outputs/StarfallSalvage-debug.apk
& $godot --headless --path . --export-release "Android Release" outputs/StarfallSalvage-release.aab
```

(`outputs/` is ignored by Git.) These export commands have not been run successfully here, because the prerequisites are missing.

To test on a phone once the SDK is installed, turn on **USB debugging**, plug it in, and press **Remote Run Project** in Godot.

## Backups

Earlier versions of the code are in `E:\test game\.work\` (`backup_original`, `backup_v2`, `backup_v3`, `backup_v4`), and the full-size originals of the menu art are in `.work\art_originals_1254`. `.work` is deliberately not in Git. Back it up yourself if you want to keep it.
