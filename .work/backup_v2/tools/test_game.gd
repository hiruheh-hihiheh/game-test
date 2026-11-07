extends SceneTree
## Automated play test. A simple bot dodges, shoots, picks cards and spends salvage.
## Run: godot --headless --path . --script tools/test_game.gd -- --test [--levels=1-60] [--tries=3]
## The --test flag makes Save use a throwaway file, so real progress is never touched.

const STEP := 1.0 / 30.0
var failures := 0
var first := 1
var last := 60
var tries := 3
var think_time := 0.1
var fumble := 0.0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--levels="):
			var parts := arg.substr(9).split("-")
			first = int(parts[0])
			last = int(parts[1])
		elif arg.begins_with("--tries="):
			tries = int(arg.substr(8))
		elif arg.begins_with("--think="):
			think_time = float(arg.substr(8))
		elif arg.begins_with("--fumble="):
			fumble = float(arg.substr(9))
	var save = root.get_node("Save")
	var audio = root.get_node("Audio")
	check(save.path == save.TEST_PATH, "tests must use the throwaway save")
	_test_content()
	await _test_menu(save, audio)
	await _test_input_regressions(save)
	await _play_campaign(save)
	await _test_endless(save)
	print("RESULT failures=", failures)
	quit(1 if failures > 0 else 0)

func _test_content() -> void:
	var levels = load("res://src/levels.gd")
	check(levels.LEVEL_COUNT == 60, "60 levels")
	for n in range(1, 61):
		var l: Dictionary = levels.build(n)
		check(not (l.waves as Array).is_empty(), "level %d has waves" % n)
		if l.boss:
			check(not (l.boss_def as Dictionary).is_empty(), "boss def %d" % n)
		var total := 0
		for w in l.waves:
			total += (w as Array).size()
		check(total > 0, "level %d has groups" % n)
	var same_a: Dictionary = levels.build(23)
	var same_b: Dictionary = levels.build(23)
	check(str(same_a.waves) == str(same_b.waves), "levels are repeatable")
	for wave in range(1, 40):
		levels.build_endless(wave)
	print("content ok")

func _test_menu(save, audio) -> void:
	var menu = load("res://title_screen.tscn").instantiate()
	root.add_child(menu)
	for screen_name in ["title", "map", "hangar", "settings", "title"]:
		menu._go(screen_name)
		for i in range(4):
			await process_frame
		check(menu.screen == screen_name, "menu shows " + screen_name)
	save.salvage = 100
	var cost: int = load("res://src/levels.gd").upgrade_cost("cannon", 0)
	check(cost == 60, "first cannon cost")
	menu._on_ui("buy_cannon")
	check(save.upgrade_level("cannon") == 1 and save.salvage == 40, "buying an upgrade")
	menu._on_ui("buy_cannon")
	check(save.upgrade_level("cannon") == 1 and save.salvage == 40, "cannot buy without salvage")
	var before: float = save.music_volume
	menu._on_ui("music_up")
	check(save.music_volume > before, "music setting changes")
	menu._on_ui("music_down")
	for sector in range(1, 7):
		save.map_sector = sector
		menu._go("map")
		await process_frame
		await process_frame
	save.map_sector = 1
	menu.queue_free()
	await process_frame
	save.upgrades = {}
	save.salvage = 0
	print("menu ok")

func _new_game(save, level: int, endless := false):
	save.play_level = level
	save.play_endless = endless
	var game = load("res://game.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	return game

func _test_input_regressions(save) -> void:
	var game = await _new_game(save, 1)
	_step(game, 2.0)
	var P = game.Phase
	check(game.phase == P.PLAYING, "intro leads into play")
	game._set_paused(true)
	check(game.phase == P.PAUSED, "pause opens")
	var frozen: Vector2 = game.player_pos
	var count: int = game.bullets.size()
	_step(game, 1.0)
	check(game.player_pos == frozen and game.bullets.size() == count, "world freezes while paused")
	game._on_ui("resume")
	check(game.phase == P.PLAYING, "resume button works")
	# Enemy shots from every source must draw without error.
	game.enemy_bullets.clear()
	game._ebullet(Vector2(360, 300), PI * 0.5, 200.0, 0)
	game._ebullet(Vector2(360, 300), PI * 0.5, 200.0, 1)
	game.drones = 2
	game.energy = 100.0
	_step(game, 0.6)
	await process_frame
	game._nova_burst()
	check(game.energy == 0.0, "nova burst spends energy")
	check(game.enemy_bullets.is_empty(), "nova burst clears shots")
	# Asteroids must hurt the ship.
	var shield_before: float = game.shield
	game.invuln = 0.0
	game.hitstop = 0.0
	game._spawn_enemy({"kind": "rock_m", "pos": game.player_pos, "move": "straight", "vel": Vector2.ZERO})
	_step(game, 0.1)
	check(game.shield < shield_before, "rocks collide with the ship")
	# Crystals must be collected.
	var salvage_before: int = game.run_salvage
	game.pickups.append({"pos": game.player_pos, "vel": Vector2.ZERO, "value": 2, "spin": 0.0, "pull": false})
	_step(game, 0.1)
	check(game.run_salvage > salvage_before and game.pickups.is_empty(), "crystals are collected")
	var off := {"pos": Vector2(50, game.H + 100.0), "vel": Vector2.ZERO, "value": 2, "spin": 0.0, "pull": false}
	game.pickups.append(off)
	game.player_alive = true
	_step(game, 0.1)
	check(game.pickups.is_empty(), "missed crystals are cleaned up")
	# Every module must apply without error.
	for card in game.CARDS:
		game.phase = P.UPGRADE
		game.phase_t = 1.0
		game.input_lock = 0.0
		game.card_options = [card]
		game.hull = 1
		game._select_card(0)
		game.input_lock = 0.0
		game.wave_index = -1
		game._install_card()
	_cleanup(game)
	await process_frame
	# The unlockable ship must load with its own stats and fly a level.
	save.ship = "interceptor"
	var alt = await _new_game(save, 3)
	check(alt.max_hull == 2, "interceptor has less hull")
	check(alt.fire_interval < 0.25, "interceptor fires faster")
	check(alt.player_sprite.texture == alt.SHIP_ART.interceptor, "interceptor uses its own art")
	_step(alt, 6.0)
	check(alt.bullets.size() > 0, "interceptor shoots")
	_cleanup(alt)
	await process_frame
	save.ship = "nova"
	print("input and regression checks done")

func _cleanup(game) -> void:
	game.queue_free()

func _step(game, seconds: float) -> void:
	var steps := int(seconds / STEP)
	for i in range(steps):
		game._process(STEP)

func _bot(game) -> void:
	var P = game.Phase
	if game.phase == P.UPGRADE:
		if game.card_picked < 0 and game.input_lock <= 0.0 and not game.card_options.is_empty():
			game._select_card(randi() % game.card_options.size())
		return
	if not game.player_alive:
		return
	if game.energy >= 100.0 and game.enemy_bullets.size() > 14:
		game._nova_burst()
	var px: Vector2 = game.player_pos
	var want: float = px.x
	var boss = game.boss
	if boss != null:
		want = float(boss.pos.x)
	else:
		var nearest := 1e9
		for e in game.enemies:
			var dy: float = px.y - float(e.pos.y)
			if dy > 0.0 and dy < nearest and float(e.pos.y) > -20.0:
				nearest = dy
				want = float(e.pos.x)
	var best: Vector2 = px
	var best_cost := 1e18
	for dx in [0.0, -70.0, 70.0, -150.0, 150.0, -240.0, 240.0]:
		for dy in [0.0, 90.0, -70.0]:
			var c := px + Vector2(dx, dy)
			c.x = clampf(c.x, 44.0, game.W - 44.0)
			c.y = clampf(c.y, game.H * 0.55, game.H - 110.0)
			var cost := absf(c.x - want) * 0.03 + absf(dx) * 0.012
			for b in game.enemy_bullets:
				for look in [0.12, 0.3, 0.5]:
					var future: Vector2 = (b.pos as Vector2) + (b.vel as Vector2) * look
					var d := future.distance_to(c)
					if d < 90.0:
						cost += (90.0 - d) * 2.0
			for e in game.enemies:
				for look in [0.15, 0.4]:
					var future: Vector2 = (e.pos as Vector2) + (e.vel as Vector2) * look
					var d := future.distance_to(c)
					var margin: float = float(e.r) + 60.0
					if d < margin:
						cost += (margin - d) * 3.0
			for l in game.lasers:
				if absf(float(l.x) - c.x) < 100.0:
					cost += 300.0
			if cost < best_cost:
				best_cost = cost
				best = c
	game.player_target = px + (best - px) * clampf(0.3 / maxf(think_time, 0.1) * 0.5, 0.0, 1.0)

func _play_level(save, level: int) -> Dictionary:
	var game = await _new_game(save, level)
	var P = game.Phase
	var elapsed := 0.0
	var think := 0.0
	var limit := 300.0
	while elapsed < limit:
		think -= STEP
		if think <= 0.0:
			think = think_time
			if randf() >= fumble:
				_bot(game)
		game._process(STEP)
		elapsed += STEP
		if game.phase == P.CLEAR or game.phase == P.DEFEAT:
			break
		if int(elapsed / STEP) % 400 == 0:
			await process_frame
	var out := {"win": game.phase == P.CLEAR, "time": elapsed, "hull_lost": game.hull_lost, "salvage": game.run_salvage, "stars": game.result_stars, "stuck": elapsed >= limit, "score": game.score, "phase": game.phase}
	await process_frame
	_cleanup(game)
	await process_frame
	return out

func _spend(save) -> void:
	# Spends like a reasonable player: cheapest useful upgrade first.
	var levels = load("res://src/levels.gd")
	var bought := true
	while bought:
		bought = false
		var cheapest := ""
		var lowest := 1 << 30
		for item in levels.HANGAR:
			if save.upgrade_level(item.id) < int(item.max):
				var cost: int = levels.upgrade_cost(item.id, save.upgrade_level(item.id))
				if cost < lowest:
					lowest = cost
					cheapest = item.id
		if not cheapest.is_empty() and save.salvage >= lowest:
			save.buy_upgrade(cheapest)
			bought = true

func _play_campaign(save) -> void:
	var levels = load("res://src/levels.gd")
	# Testing a late range on its own gives the bot the salvage it would have earned by then.
	save.salvage = int(pow(float(first - 1), 1.75) * 12.0)
	_spend(save)
	print("level  sect  try  result  time  hull_lost  salvage  stars  bank")
	var total_tries := 0
	var failed_levels := 0
	var time_by_sector := {}
	for n in range(first, last + 1):
		var won := false
		for attempt in range(1, tries + 1):
			var r: Dictionary = await _play_level(save, n)
			total_tries += 1
			check(not r.stuck, "level %d did not end (phase %d)" % [n, int(r.phase)])
			_spend(save)
			print("%5d  %4d  %3d  %6s  %4ds  %9d  %7d  %5d  %4d" % [n, levels.sector_of(n), attempt, "WIN" if r.win else "lost", int(r.time), r.hull_lost, r.salvage, r.stars, save.salvage])
			if r.win:
				won = true
				var s: int = levels.sector_of(n)
				time_by_sector[s] = float(time_by_sector.get(s, 0.0)) + float(r.time)
				break
		if not won:
			failed_levels += 1
			save.unlocked = maxi(save.unlocked, n + 1)
	print("campaign: %d levels, %d attempts, %d not beaten in %d tries" % [last - first + 1, total_tries, failed_levels, tries])
	print("seconds per sector: ", time_by_sector)
	print("upgrades: ", save.upgrades)

func _test_endless(save) -> void:
	var game = await _new_game(save, 1, true)
	var P = game.Phase
	var elapsed := 0.0
	var think := 0.0
	while elapsed < 200.0 and game.phase != P.DEFEAT:
		think -= STEP
		if think <= 0.0:
			think = 0.1
			_bot(game)
		game._process(STEP)
		elapsed += STEP
		if int(elapsed / STEP) % 400 == 0:
			await process_frame
	print("endless reached wave ", game.endless_wave, " in ", int(elapsed), "s, phase ", game.phase)
	_cleanup(game)
	await process_frame
