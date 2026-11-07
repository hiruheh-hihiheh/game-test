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
var tier_arg := 0
var gear_spec := ""
var pilot_arg := 1
var gear_db
var tiers_db
var pilot_db
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
		elif arg.begins_with("--tier="):
			tier_arg = int(arg.substr(7))
		elif arg.begins_with("--gear="):
			gear_spec = arg.substr(7)
		elif arg.begins_with("--pilot="):
			pilot_arg = int(arg.substr(8))
		elif arg == "--quick":
			quick = true

func _run() -> void:
	_args()
	save = root.get_node("Save")
	levels_db = load("res://src/data/levels.gd")
	gear_db = load("res://src/data/gear.gd")
	tiers_db = load("res://src/data/tiers.gd")
	pilot_db = load("res://src/data/pilot.gd")
	check(save.path == save.TEST_PATH, "tests must use the throwaway save")
	_test_content()
	_test_save_roundtrip()
	_test_gear_data()
	_test_pilot()
	await _test_menus()
	await _test_regressions()
	await _test_all_ships()
	await _test_all_cards()
	await _test_all_bosses()
	await _test_side_missions()
	await _test_challenges()
	await _test_gear_systems()
	await _test_tiers_and_rift()
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
	save.gear = []
	save.equipped = {}
	save.parts = 0
	save.pilot_xp = _xp_for_level(pilot_arg)
	_equip_test_gear()

func _xp_for_level(level: int) -> int:
	var total := 0
	for l in range(1, level):
		total += pilot_db.need(l)
	return total

## Gives the bot a full set of maxed gear, so tiers can be tested at a chosen power. Spec: rarity:power.
func _equip_test_gear() -> void:
	if gear_spec.is_empty():
		return
	var parts_spec := gear_spec.split(":")
	var rarity: int = ["common", "uncommon", "rare", "epic", "legendary"].find(parts_spec[0])
	var power := float(parts_spec[1]) if parts_spec.size() > 1 else 10.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	for slot in ["weapon", "reactor", "plating"]:
		var item: Dictionary = gear_db.generate(rng, power, maxi(rarity, 0), slot, 0)
		item.lvl = gear_db.level_cap(item)
		save.add_gear(item)
		save.equip(ship_id, int(item.uid))

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
	for tab in ["ships", "gear", "lab", "tech", "nova"]:
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

func _test_gear_data() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	save.gear = []
	save.equipped = {}
	save.parts = 0
	var perks_seen := 0
	for rarity in range(5):
		for slot in ["weapon", "reactor", "plating"]:
			for i in range(8):
				var item: Dictionary = gear_db.generate(rng, 10.0, rarity, slot, 3)
				check(item.slot == slot and int(item.rarity) == rarity, "gear generates the slot and rarity asked for")
				check((item.aff as Array).size() >= 1 and (item.aff as Array).size() <= 3, "gear has 1 to 3 affixes")
				check(str(item.name) != "", "gear has a name")
				if rarity == 4:
					check(str(item.perk) != "" and str(gear_db.PERKS[item.perk].slot) == slot, "legendaries carry a perk for their slot")
					perks_seen += 1
				else:
					check(str(item.perk) == "", "only legendaries carry perks")
				for a in item.aff:
					check(gear_db.affix_value(item, a) > 0.0, "affix values are positive")
					if str(a.k) == "hull_add":
						check(rarity >= 3, "hull only rolls on epic or better")
	check(perks_seen == 24, "every legendary had a perk")
	var probe: Dictionary = gear_db.generate(rng, 10.0, 2, "weapon")
	var low: float = gear_db.affix_value(probe, probe.aff[0])
	probe.lvl = 4
	check(gear_db.affix_value(probe, probe.aff[0]) > low * 1.3, "upgrading raises affix values")
	# Inventory: add, equip, move, scrap, upgrade.
	var items: Array = []
	for i in range(5):
		var it: Dictionary = gear_db.generate(rng, 8.0, 2, "weapon")
		save.add_gear(it)
		items.append(it)
	var u1 := int(items[0].uid)
	check(u1 > 0 and int(items[1].uid) == u1 + 1, "gear gets unique, rising ids")
	save.equip("nova", u1)
	check(int(save.equipped_item("nova", "weapon").uid) == u1, "equip puts gear on the ship")
	save.equip("lancer", u1)
	check(save.equipped_on(u1) == "lancer" and save.equipped_item("nova", "weapon").is_empty(), "gear moves between ships")
	check(save.scrap_gear(u1) == -1, "equipped gear cannot be scrapped")
	save.unequip("lancer", "weapon")
	var gained: int = save.scrap_gear(u1)
	check(gained > 0 and save.parts == gained and save.gear_by_uid(u1).is_empty(), "scrapping pays parts and removes the item")
	var u2 := int(items[1].uid)
	save.parts = 1000
	var rate_before: int = gear_db.rating(items[1])
	check(save.upgrade_gear(u2) and int(items[1].lvl) == 1 and gear_db.rating(items[1]) > rate_before, "upgrading spends parts and raises rating")
	var guard := 0
	while save.upgrade_gear(u2) and guard < 30:
		guard += 1
	check(int(items[1].lvl) == gear_db.level_cap(items[1]), "upgrades stop at the level cap")
	save.parts = 0
	check(not save.upgrade_gear(int(items[2].uid)), "upgrades need parts")
	# Overflow: a full bag turns new loot into parts.
	var keep: Array = save.gear.duplicate()
	while save.gear.size() < gear_db.MAX_ITEMS:
		save.add_gear(gear_db.generate(rng, 3.0, 0))
	var parts_before: int = save.parts
	var extra: Dictionary = gear_db.generate(rng, 3.0, 1)
	check(not save.add_gear(extra) and save.parts > parts_before and bool(extra.get("scrapped", false)), "a full bag scraps new loot")
	save.gear = keep
	# Stats flow into the combat dictionary.
	var s := {"dmg_mult": 1.0, "fire_mult": 1.0, "crit": 0.05, "shield_add": 0.0, "hull_add": 0.0, "drones": 0.0}
	var legendary: Dictionary = gear_db.generate(rng, 20.0, 4, "weapon")
	legendary.aff = [{"k": "dmg_mult", "r": 1.0}, {"k": "fire_mult", "r": 1.0}]
	legendary.perk = "wardens_lens"
	gear_db.apply_to(legendary, s)
	check(float(s.dmg_mult) > 1.05 and float(s.fire_mult) < 1.0 and float(s.ricochet) == 1.0, "gear and perks apply to stats")
	# Drop odds climb with power and luck.
	var rolls := 4000
	var legends_low := 0
	var legends_high := 0
	for i in range(rolls):
		if gear_db.roll_rarity(rng, 4.0, 0.0) == 4:
			legends_low += 1
		if gear_db.roll_rarity(rng, 40.0, 3.2) == 4:
			legends_high += 1
	check(legends_low < rolls / 40, "legendaries are rare early (%d of %d)" % [legends_low, rolls])
	check(legends_high > legends_low * 2 and legends_high > rolls / 50, "tier and depth improve odds (%d vs %d)" % [legends_high, legends_low])
	check(gear_db.roll_rarity(rng, 1.0, 0.0, 3) >= 3, "min rarity is respected")
	# Saving keeps gear and what is worn.
	save.equip("nova", int(items[1].uid))
	var snapshot: Dictionary = save.to_dict()
	var count_before: int = save.gear.size()
	save.gear = []
	save.equipped = {}
	save.from_dict(snapshot)
	check(save.gear.size() == count_before and int(save.equipped_item("nova", "weapon").uid) == int(items[1].uid), "gear and equipment survive a save")
	print("gear data ok")

func _test_pilot() -> void:
	save.pilot_xp = 0
	var info: Dictionary = pilot_db.level_of(0)
	check(int(info.level) == 1 and int(info.into) == 0, "pilots start at level 1")
	var last_level := 0
	for xp in range(0, 60000, 750):
		var lv: int = int(pilot_db.level_of(xp).level)
		check(lv >= last_level, "pilot level never drops as XP rises")
		last_level = lv
	var gear_before: int = save.gear.size()
	var salvage_before: int = save.salvage
	var out: Dictionary = pilot_db.grant(10000)
	check(int(out.levels) > 5 and (out.rewards as Array).size() >= 1, "XP pays out pilot levels")
	check(save.salvage > salvage_before and save.gear.size() > gear_before, "pilot levels pay salvage and gear")
	check(pilot_db.dmg_bonus() > 1.0 and pilot_db.shield_bonus() > 0.0, "pilot level adds permanent power")
	save.pilot_xp = 0
	print("pilot ok")

func _new_game(session: Dictionary):
	save.session = session
	var game = load("res://game.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	return game

func _level(n: int) -> Dictionary:
	return {"mode": "campaign", "level": n, "mutators": [], "tier": 0}

## Only the campaign simulation runs at the tier asked for on the command line.
func _level_tier(n: int) -> Dictionary:
	return {"mode": "campaign", "level": n, "mutators": [], "tier": tier_arg}

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

func _test_gear_systems() -> void:
	save.gear = []
	save.equipped = {}
	save.ship = "nova"
	save.pilot_xp = 0
	save.upgrades = {}
	var base = await _new_game(_level(10))
	var base_dmg: float = base.s.dmg_mult
	var base_fire: float = base.s.fire_mult
	var base_shield: float = base.max_shield
	var base_hull: int = base.max_hull
	base.queue_free()
	await process_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var w: Dictionary = gear_db.generate(rng, 20.0, 4, "weapon")
	w.aff = [{"k": "dmg_mult", "r": 1.0}, {"k": "fire_mult", "r": 1.0}, {"k": "crit", "r": 1.0}]
	w.perk = "wardens_lens"
	var p: Dictionary = gear_db.generate(rng, 20.0, 4, "plating")
	p.aff = [{"k": "shield_add", "r": 1.0}, {"k": "shield_regen", "r": 1.0}, {"k": "hull_add", "r": 1.0}]
	p.perk = "crown_shard"
	var r: Dictionary = gear_db.generate(rng, 20.0, 4, "reactor")
	r.aff = [{"k": "nova_gain", "r": 1.0}, {"k": "nova_start", "r": 1.0}, {"k": "magnet", "r": 1.0}]
	r.perk = "brood_heart"
	for it in [w, p, r]:
		it.lvl = 12
		save.add_gear(it)
		save.equip("nova", int(it.uid))
	var game = await _new_game(_level(10))
	check(game.s.dmg_mult > base_dmg * 1.2 and game.s.fire_mult < base_fire, "equipped weapon raises damage and fire rate")
	check(game.max_shield > base_shield + 20.0 and game.max_hull >= base_hull + 1, "equipped plating raises shield and hull")
	check(float(game.s.shield_regen) > 0.0 and game.energy > 5.0, "regen and starting Nova apply")
	check(float(game.s.ricochet) >= 1.0 and float(game.s.phoenix) >= 1.0 and float(game.s.drones) >= 1.0, "legendary perks apply in combat")
	for i in range(300):
		_bot(game)
		game._process(STEP)
		game.hull = game.max_hull
	# Loot is banked once, whatever the ending.
	var bag_before: int = save.gear.size()
	var parts_before: int = save.parts
	var xp_before: int = save.pilot_xp
	for i in range(6):
		game.roll_loot(1.0, 2.0)
	check(game.loot.size() == 6, "forced loot rolls drop gear")
	game.result_win = true
	game._bank()
	check(save.gear.size() >= bag_before + 6, "banked loot lands in the bag")
	check(save.parts > parts_before and save.pilot_xp > xp_before, "a flight pays parts and pilot XP")
	var after_bank: int = save.gear.size()
	game._bank()
	check(save.gear.size() == after_bank, "loot only banks once")
	game.queue_free()
	await process_frame
	print("gear in combat ok")

func _test_tiers_and_rift() -> void:
	save.tier_unlocked = 4
	save.gear = []
	save.equipped = {}
	var base_hp := 0.0
	var last_power := 0.0
	for t in range(5):
		var game = await _new_game({"mode": "campaign", "level": 20, "mutators": [], "tier": t})
		check(game.tier == t and absf(game.hp_mult - float(tiers_db.cfg(t).hp)) < 0.001, "tier %d scales enemy health" % t)
		var e: Dictionary = game.spawn_enemy({"kind": "fighter", "pos": Vector2(360, 100), "move": "straight", "vel": Vector2.ZERO})
		if t == 0:
			base_hp = float(e.max)
		else:
			check(float(e.max) > base_hp * 1.3, "tier %d enemies are tougher" % t)
		check(game.loot_power() > last_power, "tier %d drops stronger gear" % t)
		last_power = game.loot_power()
		for i in range(120):
			_bot(game)
			game._process(STEP)
		game.queue_free()
		await process_frame
	# Beating level 60 opens the next tier, and tiers keep their own progress.
	save.tier_unlocked = 0
	save.star_mask.erase(60)
	var finale = await _new_game({"mode": "campaign", "level": 60, "mutators": [], "tier": 0})
	finale._level_complete()
	check(save.tier_unlocked == 1, "clearing level 60 unlocks Veteran")
	var found := false
	for rw in finale.rewards:
		if str(rw.title) == "TIER UNLOCKED":
			found = true
	check(found, "the unlock is announced")
	check(finale.loot.size() >= 2, "a boss clear drops gear")
	finale.queue_free()
	await process_frame
	save.star_mask.erase(5)
	var veteran = await _new_game({"mode": "campaign", "level": 5, "mutators": [], "tier": 1})
	veteran._level_complete()
	check(save.mask_at(1, 5) > 0 and save.mask_at(0, 5) == 0 and save.unlocked_at(1) >= 6, "tier clears are recorded separately")
	veteran.queue_free()
	await process_frame
	# The Rift: dials arrive with depth and milestones pay once.
	check(Levels.build_endless(9).mutators.size() == 0 and Levels.build_endless(10).mutators.size() == 1, "the Rift adds a dial at floor 10")
	check(Levels.build_endless(20).mutators.size() == 2 and Levels.build_endless(30).mutators.size() == 3 and Levels.build_endless(60).mutators.size() == 3, "dials stack to three")
	save.rift_claimed = []
	var rift = await _new_game({"mode": "endless", "level": 1, "mutators": []})
	rift._rift_floor_cleared(5)
	check(5 in save.rift_claimed and rift.loot.size() >= 1 and rift.bonus_parts > 0, "floor 5 pays a milestone")
	var loot_count: int = rift.loot.size()
	rift._rift_floor_cleared(5)
	check(rift.loot.size() == loot_count, "milestones pay once")
	rift.endless_wave = 10
	rift.phase = rift.Phase.UPGRADE
	rift._after_card()
	check(rift.endless_wave == 11 and rift.mutators.size() == 1 and rift.score_mult > 1.0, "deeper floors turn on Hazard Dials mid-run")
	rift.queue_free()
	await process_frame
	save.tier_unlocked = 0
	save.rift_claimed = []
	print("tiers and rift ok")

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
	var game = await _new_game(_level_tier(n))
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
