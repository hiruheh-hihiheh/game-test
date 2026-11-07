extends "res://tools/test_game.gd"
## Saves real rendered screenshots of every screen. Needs a window, so no --headless.
## Run: godot --path . --script tools/shots.gd -- --test --out=C:/some/folder

var out := "user://shots"

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var save = root.get_node("Save")
	save.salvage = 640
	save.unlocked = 14
	save.upgrades = {"cannon": 2, "rapid": 1, "shield": 1}
	for n in range(1, 14):
		save.stars[n] = 3 if n % 3 != 0 else 2
	var menu = load("res://title_screen.tscn").instantiate()
	root.add_child(menu)
	await _settle(30)
	await _shot("01_title")
	save.map_sector = 2
	menu._go("map")
	await _settle(30)
	await _shot("02_map")
	menu._go("hangar")
	await _settle(30)
	await _shot("03_hangar")
	menu._go("settings")
	await _settle(30)
	await _shot("04_settings")
	menu.queue_free()
	await process_frame

	var game = await _shot_game(save, 13, 9.0)
	await _shot("05_play_level13")
	var P = game.Phase
	game.phase_t = 1.0
	game._begin_upgrade()
	game.phase_t = 1.0
	await _settle(4)
	await _shot("06_cards")
	game.card_options = []
	game.phase = P.PLAYING
	game._set_paused(true)
	await _settle(4)
	await _shot("07_pause")
	game._set_paused(false)
	game.hull = 3
	game.hull_lost = 1
	game.run_salvage = 148
	game.score = 18640
	game._level_complete()
	game.phase_t = 2.2
	game.stars_shown = 2
	await _settle(4)
	await _shot("08_results")
	game.queue_free()
	await process_frame

	game = await _shot_game(save, 20, 1.0)
	game.pending.clear()
	game.group_queue.clear()
	game.level.waves[0] = []
	for e in game.enemies:
		e.dead = true
	_step(game, 0.2)
	game._begin_warning()
	game.phase_t = 0.0
	_step(game, 0.6)
	await _settle(2)
	await _shot("09_boss_warning")
	_step(game, 8.0)
	game.boss.hp = game.boss.max * 0.55
	game.boss.stage = 1
	game.hull = 2
	_step(game, 2.0)
	await _settle(2)
	await _shot("10_boss_fight")
	game.queue_free()
	await process_frame

	game = await _shot_game(save, 50, 1.0)
	game.pending.clear()
	game.group_queue.clear()
	for e in game.enemies:
		e.dead = true
	_step(game, 0.2)
	game._spawn_boss()
	_step(game, 3.0)
	game.lasers.append({"x": 200.0, "t": 0.0, "warn": 0.3, "live": 2.0, "fired": false})
	game.lasers.append({"x": 520.0, "t": 0.0, "warn": 4.0, "live": 0.5, "fired": false})
	game.boss.attack = 0.0
	_step(game, 1.4)
	await _settle(2)
	await _shot("11_boss_laser")
	game.player_alive = true
	game.hull = 0
	game._show_defeat()
	game.phase_t = 2.0
	await _settle(4)
	await _shot("12_defeat")
	game.queue_free()
	await process_frame

	game = await _shot_game(save, 34, 12.0)
	await _shot("13_play_level34")
	game.queue_free()
	print("shots saved to ", out)
	quit()

func _shot_game(save, level: int, seconds: float):
	var game = await _new_game(save, level)
	var elapsed := 0.0
	var think := 0.0
	while elapsed < seconds:
		think -= STEP
		if think <= 0.0:
			think = 0.1
			_bot(game)
		game._process(STEP)
		elapsed += STEP
	await _settle(2)
	return game

func _settle(frames: int) -> void:
	for i in range(frames):
		await process_frame

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(out.path_join(shot_name + ".png"))
