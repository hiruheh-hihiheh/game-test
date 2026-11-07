extends SceneTree
## Automated play test. A bot dodges, shoots, picks cards and spends salvage.
## Run: godot --headless --path . --script tools/test_game.gd -- --test [options]
##   --levels=1-60   range to play        --tries=3      attempts per level
##   --think=0.3     seconds between bot decisions (higher plays more like a person)
##   --fumble=0.25   chance the bot misses a decision
##   --ship=lancer   ship to fly          --quick        checks only, no campaign
## The --test flag makes Save use a throwaway file, so real progress is never touched.

const STEP := 1.0 / 30.0
var failures := 0
var first := 1
var last := 60
var tries := 3
var think_time := 0.1
var fumble := 0.0
var ship_id := "nova"
var quick := false
var save
var levels_db

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)

func _args() -> void:
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
		elif arg.begins_with("--ship="):
			ship_id = arg.substr(7)
		elif arg == "--quick":
			quick = true

func _run() -> void:
	_args()
	save = root.get_node("Save")
	levels_db = load("res://src/data/levels.gd")
	check(save.path == save.TEST_PATH, "tests must use the throwaway save")
	_test_content()
	_test_save_roundtrip()
	await _test_menus()
	await _test_regressions()
	await _test_all_ships()
	await _test_all_cards()
	await _test_all_bosses()
	await _test_side_missions()
	await _test_challenges()
	await _test_expedition()
	await _test_endless()
	_reset_progress()
	if not quick:
		await _play_campaign()
	print("RESULT failures=", failures)
	quit(1 if failures > 0 else 0)

func _reset_progress() -> void:
	save.upgrades = {}
	save.salvage = 0
	save.unlocked = 1
	save.star_mask = {}
	save.ship = ship_id
	if not ship_id in save.owned_ships:
		save.owned_ships.append(ship_id)
	save.blueprints = []
	save.loadout = []
	save.mastery = {}

func _test_content() -> void:
	var Enemies_ = load("res://src/data/enemies.gd")
	var Cards_ = load("res://src/data/cards.gd")
	var events := ["storm", "flare", "row", "ember", "frost", "well", "spokes", "treasure", "escort", "ambush"]
	var ids: Array = range(1, 61) + [101, 102, 103, 104, 105, 106]
	for n in ids:
		var l: Dictionary = levels_db.build(n)
		check(not (l.waves as Array).is_empty(), "level %d has waves" % n)
		check(str(levels_db.objective_text(l.obj)) != "", "level %d has an objective" % n)
		for wave in l.waves:
			for g in wave:
				if g.has("event"):
					check(str(g.event) in events, "level %d unknown event %s" % [n, g.event])
				else:
					var kind: String = "swarmlet" if str(g.kind) == "swarm" else g.kind
					check(Enemies_.DB.has(kind) or kind == "rocks", "level %d unknown enemy %s" % [n, kind])
	check(str(levels_db.build(23).waves) == str(levels_db.build(23).waves), "levels are repeatable")
	var evolutions := 0
	for id in Cards_.LIST:
		var c: Dictionary = Cards_.LIST[id]
		check(Cards_.ICONS.has(c.icon), "card %s has an icon" % id)
		if int(c.rarity) == Cards_.EVOLVED:
			evolutions += 1
			for need in c.needs:
				check(Cards_.LIST.has(need), "evolution %s needs a real card" % id)
	check(evolutions == 10, "ten evolutions, found %d" % evolutions)
	for sector in range(1, 7):
		for wave in [1, 7, 25]:
			levels_db.build_endless(wave)
		for tier in range(1, 8):
			levels_db.build_node(tier * 77, sector, tier, "battle")
			levels_db.build_node(tier * 79, sector, tier, "elite")
	print("content ok")

func _test_save_roundtrip() -> void:
	var legacy := ConfigFile.new()
	legacy.set_value("progress", "unlocked", 23)
	legacy.set_value("progress", "stars", {1: 3, 2: 2})
	legacy.set_value("progress", "salvage", 77)
	legacy.save("user://legacy_test.cfg")
	var keep_path: String = save.path
	save.path = "user://legacy_test.cfg"
	save.unlocked = 1
	save.star_mask = {}
	save.blueprints = []
	save.bosses_beaten = []
	save.load_data()
	check(save.unlocked == 23 and save.salvage == 77, "old saves migrate")
	check(save.stars_for(1) == 2 and save.stars_for(2) == 1, "old stars migrate")
	check("bp_interceptor" in save.blueprints and "bp_lancer" in save.blueprints, "old saves keep boss unlocks")
	DirAccess.remove_absolute("user://legacy_test.cfg")
	DirAccess.remove_absolute("user://legacy_test.cfg.bak")
	save.path = keep_path
	var meta = root.get_node("Meta")
	save.stats = {}
	save.contracts = {}
	meta.refresh_contracts()
	check((save.contracts.list as Array).size() == 3, "three daily contracts")
	var c: Dictionary = save.contracts.list[0]
	meta.count(c.stat, int(c.goal))
	check(c.done, "contract completes")
	var before: int = save.salvage
	check(meta.claim_contract(0) and save.salvage > before, "contract pays out")
	var cloud = load("res://src/meta/cloud_save.gd")
	var blob: String = cloud.export_blob()
	save.salvage = 0
	check(cloud.import_blob(blob) and save.salvage > 0, "cloud blob round trip keeps the best values")
	save.salvage = 0
	print("save ok")

func _test_menus() -> void:
	var menu = load("res://title_screen.tscn").instantiate()
	root.add_child(menu)
	for screen_name in ["title", "map", "hangar", "ops", "expedition", "settings", "title"]:
		menu.go(screen_name)
		for i in range(4):
			await process_frame
		check(menu.screen == screen_name, "menu shows " + screen_name)
	for tab in ["ships", "gear", "tech", "nova"]:
		menu.go("hangar")
		menu.pages.hangar.tab = tab
		await process_frame
		await process_frame
	for tab in ["today", "awards", "codex", "records"]:
		menu.go("ops")
		menu.pages.ops.tab = tab
		await process_frame
		await process_frame
	menu.pages.map.open_level(1)
	await process_frame
	await process_frame
	check(menu.screen == "preflight", "level opens the briefing")
	menu.go("loadout")
	await process_frame
	await process_frame
	save.salvage = 100
	check(load("res://src/data/hangar.gd").cost("cannon", 0) == 50, "first cannon cost")
	menu.pages.hangar.on_ui("buy_cannon")
	check(save.upgrade_level("cannon") == 1 and save.salvage == 50, "buying an upgrade")
	menu.pages.hangar.on_ui("buy_rapid")
	menu.pages.hangar.on_ui("buy_hull")
	check(save.upgrade_level("hull") == 0, "cannot buy without salvage")
	menu.pages.settings.on_ui("set_music_volume:0.4")
	check(absf(float(save.opt.music_volume) - 0.4) < 0.01, "settings apply")
	menu.pages.settings.on_ui("set_nova_side:left")
	check(str(save.opt.nova_side) == "left", "nova side option")
	menu.pages.settings.on_ui("set_nova_side:right")
	menu.queue_free()
	await process_frame
	save.upgrades = {}
	print("menus ok")

func _new_game(session: Dictionary):
	save.session = session
	var game = load("res://game.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	return game

func _level(n: int) -> Dictionary:
	return {"mode": "campaign", "level": n, "mutators": []}

func _test_regressions() -> void:
	var game = await _new_game(_level(1))
	_step(game, 2.0)
	var P = game.Phase
	check(game.phase == P.PLAYING, "intro leads into play")
	game.set_paused(true)
	check(game.phase == P.PAUSED, "pause opens")
	var frozen: Vector2 = game.player_pos
	_step(game, 1.0)
	check(game.player_pos == frozen, "world freezes while paused")
	game.input_lock = 0.0
	game._on_ui("resume")
	_step(game, 1.2)
	check(game.phase == P.PLAYING, "resume returns to play after the countdown")
	game.ebullet(Vector2(360, 300), PI * 0.5, 200.0, 0)
	game.energy = 100.0
	game.try_nova()
	check(game.energy == 0.0 and game.field.count == 0, "nova burst clears shots")
	game.hitstop = 0.0
	var before: float = game.shield
	game.invuln = 0.0
	game.spawn_enemy({"kind": "rock_m", "pos": game.player_pos, "move": "straight", "vel": Vector2.ZERO})
	_step(game, 0.1)
	check(game.shield < before, "rocks collide with the ship")
	var salvage_before: int = game.run_salvage
	game.pickups.append({"pos": game.player_pos, "vel": Vector2.ZERO, "value": 2, "spin": 0.0, "pull": false})
	_step(game, 0.1)
	check(game.run_salvage > salvage_before, "crystals are collected")
	# Regression: a hull hit clears nearby shots while the bullet loop is running.
	game.shield = 0.0
	game.invuln = 0.0
	game.hull = 3
	for i in range(60):
		game.ebullet(game.player_pos + Vector2(randf_range(-40, 40), randf_range(-40, 40)), PI * 0.5, 10.0, 0)
	_step(game, 0.2)
	check(game.hull < 3, "bullets damage hull")
	game.queue_free()
	await process_frame
	print("regressions ok")

func _test_all_ships() -> void:
	var Ships_ = load("res://src/data/ships.gd")
	for id in Ships_.ORDER:
		save.ship = id
		if not id in save.owned_ships:
			save.owned_ships.append(id)
		var game = await _new_game(_level(12))
		check(game.ship_id == id, "flying " + id)
		for i in range(600):
			_bot(game)
			game._process(STEP)
			game.hull = game.max_hull
		check(game.kills > 0, id + " destroys enemies")
		print("  ship %-12s kills after 20s: %d" % [id, game.kills])
		game.queue_free()
		await process_frame
	save.ship = "nova"
	print("ships ok")

func _test_all_cards() -> void:
	var Cards_ = load("res://src/data/cards.gd")
	save.blueprints = ["bp_seeker", "bp_burn", "bp_arc", "bp_cryo", "bp_spike", "bp_phoenix", "bp_echo"]
	for ship in ["nova", "lancer", "warden"]:
		save.ship = ship
		var game = await _new_game(_level(35))
		var P = game.Phase
		for id in Cards_.LIST:
			game.phase = P.UPGRADE
			game.phase_t = 1.0
			game.input_lock = 0.0
			game.card_options = [id]
			game.card_picked = -1
			game.select_card(0)
			game.input_lock = 0.0
			game.level.waves.append([])
			game._install_card()
			game.phase = P.PLAYING
		for i in range(200):
			_bot(game)
			game._process(STEP)
		check(game.held.size() == Cards_.LIST.size(), "all cards stack without error")
		game.energy = 100.0
		game.try_nova()
		_step(game, 3.0)
		game.queue_free()
		await process_frame
	for mode_id in ["singularity", "overdrive", "aegis"]:
		save.nova_mode = mode_id
		var game = await _new_game(_level(20))
		_step(game, 3.0)
		game.energy = 100.0
		game.try_nova()
		_step(game, 7.0)
		game.queue_free()
		await process_frame
	save.nova_mode = "pulse"
	save.ship = "nova"
	save.blueprints = []
	print("cards ok")

func _test_all_bosses() -> void:
	# Every boss gets fought through all three phases and killed.
	save.upgrades = {"cannon": 6, "rapid": 6}
	for sector in range(1, 7):
		var game = await _new_game(_level(sector * 10))
		var P = game.Phase
		game.level.waves[0] = []
		_step(game, 2.5)
		var guard := 0
		while game.boss == null and game.phase != P.CLEAR and guard < 400:
			game.hull = game.max_hull
			game._process(STEP)
			guard += 1
		check(game.boss != null, "boss %d spawns" % sector)
		_check_weak_points(game, sector)
		var stages := {}
		var elapsed := 0.0
		var next_nudge := 12.0
		while game.phase != P.CLEAR and game.phase != P.DEFEAT and elapsed < 200.0:
			game.hull = game.max_hull
			game.invuln = 1.0
			_bot(game)
			for i in range(3):
				game._process(STEP)
				elapsed += STEP
			if game.boss != null:
				stages[game.boss.stage] = true
				if elapsed > next_nudge and game.boss.can_be_hit():
					next_nudge += 4.0
					game.boss.nova_hit(game.boss.max_hp * 0.2)
		check(stages.size() == 3, "boss %d reaches all 3 phases (saw %d)" % [sector, stages.size()])
		check(game.phase == P.CLEAR, "boss %d can be killed (phase %d, %ds)" % [sector, game.phase, int(elapsed)])
		print("  boss %d down in %ds" % [sector, int(elapsed)])
		game.queue_free()
		await process_frame
	save.upgrades = {}
	print("bosses ok")

## A straight shot from below must reach every weak point before armour stops it.
## Rings are skipped: firing through their moving gaps is the point of that fight.
func _check_weak_points(game, sector: int) -> void:
	var boss = game.boss
	for i in range(120):
		game.hull = game.max_hull
		game.invuln = 1.0
		game._process(STEP)
	if sector == 2:
		boss.set_vents(true)
	if sector == 5:
		boss.bridge.mult = 1.5
		boss.bridge.weak = true
	for i in range(3):
		boss.update(0.0)
	var checked := 0
	for p in boss.parts:
		if not p.alive or not bool(p.weak):
			continue
		checked += 1
		var x: float = float(p.at.x)
		var y: float = float(p.at.y) + float(p.ry) + 120.0
		var first := {}
		while y > float(p.at.y) - float(p.ry):
			for q in boss.parts:
				if q.alive and (q.arc as Dictionary).is_empty() and (float(q.mult) > 0.0 or float(q.own_hp) <= 0.0) and boss._inside(q, Vector2(x, y)):
					first = q
					break
			if not first.is_empty():
				break
			y -= 10.0
		check(not first.is_empty() and bool(first.weak), "boss %d weak point can be reached from below" % sector)
	check(checked > 0, "boss %d has a weak point" % sector)

func _test_side_missions() -> void:
	for n in [101, 102, 103, 104, 105, 106]:
		var game = await _new_game({"mode": "side", "level": n, "mutators": []})
		for i in range(300):
			_bot(game)
			game._process(STEP)
		game.queue_free()
		await process_frame
	print("side missions ok")

func _test_challenges() -> void:
	var meta = root.get_node("Meta")
	var mutators = load("res://src/data/mutators.gd")
	save.unlocked = 40
	save.bosses_beaten = [1, 2, 3]
	var P_clear := -1
	for kind in ["daily", "weekly"]:
		var c: Dictionary = meta.daily_challenge() if kind == "daily" else meta.weekly_challenge()
		var game = await _new_game({"mode": kind, "level": c.level, "mutators": c.mutators, "reward": c.reward})
		P_clear = game.Phase.CLEAR
		check(game.mode == kind and game.mutators.size() > 0, kind + " starts with its dials")
		var elapsed := 0.0
		while game.phase != P_clear and game.phase != game.Phase.DEFEAT and elapsed < 240.0:
			game.hull = game.max_hull
			game.invuln = 1.0
			if game.boss != null and game.boss.can_be_hit():
				game.boss.nova_hit(game.boss.max_hp * 0.01)
			_bot(game)
			for i in range(3):
				game._process(STEP)
				elapsed += STEP
		check(game.phase == P_clear, kind + " can be finished")
		game.queue_free()
		await process_frame
		var again: Dictionary = meta.daily_challenge() if kind == "daily" else meta.weekly_challenge()
		check(int(again.best) > 0, kind + " records a best score")
	for id in mutators.ORDER:
		var game = await _new_game({"mode": "campaign", "level": 24, "mutators": [id]})
		check(game.score_mult > 1.0, "dial %s raises the score multiplier" % id)
		for i in range(240):
			game.hull = game.max_hull
			_bot(game)
			game._process(STEP)
		await process_frame
		game.queue_free()
		await process_frame
	check(int(save.stats.get("mutated_clear", 0)) >= 1, "dialled clears count toward contracts")
	save.unlocked = 1
	save.bosses_beaten = []
	print("challenges and dials ok")

func _test_expedition() -> void:
	var Exp = load("res://src/meta/expedition.gd")
	Exp.start(1)
	check(Exp.active(), "expedition starts")
	var type: String = Exp.enter_node(0)
	check(type == "battle", "first node is a fight")
	save.expedition.hull = 2
	var game = await _new_game({"mode": "expedition", "level": 1, "mutators": []})
	check(game.hull == 2, "expedition hull carries in")
	var P = game.Phase
	var elapsed := 0.0
	while game.phase != P.CLEAR and game.phase != P.DEFEAT and elapsed < 140.0:
		game.hull = game.max_hull
		game.invuln = 1.0
		_bot(game)
		for i in range(3):
			game._process(STEP)
			elapsed += STEP
	check(game.phase == P.CLEAR, "expedition node finishes")
	game.queue_free()
	await process_frame
	check(int(save.expedition.layer) == 1, "route advances")
	var msg: String = Exp.apply_choice({"salvage": 10})
	check(msg != "", "signal choices apply")
	Exp.on_run_lost()
	check(not Exp.active(), "run ends")
	print("expedition ok")

func _test_endless() -> void:
	var game = await _new_game({"mode": "endless", "level": 1, "mutators": []})
	var P = game.Phase
	var elapsed := 0.0
	while elapsed < 200.0 and game.phase != P.DEFEAT:
		_bot(game)
		for i in range(3):
			game._process(STEP)
			elapsed += STEP
		game.hull = maxi(game.hull, 2)
		if int(elapsed / STEP) % 300 == 0:
			await process_frame
	print("endless reached wave ", game.endless_wave, " in ", int(elapsed), "s")
	check(game.endless_wave >= 5, "endless progresses past a boss")
	game.queue_free()
	await process_frame

func _step(game, seconds: float) -> void:
	for i in range(int(seconds / STEP)):
		game._process(STEP)

func _bot(game) -> void:
	var P = game.Phase
	if game.phase == P.UPGRADE:
		if game.card_picked < 0 and game.input_lock <= 0.0 and not game.card_options.is_empty():
			game.select_card(randi() % game.card_options.size())
		return
	if not game.player_alive:
		return
	if game.energy >= 100.0 and game.field.count > 12:
		game.try_nova()
	var px: Vector2 = game.player_pos
	var want: float = px.x
	var boss = game.boss
	if boss != null:
		want = float(boss.aim_point().x)
	else:
		var nearest := 1e9
		for e in game.enemies:
			var dy: float = px.y - float(e.pos.y)
			if dy > 0.0 and dy < nearest and float(e.pos.y) > -20.0 and not e.ally:
				nearest = dy
				want = float(e.pos.x)
	var best: Vector2 = px
	var best_cost := 1e18
	var field = game.field
	var floor_y: float = game.H - game.FLOOR_MARGIN - game.inset.y
	for dx in [0.0, -70.0, 70.0, -150.0, 150.0, -240.0, 240.0]:
		for dy in [0.0, 90.0, -70.0]:
			var c := px + Vector2(dx, dy)
			c.x = clampf(c.x, 44.0, game.W - 44.0)
			c.y = clampf(c.y, game.H * 0.55, floor_y)
			var cost := absf(c.x - want) * 0.03 + absf(dx) * 0.012
			for i in range(field.count):
				for look in [0.12, 0.3, 0.5]:
					var d: float = (field.pos[i] + field.vel[i] * look).distance_to(c)
					if d < 90.0:
						cost += (90.0 - d) * 2.0
			for e in game.enemies:
				if e.ally:
					continue
				for look in [0.15, 0.4]:
					var d: float = ((e.pos as Vector2) + (e.vel as Vector2) * look).distance_to(c)
					var margin: float = float(e.r) + 60.0
					if d < margin:
						cost += (margin - d) * 3.0
			for b in game.hazards.beams:
				var p: float = c.x if str(b.axis) == "col" else c.y
				if absf(float(b.at) - p) < float(b.w) + 40.0:
					cost += 300.0
			if cost < best_cost:
				best_cost = cost
				best = c
	game.player_target = px + (best - px) * clampf(0.15 / maxf(think_time, 0.05), 0.0, 1.0)

func _play_level(n: int) -> Dictionary:
	var game = await _new_game(_level(n))
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
	var out := {"win": game.phase == P.CLEAR, "time": elapsed, "hull_lost": game.hull_lost, "salvage": game.run_salvage, "mask": game.result_mask, "stuck": elapsed >= limit, "phase": game.phase}
	await process_frame
	game.queue_free()
	await process_frame
	return out

func _spend() -> void:
	var hangar = load("res://src/data/hangar.gd")
	var bought := true
	while bought:
		bought = false
		var cheapest := ""
		var lowest := 1 << 30
		for item in hangar.LIST:
			if str(item.kind) == "gear" and save.upgrade_level(item.id) < int(item.max):
				var cost: int = hangar.cost(item.id, save.upgrade_level(item.id))
				if cost < lowest:
					lowest = cost
					cheapest = item.id
		if not cheapest.is_empty() and save.salvage >= lowest:
			save.buy_upgrade(cheapest)
			bought = true

func _play_campaign() -> void:
	save.salvage = int(pow(float(first - 1), 1.7) * 10.0)
	_spend()
	print("level  sect  try  result  time  hull_lost  salvage  stars  bank")
	var total := 0
	var failed := 0
	for n in range(first, last + 1):
		var won := false
		for attempt in range(1, tries + 1):
			var r: Dictionary = await _play_level(n)
			total += 1
			check(not r.stuck, "level %d did not end (phase %d)" % [n, int(r.phase)])
			_spend()
			var stars: int = (int(r.mask) & 1) + ((int(r.mask) >> 1) & 1) + ((int(r.mask) >> 2) & 1)
			print("%5d  %4d  %3d  %6s  %4ds  %9d  %7d  %5d  %4d" % [n, levels_db.sector_of(n), attempt, "WIN" if r.win else "lost", int(r.time), r.hull_lost, r.salvage, stars, save.salvage])
			if r.win:
				won = true
				break
		if not won:
			failed += 1
			save.unlocked = maxi(save.unlocked, n + 1)
	print("campaign: %d levels, %d attempts, %d not beaten in %d tries" % [last - first + 1, total, failed, tries])
	print("upgrades: ", save.upgrades, " bank: ", save.salvage)
