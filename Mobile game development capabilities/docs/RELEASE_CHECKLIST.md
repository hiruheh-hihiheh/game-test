# Android Release Checklist

Status of each step toward a Google Play launch. Items marked **you** need your accounts or your decision.

## 1. Install the build tools

- [ ] In Godot: **Editor > Manage Export Templates > Download and Install** (version 4.7.2).
- [ ] Install Android Studio or the command-line tools. This PC's SDK folders are missing build-tools and platform-tools:
  - `C:\Program Files (x86)\Android\android-sdk` only has `cmdline-tools` and `platforms`.
  - Godot currently points at `C:\Users\itssi\AppData\Local\Android\Sdk`, so check that folder exists.
- [ ] Install SDK Platform 35 or newer, Build-Tools and Platform-Tools.
- [ ] Set **Java SDK Path** in Godot's Editor Settings. It is currently blank. Android builds need JDK 17, and one is already installed.
- [ ] **Project > Install Android Build Template** (needed for the `.aab` release preset).

## 2. Signing (you)

Never commit a keystore or its passwords, and back the keystore up somewhere safe. Losing it can lock you out of updating the game.

```powershell
keytool -genkey -v -keystore starfall-release.keystore -alias starfall -keyalg RSA -keysize 2048 -validity 10000
```

Then either enter it under **Project > Export > Android Release > Keystore**, or use environment variables so it never touches the project:

```powershell
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = "C:\keys\starfall-release.keystore"
$env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = "starfall"
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = "your-password"
```

## 3. Before uploading

- [ ] Change `package/unique_name` from `com.starfall.salvage` to a domain you control. It can't be changed after launch.
- [ ] Bump `version_code` for every upload.
- [ ] Replace the placeholder details in `docs/PRIVACY_POLICY.md` and host it at a public URL.
- [ ] Run all automated tests (see `RUNNING.md`).
- [ ] Do the device checks in `docs/DEVICE_TESTING.md`.
- [ ] Listen to all audio on real speakers and headphones.

## 4. Play Console (you)

- [ ] Create the developer account and the app listing.
- [ ] Store assets: 512x512 icon, 1024x500 feature graphic, phone screenshots. `tools/shots.gd` renders real screens.
- [ ] Complete Data Safety. The game collects no data and has no internet permission as shipped.
- [ ] Complete the content rating questionnaire.
- [ ] Run Internal Testing, then Closed Testing. Play requires a closed test period for new personal developer accounts, so check the current rules.

## 5. Optional services (not built yet)

Each has a clean seam, so adding it won't touch game code.

| Service | Where it plugs in | Notes |
|---|---|---|
| Cloud save | Built: `src/meta/cloud_sync.gd`, `cloud_save.gd`, `cloud_play_games.gd` | **Not tested on a device.** Needs the Play Games plugin, a Play Console game, OAuth clients with SHA-1s for debug, release and Play App Signing, and the Game ID. Steps and the phone test plan: [CLOUD_SAVE.md](CLOUD_SAVE.md) |
| Analytics | `src/meta/telemetry.gd`: set `provider` | Must be opt-in, and needs Data Safety and privacy policy updates |
| Crash reporting | Same `provider`, plus breadcrumbs in `user://breadcrumbs.log` | A session lock already detects unclean exits |
| Leaderboards | Read `Save.best_score` and `Save.endless_best_wave` | Needs Play Games |

Adding any of these needs the internet permission, which is currently off. Cloud save through Google Play Games also needs network access: check the merged manifest of the Gradle build (`aapt dump permissions`) and add the permission if the Play Games SDK did not bring it. Update the Data Safety form at the same time.
