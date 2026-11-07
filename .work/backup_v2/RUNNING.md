# STARFALL // SALVAGE — Running and Testing

## Play it on this PC

Godot 4.7.2 is at `E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe`.

1. Open Godot and import `project.godot` from this folder.
2. Press **F5** to run. The game opens on the title screen.

**PC controls:** mouse drag or WASD / arrow keys to move, Space for Nova Burst, Esc to pause, 1 / 2 / 3 to pick a module card, Enter for the next level, R to retry.

**Phone controls:** drag anywhere to move. The ship follows your thumb's movement, so your thumb never covers it. The ship fires by itself. Tap the Nova button when it is full.

## How the game works

- **60 levels** across 6 sectors. Every 5th level has an elite enemy, and every 10th is a boss.
- **Stars:** 3 for losing no hull, 2 for losing one, 1 for finishing.
- **Module cards:** pick one after each wave. They last for that level only.
- **Salvage:** collect crystals and spend them in the Hangar on permanent upgrades. You keep salvage even if you lose.
- **Nova Burst:** a charged special that clears all enemy shots and damages everything on screen.
- **Endless mode** unlocks at level 11.

## Automated tests

A bot plays the game, dodging, shooting, picking cards and buying upgrades. Tests use a throwaway save, so your real progress is safe.

```powershell
$godot = "E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
& $godot --headless --path . --script tools/test_game.gd -- --test --levels=1-60 --tries=3
```

Add `--think=0.3 --fumble=0.25` to make the bot react more like a person.

Screenshots of every screen (this opens a window):

```powershell
& $godot --path . --script tools/shots.gd -- --test --out=C:/temp/shots
```

## Regenerating the art and sound

All music, sound effects, fonts and backgrounds are made by scripts in `tools/`, so they are original and license-free. Edit a script and rerun it, then open the project in Godot to reimport.

```powershell
node tools/gen_audio.mjs
node tools/gen_font.mjs
node tools/gen_backgrounds.mjs
```

## Building for Android

Export templates are not installed yet, so no APK can be built until this is done.

1. In Godot, open **Editor > Manage Export Templates** and click **Download and Install**.
2. Open **Editor > Editor Settings > Export > Android** and set:
   - Android SDK Path: `C:\Program Files (x86)\Android\android-sdk`
   - Java SDK Path: your JDK folder (not just `java.exe`)
3. Use **Project > Export**, select **Android Debug**, and click **Export Project**. The APK goes to `outputs/`, so create that folder first.

To test straight on a phone, turn on **USB debugging**, plug it in, and press **Remote Run Project** in Godot.

The original game files from before the rebuild are in `..\.work\backup_original\`.
