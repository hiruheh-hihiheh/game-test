extends "res://tools/test_game.gd"
## Saves real rendered screenshots of every screen. Needs a window, so no --headless.
## Run: godot --path . --position 40,20 --script tools/shots.gd -- --test --out=C:/some/folder
## Add --only=boss to capture just the shots with that word in their name.

var out := "user://shots"
var only := ""

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
		elif arg.begins_with("--only="):
			only = arg.substr(7)
	DirAccess.make_dir_recursive_absolute(out)
	save = root.get_node("Save")
	save.salvage = 1640
	save.unlocked = 26
	save.upgrades = {"cannon": 2, "rapid": 1, "shield": 1, "slot": 1}
	save.blueprints = ["bp_interceptor", "bp_lancer", "bp_singularity", "bp_seeker"]
	save.owned_ships = ["nova", "interceptor", "lancer"]
	save.loadout = ["spread", "pierce"]
	save.mastery = {"nova": 2600}
	save.tutorial = {"move": true, "card": true, "nova": true, "gear": true, "crystal": true}
	save.tier_unlocked = 2
	save.pilot_xp = 3400
	save.parts = 386
	save.map_tier = 2
	var gear_rng := RandomNumberGenerator.new()
	gear_rng.seed = 11
	var gdb = load("res://src/data/gear.gd")
	for i in range(13):
		var it: Dictionary = gdb.roll_item(gear_rng, 14.0 + float(i), 1.5, 0, 3)
		it.lvl = gear_rng.randi() % 3
		save.add_gear(it)
	for slot in ["weapon", "reactor", "plating"]:
		var best: Dictionary = {}
		for it in save.gear:
			if str(it.slot) == slot and (best.is_empty() or int(it.rarity) > int(best.rarity)):
				best = it
		if not best.is_empty():
			save.equip("nova", int(best.uid))
	save.gear[2]["new"] = true
	save.gear[4]["new"] = true
	save.bosses_beaten = [1, 2]
	for n in range(1, 26):
		save.star_mask[n] = 7 if n % 3 != 0 else 3
	for id in ["enemy_fighter", "enemy_rock_l", "enemy_raider", "enemy_wreck", "boss_1", "boss_2"]:
		save.codex[id] = true
	await _menus()
	for sector in range(1, 7):
		await _boss_shot(sector)
	await _gameplay()
	print("shots saved to ", out)
	quit()

func _want(shot_name: String) -> bool:
	return only.is_empty() or shot_name.contains(only)

func _menus() -> void:
	var menu = load("res://title_screen.tscn").instantiate()
	root.add_child(menu)
	await _settle(30)
	await _shot("menu_title")
	save.map_sector = 3
	menu.go("map")
	await _settle(20)
	await _shot("menu_map")
	menu.pages.map.open_level(23)
	menu.pages.map.dials = ["swift", "armor"]
	await _settle(20)
	await _shot("menu_preflight")
	menu.go("loadout")
	await _settle(20)
	await _shot("menu_loadout")
	save.map_tier = 2
	for tab in ["ships", "gear", "lab", "tech", "nova"]:
		menu.pages.hangar.tab = tab
		menu.go("hangar")
		await _settle(20)
		await _shot("menu_hangar_" + tab)
	for tab in ["today", "awards", "codex"]:
		menu.pages.ops.tab = tab
		menu.go("ops")
		await _settle(20)
		await _shot("menu_ops_" + tab)
	menu.go("expedition")
	await _settle(20)
	await _shot("menu_exp_sectors")
	load("res://src/meta/expedition.gd").start(2)
	await _settle(20)
	await _shot("menu_exp_route")
	save.expedition = {}
	menu.go("settings")
	await _settle(20)
	await _shot("menu_settings")
	menu.queue_free()
	await process_frame

func _boss_shot(sector: int) -> void:
	var name_ := "boss_%d" % sector
	if not _want(name_):
		return
	var game = await _new_game(_level(sector * 10))
	game.level.waves[0] = []
	_step(game, 2.2)
	var guard := 0
	while game.boss == null and guard < 300:
		game._process(STEP)
		guard += 1
	_step(game, 1.5)
	await _settle(2)
	await _shot(name_ + "_intro")
	for i in range(160):
		game.hull = game.max_hull
		game.invuln = 1.0
		_bot(game)
		game._process(STEP)
	game.boss.hp = game.boss.max_hp * 0.5
	game.boss._apply(0.1)
	for i in range(120):
		game.hull = game.max_hull
		game.invuln = 1.0
		_bot(game)
		game._process(STEP)
	await _settle(2)
	await _shot(name_ + "_fight")
	game.queue_free()
	await process_frame

func _gameplay() -> void:
	for pick in [[3, "nova"], [13, "lancer"], [24, "nova"], [33, "interceptor"], [43, "nova"], [52, "lancer"]]:
		save.ship = pick[1]
		var name_ := "play_%d" % int(pick[0])
		if _want(name_):
			var game = await _fly(int(pick[0]), 14.0)
			await _shot(name_)
			game.queue_free()
			await process_frame
	save.ship = "nova"
	if not _want("over"):
		return
	var game = await _fly(23, 6.0)
	game.held = {"spread": 1, "pierce": 1}
	game.phase_t = 1.0
	game._begin_upgrade()
	game.card_options = ["prism", "ricochet", "glass"]
	game.phase_t = 1.0
	await _settle(4)
	await _shot("over_cards")
	game.phase = game.Phase.PLAYING
	game.set_paused(true)
	await _settle(4)
	await _shot("over_pause")
	game.phase = game.Phase.PLAYING
	game.hull_lost = 1
	game.run_salvage = 148
	game.score = 18640
	game.level_num = 20
	game.level = Levels.build(20)
	game.rewards = []
	for i in range(8):
		game.roll_loot(1.0, 3.0)
	game._level_complete()
	game.rewards = [{"title": "BOSS BLUEPRINT", "detail": "LANCER ship"}]
	game.phase_t = 2.6
	game.stars_shown = 2
	await _settle(4)
	await _shot("over_results")
	game.queue_free()

func _fly(level_id: int, seconds: float):
	var game = await _new_game(_level(level_id))
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
	if not _want(shot_name):
		return
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(out.path_join(shot_name + ".png"))
