# Cloud save and Google Play Games

**Status in one paragraph.** The game side is built and tested on desktop, against a mock cloud service and against a stand-in for the Google Play Games plugin. **The real plugin is not installed in this repository. No Android build with it has ever been made. Real Google Play Games sign-in and Saved Games have never been run, on a phone or anywhere else.** Section 11 lists exactly what is and is not verified. Desktop builds play as a local guest and say so.

## 1. What the player gets

- The local save file stays the source of truth. The game never waits for the cloud, never reads progress from it while playing, and every cloud failure leaves local progress exactly as it was.
- On Android with Google Play Games signed in, the whole progress save is copied to one Saved Games snapshot (`starfall_salvage_main`) after meaningful changes, and restored on a new install or a second device.
- The Pilot Profile has an **ACCOUNT & CLOUD SAVE** section with real states: LOCAL GUEST, CONNECTING, GOOGLE PLAY GAMES CONNECTED, CLOUD SYNCED, SYNC PENDING, OFFLINE, SYNC ERROR, CHOOSE A SAVE (two saves disagree) and ACCOUNT CHANGED / SYNC PAUSED (a different Google account is signed in). It shows the last sync time, an unsynced indicator, and Sync Now / Retry / Connect buttons.
- Settings (volume, interface size, accessibility) are device choices and are **not** in the cloud save.

## 2. Files

| File | Job |
|---|---|
| `src/meta/cloud_save.gd` (`CloudSave`) | Pure data: the `Backend` interface, versioned encode/decode, validation, `has_progress`, fingerprints, summaries, the account hash. No network. |
| `src/meta/cloud_sync.gd` (autoload `Cloud`) | The orchestrator: decides upload, restore or ask; account binding and account-change choices; debounce, retry, timeouts, session cleanup. |
| `src/meta/cloud_play_games.gd` | The adapter for the `godot-play-game-services` plugin: lifecycle, sign-in, player identity, snapshots, conflicts. |
| `src/menus/menu_profile.gd` | The ACCOUNT & CLOUD SAVE section, the conflict screen and the account-change screen. |
| `tools/mock_cloud.gd` | An in-memory service for tests: async, several accounts, offline, failures, silence, conflicts, held and late answers. |
| `tools/fake_pgs/` | A stand-in for the plugin (autoload, native object, three client Nodes) that copies the v3.4.0 wrapper behaviour. Tests only. |
| `src/save.gd` | `Save.restore_progress()` (validated whole-save restore) and the `saved` signal. |

## 3. What is stored

`CloudSave.encode(Save.to_dict())`: a small plain-ASCII JSON envelope `{format, game, save_version, saved_at, checksum, payload}`. The payload is the complete progress dictionary (every key of `Save.PROGRESS_KEYS`) in Godot's variant encoding, base64 inside the JSON, so integer keys and number types survive. The checksum is SHA-256 of the payload. It guards against damage and is not a signature.

No tokens, account names or credentials are in the blob or in `starfall_save.cfg`. The sync record (`starfall_save.cfg.cloud`) holds four things: two fingerprints, a time, and **a one-way SHA-256 hash of the Google Play Games player id** (never the id). A test checks the id does not appear in it and that the save file contains none of `oauth`, `access_token`, `id_token`, `bearer`, `password`.

## 4. Reading a cloud save is strict

`CloudSave.decode` refuses, and the game keeps its local save, when the blob is empty, over 2.5 MB, not plain ASCII, not JSON, missing fields, from another game, a newer blob format, failing its checksum, written by a newer save version, or when `validate_progress` finds a wrong type, a value out of range, an unknown ship, a ship that is not owned, or bad gear. Older save versions are accepted and missing keys take a new player's values (`CloudSave.migrate` is where a step goes for the next version bump). The payload is only decoded after its checksum matches.

Restoring uses `Save.restore_progress`: reset progress, apply the validated data, write. **There is no merge and no "take the larger number"**, because a lower balance may be a real purchase.

## 5. What counts as progress (`CloudSave.has_progress`)

A save is "a fresh install" only if `has_progress` is false. That decides whether a cloud save may be restored silently, and whether an empty save may ever be uploaded. It checks every field of `Save.PROGRESS_KEYS`:

| Counts as progress | Fields |
|---|---|
| Any value above a new player's | `salvage`, `parts`, `pilot_xp`, `best_score`, `endless_best_wave`, `expedition_wins`, `tier_unlocked`, `reroll_tokens`, `unlocked`, `ship` (not nova), `nova_mode` (not pulse) |
| Anything in it | `star_mask`, `level_best`, `upgrades`, `mastery`, `paints`, `tutorial`, `achievements`, `codex`, `expedition`, `weekly_best`, `daily_best`, `equipped`, `tier_data`, `gear`, `blueprints`, `loadout`, `side_cleared`, `bosses_beaten`, `seen_unlocks`, `rift_claimed`, and `owned_ships` with more than one ship |
| Only once the player has touched it | `contracts` (today's three contracts are generated at every launch: they count once one has progress, is done or is claimed), `stats` (the title screen mirrors `ships_owned`, `best_mastery`, `pilot_level`, `stars`, `side` and `tier_unlocked` into stats at every launch, so those keys never count; any other stat above zero does), `danger` (a completed contract or a remembered pick) |
| Never | `gear_uid` (a counter that follows the gear list) |

Generated or temporary data must not make a new install look played, or a second device would be asked a question instead of restoring. A test per field proves each meaningful one alone stops a save being taken for fresh, a test proves a new install with generated contracts and derived stats is still fresh, and **a test fails if a new key is added to `Save.PROGRESS_KEYS` without being classified here** (`CloudSave.GENERATED_KEYS` or `has_progress`).

## 6. When a sync happens

The sync record remembers the fingerprints of the last state this device and the cloud agreed on. On each sync:

| Situation | Result |
|---|---|
| Cloud equals this device | Nothing to do |
| New install (no local progress, never synced) and the cloud has a save | Restore it, silently |
| Cloud empty and this device has progress | Upload |
| Only this device changed since the last sync | Upload |
| Only the cloud changed (another device played) | Restore it, after keeping this device's old save in `starfall_save.cfg.before_cloud` |
| Both changed, or never synced and both have progress | Ask the player: CHOOSE A SAVE |
| This device has no progress but did before (erased) and the cloud has some | Ask. An empty save is never pushed silently, never restored silently. |
| The cloud save is unreadable and this device has progress | Ask, offering only KEEP THIS DEVICE'S SAVE |
| The cloud save is unreadable and this device is new | Error. Nothing is restored, nothing is uploaded. |
| Google reports two versions of the cloud save | Error. See section 9. |
| A different account is signed in, or the account cannot be confirmed | See section 8 |

When it runs: at launch once Google Play Games reports signed in; after the local save changes (6 second debounce, so several saves become one upload); not during a flight (`Cloud.hold`); at once when the app goes to the background; when the app returns after a minute or more; and retrying after a failure at 15 s, 30 s, 1 min, 2 min, then every 5 min. Never per frame. A conflict is not retried on a timer: only the player's Sync Now tries it again.

Every request is asynchronous with a 25 second timeout. Silence becomes OFFLINE, the backend is told to drop the request, and the next sync goes through. A late answer is ignored twice over: by an operation token in `Cloud` and by the adapter dropping its callbacks.

## 7. The player decides a disagreement

CHOOSE A SAVE shows both saves (pilot level, salvage, stars, gear, time saved) and two buttons, each with what it does and a second tap to confirm:

- **KEEP THIS DEVICE'S SAVE** uploads this device's progress over the cloud save. The cloud save it replaces is kept in `starfall_save.cfg.cloudconflict`.
- **RESTORE CLOUD SAVE** replaces this device's progress with the cloud save. This device's save is kept in `starfall_save.cfg.before_cloud` and `.cloudconflict`.

The kept files are never read by the game and never deleted by it (they are for support or a manual recovery).

### Nothing is replaced until its copy is safe

Every action that replaces data first writes the copy that makes it recoverable, **reads that file back and compares it byte for byte**, and only then proceeds. If a copy cannot be written (the file cannot be opened, the write fails, a write stops short, a copy of the save file fails), nothing is replaced, nothing is bound or recorded, the decision stays open, and the profile shows in red "Could not keep a copy of ... Your saves are unchanged. Free some storage space and try again."

| Action | Copy made first |
|---|---|
| KEEP THIS DEVICE'S SAVE (replaces the cloud snapshot) | The cloud save **exactly as the cloud sent it** (`.cloudconflict`), whether readable, damaged or written by a newer game. It is never re-encoded. |
| RESTORE CLOUD SAVE, and the silent restores on a new install or after another device played | This device's save file (`.before_cloud`) and its progress in the cloud format (`.cloudconflict`). A silent restore that cannot make them does not happen: SYNC ERROR, retried later. |
| Account change: USE THIS DEVICE'S SAVE | The new account's cloud save exactly as sent (`.cloudconflict`), readable or not. The account is bound only after it is written. |
| Account change: LOAD THIS ACCOUNT'S CLOUD SAVE | This device's save, as for RESTORE. The account is bound only after it is written. |
| Google reports two versions | Each version exactly (`.cloudconflict.1`, `.2`). Old files from an earlier conflict are removed first, and the message states how many were really written: it says "both versions were kept" only if both were. |

A Google conflict reported while looking at a new account (the probe) is kept the same way and shown on the account screen as CONFLICT. While Google holds two versions for that account, neither USE THIS DEVICE'S SAVE nor LOAD THIS ACCOUNT'S CLOUD SAVE is possible, only PAUSE CLOUD SYNC.

## 8. Which Google account (data safety)

A cloud save belongs to one Google Play Games player. Without knowing which, switching accounts on a phone could upload one person's progress into another's cloud save, or replace it.

- **Identity.** Before every sync the backend confirms who is signed in. The adapter asks the plugin's `PlayGamesPlayersClient.load_current_player(true)` (a forced reload, so a cached previous player is never used) and reads `player_id`. The sync record stores only `SHA-256("starfall_salvage_pgs_account_v1:" + id)`. Google's `Player.getPlayerId()` is scoped to this game and is stable for the player; the game never receives a name, email or token.
- **Uncertain identity means no sync.** If the player id is empty, missing or the check fails, nothing is read or written: the status is SYNC ERROR with "Could not confirm which Google Play Games account is signed in", and it retries on the normal schedule.
- **First sync with an account** binds this device's record to it. An older record with no account (from before accounts were recorded) is not trusted: its fingerprints are dropped, so two saves with progress produce a question, never a silent upload or restore.
- **A different account** than the bound one: nothing is uploaded, restored or written. `Cloud` reads the new account's cloud save (read-only apart from creating an empty snapshot, see section 11) and the profile shows ACCOUNT CHANGED with this device's save beside the new account's cloud save and three choices, each confirmed with a second tap where it changes something:
  - **USE THIS DEVICE'S SAVE** carries this device's save to the new account, replacing whatever it had in the cloud (kept in `.cloudconflict`). Disabled when this device has no progress.
  - **LOAD THIS ACCOUNT'S CLOUD SAVE** replaces this device's progress with the new account's (this device's save is kept in `.before_cloud` and `.cloudconflict`). Disabled when the account has none or it is unreadable.
  - **PAUSE CLOUD SYNC** changes nothing and syncs nothing (SYNC PAUSED, with a button to choose again).
  Until the player chooses, neither the local save nor the new account's cloud save is changed, and scheduled syncs, the flight-end sync and the app-resume sync do nothing.
- **Switching back** to the bound account resumes normal syncing without a question. Signing out and signing in as the same account needs no decision.
- **Any change of sign-in state** ends the session: the running request is abandoned, the backend drops its callbacks, scheduled work is cancelled, and pending decisions are forgotten. Late answers cannot change the new session, and signing in again starts a fresh operation.

## 9. Conflicts reported by Google: what the plugin really does

Read from `SnapshotsProxy.kt` in v3.4.0:

- `saveGame` opens the snapshot with `RESOLUTION_POLICY_HIGHEST_PROGRESS` and `loadGame` with `RESOLUTION_POLICY_MOST_RECENTLY_MODIFIED`. Google's documentation says a non-manual policy resolves conflicts itself, so the plugin's conflict branch should be rare. **That is unverified here.** The plugin's source does not rely on it: if `isConflict` is true it only emits `conflict_emitted` (with `origin` "SAVE" or "LOAD", `conflicting_snapshot` and `server_snapshot`) and **returns**. `game_saved` or `game_loaded` never follow.
- The plugin has **no method to resolve a conflict**. Google's native `resolveConflict` is not exposed, and an unresolved conflict is not closed by the plugin.
- Other gaps in the same file: `saveGame` emits `game_saved(true)` right after calling `commitAndClose`, without waiting for it to finish, and a failed `open` emits nothing at all (so a failed save is silence). A failed load emits nothing either, except a not-found status (which gives a null snapshot).

What this game does about it, in `cloud_play_games.gd`:

- A conflict from a save **or** a load completes the pending request immediately, exactly once, as a failure of kind `conflict` that carries both snapshots' bytes. `Cloud` writes them to `starfall_save.cfg.cloudconflict.1` and `.2`, leaves the local save and the cloud untouched, and shows SYNC ERROR: "Google Play Games reported two different cloud versions of your save... This build cannot settle that." No timeout wait, no retry timer; Sync Now tries again.
- A save is only reported as done after the snapshot has been read back and matches what was written. A mismatch is an error ("unverified"). Silence is covered by `Cloud`'s timeout.
- Callbacks complete exactly once; `abort()` drops them; late answers after a conflict, a timeout or a sign-out are ignored. All of this is tested against the stand-in plugin.

**The limitation, stated plainly:** this plugin cannot resolve a conflict Google reports, so a conflict that does occur stays unresolved on Google's side, and the game can only preserve both versions and stop. If that proves common on a phone, the right fix is not to work around the plugin but to use a different backend:

> Write a small Godot Android plugin in Kotlin around `play-services-games-v2` that opens the snapshot with `RESOLUTION_POLICY_MANUAL`, resolves conflicts with `SnapshotsClient.resolveConflict` once the player (or `Cloud`) has chosen a version, only emits "saved" from the `commitAndClose` completion listener, emits failures instead of staying silent, and returns the current player id. `CloudSave.Backend` is the seam: a new adapter implementing `check_account`, `load_snapshot` and `save_snapshot` replaces `cloud_play_games.gd` without touching `Cloud` or the screens. This has **not** been written here: it cannot be built or tested without an Android SDK, and untested native save code is worse than none.

Alternatively, keep the stock plugin and accept the limitation. Google also offers a snapshot selection UI (`show_saved_games`), which this game does not use.

## 10. Installing and setting up (needs your accounts and an Android toolchain)

Names in Play Console change; follow Google's current Play Games Services (PGS v2) documentation alongside this.

1. **Play Console**: create the app with package `com.starfall.salvage` (the package in `export_presets.cfg`; changing it later breaks the credentials below). In its Play Games Services configuration create the game entry: this gives the **Game ID** (a numeric app id). Enable **Saved games**. Add your Google accounts as **testers** until the game is published.
2. **Install the plugin** (v3.4.0 was read for this work). The tag ships only a debug build, `addons/GodotPlayGameServices/bin/debug/GodotPlayGameServices-debug.aar`; there is no release AAR in the repository, so for a release build either use a release from the plugin's GitHub releases or build it (`./gradlew assemble` in the plugin repository, which needs the Android SDK). The Kotlin source builds against the Godot library **4.5.1**, not 4.7.x: whether that AAR works with a 4.7.2 export template is **untested**. Copy the folder to `res://addons/GodotPlayGameServices/` and enable **GodotPlayGameServices** in Project Settings > Plugins.
3. **Check what enabling it added.** The plugin's editor script registers one autoload, `GodotPlayGameServices="*res://addons/GodotPlayGameServices/scripts/autoloads/godot_play_game_services.gd"`, in `project.godot`, and an export plugin that adds `play-services-games-v2:21.0.0` and gson, the `com.google.android.gms.games.APP_ID` manifest entry, and the export option below. This repository does not add that autoload itself, because it does not exist until the plugin is installed. **Do not call `GodotPlayGameServices.initialize()` anywhere else:** `cloud_play_games.gd` does it (see below), and a second call returns an error.
4. **Android build template and Gradle**: Project > Install Android Build Template, and use a Gradle build. The Release preset already has `gradle_build/use_gradle_build=true`; the Debug preset does not, so turn it on to test on a phone.
5. **Game ID**: in the Android export preset set `godot_play_game_services/game_id` (the plugin writes it to `android/build/res/values/strings.xml`). It is not secret and ships inside the app. An empty value is printed as an error at export and then breaks sign-in.
6. **Credentials** (Google Cloud / Play Games Services > Credentials): add an Android OAuth client for the package, once for each signing certificate that will run the game, each with that certificate's **SHA-1**:
   - *Debug* builds use Godot's debug keystore (`%APPDATA%\Godot\keystores\debug.keystore`, alias `androiddebugkey`, password `android`): `keytool -list -v -keystore <path> -alias androiddebugkey -storepass android`.
   - *Release* builds use your upload key: `keytool -list -v -keystore <release keystore> -alias <alias>`.
   - *Play App Signing*: once on Play, Google re-signs the app. Add the **App signing key certificate** SHA-1 from Play Console > App integrity as well, or the Play-installed build cannot sign in even though your release build can.
   Also configure the OAuth consent screen if Google asks for it.
7. **Permissions**: the preset has `permissions/internet=false`. The Play Games SDK needs network access and normally brings `INTERNET` and `ACCESS_NETWORK_STATE` through manifest merging. After the first Gradle export run `aapt dump permissions app.apk` and, if `INTERNET` is missing, turn on the Internet permission in the preset. Update Data Safety (see `docs/PRIVACY_POLICY.md`).
8. **Never commit** keystores, their passwords, or any service-account JSON. Nothing in the game needs a server secret.

### How the game starts the plugin (`cloud_play_games.gd`)

The v3 plugin has **one autoload** (`GodotPlayGameServices`). Its clients are not autoloads: `PlayGamesSignInClient`, `PlayGamesSnapshotsClient` and `PlayGamesPlayersClient` are plain Nodes, and each connects to the native plugin inside its own `_ready()`, **only if `android_plugin` already exists**. The autoload creates `android_plugin` only when `initialize()` is called, and calling it a second time returns `PLUGIN_NOT_FOUND`. So:

1. `CloudSave.make_backend()` returns the adapter only when `available()`: running on Android, the `GodotPlayGameServices` autoload exists, the three client scripts exist, and the native `GodotPlayGameServices` singleton is registered (`Engine.has_singleton`). Otherwise the game plays as a local guest.
2. `start()` calls `initialize()` (only while `android_plugin` is empty) and treats any result but OK as unavailable, again LOCAL GUEST.
3. Only then it creates the three client Nodes and adds them under the `Cloud` autoload, where they live for the whole session. It checks they have the expected signals and methods (an incompatible plugin version means LOCAL GUEST, not a crash) and connects to them.
4. The plugin makes no automatic sign-in check (the v3 README says so), so `is_authenticated()` is called explicitly. If nothing answers within 20 seconds the state becomes SYNC ERROR.

This order is covered by the stand-in plugin in `tools/fake_pgs`, whose client Nodes wire themselves only if the native object already exists, as the real ones do.

## 11. What is verified and what is not

Executed (quick suite, `-- --test --quick`): **5625 checks, 0 failures** (the count varies by a few between runs, because some tests loop until a state is reached), including every cloud test below, run on Windows with Godot 4.7.2 headless.

- Data: every progress key survives encode, decode and restore; settings are untouched; more than twenty kinds of damaged, foreign, newer or invalid blob are refused; older versions are accepted.
- `has_progress`: each meaningful field alone, the generated data that must not count, and that every `PROGRESS_KEYS` entry is classified.
- Sync (mock service): new-install restore, guest upload, fast-forward, lower balances restored as they are, erased saves, offline, failed uploads, timeouts, debounce, flight hold, both conflict choices and their kept files, an unreadable or newer cloud save, Google-reported conflicts from a save and from a load (both versions kept, no timeout wait, no overwrite, no timer retry).
- Data preservation (mock service, and `tools/faulty_cloud_sync.gd`, which makes file operations fail): unreadable (corrupted) and newer-version cloud data followed by KEEP THIS DEVICE'S SAVE keep the exact original bytes; the same during an account switch; a Google conflict while looking at a new account keeps both versions and blocks replacing; stale conflict files are replaced or removed; a backup that cannot be opened (a directory in its place), a write that fails, and a write that stops short each leave the cloud save and local progress untouched and the decision open; restoring when this device's save cannot be backed up (copy failure, open failure, write failure, short write) does nothing, for the conflict choice, the silent new-install restore and the account choice; the message never claims both Google versions were kept when a write failed. Five deliberate breakages of this code each made the suite fail (done by hand, not part of the suite).
- Accounts (mock service): A to B with and without a cloud save, each choice and its kept files, pausing, switching back to A, signing out and in as the same account, a switch while a request is pending (late answer ignored), a switch nobody announced, an unknown identity (no sync, nothing recorded), an older sync record without an account.
- Session cleanup: sign out while a load is pending and while a save is pending, then sign in again; a scheduled retry cancelled by sign-out; a sign-in check that never answers.
- Plugin adapter (stand-in plugin): availability in six situations, initialize once, clients created after initialization and persistent, sign-in, forced player reload, the snapshot open/save/read-back sequence, a read-back mismatch, conflicts from SAVE and LOAD, exactly-once completion, silence and timeout, late answers, sign-out with a request pending, an empty player id.
- The profile screen in every state, including ACCOUNT CHANGED, its three choices, the two-tap confirmation and full-size touch targets (also in `tools/touch_audit.gd`).
- A mutation check, done once by hand and not part of the suite: disabling the account comparison and the conflict handler made the suite fail.

**Not executed, and not verified:**

- **Real Google Play Games sign-in and Saved Games have never been run.** Not on a phone, not in an emulator, not once.
- **No Android build exists.** An Android debug export was attempted and failed immediately: there are no Android export templates for 4.7.2, no Android SDK (`platform-tools`, `build-tools`) or Java SDK path in Editor Settings, no Android build template in the project, and the plugin is not installed.
- The stand-in plugin copies what the v3.4.0 wrappers do, but it is a copy, not the plugin. If the real wrappers differ from the source as read (for example how a `PackedByteArray` is assigned from the JSON content array, which the stand-in copies verbatim and which works in Godot 4.7.2 desktop), the adapter could differ.
- That the 4.5.1-built plugin runs under a 4.7.x export template.
- Whether Google ever actually reports a snapshot conflict under these policies, and what an unresolved one does to later opens of that snapshot.
- That the read-back after a save sees the committed data: `commitAndClose` is not awaited by the plugin, so the adapter waits 0.8 s then reads the snapshot back. A mismatch is reported as an error and retried later, so the failure mode is a retry, not a false success. The delay is a guess.
- `load_game(name, true)` creates an empty snapshot in an account that has none. The account-change screen reads the new account's cloud save this way, so merely signing in with a new account can create an empty `starfall_salvage_main` snapshot there. It contains nothing.
- Whether `Player.getPlayerId()` is stable across reinstalls and devices for one player in this game (Google documents it so; it was not observed).
- Play App Signing, a second device, airplane mode, and the layout on a real phone (the section was built at the 720-unit layout width and checked by the touch audit and screenshots in `screenshots/cloud-save/`).

## 12. Manual test plan for a phone (once the plugin builds)

1. Fresh debug install, signed in to a tester account. Open Pilot Profile: expect CONNECTING, then CLOUD SYNCED. Play a level: SYNC PENDING then CLOUD SYNCED.
2. Uninstall, reinstall, sign in: progress returns without a question.
3. Airplane mode, play a level: OFFLINE and an unsynced indicator. Turn it off and press Retry: CLOUD SYNCED.
4. Two devices, different progress on each while offline, both online: CHOOSE A SAVE with real numbers.
5. Switch the phone to a second Google account in the Play Games app: ACCOUNT CHANGED, nothing changed on either side. Try each choice, then switch back to the first account.
6. Sign out of Play Games: LOCAL GUEST and a Connect button, progress intact.
7. Install the Play-signed build from an internal test track and repeat step 1 (the Play App Signing SHA-1 check).
8. In `adb logcat`, watch for `SnapshotsProxy` "Conflict with id" lines, and confirm nothing prints a token or a player id.
