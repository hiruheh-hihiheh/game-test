# Cloud save and Google Play Games

Status in one paragraph: the game side is built and tested against a mock cloud service. **The Google Play Games plugin is not installed in this repository, the Android build with it has never been made, and nothing here has run against Google's servers or on a phone.** Section 9 lists exactly what is unverified. Desktop builds play as a local guest and say so.

## 1. What the player gets

- The local save file stays the source of truth. The game never waits for the cloud, never reads progress from it while playing, and every cloud failure leaves local progress exactly as it was.
- On Android with Google Play Games signed in, the whole progress save is copied to one Saved Games snapshot (`starfall_salvage_main`) after meaningful changes, and restored on a new install or a second device.
- The Pilot Profile has an **ACCOUNT & CLOUD SAVE** section with real states: LOCAL GUEST, CONNECTING, GOOGLE PLAY GAMES CONNECTED, CLOUD SYNCED, SYNC PENDING, OFFLINE, SYNC ERROR, and CHOOSE A SAVE when two saves disagree. It shows the last sync time, an unsynced indicator, and Sync Now / Retry / Connect buttons.
- Settings (volume, interface size, accessibility) are device choices and are **not** in the cloud save.

## 2. Files

| File | Job |
|---|---|
| `src/meta/cloud_save.gd` (`CloudSave`) | Pure data: the `Backend` interface, versioned encode/decode, validation, fingerprints, summaries. No network. |
| `src/meta/cloud_sync.gd` (autoload `Cloud`) | The orchestrator: decides upload, restore or ask; debounce, retry, timeouts, pause, the conflict choices. |
| `src/meta/cloud_play_games.gd` | The Google Play Games adapter for the `godot-play-game-services` plugin. Looked up by name at run time. **Never run against the plugin.** |
| `src/menus/menu_profile.gd` | The ACCOUNT & CLOUD SAVE section and the conflict screen. |
| `tools/mock_cloud.gd` | An in-memory service for tests: async, can go offline, fail, fall silent, report conflicts. |
| `src/save.gd` | `Save.restore_progress()` (validated whole-save restore) and the `saved` signal. |

## 3. What is stored

`CloudSave.encode(Save.to_dict())`: a small plain-ASCII JSON envelope `{format, game, save_version, saved_at, checksum, payload}`. The payload is the complete progress dictionary (every key of `Save.PROGRESS_KEYS`: salvage, parts, pilot XP, stars, upgrades, ships, gear and what is equipped, mastery, achievements, codex, tiers, Rift claims, Danger Contracts, and so on) in Godot's variant encoding, base64 inside the JSON, so integer keys and number types survive. The checksum is SHA-256 of the payload and only protects against damage, it is not a signature.

No tokens, account names or credentials are in the blob, in `starfall_save.cfg`, or in the sync record. A test checks that the save file contains none of `oauth`, `access_token`, `id_token`, `bearer`, `password`.

## 4. Reading a cloud save is strict

`CloudSave.decode` refuses, and the game keeps its local save, when the blob is empty, over 2.5 MB, not plain ASCII, not JSON, missing fields, from another game, a newer blob format, failing its checksum, written by a newer save version, or when `validate_progress` finds a wrong type, a value out of range, an unknown ship, a ship that is not owned, or bad gear (repeated ids, unknown slot or stat, level above the cap). Older save versions are accepted and filled in with a new player's values for any key they lack (`CloudSave.migrate` is where a step goes for the next version bump).

Restoring uses `Save.restore_progress`: reset progress, apply the validated data, write the save. **There is no merge and no "take the larger number"**, because a lower balance may be a real purchase. A test restores a cloud save with a lower balance and expects the lower balance.

## 5. When a sync happens

A small file beside the save, `starfall_save.cfg.cloud`, remembers the fingerprints (SHA-256 of the progress without its `saved_at` time) of the last state this device and the cloud agreed on, and when. On each sync:

| Situation | Result |
|---|---|
| Cloud equals this device | Nothing to do |
| New install (no local progress, never synced) and the cloud has a save | Restore it, silently |
| Cloud empty and this device has progress | Upload |
| Only this device changed since the last sync | Upload |
| Only the cloud changed (another device played) | Restore it, after keeping this device's old save in `starfall_save.cfg.before_cloud` |
| Both changed, or never synced and both have progress | Ask the player: CHOOSE A SAVE |
| This device has no progress but did before (erased) and the cloud has some | Ask. An empty save is never pushed silently, and never restored silently. |
| The cloud save is unreadable and this device has progress | Ask, offering only KEEP THIS DEVICE'S SAVE |
| The cloud save is unreadable and this device is new | Error. Nothing is restored, nothing is uploaded. |

When it runs: at launch once Google Play Games reports signed in; after the local save changes (a 6 second debounce, so several saves in a row become one upload); not during a flight (`Cloud.hold`, released when the flight scene closes); at once when the app goes to the background; when the app comes back after a minute or more; and retrying after a failure at 15 s, 30 s, 1 min, 2 min, then every 5 min. Never per frame.

Every request is asynchronous and has a 25 second timeout. A request that never answers becomes OFFLINE, the backend is told to forget it, and the next sync goes through. A late answer to an abandoned request is ignored.

## 6. Conflicts

The screen shows both saves (pilot level, salvage, stars, gear, time saved) and two buttons, each followed by what it does:

- **KEEP THIS DEVICE'S SAVE**: uploads this device's progress and replaces the cloud save. The cloud save it replaces is kept in `starfall_save.cfg.cloudconflict`.
- **RESTORE CLOUD SAVE**: replaces this device's progress with the cloud save. This device's save is kept in `starfall_save.cfg.before_cloud` and `.cloudconflict`.

Each needs a second tap on a confirmation naming the consequence. Nothing is changed until then. The kept files are not read by the game and are not deleted by it (they are for support or a manual recovery); the test runs delete their own.

If Google reports that it settled a conflict itself while saving, the game does not trust the upload: it reads the cloud again and runs the table above.

## 7. Uninstall and reinstall

Uninstalling removes the local save and the sync record. On the next install, once Google Play Games signs in, the game finds a cloud save, sees a new player with no progress and no sync record, and restores it without asking. If the player made progress on the new install before signing in, the two saves are compared and they are asked to choose.

## 8. Setting up Google Play Games (not done: needs your accounts)

Names in Play Console change; follow the current Google documentation for Play Games Services (PGS v2) alongside this list.

1. **Play Console**: create the app with package `com.starfall.salvage` (the package in `export_presets.cfg`; changing it later breaks the credentials below).
2. **Play Games Services**: in the app's PGS configuration, create the game entry. This gives a **Game ID** (a numeric app id). Enable **Saved games** for it. Add your Google accounts as **testers** until the game is published.
3. **Credentials**: add an Android OAuth client for the package, once for each signing certificate that will run the game. Each needs that certificate's **SHA-1**:
   - *Debug* builds from Godot use the debug keystore: `keytool -list -v -keystore <path>\debug.keystore -alias androiddebugkey -storepass android`.
   - *Release* builds signed with your upload key: `keytool -list -v -keystore <your release keystore> -alias <alias>`.
   - *Play App Signing*: when the app is on Play, Google re-signs it. Copy the **App signing key certificate** SHA-1 from Play Console → App integrity, and add it as well. Without this the installed-from-Play build cannot sign in even though your release build can.
4. **Plugin**: install `godot-play-game-services` (Asset Library or GitHub, version 3.4.0 was the one read for this work) into `res://addons/`, enable it in Project Settings → Plugins, install the **Android build template** (Project → Install Android Build Template), and use a **Gradle build** (`gradle_build/use_gradle_build=true`). The Release preset already has it. The Debug preset in `export_presets.cfg` does not: turn it on to test on a phone.
5. **Game ID**: set it in the export preset options (the plugin's `godot_play_game_services/game_id` option). It is not a secret and ships inside the app, but keep it out of the repository if you prefer one build config per environment.
6. **Check the merged manifest**: the preset has `permissions/internet=false` for the game's own use. The Play Games SDK needs network access and normally brings its own `INTERNET` and `ACCESS_NETWORK_STATE` through manifest merging. After the first export run `aapt dump permissions app.apk`. If `INTERNET` is missing, turn on the Internet permission in the preset. Update the Data Safety answers (see `docs/PRIVACY_POLICY.md`).
7. **Never commit** keystores, their passwords, or any service-account JSON. The debug keystore password `android` in the preset is the standard public debug value. Nothing in the game needs a server secret: sign-in and Saved Games run through the installed Play Games app and Google's SDK.

`CloudSave.make_backend()` returns the Play Games adapter only when running on Android **and** the plugin's `PlayGamesSignInClient` and `PlayGamesSnapshotsClient` nodes exist with the methods the adapter calls. Anywhere else the game plays as a local guest.

## 9. What is verified and what is not

Verified by `tools/test_game.gd` (`_test_cloud_save`, `_test_cloud_sync`, `_test_cloud_profile`, all in the quick suite) with the mock service:

- Every progress key survives encode, decode and restore; settings are untouched; gear and equipment, pilot XP, mastery and ships come back.
- Damaged, truncated, foreign, newer, checksum-broken and invalid blobs are refused (more than twenty cases); an older version is accepted and filled in.
- New-install restore, guest upload, empty-cloud no-op, fast-forward from another device, lower balances restored as they are, and that a fresh default save never overwrites a cloud save.
- Offline, failed upload, timeout and retry; several quick saves make one upload; no sync during a flight; a reported conflict triggers a re-read.
- Conflicts: both choices, the kept loser files, an erased save, an unreadable cloud save, a newer cloud save.
- The profile screen in each state, the text it shows, the two-tap confirmation, and that every new button is a full touch target (also in `tools/touch_audit.gd`).
- Desktop: the game's own `Cloud` is a local guest and claims no cloud saving.

**Not verified, and cannot be without your accounts and a phone:**

- That the plugin installs, exports and builds with Godot 4.7.2. Nothing in its documentation mentions 4.7; it has unresolved issues about snapshots and sign-in, and the maintainer has reported losing their Play developer account. If it does not build, the fallback is a minimal Kotlin Godot Android plugin around `play-services-games-v2` (`SnapshotsClient.open/commitAndClose`) exposing the same five calls the adapter uses (`is_authenticated`, `sign_in`, `load_game`, `save_game`, signals). The adapter would not change.
- Whether sign-in is automatic at launch, what `snapshot.content` is at run time (the adapter accepts bytes, an array of ints or text), that `load_game(name, true)` returns an empty snapshot for a first-time player, and that a failed load emits a null snapshot rather than nothing (silence is covered by the timeout).
- How the plugin settles a snapshot conflict. The adapter sends the write time as the snapshot's progress value so the newest write wins under the plugin's highest-progress rule, and the game re-reads afterwards, but this has not been observed.
- Signing out of Google, switching Google accounts, airplane mode, Play App Signing, a second device, and Play's own save-slot size limits. Switching accounts is a known gap: the sync record does not know which account it belongs to, so after switching, this device's progress is compared with the new account's cloud save as if it were the same player's.
- The ACCOUNT & CLOUD SAVE layout on a real phone. It was built and measured at the 720-unit layout width and checked in the touch audit, not photographed on a device.

## 10. Manual test plan for a phone

1. Fresh debug install, signed in to a tester account. Open Pilot Profile: expect CONNECTING, then CLOUD SYNCED. Play a level. Return to the profile: expect SYNC PENDING then CLOUD SYNCED.
2. Uninstall, reinstall, sign in: progress returns without a question.
3. Airplane mode, play a level: expect OFFLINE and an unsynced indicator. Turn it off and press Retry: expect CLOUD SYNCED.
4. Two devices (or one device and a reinstall): play different progress on each while offline, bring both online: expect CHOOSE A SAVE with real numbers, both choices behaving as described in section 6.
5. Sign out of Play Games: expect LOCAL GUEST and a Connect button, with progress intact.
6. Install the Play-signed build from an internal testing track and repeat step 1 (this is the Play App Signing SHA-1 check).
7. Read `adb logcat` for the plugin's errors, and confirm nothing prints a token.
