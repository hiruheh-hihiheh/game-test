extends "res://tools/test_game.gd"
## Reports the touch size of every control on every screen, for two phone profiles, and where touch areas overlap.
## Run: godot --headless --path . --script tools/touch_audit.gd -- --test
##
## The layout is 720 units wide on every phone, so one unit is width_dp / 720 dp. A control keeps its drawn size and
## gets an invisible margin up to the minimum for the device (48 dp). These are layout calculations and simulated
## touches, not a measurement on a real phone.

const PROFILES := [["360 dp phone (720 px at 320 dpi, 57 mm wide)", 360.0, 57.2], ["411 dp phone (1080 px at 420 dpi, 65 mm wide)", 411.0, 65.3]]

func _run() -> void:
	save = root.get_node("Save")
	gear_db = load("res://src/data/gear.gd")
	var UL = load("res://src/ui_layer.gd")
	var targets: Array = await _collect_targets()
	var rows: Array = []
	var by_screen := {}
	var seen := {}
	for t in targets:
		var r: Rect2 = t.rect
		if r.size.x < 1.0 or r.size.y < 1.0 or r.end.y < 0.0 or r.position.y > 1280.0:
			continue
		var key := "%s|%s" % [t.screen, t.id]
		if seen.has(key):
			continue
		seen[key] = true
		rows.append({"key": key, "screen": str(t.screen), "id": str(t.id), "rect": r, "index": int(t.index), "covers": t.covers})
		if not by_screen.has(t.screen):
			by_screen[t.screen] = []
		by_screen[t.screen].append(rows[rows.size() - 1])
	print("%d controls on %d screens and combat states, %d touch probes, %d probe problems." % [rows.size(), by_screen.size(), touch_probes, touch_issues.size()])
	print("")
	for p in PROFILES:
		var min_units: float = UL.min_touch_for(float(p[1]), 720.0)
		var dp_unit: float = float(p[1]) / 720.0
		var mm_unit: float = float(p[2]) / 720.0
		var smallest_drawn := 999.0
		var smallest_eff := 999.0
		var relying := 0
		for row in rows:
			var r: Rect2 = row.rect
			var drawn := minf(r.size.x, r.size.y)
			var eff: Rect2 = UL.touch_rect(r, min_units)
			smallest_drawn = minf(smallest_drawn, drawn)
			smallest_eff = minf(smallest_eff, minf(eff.size.x, eff.size.y))
			if drawn < min_units:
				relying += 1
		print("%s" % p[0])
		print("  minimum touch size: %.1f units = %.0f dp = %.1f mm" % [min_units, min_units * dp_unit, min_units * mm_unit])
		print("  smallest drawn control: %.0f units = %.0f dp = %.1f mm" % [smallest_drawn, smallest_drawn * dp_unit, smallest_drawn * mm_unit])
		print("  smallest effective touch area: %.1f units = %.1f dp = %.1f mm" % [smallest_eff, smallest_eff * dp_unit, smallest_eff * mm_unit])
		print("  controls that rely on an invisible margin: %d of %d" % [relying, rows.size()])
		print("")
	# Which controls rely on margins: grouped by screen and kind of control.
	var min360: float = UL.min_touch_for(360.0, 720.0)
	var min411: float = UL.min_touch_for(411.0, 720.0)
	var groups := {}
	for row in rows:
		var r: Rect2 = row.rect
		if minf(r.size.x, r.size.y) >= min360:
			continue
		var kind := str(row.id).split(":")[0].rstrip("0123456789")
		if kind.begins_with("set_"):
			kind = "set_* (settings options)"
		elif kind.begins_with("tab_"):
			kind = "tab_* (Hangar and Ops tabs)"
		elif kind.begins_with("g_filter_"):
			kind = "g_filter_* (Gear filter chips)"
		elif kind.begins_with("g_scrap_") or kind.begins_with("g_equip_") or kind.begins_with("g_up_") or kind.begins_with("g_unequip_"):
			kind = "g_* (Gear card buttons)"
		if not groups.has(kind):
			groups[kind] = {"count": 0, "w": r.size.x, "h": r.size.y, "screens": {}}
		groups[kind].count += 1
		groups[kind].screens[str(row.screen).split("@")[0]] = true
		groups[kind].h = minf(float(groups[kind].h), r.size.y)
		groups[kind].w = minf(float(groups[kind].w), r.size.x)
	var names: Array = groups.keys()
	names.sort_custom(func(a, b): return float(groups[a].h) < float(groups[b].h))
	print("Controls drawn smaller than the 360 dp minimum (%.0f units), smallest first. Drawn size, then the touch area on each phone:" % min360)
	print("  %-34s %5s %7s  %-9s  %-18s  %-18s" % ["control", "count", "screens", "drawn", "360 dp touch", "411 dp touch"])
	for n in names:
		var g: Dictionary = groups[n]
		var r2 := Rect2(0, 0, float(g.w), float(g.h))
		var e360: Rect2 = UL.touch_rect(r2, min360)
		var e411: Rect2 = UL.touch_rect(r2, min411)
		print("  %-34s %5d %7d  %3.0fx%-3.0f   %3.0fx%-3.0f = %2.0fx%-2.0f dp   %3.0fx%-3.0f = %2.0fx%-2.0f dp" % [n, g.count, g.screens.size(), g.w, g.h, e360.size.x, e360.size.y, e360.size.x * 0.5, e360.size.y * 0.5, e411.size.x, e411.size.y, e411.size.x * 411.0 / 720.0, e411.size.y * 411.0 / 720.0])
	print("")
	# Overlapping enlarged touch areas, within one screen. The hit test settles each overlap: a touch on a
	# control's own rectangle always wins, and a touch in an overlap goes to the nearer control.
	var pairs := 0
	var intrusions := 0
	var worst: Array = []
	for screen_name in by_screen:
		var list: Array = by_screen[screen_name]
		for i in range(list.size()):
			var a: Rect2 = list[i].rect
			var ta: Rect2 = UL.touch_rect(a, min360)
			for j in range(i + 1, list.size()):
				var b: Rect2 = list[j].rect
				var tb: Rect2 = UL.touch_rect(b, min360)
				var both := ta.intersection(tb)
				if both.size.x <= 0.5 or both.size.y <= 0.5:
					continue
				# Where an opaque strip covers the earlier control (scrolled content under a header), it is not active.
				var hidden := false
				for cv in list[i].covers:
					if int(cv.below) > int(list[i].index) and (cv.rect as Rect2).has_point(both.get_center()):
						hidden = true
				if hidden:
					continue
				if a.intersects(b) and (a.encloses(b) or b.encloses(a)):
					continue  # a control sitting on a larger one is a stack, not a neighbour
				pairs += 1
				var hits_rect := ta.intersects(b) and not a.intersects(b) or tb.intersects(a) and not a.intersects(b)
				if hits_rect:
					intrusions += 1
				var small := minf(a.size.x * a.size.y, b.size.x * b.size.y)
				worst.append({"label": "%s: %s / %s" % [screen_name, list[i].id, list[j].id], "frac": both.size.x * both.size.y / small, "reaches_rect": hits_rect})
	worst.sort_custom(func(a, b): return a.frac > b.frac)
	print("Neighbouring controls whose enlarged touch areas overlap (360 dp phone, not counting content hidden under a header or bar): %d pairs, %d of them where one margin reaches the other control's own rectangle." % [pairs, intrusions])
	print("The hit test settles all of them: a touch inside a control always reaches it, and a touch only in an overlap goes to the nearer control. Largest overlaps, as a share of the smaller control:")
	for k in range(mini(12, worst.size())):
		print("  %3.0f%%  %s%s" % [float(worst[k].frac) * 100.0, worst[k].label, "  (margin reaches the other's rectangle)" if worst[k].reaches_rect else ""])
	quit()
