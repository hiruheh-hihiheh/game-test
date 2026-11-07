# Game preview, verification and delivery

Keep Open Source Licenses unless asked otherwise.

Godot workflow. Three.js uses the Web build/checkpoint flow and [Game sharing](game-sharing.md).
Reuse current guidance in context; otherwise read opening rules, [delivery scope](#delivery-scope-and-stopping-boundary)
and task-relevant sections, including dependencies. New games need config, commands, Preview, validation, loading,
sharing, [export constraints](#export-constraints) and version preparation; add Publishing only when requested.

Use the current Session project, GODOT_BIN, HOST and PORT. After an Addon upgrade, the latest run-start
preview commands supersede init/attach commands. For other helpers, export its current GAME_RUNTIME as
its own statement in each shell; shell variables do not carry between exec calls.

On the user's computer, mute agent-launched Godot with `--audio-driver Dummy` (already used by `--headless`).
Omit it only for SFX/music checks and restore it afterwards. Requested browser debugging launches muted
(e.g. Chromium `--mute-audio`) with the same exception. Keep muting process-scoped: never change OS volume,
in-game/saved settings or the user's Host Preview; leave user acceptance audible.

## Game publishing configuration

After init/attach, webdev.config GET config must show build.command="true" and build.outputDirectory="site".
Otherwise read [configuration](configuration.md), [deployment](deployment.md) and the
[static build](build-contracts.md#static-build) contract, then set only the build domain without reselecting architecture:
```json
{"method":"PUT","path":"config/build","body":{"build":{"command":"true","outputDirectory":"site"}}}
```
Require write success and GET config readback before release preparation; do not defer this to Publish. Preserve server/database,
backend deployment and other domains; whole-config replacements retain true/site. Online Games keep site/ plus backend.

save-release.mjs commits verified site/; true serves it without rebuilding Godot. dist/ is local export/cache only.
If publish requests dist/ despite confirmed true/site, report the SHA/error as a publish/config mismatch;
do not change the contract or copy site/ into dist/.

## Project commands

Godot Addon aliases use npm, which is part of the required Node toolchain. They dispatch Node helpers
without installing dependencies; preserve starter package-manager declarations and lockfiles.

| Command | Purpose |
| --- | --- |
| npm run check | Finite import/boot and configured gameplay checks |
| npm run check -- --pack | Check matching prepared release PCK/export; no re-export |
| npm run dev | Resident server with explicit receipt HOST/PORT |
| npm run preview:build / preview:status | Build one coherent batch / inspect current build |
| npm run doctor | Only for missing/mismatched toolchain |
| npm run build | Requested portable WASM/PCK export to dist/standalone, not a platform checkpoint |

Addon-owned aliases follow the runtime selected at run start. If the receipt cannot confirm the selection
is current (including attach before run start), selection failed, or the project has no managed aliases,
use the latest receipt's direct commands; preserve custom scripts. A missing old SHA path
requires current commands, not another attempt at that path or project reinitialization. Windows uses Node/npm, not POSIX
exports/.sh. Portable export uses present assets without
Manus credentials, uploads, commits, publication or site/ replacement; online services still need configuration.

## Godot command environment

Reuse the receipt's GODOT_BIN in each native shell. Only if it is missing or unavailable:
```sh
GODOT_BIN="$(node "$GAME_RUNTIME/doctor.mjs" --executable)" && export GODOT_BIN
```
Stop on failure; native calls use `"$GODOT_BIN" --path .` despite older READMEs. Doctor is read-only. Failed init may
retry original arguments for missing macOS dependencies; fix invalid custom paths, versions or presets without
overwriting them or changing PATH globally.

## Delivery scope and stopping boundary

Default managed delivery requires a verified saved checkpoint. "Stop editing", "no more changes" or "let me play
what is ready" means wrap up with a minimally playable checkpoint: stop new features and polish, fix only blockers
to launching and playing the implemented core interaction, verify that interaction through existing checks or
entry points, then finish [version preparation and checkpoint readback](#prepare-a-version). Do not wait to finish
the full original brief; if scope remains unfinished, label the saved version as partial and disclose those limits.

Skip saving only when the user explicitly asks not to save a version; Preview or local play alone does not imply
that choice. If playability or saving remains blocked, report the blocker, any usable Preview and the last confirmed
checkpoint separately. Do not claim the current changes are saved or playable without evidence.
Local First selects the execution environment, not the delivery scope. Checkpoint,
portable export, release-ready and live-publication requests need their matching pipeline, and publication needs
authorization. Fix failures that block the requested result; do not pursue unrequested publication or auxiliary
records as new goals. A blocked requested result remains partial, not complete. Never bypass guards, forge receipts,
patch installed helpers or turn delivery into framework, exporter or validator development. Repeat checks, builds or saves only after relevant changes, a transient failure or a new diagnostic
hypothesis, and read back uncertain operations before replaying them. Keep diagnostics and usable artifacts; without a
supported next step, report the blocker instead of inspecting tool internals. Costly recovery follows the approval rule in
the [workflow](game-workflow.md).

## Resident preview

Check the latest receipt's preview status command and reuse a healthy server. In Local First, get the verified
`git_dir`/`project_dir` and Managed base from webdev.manus_git status and [Local](../worklocally/SKILL.md). Only a new
Game with unborn Managed HEAD and no remote refs may create an empty initialization commit; never start new history
for an existing resource. The local server and prepare-release set only GIT_DIR/GIT_WORK_TREE to the returned paths,
and saves and pushes use manus_git. Never copy credential env/helpers/remotes into services or source.
Start a server only when none is running, as a resident process with the receipt numeric PORT and HOST
(127.0.0.1 Local, 0.0.0.0 Cloud; Local needs a narrow network grant): run the receipt's preview start command as
written, adding its PORT. Without one, prefix HOST/PORT to the project's `dev` script or `node <literal runtime dir>/server.mjs`.
Use this Session's declared port; never hardcode ports, kill unrelated processes, await server exit or substitute a
static server. Startup does not build. Implement the requested game before first build, then run the receipt's preview
build command in another exec per coherent batch (no args or --status only, never --project/--out). Builds may reset
play; failure keeps the last success. Init/Preview already hydrate assets; manual hydration is only for missing media.
Diagnose before rebuilding. After recovery, verify HTTP on the current registered preview and browser WASM
startup before reporting it playable; a successful build alone does not establish that an old URL works.
Identity diagnostics and port conflicts follow [runtime](game-runtime.md#preview-identity-and-recovery).

## Develop and validate

Reuse finite checks for changed gameplay/input/audio/saves/localization/tuning through existing entry points.
Boot/export/logs alone do not prove gameplay; docs-only edits need no engine boot.
Visuals: bounded real-renderer captures (`get_viewport().get_texture().get_image()` and `Image.save_png()`);
Dummy is not visual evidence. No audit reports, speculative suites, self-review phases or extra
validation/review workers. Fast: no exhaustive captures/new acceptance frameworks.
No tests if evidence suffices; otherwise only requested or minimal bounded checks for critical required behavior
that lacks evidence and cannot use existing entry points. Assert real actions, not assigned outcomes or unrelated
rejected actions. No framework building/repair for acceptance formats. Unsuitable hooks/checks limit evidence;
do not port them. Missing `game-verification.json` or zero outcomeChecks is not a task.
Pack evidence is separate: --pack runs SceneTree `kind:"script"` hooks, skips `kind:"scene"` checks
and respects release-disabled debug hooks. Reuse PCK without re-export. Inspect native output/devserver.log;
reuse .manus-logs/{browserConsole.log,networkRequests.log,sessionReplay.log}. Browser screenshots/automation/self-tests/
loading tests need explicit browser-debugging requests; otherwise report Web input/audio/layout as pending user
acceptance. Never claim unobserved passes.

## Wire the game's loading screen

Apply the shared [game-specific loading screen](game-sharing.md#game-specific-loading-screen) requirement to new
games and remixes, including Fast prototype. Inspect the active Web preset's `html/custom_html_shell` and any
`web/export.json` shell builder; edit the authored shell/style/data inputs, not generated HTML or helpers.
Put a new or rewritten shell beside the active one (Puzzle: `ui/web/`); Git-ignored paths such as Puzzle's `web/`
are not export inputs.
If no shell exists, copy runtime loading-shell.html once to web/loading.html and set
html/custom_html_shell="res://web/loading.html". Use `npm run inspect -- <shell-source>` to avoid dumping embedded fonts.
Set application boot_splash/show_image=false (or use this game's own splash) with a matching solid bg_color.
Keep shell, preset and loading data together in source. Preserve the game's customized loader on resume, not
inherited template artwork. Preserve
Engine.startGame({onProgress}), the engine placeholders and canvas, and
`<meta name="manus-game-loading-screen" content="1">`. Use lightweight localized HTML/CSS/JS with live progress,
status, Retry, reduced motion and usable desktop resizing; loading behavior details are in
[runtime](game-runtime.md#fast-recoverable-startup). Loader art must load before the PCK: embed small art or upload
it through [project storage](storage.md) and use its returned immutable /manus-storage/<key> path, never res://,
PCK-only assets, expiring URLs or uncopied siblings. This includes the minimum loader's game-specific favicon.
If using this game's own OG/title art, keep controls clear of the title and subject, and retain the solid-color fallback.

## Sharing metadata

Before metadata/artwork changes or `game/sharing` writes, follow
[Game sharing](game-sharing.md#godot-preparation) for Godot artwork, registration and preparation.

## Prepare a version

Use the [delivery scope](#delivery-scope-and-stopping-boundary). Intermediate progress saves are allowed when labeled
incomplete. For checkpoints/releases, the Host integrates canonical main per [Git/checkpoints](git-checkpoints.md)
before freezing; save never pushes, merges or chooses destinations.
Cloud terminal:
```sh
node "$GAME_RUNTIME/save-release.mjs" --message "Update"
```
Local webdev.manus_git (adapt POSIX process-scoped env to your shell):
```sh
GIT_AUTHOR_NAME=Manus GIT_AUTHOR_EMAIL=dev-agent@manus.ai GIT_COMMITTER_NAME=Manus GIT_COMMITTER_EMAIL=dev-agent@manus.ai node "$GAME_RUNTIME/save-release.mjs" --message "Update"
```
Keep Host GIT_CONFIG_* intact and never use the user's Git. Save syncs assets, prepares or reuses the snapshot and
commits the frozen candidate with normal hooks; later edits stay in the working tree. Inspect staged-index or
hook-altered-commit errors before retrying. Unchanged commits are skipped. No extra sync/standalone export or
wrapper commit, except the [assets guide's pre-save grouping sync](game-assets.md#asset-browser-groups).
Run applicable npm run check -- --pack on this candidate before pushing.
Push the receipt's exact SHA to canonical main through Cloud Git or Local manus_git, never later HEAD/extra
merge/force push. checkpoint:not_recorded means unconfirmed: verify with the readback below. Retry transport failures
with that SHA without rebuilding; a moved main requires integration and a new save even with an unchanged tree.
Registration-only failure uses reconciliation, not another save/push. A source-only push cannot replace release
preparation. Release-candidate internals and developer-UI exclusion are in [runtime](game-runtime.md#release-candidates-and-developer-ui-exclusion).

### Release candidate commands

prepare-release.mjs: no args prepares; --verify-prepared checks the frozen candidate; --verify checks current
source, site and history; --stage stages the last candidate without rebuilding or committing. Damaged candidates need
a new preparation. Never edit generated manifests, site or hashes, or commit signed URLs, dist/, .godot, dependencies
or hydrated media.

### Checkpoint readback

GET game/sharing/releases/<exact pushed sha>: 200 ok:true confirms registration, not card delivery;
404 is absent/inaccessible/unconfirmed. preparation is sharing status; publish needs gamePublishReady:true.
checking waits without rebuilding. gamePublishCheckUnavailable retries this read once, never save/push.
gamePublishBlocker: required_secret_missing or publish_contract_missing need webdev.config repair.
publish_config_invalid: repair the webdev.config field at gamePublishConfigIssue.path, then read back.
game_backend_contract_missing: [backend recovery](game-backend.md#prepare-verify-and-recover).
Other failures need diagnostics/source/config fixes before saving; report blockers.
Sharing alone proves no readiness; absent sharing does not block a basic release.

## Publishing

Publish an authorized, verified checkpoint through the Dashboard or the supported corridor under Git/checkpoints.
Verify the [Game publishing configuration](#game-publishing-configuration) before release preparation;
requested online services keep the static client plus API hybrid contract. Historical artifacts are immutable,
version Preview disables external services, and Local First rollback is unavailable. Fix stale releases with a new
prepared version, never forged hashes. Report only the actual publish result and returned project domain, not
invented titles or storage URLs. Preview, checkpoint and publication are distinct results.

## Export inputs

### Export constraints
Use discoverable literal resources, tracked import/UID sidecars and `include_filter` for runtime JSON/CSV/TXT.
Web presets keep `thread_support=false`, `export_filter="all_resources"`, engine placeholders and template export
budgets. Keep tests, captures, tooling, provenance and raw masters out of player exports. Change identity in
project.godot or the editable shell, never generated site/ or dist/. Use installed delivery commands and receipt
ports, not historical Sandbox scripts, cached PCKs or template-local servers.
