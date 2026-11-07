extends "res://tools/shots.gd"
## Frame time and draw calls on the busiest menu screens. Needs a window, and runs with vsync off.
## Run: godot --path . --script tools/drawcost.gd -- --test [--mode=both|plain]
##   both  (default) measures UI.classic = true (flat panels) and then false (glass) in this checkout.
##   plain measures the checkout as it is, with no switch. Use it to compare two commits: run it in a copy
##         of the old commit and in this one, on the same PC. That is the only true before/after, because
##         UI.classic cannot undo layout changes such as the title pad.

func _measure(frames: int, game = null) -> Array:
	var total := 0.0
	var calls := 0
	var prims := 0
	var last := Time.get_ticks_usec()
	for i in range(frames):
		if game != null:
			game.hull = game.max_hull
			game.invuln = 1.0
		await process_frame
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		total += float(now - last) / 1000.0
		last = now
		calls = maxi(calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		prims = maxi(prims, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	return [total / float(frames), calls, prims]

func _run() -> void:
	var mode := "both"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			mode = arg.substr(7)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	save = root.get_node("Save")
	save.unlocked = 26
	save.salvage = 1640
	save.owned_ships = ["nova", "interceptor", "lancer"]
	save.tutorial = {"move": true, "card": true, "nova": true, "gear": true, "crystal": true}
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var gdb = load("res://src/data/gear.gd")
	for i in range(30):
		var it: Dictionary = gdb.roll_item(rng, 14.0 + float(i), 1.5, 0, 3)
		it["new"] = false
		save.add_gear(it)
	var menu = load("res://title_screen.tscn").instantiate()
	root.add_child(menu)
	await _settle(30)
	var screens := [["title", ""], ["hangar", "ships"], ["hangar", "gear"], ["hangar", "tech"], ["ops", "today"], ["settings", ""], ["map", ""]]
	var ui_script = load("res://src/ui.gd")
	for pass_name in (["classic", "glass"] if mode == "both" else ["plain"]):
		if mode == "both":
			ui_script.classic = pass_name == "classic"
		for sc in screens:
			if sc[1] != "":
				if sc[0] == "hangar":
					menu.pages.hangar.tab = sc[1]
				else:
					menu.pages.ops.tab = sc[1]
			menu.go(sc[0])
			await _settle(40)
			var r: Array = await _measure(120)
			print("DRAWCOST %-8s %-9s %-6s avg %.2f ms  draw calls %d  primitives %d" % [pass_name, sc[0], sc[1], r[0], r[1], r[2]])
	menu.queue_free()
	await process_frame
	# Combat: a busy level and a boss fight, with the simulation running and the ship kept alive.
	for scene in [["combat", 33], ["boss", 10]]:
		var game = await _new_game(_level(int(scene[1])))
		game.set_process(true)
		if scene[0] == "boss":
			game.level.waves[0] = []
			var guard := 0
			while game.boss == null and guard < 900:
				game.hull = game.max_hull
				await process_frame
				guard += 1
			for i in range(120):
				game.hull = game.max_hull
				game.invuln = 1.0
				await process_frame
		else:
			for i in range(240):
				game.hull = game.max_hull
				game.invuln = 1.0
				await process_frame
		var r2: Array = await _measure(180, game)
		print("DRAWCOST %-8s %-9s %-6s avg %.2f ms  draw calls %d  primitives %d" % [mode if mode == "plain" else "both", scene[0], "", r2[0], r2[1], r2[2]])
		game.queue_free()
		await process_frame
	print("drawcost done")
	quit()
