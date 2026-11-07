import { dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { runGodotCheck } from './godot-check.mjs'
const root = dirname(dirname(fileURLToPath(import.meta.url)))
for (const [script, marker] of [['smoke', '[SMOKE_PASS]'], ['template_contract', '[BULLET_HELL_CONTRACT_PASS]']]) {
  runGodotCheck(process.env.GODOT_BIN || 'godot', ['--headless', '--path', root, '--script', `test/${script}.gd`], marker, root)
}
