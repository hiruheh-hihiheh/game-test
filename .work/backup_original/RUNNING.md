# STARFALL // SALVAGE — Local Testing

## Open the project in Godot

1. Install **Godot 4.7.x Standard** for Windows. The project uses the Godot 4.7 project format and the GL Compatibility renderer.
2. Open Godot and choose **Import**.
3. Select:

   `E:\test game\Mobile game development capabilities\project.godot`

4. Open the project and wait for the asset import scan to finish.
5. Press **F6** to run the current scene or **F5** to run the configured main scene.

The configured main scene is `title_screen.tscn`. Desktop controls are **A/D** or **Left/Right Arrow**. On the title screen, press **Enter/Space** or click. During gameplay, drag in the lower half of the playfield to steer; shooting is automatic. Press **Esc** to pause.

## Android SDK setup

The attached desktop currently has an Android SDK at:

`C:\Program Files (x86)\Android\android-sdk`

In Godot, open **Editor > Editor Settings > Export > Android** and set:

- Android SDK Path: `C:\Program Files (x86)\Android\android-sdk`
- Java SDK Path: the installed JDK directory, not only the `java.exe` shim

Install or confirm these SDK components in Android Studio's SDK Manager or with `sdkmanager`:

- Android SDK Platform 36
- Android SDK Build-Tools
- Android SDK Platform-Tools
- Android SDK Command-line Tools

## Test Android touch controls

1. Enable **Developer options** and **USB debugging** on the Android phone.
2. Connect the phone by USB and accept the debugging authorization prompt.
3. In Godot, select the phone in the top-right device selector.
4. Press **Remote Run Project**.
5. Test title-screen tap, lower-half drag steering, automatic fire, pause/resume, upgrade-card taps, and restart after game over.

The project is configured for portrait orientation, a 720x1280 logical viewport, canvas-item scaling, and touch/mouse emulation for desktop testing.

## Export presets

The project includes:

- **Windows Desktop** — `outputs/StarfallSalvage-desktop.exe`
- **Android Debug** — `outputs/StarfallSalvage-debug.apk`

Use **Project > Export**, select **Android Debug**, and click **Export Project**. The debug preset uses the standard Godot debug keystore settings and supports ARM64 plus ARMv7 devices.

For command-line export after Godot is installed and on PATH:

```powershell
New-Item -ItemType Directory -Force outputs
 godot --headless --path . --export-debug "Android Debug" outputs/StarfallSalvage-debug.apk
 godot --headless --path . --export-release "Windows Desktop" outputs/StarfallSalvage-desktop.exe
```

If Godot is installed but `godot` is not on PATH, replace `godot` with the full path to `Godot.exe`.

## Current validation status

The project has been repaired to be self-contained: scene paths point to the root scripts, stale template autoloads/assets are no longer runtime dependencies, gameplay audio safely falls back to silence when optional template audio is unavailable, the supplied Starfall PNG assets remain included, and Android/desktop presets are present. A final native desktop run and APK build are still blocked on this desktop because Godot 4.7.x and its export templates are not installed or available on PATH.
