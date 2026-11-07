# Legacy template files (not used by this project)

These files came with the starter template Starfall Salvage was created from. They are kept for reference only. **Nothing here describes how this project is built, tested or released.**

| File | What it was | Why it does not apply |
|---|---|---|
| `SKILL.md`, `game-*.md`, `git-checkpoints.md` | Instructions for a hosted web-game workflow (previews, checkpoints, publishing, asset browser) | That workflow and its tools are not part of this repository |
| `check-game.mjs` | Node wrapper that ran two Godot checks | Imports `godot-check.mjs` and runs `test/smoke.gd`, neither of which exists |
| `template_contract.gd` | A check of the template's own layout (1280x720, `scripts/game.gd`, `scenes/game.tscn`, an Exo 2 font) | Starfall Salvage is 720x1280 portrait with a different file layout, so it would fail if run |

The working workflow is in `RUNNING.md` at the project root: run `tools/test_game.gd` with Godot, and use the `tools/gen_*.mjs` generators for art, audio and fonts.
