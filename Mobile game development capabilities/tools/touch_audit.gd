extends "res://tools/test_game.gd"
## Lists the smallest controls on every screen, with their real-world size on a phone.
## Run: godot --headless --path . --script tools/touch_audit.gd -- --test
## The layout is 720 units wide on every phone, so one unit is width_dp / 720 dp.

const PROFILES := [["compact 360 dp (720 px at 320 dpi)", 360.0, 57.2], ["typical 411 dp (1080 px at 420 dpi)", 411.0, 65.3]]

func _run() -> void:
	save = root.get_node("Save")
	gear_db = load("res://src/data/gear.gd")
	var ui_layer = load("res://src/ui_layer.gd")
	var targets: Array = await _collect_targets()
	var rows: Array = []
	var seen := {}
	for t in targets:
		var r: Rect2 = t.rect
		if r.size.x < 1.0 or r.size.y < 1.0 or r.end.y < 0.0 or r.position.y > 1280.0:
			continue
		var key := "%s|%s" % [t.screen, t.id]
		if seen.has(key):
			continue
		seen[key] = true
		rows.append({"key": key, "raw": minf(r.size.x, r.size.y), "eff": minf(ui_layer.touch_rect(r).size.x, ui_layer.touch_rect(r).size.y), "size": r.size})
	rows.sort_custom(func(a, b): return a.raw < b.raw)
	print("%d controls. Minimum touch area is %.0f units." % [rows.size(), ui_layer.MIN_TOUCH])
	for p in PROFILES:
		print("  %s: %.0f units = %.0f dp = %.1f mm" % [p[0], ui_layer.MIN_TOUCH, ui_layer.MIN_TOUCH * float(p[1]) / 720.0, ui_layer.MIN_TOUCH * float(p[2]) / 720.0])
	print("Smallest drawn controls (units drawn, after slop and margin, then dp on a typical phone):")
	var shown := {}
	for row in rows:
		var kind := str(row.key).split("|")[0].split("@")[0] + "|" + str(row.key).split("|")[1].split(":")[0].rstrip("0123456789")
		if shown.has(kind):
			continue
		shown[kind] = true
		print("  %-44s %3.0f x %3.0f drawn -> %3.0f touch  (%2.0f dp drawn, %2.0f dp touch)" % [row.key, row.size.x, row.size.y, row.eff, row.raw * 411.0 / 720.0, row.eff * 411.0 / 720.0])
		if shown.size() >= 28:
			break
	var below := 0
	for row in rows:
		if row.raw < ui_layer.MIN_TOUCH:
			below += 1
	print("%d of %d controls are drawn smaller than %.0f units and rely on the touch margin." % [below, rows.size(), ui_layer.MIN_TOUCH])
	quit()
