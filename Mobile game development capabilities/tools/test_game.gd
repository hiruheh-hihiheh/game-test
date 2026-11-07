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
var danger_arg: Array = []   # --danger=rush,hostiles plays the campaign sim with contracts
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
		elif arg.begins_with("--danger="):
			danger_arg = Array(arg.substr(9).split(","))
		elif arg == "--quick":
			quick = true

func _run() -> void:
	_args()
	save = root.get_node("Save")
	levels_db = load("res://src/data/levels.gd")
	gear_db = load("res://src/data/gear.gd")
	tiers_db = load("res://src/data/tiers.gd")
	pilot_db = load("res://src/data/pilot.gd")
	check(save.test_mode and save.path.begins_with(save.TEST_PREFIX), "tests must use the throwaway save")
	_test_content()
	_test_save_roundtrip()
	_test_gear_data()
	_test_pilot()
	await _test_ui_art()
	await _test_runtime_leaks()
	await _test_menus()
	await _test_regressions()
	await _test_all_ships()
	await _test_all_cards()
	await _test_all_bosses()
	await _test_side_missions()
	await _test_challenges()
	await _test_gear_systems()
	await _test_tiers_and_rift()
	await _test_danger()
	await _test_glass_ui()
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

## Save files are tested at paths of their own, named after this process, so runs can overlap.
func _qa_path(tag: String) -> String:
	return "user://qa_%s_%d.cfg" % [tag, OS.get_process_id()]

func _write_legacy(p: String, progress: Dictionary, settings := {}) -> void:
	var legacy := ConfigFile.new()
	for k in progress:
		legacy.set_value("progress", k, progress[k])
	for k in settings:
		legacy.set_value("settings", k, settings[k])
	check(legacy.save(p) == OK, "can write a legacy test save (is user:// writable?)")

func _write_text(p: String, text: String) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	check(f != null, "can write " + p)
	if f:
		f.store_string(text)

## Sets many options away from their defaults, as if another player's save had been loaded before.
func _dirty_options() -> void:
	save.opt.music_volume = 0.1
	save.opt.sfx_volume = 0.2
	save.opt.haptics = 0.5
	save.opt.shake = 0.0
	save.opt.reduced_flash = true
	save.opt.reduced_motion = true
	save.opt.particles = 0
	save.opt.nova_side = "left"
	save.opt.nova_double_tap = true
	save.opt.sensitivity = 1.7
	save.opt.ui_scale = 1.12
	save.opt.colorblind = true
	save.opt.bullet_outline = true
	save.opt.bullet_size = 1.4
	save.opt.fps = 30
	save.opt.telemetry = true
	save.opt.show_hitbox = false

## Every option must equal its default, except the ones named.
func _options_are_default(label: String, except := []) -> void:
	for k in save.DEFAULT_OPT:
		if k in except:
			continue
		check(save.opt.get(k) == save.DEFAULT_OPT[k], "%s: option %s returns to its default (%s)" % [label, k, str(save.opt.get(k))])
	check(save.opt.size() == save.DEFAULT_OPT.size(), label + ": no stray options")

## Every way a save can be loaded: fresh, version 1, current, and each backup fallback.
func _test_save_loading() -> void:
	var keep_path: String = save.path
	var p := _qa_path("load")
	save.remove_files(p)
	save.path = p

	# A fresh install, even when memory still holds somebody else's progress.
	save.salvage = 999
	save.parts = 50
	save.gear = [{"uid": 3}]
	_dirty_options()
	check(save.load_data() == "none", "no file means a fresh start")
	_options_are_default("fresh start")
	check(save.unlocked == 1 and save.salvage == 0 and save.parts == 0 and (save.gear as Array).is_empty() and save.ship == "nova", "fresh start is a clean slate")

	# A version 1 save, loaded over leftovers: nothing may leak through, and nothing may be lost.
	_write_legacy(p, {"unlocked": 23, "stars": {1: 3, 2: 2}, "salvage": 77}, {"vibration": false})
	save.salvage = 5
	save.parts = 9
	save.pilot_xp = 400
	save.tier_unlocked = 3
	save.gear = [{"uid": 8}]
	save.bosses_beaten = [6]
	_dirty_options()
	check(save.load_data() == "main", "legacy save loads from the main file")
	check(is_zero_approx(float(save.opt.haptics)), "legacy vibration=false migrates to haptics 0")
	_options_are_default("legacy save", ["haptics"])
	check(save.unlocked == 23 and save.salvage == 77, "old saves migrate")
	check(save.stars_for(1) == 2 and save.stars_for(2) == 1, "old stars migrate")
	check("bp_interceptor" in save.blueprints and "bp_lancer" in save.blueprints, "old saves keep boss unlocks")
	check(save.bosses_beaten == [1, 2], "old saves keep exactly the bosses they beat")
	check(save.migrated_from == 1, "migration is recorded")
	check(save.parts == 0 and save.pilot_xp == 0 and save.tier_unlocked == 0 and (save.gear as Array).is_empty(), "migration starts from a clean slate")
	check(is_zero_approx(float(save.opt.haptics)), "old vibration setting migrates")

	# A legacy save with only a backup.
	save.remove_files(p)
	_write_legacy(p + ".bak", {"unlocked": 12, "salvage": 40}, {"music_volume": 0.3})
	_dirty_options()
	check(save.load_data() == "backup" and save.unlocked == 12 and save.salvage == 40, "legacy backup is used when the main file is gone")
	check(absf(float(save.opt.music_volume) - 0.3) < 0.001, "legacy backup keeps the setting it stored")
	_options_are_default("legacy backup", ["music_volume"])
	save.remove_files(p)

	# A current-version save round-trips without being mistaken for a legacy one.
	save.reset_progress()
	save.salvage = 321
	save.unlocked = 41
	save.star_mask = {5: 7, 41: 3}
	save.pilot_xp = 777
	save.parts = 12
	save.tier_unlocked = 2
	save.tier_data = {"1": {"stars": {"3": 7}}}
	save.opt.music_volume = 0.35
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var item: Dictionary = gear_db.generate(rng, 12.0, 3, "reactor", 0)
	save.add_gear(item)
	save.equip("nova", int(item.uid))
	save.save_data()
	save.reset_progress()
	save.opt.music_volume = 0.8
	check(save.load_data() == "main", "current save loads from the main file")
	check(save.migrated_from == 0, "current saves are not migrated")
	check(save.salvage == 321 and save.unlocked == 41 and save.pilot_xp == 777 and save.parts == 12 and save.tier_unlocked == 2, "current save keeps its progress")
	check(save.stars_for(5) == 3 and save.stars_for(41) == 2, "current save keeps its stars")
	check((save.gear as Array).size() == 1 and not save.equipped_on(int(save.gear[0].uid)).is_empty(), "current save keeps equipped gear")
	check(absf(float(save.opt.music_volume) - 0.35) < 0.001, "current save keeps its settings")

	# Backup fallback: the second save leaves the first as the backup.
	save.salvage = 500
	save.save_data()
	check(FileAccess.file_exists(p + ".bak"), "saving twice keeps a backup")
	_write_text(p, "this is [not a save")
	save.reset_progress()
	_dirty_options()
	check(save.load_data() == "backup" and save.salvage == 321, "a corrupt main file falls back to the backup")
	check(absf(float(save.opt.music_volume) - 0.35) < 0.001, "the backup brings its own settings")
	_options_are_default("corrupt main", ["music_volume"])
	_write_text(p, "[meta]\nversion=2\n[progress]\ndata={}\n")
	save.reset_progress()
	check(save.load_data() == "backup" and save.salvage == 321, "an empty main file does not hide the backup")
	save.remove_files(p)
	_write_text(p + ".bak", "garbage")
	save.salvage = 9
	_dirty_options()
	check(save.load_data() == "none" and save.salvage == 0, "two bad files give a fresh start, not a crash")
	_options_are_default("two bad files")
	save.remove_files(p)
	# Session-only state is not part of a save, but a load starts it fresh too.
	save.map_sector = 4
	save.map_tier = 2
	save.load_data()
	check(save.map_sector == 1 and save.map_tier == 0, "a load does not keep the map position of an earlier save")
	save.path = keep_path
	save.reset_progress()
	save.reset_settings()
	print("save loading ok")

func _test_save_roundtrip() -> void:
	_test_save_loading()
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

## The illustration pack: every place that needs art has some, and Reduce motion really stops it.
func _test_ui_art() -> void:
	var art = load("res://src/ui_art.gd")
	var hangar_db = load("res://src/data/hangar.gd")
	var ships_db = load("res://src/data/ships.gd")
	art.clear()
	check(art.loaded_keys().is_empty(), "no illustration is loaded until a page asks")
	var in_group := {}
	for g in art.GROUPS:
		for key in art.GROUPS[g]:
			in_group[key] = true
	for key in art.FILES:
		check(in_group.has(key), "art key belongs to a group: " + str(key))
		check(ResourceLoader.exists(art.path_of(key)), "art file exists: " + str(key))
	for slot in gear_db.SLOTS:
		check(art.has(slot), "loot art for slot " + str(slot))
	for item in hangar_db.LIST:
		if str(item.kind) != "lab":
			check(art.has(str(item.id)), "hangar art for " + str(item.id))
	for mode in ships_db.NOVA_MODES:
		check(art.has(str(mode)), "nova art for " + str(mode))
	for key in ["hangar", "ops", "expedition", "rift", "rank", "locked"]:
		check(art.has(key), "art key " + key)
	# Phones never need more than ~3x the drawn size. Menu art is capped at 256 px.
	art.load_now(["home", "pilot", "loot", "upgrades", "tech", "nova"])
	for key in art.loaded_keys():
		var tex: Texture2D = art.tex_of(key)
		check(tex != null and maxi(tex.get_width(), tex.get_height()) <= 256, "art is phone sized: " + str(key))
	check(art.memory_bytes() < 8 * 1024 * 1024, "all menu art fits in 8 MB of video memory (%d KB)" % (art.memory_bytes() / 1024))
	# Pages stream what they need in the background and release the rest.
	art.clear()
	art.focus(["nova"])
	var guard := 0
	while not art.is_ready(["home", "pilot", "nova"]) and guard < 300:
		art.pump()
		await process_frame
		guard += 1
	check(art.is_ready(["home", "pilot", "nova"]), "streamed art arrives without blocking")
	check(not "cannon" in art.loaded_keys(), "art for other pages is not loaded")
	art.focus(["tech"])
	check(not "pulse" in art.loaded_keys() and "hangar" in art.loaded_keys(), "leaving a page releases its art but keeps the title art")
	guard = 0
	while not art.is_ready(["tech"]) and guard < 300:
		art.pump()
		await process_frame
		guard += 1
	check(art.is_ready(["tech"]), "the next page's art arrives")
	art.focus([])
	await process_frame
	art.pump()
	check(art.loaded_keys().size() == art.keys_of(art.CORE).size(), "only the title art stays resident")
	var moved := false
	for key in ["hangar", "ops", "expedition", "rift", "weapon", "reactor", "plating", "pulse", "singularity", "overdrive", "aegis"]:
		var still: Dictionary = art.pose_of(key, 1.7, false)
		check(still.off == Vector2.ZERO and is_zero_approx(float(still.rot)) and is_equal_approx(float(still.scale), 1.0), "still pose for " + key)
		for step in range(40):
			var p: Dictionary = art.pose_of(key, float(step) * 0.37, true)
			check(absf(float(p.off.y)) <= 3.01 and absf(float(p.rot)) <= deg_to_rad(6.01) and absf(float(p.scale) - 1.0) <= 0.031, "motion stays small for " + key)
			if p.off != Vector2.ZERO or not is_zero_approx(float(p.rot)) or not is_equal_approx(float(p.scale), 1.0):
				moved = true
	check(moved, "illustrations animate when motion is on")
	save.opt.reduced_motion = true
	check(art.calm() and art.quiet(), "Reduce motion makes art still")
	save.opt.reduced_motion = false
	save.opt.reduced_flash = true
	check(not art.calm() and art.quiet(), "Reduce flashes drops halos but keeps motion")
	save.opt.reduced_flash = false
	print("ui art ok")

## Opens and closes every menu page and a level many times. What a player does for hours must not
## make objects, resources or nodes pile up. (Shutdown warnings are a different matter: see docs/UI_ART.md.)
func _test_runtime_leaks() -> void:
	var cycle := func() -> void:
		var menu = load("res://title_screen.tscn").instantiate()
		root.add_child(menu)
		for page in ["title", "map", "hangar", "ops", "expedition", "settings", "title"]:
			menu.go(page)
			if page == "hangar":
				for tab in ["gear", "lab", "tech", "nova", "ships"]:
					menu.pages.hangar.tab = tab
					menu.pages.hangar.on_ui("tab_" + tab)
					for i in range(3):
						await process_frame
			for i in range(3):
				await process_frame
		menu.queue_free()
		await process_frame
		var game = await _new_game(_level(3))
		_step(game, 1.0)
		game.queue_free()
		await process_frame
		await process_frame
	for i in range(3):
		await cycle.call()
	var objects_before := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var resources_before := int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	for i in range(12):
		await cycle.call()
	var objects_after := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var nodes_after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var resources_after := int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	print("leak check: objects %d -> %d, nodes %d -> %d, resources %d -> %d, orphans %d" % [objects_before, objects_after, nodes_before, nodes_after, resources_before, resources_after, orphans])
	check(nodes_after <= nodes_before + 2, "menus and levels do not leak nodes (%d -> %d)" % [nodes_before, nodes_after])
	check(objects_after <= objects_before + 80, "menus and levels do not leak objects (%d -> %d)" % [objects_before, objects_after])
	check(resources_after <= resources_before + 10, "menus and levels do not leak resources (%d -> %d)" % [resources_before, resources_after])
	check(orphans == 0, "no orphan nodes (%d)" % orphans)

## Danger Contracts: the rules, the payouts, the save data, and real runs that win and lose with them.
func _test_danger() -> void:
	var D = load("res://src/data/danger.gd")
	var art = load("res://src/ui_art.gd")
	var mut = load("res://src/data/mutators.gd")
	var ctx := {"mode": "campaign", "dials": [], "picks": 3}

	# --- The data itself ---
	var fx_keys := ["hull_add", "bullet", "fire", "pace", "elite", "nova_off", "regen", "cards_minus", "no_reroll"]
	var reward_keys := ["salvage", "parts", "xp", "luck", "rolls"]
	var names := {}
	check(D.ORDER.size() == D.LIST.size(), "every contract is listed in ORDER")
	for id in D.ORDER:
		var def: Dictionary = D.LIST[id]
		check(not names.has(def.name), "contract names are unique: " + str(def.name))
		names[def.name] = true
		check(D.GROUPS.has(def.group), "contract group exists: " + id)
		check(art.has(str(def.art)), "contract art exists: " + id)
		check(int(def.heat) >= 1 and int(def.heat) <= 3, "heat is 1 to 3: " + id)
		check(not (def.fx as Dictionary).is_empty() and not (def.reward as Dictionary).is_empty(), "contract has a cost and a payout: " + id)
		for k in def.fx:
			check(k in fx_keys, "known effect %s in %s" % [k, id])
		for k in def.reward:
			check(k in reward_keys, "known reward %s in %s" % [k, id])
		for roll in def.reward.get("rolls", []):
			check(int(roll.min) >= 0 and int(roll.min) <= 4, "roll rarity is valid: " + id)
		for d in def.get("bad_dials", []):
			check(mut.LIST.has(d), "conflicting dial exists: %s in %s" % [d, id])
		check(not D.reward_lines(id).is_empty(), "contract can describe its payout: " + id)

	# --- Selection rules ---
	check(D.blocked_reason([], "fragile", ctx) == "", "a contract can be picked on its own")
	check(D.blocked_reason(["fragile"], "cold", ctx) != "", "two ship contracts contradict each other")
	check(D.blocked_reason(["fragile", "rush"], "silence", ctx) != "", "no more than two contracts")
	check(D.blocked_reason(["rush"], "rush", ctx) == "", "a chosen contract can always be switched off")
	check(D.blocked_reason([], "bogus", ctx) != "", "unknown contracts are refused")
	check(D.blocked_reason([], "elite_signal", {"dials": ["elites"]}) != "", "Elite Signal conflicts with the Elite Invasion dial")
	check(D.blocked_reason([], "fragile", {"dials": ["brittle"]}) != "", "Fragile Hull conflicts with the Brittle dial")
	check(D.blocked_reason([], "hostiles", {"dials": ["swift"]}) != "" and D.blocked_reason([], "hostiles", {"dials": ["frenzy"]}) != "", "Overclocked Hostiles conflicts with the enemy-fire dials")
	check(D.blocked_reason([], "cold", {"dials": ["noregen"]}) != "", "Cold Reactor conflicts with Dry Cells")
	check(D.blocked_reason([], "rush", {"dials": ["swarm", "armor", "blackout"]}) == "", "unrelated dials never block a contract")
	check(D.blocked_reason([], "fragile", {"mode": "expedition", "dials": []}) != "", "Fragile Hull is not offered in the Expedition, where hull carries over")
	check(D.blocked_reason([], "lean", {"mode": "campaign", "dials": [], "picks": 1}) != "", "Lean Loadout needs a level with module picks")
	check(D.blocked_reason([], "lean", {"mode": "endless", "dials": [], "picks": -1}) == "", "Lean Loadout is fine where picks are open-ended")
	check(not D.validate(["rush", "rush"], ctx).is_empty() and not D.validate(["fragile", "cold"], ctx).is_empty() and D.validate(["rush", "hostiles"], ctx).is_empty(), "validate reports duplicates and conflicts")
	check(D.sanitize(["fragile", "bogus", "cold", "fragile", "rush", "silence"], ctx) == ["fragile", "rush"], "sanitize keeps the valid part, in order")
	check(D.dial_conflict(["elite_signal"], "elites") == "ELITE SIGNAL" and D.dial_conflict(["rush"], "elites") == "", "a dial can ask which contract blocks it")
	# Every legal pair obeys the rules and stays inside the payout caps.
	var legal := 0
	for a in D.ORDER:
		for b in D.ORDER:
			if a == b or D.blocked_reason([a], b, ctx) != "":
				continue
			legal += 1
			check(D.LIST[a].group != D.LIST[b].group, "pairs never share a group: %s %s" % [a, b])
			var r: Dictionary = D.rewards([a, b])
			for k in D.CAPS:
				check(float(r[k]) <= float(D.CAPS[k]) + 0.0001, "payout cap holds for %s+%s %s" % [a, b, k])
			check((r.rolls as Array).size() <= D.MAX_ROLLS, "no more than two bonus rolls: %s %s" % [a, b])
	check(legal >= 20, "plenty of legal pairs exist (%d)" % legal)

	# --- Reward scaling ---
	var none: Dictionary = D.rewards([])
	check(float(none.salvage) == 0.0 and float(none.parts) == 0.0 and float(none.xp) == 0.0 and float(none.luck) == 0.0 and (none.rolls as Array).is_empty(), "no contracts, no bonus")
	check(is_equal_approx(float(D.rewards(["rush"]).salvage), 0.25), "Salvage Rush pays 25% salvage")
	check(is_equal_approx(float(D.rewards(["rush", "hostiles"]).salvage), 0.25 * D.DOUBLE_BONUS), "two contracts pay 15% more together")
	check(is_equal_approx(float(D.rewards(["hostiles", "rush"]).parts), 0.6 * D.DOUBLE_BONUS), "parts scale the same way")
	check(float(D.rewards(["fragile"]).luck) == 2.0 and (D.rewards(["fragile"]).rolls as Array).size() == 1, "Fragile Hull improves gear odds and adds a roll")
	check(int(D.rewards(["silence"]).rolls[0].min) == gear_db.EPIC, "Nova Silence guarantees an Epic or better roll")
	check(bool(D.rewards(["elite_signal"]).rolls[0].boss), "Elite Signal is a boss cache")
	check(D.heat(["silence", "rush"]) == 4 and D.heat([]) == 0, "heat adds up")
	check(D.names(["rush", "cold"]) == "SALVAGE RUSH + COLD REACTOR", "names read cleanly")
	check(float(D.rewards(["rush", "cold"]).salvage) <= 0.6, "salvage never exceeds the cap")

	# --- Daily and weekly: one featured contract, the same for everyone, never in conflict ---
	var dial_sets: Array = []
	for a in Goals.DAILY_DIALS:
		for b in Goals.DAILY_DIALS:
			if a != b:
				dial_sets.append([a, b])
	for day in range(1, 41):
		for dials in dial_sets:
			var f: String = D.featured(day, dials, "daily")
			check(f != "" and D.blocked_reason([], f, {"mode": "daily", "dials": dials, "picks": 2}) == "", "featured contract is legal on day %d with %s" % [day, str(dials)])
	check(D.featured(7, ["swift", "swarm"], "daily") == D.featured(7, ["swift", "swarm"], "daily"), "the featured contract is the same for everyone")
	var seen_featured := {}
	for day in range(1, 60):
		seen_featured[D.featured(day, ["swarm", "armor"], "daily")] = true
	check(seen_featured.size() >= 4, "the featured contract rotates (%d kinds in 60 days)" % seen_featured.size())

	# --- Save and load ---
	save.danger = D.repair({"done": {"rush": 2, "bogus": 9, "cold": -4}, "last": {"campaign": ["rush", "bogus", "rush", "cold", "fragile"]}})
	check(save.danger.done == {"rush": 2, "cold": 0}, "repair drops unknown contracts and negative counts")
	check(save.danger.last.campaign == ["rush", "cold"], "repair keeps a valid, short last selection")
	var keep_path: String = save.path
	var p := _qa_path("danger")
	save.remove_files(p)
	save.path = p
	save.danger = {"done": {"rush": 3, "silence": 1}, "last": {"endless": ["silence", "rush"]}}
	save.save_data()
	save.reset_progress()
	check(save.danger.is_empty(), "a fresh player has no contract history")
	check(save.load_data() == "main", "the contract save loads")
	check(save.danger.done.rush == 3 and save.danger.done.silence == 1 and D.recall("endless") == ["silence", "rush"], "contract history survives a save and load")
	save.danger = {"done": {"rush": 1}}
	save.merge_remote({"danger": {"done": {"rush": 5, "cold": 2, "bogus": 7}}})
	check(save.danger.done.rush == 5 and save.danger.done.cold == 2 and not save.danger.done.has("bogus"), "cloud merge keeps the best counts and ignores unknown contracts")
	save.remove_files(p)
	save.path = keep_path
	save.reset_progress()
	_reset_progress()
	save.unlocked = 30
	check(D.unlocked(), "contracts unlock after the first boss")
	save.unlocked = 10
	check(not D.unlocked(), "contracts stay locked before the first boss")
	save.unlocked = 30

	# --- Effects in a real run ---
	var base = await _new_game(_level(3))
	_step(base, 2.2)
	var base_hull: int = base.max_hull
	var base_bullet: float = base.bullet_mult
	var base_fire: float = base.fire_mult_enemy
	var base_elite: float = base.elite_chance
	check(base.danger.is_empty() and not base.nova_sealed and is_equal_approx(base.danger_pace, 1.0), "a run without contracts is untouched")
	base.queue_free()
	await process_frame

	var game = await _new_game(_dsession(3, ["fragile"]))
	check(game.max_hull == maxi(1, base_hull - 1) and game.hull == game.max_hull, "Fragile Hull removes one hull")
	game.queue_free()
	await process_frame
	game = await _new_game(_dsession(3, ["hostiles"]))
	check(is_equal_approx(game.bullet_mult, base_bullet * 1.15) and is_equal_approx(game.fire_mult_enemy, base_fire * 1.2), "Overclocked Hostiles speeds up enemy fire")
	game.queue_free()
	await process_frame
	game = await _new_game(_dsession(3, ["elite_signal"]))
	check(game.elite_chance >= 0.25 and game.elite_chance > base_elite, "Elite Signal raises the elite chance")
	game.queue_free()
	await process_frame
	game = await _new_game(_dsession(3, ["rush", "cold"]))
	check(is_equal_approx(game.danger_pace, 1.3) and is_equal_approx(game.danger_regen, 0.5), "Rush speeds up waves and Cold Reactor slows the shield")
	game.queue_free()
	await process_frame
	game = await _new_game(_dsession(3, ["silence"]))
	_step(game, 2.2)
	game.energy = 100.0
	var nova_before: int = int(save.stats.get("nova", 0))
	game.try_nova()
	check(game.nova_sealed and game.energy == 100.0 and int(save.stats.get("nova", 0)) == nova_before, "Nova Silence seals Nova Burst")
	game.queue_free()
	await process_frame
	game = await _new_game(_dsession(3, ["lean"]))
	game._begin_upgrade()
	check(game.card_options.size() == 2 and game.rerolls == 0, "Lean Loadout offers one fewer module and no rerolls")
	game.queue_free()
	await process_frame
	game = await _new_game(_dsession(3, ["elite_signal", "rush"], ["elites"]))
	check(game.danger == ["rush"], "a conflicting contract is dropped, never stacked with its dial")
	game.queue_free()
	await process_frame
	game = await _new_game(_dsession(3, ["bogus", "rush", "rush"]))
	check(game.danger == ["rush"], "a damaged session cannot smuggle in unknown or doubled contracts")
	game.queue_free()
	await process_frame

	# --- A successful run pays exactly what the card promised ---
	var control = await _new_game(_level(3))
	control.phase = control.Phase.PLAYING
	control.run_salvage = 100
	control.kills = 0
	control._level_complete()
	var control_parts: int = control.result_parts
	var control_xp: int = control.result_pilot_xp
	var control_salvage: int = control.run_salvage
	check(control.danger_paid.is_empty() and control.rewards.filter(func(r): return str(r.title) == "DANGER BONUS").is_empty(), "no contract, no bonus line")
	control.queue_free()
	await process_frame
	var done_before: int = D.total_done()
	var won = await _new_game(_dsession(3, ["rush", "hostiles"]))
	won.phase = won.Phase.PLAYING
	won.run_salvage = 100
	won.kills = 0
	var loot_before: int = (won.loot as Array).size()
	won._level_complete()
	var pay: Dictionary = D.rewards(["rush", "hostiles"])
	var pre: int = 100 + won.result_reward
	check(won.run_salvage == pre + int(float(pre) * float(pay.salvage)), "salvage bonus is exactly the promised share")
	check(won.result_parts == int(float(control_parts) * (1.0 + float(pay.parts))), "parts bonus is exactly the promised share (%d vs %d)" % [won.result_parts, control_parts])
	check(won.result_pilot_xp >= control_xp and won.result_pilot_xp == int(float(control_xp) * (1.0 + float(pay.xp))), "pilot XP bonus is exactly the promised share")
	check(str(won.rewards[0].title) == "DANGER BONUS", "the results screen leads with the contract bonus")
	check(D.total_done() == done_before + 2 and D.done_count("rush") >= 1 and D.recall("campaign") == ["rush", "hostiles"], "completion is recorded and remembered")
	check(save.stats.get("danger_clear", 0) >= 1 and save.stats.get("danger_double", 0) >= 1, "completion feeds achievements")
	check(won.danger_paid.size() > 0 and won.result_win, "the run was paid once")
	won.queue_free()
	await process_frame
	var silent = await _new_game(_dsession(3, ["silence"]))
	silent.phase = silent.Phase.PLAYING
	silent._level_complete()
	var best := 0
	for it in silent.loot:
		best = maxi(best, int(it.rarity))
	check(best >= gear_db.EPIC, "Nova Silence pays an Epic or better gear drop")
	silent.queue_free()
	await process_frame

	# --- A lost run costs nothing extra and pays nothing extra ---
	var lost = await _new_game(_dsession(3, ["fragile", "hostiles"]))
	lost.run_salvage = 100
	var tally: int = D.total_done()
	lost._show_defeat()
	check(lost.danger_paid.is_empty() and D.total_done() == tally, "a loss pays no bonus and records no completion")
	check(lost.run_salvage == 100 + int(lost.level.reward) / 4, "a loss multiplies nothing")
	check(not lost.rewards.filter(func(r): return str(r.title) == "CONTRACT NOT COMPLETED").is_empty(), "a loss says so kindly")
	lost.queue_free()
	await process_frame

	# --- The Rift: bonus drops at milestones, payout once enough floors are cleared ---
	var rift_a = await _new_game({"mode": "endless", "level": 1, "mutators": [], "tier": 0})
	var rift_b = await _new_game({"mode": "endless", "level": 1, "mutators": [], "tier": 0, "danger": ["silence", "rush"]})
	rift_a._rift_floor_cleared(5)
	save.rift_claimed = []
	rift_b._rift_floor_cleared(5)
	save.rift_claimed = []
	check((rift_b.loot as Array).size() == (rift_a.loot as Array).size() + 1, "a Rift milestone adds one contract roll")
	rift_b.rift_floors = D.RIFT_MIN_FLOORS - 1
	rift_b.run_salvage = 100
	rift_b._bank()
	check(rift_b.danger_paid.is_empty(), "a short Rift run is not paid")
	rift_b.queue_free()
	var rift_c = await _new_game({"mode": "endless", "level": 1, "mutators": [], "tier": 0, "danger": ["silence", "rush"]})
	rift_c.rift_floors = D.RIFT_MIN_FLOORS
	rift_c.run_salvage = 100
	rift_c._bank()
	check(not rift_c.danger_paid.is_empty() and rift_c.run_salvage == 100 + int(100.0 * float(D.rewards(["silence", "rush"]).salvage)), "a Rift run that got far enough is paid")
	rift_a.queue_free()
	rift_c.queue_free()
	await process_frame

	# --- The screens ---
	save.unlocked = 30
	var menu = load("res://title_screen.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	var map = menu.pages.map
	map.open_level(3)
	await process_frame
	map.on_ui("danger_rush")
	map.on_ui("danger_fragile")
	map.on_ui("danger_cold")
	check(map.picker.chosen == ["rush", "fragile"], "the briefing accepts valid picks")
	check(not "cold" in map.picker.chosen, "the briefing refuses a contradicting pick and says why (%s)" % map.picker.note)
	map.on_ui("danger_rush")
	map.on_ui("danger_fragile")
	check(map.picker.chosen.is_empty(), "picks can be switched off")
	map.on_ui("danger_elite_signal")
	map.on_ui("dial_elites")
	check(not "elites" in map.dials and map.picker.chosen == ["elite_signal"], "a dial that clashes with a contract is refused")
	map.on_ui("dial_swarm")
	check("swarm" in map.dials, "dials that do not clash still work")
	map.picker.chosen = []
	map.on_ui("dial_elites")
	map.on_ui("danger_elite_signal")
	check(map.picker.chosen.is_empty() and "elites" in map.dials, "a contract that clashes with a chosen dial is refused")
	map.open_endless()
	check(map.picker.chosen.is_empty(), "each briefing starts with nothing chosen")
	# Expedition: the hard fights offer contracts, ordinary battles do not.
	load("res://src/meta/expedition.gd").start(1)
	save.expedition.layer = 1
	save.expedition.layers[1][0]["type"] = "elite"
	menu.go("expedition")
	await process_frame
	var ex = menu.pages.expedition
	ex._enter(0)
	check(ex.overlay == "danger", "an Expedition elite node offers contracts")
	ex.on_ui("danger_fragile")
	check(ex.picker.chosen.is_empty(), "Fragile Hull is refused in the Expedition")
	ex.on_ui("danger_rush")
	ex.on_ui("danger_hostiles")
	check(ex.picker.chosen == ["rush", "hostiles"], "the Expedition takes two contracts")
	ex.on_ui("danger_cancel")
	check(ex.overlay == "" and (save.expedition.current as Dictionary).is_empty(), "backing out of the Expedition offer leaves the route unchanged")
	save.expedition = {}
	# Ops: today's featured contract is opt-in.
	var ops = menu.pages.ops
	var daily: Dictionary = root.get_node("Meta").daily_challenge()
	check(ops._danger_for("daily", daily).is_empty(), "the featured daily contract is off until chosen")
	ops.on_ui("danger_daily")
	check(ops._danger_for("daily", daily) == [ops.featured_id("daily", daily)] and not ops.featured_id("daily", daily).is_empty(), "switching it on adds exactly the featured contract")
	ops.on_ui("danger_daily")
	check(ops._danger_for("daily", daily).is_empty(), "and it can be switched off again")
	save.unlocked = 5
	check(ops._danger_for("weekly", root.get_node("Meta").weekly_challenge()).is_empty(), "no contracts before the first boss")
	save.unlocked = 30
	for i in range(8):
		menu.go("map")
		menu.pages.map.open_level(3)
		await process_frame
		menu.go("expedition")
		await process_frame
		menu.go("ops")
		await process_frame
	menu.queue_free()
	await process_frame

	# Every contract completed once earns the collector achievement.
	for id in D.ORDER:
		D.record_win([id], "campaign")
	check(save.achievements.has("danger_all") and save.achievements.has("danger_1"), "completing every contract earns the achievements")
	save.danger = {}
	save.stats = {}
	save.achievements = {}
	_reset_progress()
	print("danger ok")

## A campaign session with contracts, and optionally dials.
func _dsession(n: int, picks: Array, dials := []) -> Dictionary:
	return {"mode": "campaign", "level": n, "mutators": dials, "tier": 0, "danger": picks}

## The glass interface: accessibility switches, every button still present and where it is drawn,
## scrolling that carries hit areas along, a real touch on a segmented control, and every screen
## painting under each combination of comfort settings.
func _test_glass_ui() -> void:
	var U = load("res://src/ui.gd")
	save.opt.reduced_motion = false
	save.opt.reduced_flash = false
	check(U.motion_ok() and U.flash_ok(), "motion and flashes are on by default")
	save.opt.reduced_flash = true
	check(U.motion_ok() and not U.flash_ok() and is_equal_approx(U.breathe(), 0.6), "Reduce flashes steadies every pulse but keeps motion")
	save.opt.reduced_motion = true
	check(not U.motion_ok() and not U.flash_ok() and is_equal_approx(U.breathe(), 0.6), "Reduce motion turns off ambient animation")
	save.opt.reduced_motion = false
	save.opt.reduced_flash = false
	check(is_zero_approx(U.ease_out(0.0)) and is_equal_approx(U.ease_out(1.0), 1.0) and U.ease_out(0.5) > 0.5, "easing runs from 0 to 1 and starts fast")
	for kind in [U.Kind.INFO, U.Kind.CARD, U.Kind.SELECTED, U.Kind.PRIMARY, U.Kind.DISABLED, U.Kind.REWARD, U.Kind.WARNING]:
		check(int(kind) >= 0, "panel kind exists")
	check(U.Kind.size() == 7, "seven panel kinds")

	var menu = load("res://title_screen.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	save.unlocked = 30
	# Every button a player can press is still there, with a real hit area.
	var expected := {
		"title": ["play", "hangar", "ops", "expedition", "endless", "settings"],
		"hangar": ["back", "tab_ships", "tab_gear", "tab_lab", "tab_tech", "tab_nova", "ship_nova"],
		"ops": ["back", "tab_today", "tab_awards", "tab_codex", "tab_records", "daily", "weekly"],
		"settings": ["back", "set_music_volume:0.4", "set_nova_side:left", "set_sensitivity:1.7", "set_sfx_volume:0.7"],
		"map": ["back", "prev", "next", "level1"],
		"expedition": ["back", "start1", "start2"],
	}
	for screen_name in expected:
		menu.go(screen_name)
		for i in range(6):
			await process_frame
		for id in expected[screen_name]:
			var rect: Rect2 = menu.ui.rect_of(str(id))
			check(rect.size.x >= 40.0 and rect.size.y >= 40.0, "button %s on %s keeps a touch-sized hit area" % [id, screen_name])
	menu.pages.hangar.on_ui("tab_gear")
	menu.go("hangar")
	menu.pages.hangar.on_ui("tab_gear")
	for i in range(4):
		await process_frame
	for id in ["g_scrap_low", "g_filter_all", "g_filter_weapon"]:
		check(menu.ui.rect_of(id).size.y >= 48.0, "gear button %s is present" % id)
	menu.pages.hangar.on_ui("tab_nova")
	for i in range(4):
		await process_frame
	check(menu.ui.rect_of("nova_pulse").size.y >= 100.0, "Nova row is pressable")
	menu.pages.map.open_level(3)
	for i in range(4):
		await process_frame
	for id in ["launch", "back"]:
		check(menu.ui.rect_of(id).size.x >= 80.0, "briefing button %s is present" % id)
	check(menu.ui.rect_of("danger_rush").size.y >= 90.0, "contract cards are pressable")
	check(menu.ui.rect_of("launch").end.y <= float(menu.H) - float(menu.bottom) + 1.0, "Launch stays inside the safe area")

	# Scrolling carries the hit areas with it.
	menu.go("settings")
	for i in range(5):
		await process_frame
	check(menu.ui.scroll_max > 100.0, "the settings page scrolls (%.0f)" % menu.ui.scroll_max)
	var before: Rect2 = menu.ui.rect_of("set_nova_side:left")
	menu.ui.scroll = 150.0
	for i in range(3):
		await process_frame
	var after: Rect2 = menu.ui.rect_of("set_nova_side:left")
	check(absf((before.position.y - after.position.y) - 150.0) < 1.0, "hit areas move with the scroll")
	menu.ui.scroll = 0.0
	for i in range(3):
		await process_frame
	# A real touch on a segmented control.
	var seg: Rect2 = menu.ui.rect_of("set_nova_side:left")
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.position = seg.get_center()
	down.pressed = true
	menu.ui._input(down)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.position = seg.get_center()
	up.pressed = false
	menu.ui._input(up)
	check(str(save.opt.nova_side) == "left", "touching a segment sets the option")
	menu.pages.settings.on_ui("set_nova_side:right")

	# Every screen paints under each combination of comfort settings.
	for combo in [[false, false, 1.0, false], [true, false, 1.0, false], [false, true, 1.0, true], [true, true, 1.12, true]]:
		save.opt.reduced_motion = combo[0]
		save.opt.reduced_flash = combo[1]
		save.opt.ui_scale = combo[2]
		save.opt.colorblind = combo[3]
		save.apply_display()
		for screen_name in ["title", "hangar", "map", "ops", "settings", "expedition"]:
			menu.go(screen_name)
			if screen_name == "hangar":
				for tab in ["ships", "gear", "lab", "tech", "nova"]:
					menu.pages.hangar.on_ui("tab_" + tab)
					await process_frame
					await process_frame
			for i in range(3):
				await process_frame
		check(menu.ui.rect_of("back").size.x >= 40.0 or menu.screen == "title", "screens still lay out with motion=%s flashes=%s scale=%.2f" % [str(combo[0]), str(combo[1]), combo[2]])
	save.opt.reduced_motion = false
	save.opt.reduced_flash = false
	save.opt.ui_scale = 1.0
	save.opt.colorblind = false
	save.apply_display()
	menu.queue_free()
	await process_frame
	save.unlocked = 1
	print("glass ui ok")

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
	return {"mode": "campaign", "level": n, "mutators": [], "tier": tier_arg, "danger": danger_arg.duplicate()}

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
