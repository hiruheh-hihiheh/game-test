extends "res://tools/test_game.gd"
## Runs only the named test sections of tools/test_game.gd, for quick work on one area.
## Run: godot --headless --path . --script tools/test_only.gd -- --test --only=_test_stars,_test_telegraphs

func _run() -> void:
	_args()
	save = root.get_node("Save")
	levels_db = load("res://src/data/levels.gd")
	gear_db = load("res://src/data/gear.gd")
	tiers_db = load("res://src/data/tiers.gd")
	pilot_db = load("res://src/data/pilot.gd")
	TgS = load("res://src/combat/telegraph.gd")
	TgPaintS = load("res://src/combat/telegraph_paint.gd")
	BfS = load("res://src/combat/bullet_field.gd")
	BossS = load("res://src/combat/boss_base.gd")
	check(save.test_mode and save.path.begins_with(save.TEST_PREFIX), "tests must use the throwaway save")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			for name_ in arg.substr(7).split(","):
				if has_method(name_):
					await call(name_)
				else:
					check(false, "no test section called " + name_)
	print("RESULT failures=", failures, " checks=", checks_run)
	quit(1 if failures > 0 else 0)
