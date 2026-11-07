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
var checks_run := 0
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
	checks_run += 1
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
	await _test_pilot_profile()
	await _test_cloud_save()
	await _test_glass_hud()
	await _test_touch_targets()
	await _test_expedition()
	await _test_endless()
	_reset_progress()
	if not quick:
		await _play_campaign()
	print("RESULT failures=", failures, " checks=", checks_run)
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

## Every control painted on the main screens and in every combat phase, as {screen, id, rect}.
func _collect_targets() -> Array:
	var out: Array = []
	save.unlocked = 30
	save.pilot_xp = 3000
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for i in range(8):
		save.add_gear(gear_db.roll_item(rng, 12.0 + float(i), 1.0, 0, 3))
	var menu = load("res://title_screen.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	var take := func(label: String) -> void:
		_probe_touches(menu.ui, label)
		var covers: Array = (menu.ui._covers as Array).duplicate()
		for k in range(menu.ui._buttons.size()):
			var b: Dictionary = menu.ui._buttons[k]
			out.append({"screen": label, "id": str(b.id), "rect": b.rect, "index": k, "covers": covers})
	var scrolled := func(label: String, positions: Array) -> void:
		for sc in positions:
			menu.ui.scroll = float(sc)
			for i in range(3):
				await process_frame
			take.call("%s@%d" % [label, int(sc)])
		menu.ui.scroll = 0.0
	menu.go("title")
	for i in range(4):
		await process_frame
	take.call("title")
	for tab in ["ships", "gear", "lab", "tech", "nova"]:
		menu.go("hangar")
		menu.pages.hangar.on_ui("tab_" + tab)
		for i in range(4):
			await process_frame
		await scrolled.call("hangar/" + tab, [0, 500, 1000])
	for tab in ["today", "awards", "codex", "records"]:
		menu.go("ops")
		menu.pages.ops.tab = tab
		for i in range(4):
			await process_frame
		await scrolled.call("ops/" + tab, [0, 600])
	menu.go("settings")
	for i in range(4):
		await process_frame
	await scrolled.call("settings", [0, 500, 1000, 1500])
	menu.go("profile")
	for i in range(5):
		await process_frame
	await scrolled.call("profile", [0, 700, 1400, 2100])
	# The cloud section with a service signed in, and with a save to choose: its buttons are touch targets too.
	var cloud_live = root.get_node("Cloud")
	var cloud_plain = cloud_live.backend
	var cloud_mock = load("res://tools/mock_cloud.gd").new()
	var cloud_lib = load("res://src/meta/cloud_save.gd")
	cloud_mock.set_auth(cloud_lib.Auth.SIGNED_IN)
	cloud_live.forget_state()
	cloud_live.debounce = 60.0
	cloud_live.use(cloud_mock)
	for i in range(30):
		await process_frame
	menu.go("profile")
	for i in range(5):
		await process_frame
	await scrolled.call("profile/cloud", [0])
	var other_side: Dictionary = save.to_dict()
	other_side.salvage = 4
	cloud_mock.set_blob(cloud_lib.encode(other_side))
	save.salvage += 5
	save.save_data()
	cloud_live.sync_now()
	for i in range(30):
		await process_frame
	await scrolled.call("profile/choose", [0, 400])
	menu.pages.profile.on_ui("cloud_keep")
	for i in range(3):
		await process_frame
	await scrolled.call("profile/confirm", [0, 400])
	menu.pages.profile.on_ui("cloud_cancel")
	# An account change, with the choices and then its confirmation.
	cloud_mock.set_auth(cloud_lib.Auth.SIGNED_OUT)
	cloud_mock.set_account("acct-B")
	cloud_mock.set_blob(cloud_lib.encode(other_side))
	cloud_mock.set_auth(cloud_lib.Auth.SIGNED_IN)
	for i in range(30):
		await process_frame
	await scrolled.call("profile/account", [0, 400])
	menu.pages.profile.on_ui("cloud_acct_cloud")
	for i in range(3):
		await process_frame
	await scrolled.call("profile/account-confirm", [0, 400])
	menu.pages.profile.on_ui("cloud_acct_cancel")
	cloud_live.use(cloud_plain)
	cloud_live.forget_state()
	cloud_live.debounce = cloud_live.DEBOUNCE
	menu.go("profile")
	save.map_sector = 3
	menu.go("map")
	for i in range(4):
		await process_frame
	take.call("map")
	menu.pages.map.open_level(23)
	for i in range(4):
		await process_frame
	await scrolled.call("briefing", [0, 500, 1000])
	menu.go("loadout")
	for i in range(4):
		await process_frame
	await scrolled.call("loadout", [0, 600])
	menu.go("expedition")
	for i in range(4):
		await process_frame
	take.call("expedition/sectors")
	load("res://src/meta/expedition.gd").start(1)
	save.expedition.layer = 1
	save.expedition.layers[1][0]["type"] = "elite"
	menu.go("expedition")
	for i in range(4):
		await process_frame
	take.call("expedition/route")
	menu.pages.expedition._enter(0)
	for i in range(4):
		await process_frame
	await scrolled.call("expedition/contracts", [0, 500])
	menu.pages.expedition.overlay = "depot"
	for i in range(3):
		await process_frame
	take.call("expedition/depot")
	menu.pages.expedition.overlay = "signal"
	menu.pages.expedition.signal_event = load("res://src/meta/expedition.gd").SIGNALS[0]
	for i in range(3):
		await process_frame
	take.call("expedition/signal")
	menu.pages.expedition.overlay = ""
	save.expedition = {}
	menu.queue_free()
	await process_frame

	# Combat: playing with Nova ready, the upgrade cards, pause, results and defeat.
	var phases := ["play", "cards", "pause", "results", "defeat"]
	for which in phases:
		var game = await _new_game(_level(3))
		_step(game, 2.4)
		match which:
			"play":
				game.energy = 100.0
			"cards":
				game._begin_upgrade()
				game.phase_t = 2.0
				game.input_lock = 0.0
			"pause":
				game.set_paused(true)
			"results":
				game.phase = game.Phase.PLAYING
				game._level_complete()
				game.phase_t = 3.0
			"defeat":
				game._show_defeat()
				game.phase_t = 3.0
		for i in range(4):
			await process_frame
		_probe_touches(game.ui, "combat/" + which)
		var game_covers: Array = (game.ui._covers as Array).duplicate()
		for k in range(game.ui._buttons.size()):
			var gb: Dictionary = game.ui._buttons[k]
			out.append({"screen": "combat/" + which, "id": str(gb.id), "rect": gb.rect, "index": k, "covers": game_covers})
		game.queue_free()
		await process_frame
	save.unlocked = 1
	save.gear = []
	save.pilot_xp = 0
	return out

## Touch targets. The layout is `logical width` units wide on every phone, so what a control is on a real device
## depends on the phone: one unit is width_dp / 720 dp. These are checks in layout units with the dp conversion
## printed next to them. They are simulated touches, not proof that a thumb will find a control on a real phone.
const TOUCH_PROFILES := [["compact", 360.0], ["typical", 411.0]]
var touch_probes := 0
var touch_issues: Array = []

## Probes one painted screen with the real hit test: a touch inside a control must reach a control that
## contains it, and a touch in a margin must reach the nearest control whose enlarged area contains it.
func _probe_touches(ui, label: String) -> void:
	var UL = load("res://src/ui_layer.gd")
	var list: Array = ui._buttons
	for i in range(list.size()):
		var r: Rect2 = list[i].rect
		if r.size.x < 1.0 or r.end.y < 0.0 or r.position.y > 1280.0:
			continue
		var inside := [r.get_center(), r.position + Vector2(3.0, 3.0), Vector2(r.end.x - 3.0, r.position.y + 3.0), Vector2(r.position.x + 3.0, r.end.y - 3.0), r.end - Vector2(3.0, 3.0)]
		for p in inside:
			if ui._covered(i, p):
				continue
			touch_probes += 1
			var hit: Dictionary = ui._find(p)
			if hit.is_empty() or not (hit.rect as Rect2).has_point(p):
				touch_issues.append("%s: a touch inside %s did not reach a control under it" % [label, str(list[i].id)])
		for side in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
			var q: Vector2 = r.get_center() + Vector2(side.x * (r.size.x * 0.5 + 8.0), side.y * (r.size.y * 0.5 + 8.0))
			if ui._covered(i, q):
				continue
			touch_probes += 1
			var margin_hit: Dictionary = ui._find(q)
			if margin_hit.is_empty() or (margin_hit.rect as Rect2).has_point(q):
				continue
			var found_d: float = UL.margin_distance(margin_hit, q)
			if not UL.touch_rect(margin_hit.rect, ui._min_touch).has_point(q):
				touch_issues.append("%s: a margin touch near %s reached %s outside its touch area" % [label, str(list[i].id), str(margin_hit.id)])
			for j in range(list.size()):
				var other: Rect2 = list[j].rect
				if UL.touch_rect(other, ui._min_touch).has_point(q) and not ui._covered(j, q) and UL.margin_distance(list[j], q) < found_d - 0.01:
					touch_issues.append("%s: a margin touch near %s skipped the nearer control %s" % [label, str(list[i].id), str(list[j].id)])
					break

func _test_touch_targets() -> void:
	touch_probes = 0
	touch_issues = []
	var targets: Array = await _collect_targets()
	var ui_layer = load("res://src/ui_layer.gd")
	# The minimum follows the device: 48 dp on every profile.
	check(is_equal_approx(ui_layer.min_touch_for(360.0, 720.0), 96.0), "a 360 dp phone needs 96 units for 48 dp")
	check(absf(ui_layer.min_touch_for(411.0, 720.0) - 84.09) < 0.05, "a 411 dp phone needs about 84 units for 48 dp")
	check(is_equal_approx(ui_layer.min_touch_for(320.0, 720.0), 108.0), "a 320 dp phone needs 108 units")
	check(is_equal_approx(ui_layer.min_touch_for(800.0, 720.0), ui_layer.MIN_UNITS) and is_equal_approx(ui_layer.min_touch_for(150.0, 720.0), ui_layer.MAX_UNITS), "the minimum stays between its floor and its ceiling")
	check(ui_layer.min_touch_for(411.0, 800.0) > ui_layer.min_touch_for(411.0, 720.0), "a wider layout means smaller units, so more of them")
	var probe_ui = ui_layer.new()
	ui_layer.width_dp_override = 0.0
	check(is_equal_approx(probe_ui.device_width_dp(), ui_layer.COMPACT_DP), "a desktop assumes the stricter 360 dp phone")
	ui_layer.width_dp_override = 411.0
	check(is_equal_approx(probe_ui.device_width_dp(), 411.0), "the width can be overridden for tests")
	check(absf(ui_layer.min_touch_for(probe_ui.device_width_dp(), probe_ui.layout_width()) - 84.09) < 0.05, "the override feeds the minimum the way a real 411 dp phone would")
	ui_layer.width_dp_override = 360.0
	check(is_equal_approx(ui_layer.min_touch_for(probe_ui.device_width_dp(), probe_ui.layout_width()), 96.0), "and a 360 dp phone gets 96 units")
	ui_layer.width_dp_override = 0.0
	probe_ui.free()
	# Every control on every screen, for both device profiles.
	var seen := {}
	var checked := 0
	var worst := {}
	for p in TOUCH_PROFILES:
		worst[p[0]] = 999.0
	for t in targets:
		var r: Rect2 = t.rect
		if r.size.x < 1.0 or r.size.y < 1.0 or r.end.y < 0.0 or r.position.y > 1280.0:
			continue
		var key := "%s|%s" % [t.screen, t.id]
		if seen.has(key):
			continue
		seen[key] = true
		checked += 1
		for p in TOUCH_PROFILES:
			var need: float = ui_layer.min_touch_for(float(p[1]), 720.0)
			var eff: Rect2 = ui_layer.touch_rect(r, need)
			var dp_per_unit: float = float(p[1]) / 720.0
			var side_dp: float = minf(eff.size.x, eff.size.y) * dp_per_unit
			worst[p[0]] = minf(float(worst[p[0]]), side_dp)
			check(side_dp >= 47.9, "touch area of %s is %.1f dp on a %.0f dp phone (48 needed)" % [key, side_dp, float(p[1])])
	check(checked > 150, "the touch audit looked at enough controls (%d)" % checked)
	check(touch_probes > 3000, "the touch probes ran (%d)" % touch_probes)
	for issue in touch_issues.slice(0, 8):
		check(false, str(issue))
	check(touch_issues.is_empty(), "no touch probe reached the wrong control (%d problems in %d probes)" % [touch_issues.size(), touch_probes])
	print("touch targets: %d controls, smallest effective area %.1f dp (360 dp phone) and %.1f dp (411 dp phone); %d probes, %d problems" % [checked, float(worst["compact"]), float(worst["typical"]), touch_probes, touch_issues.size()])

	# The hit test on synthetic neighbours.
	var ui = ui_layer.new()
	ui._min_touch = 96.0
	var add := func(id: String, rect: Rect2) -> void:
		ui._buttons.append({"id": id, "rect": rect})
	add.call("a", Rect2(0, 0, 100, 40))
	add.call("b", Rect2(106, 0, 100, 40))   # six units to the right of a
	add.call("c", Rect2(0, 50, 100, 40))    # ten units below a: their enlarged areas overlap
	var id_at := func(x: float, y: float) -> String:
		return str(ui._find(Vector2(x, y)).get("id", ""))
	check(id_at.call(99.0, 20.0) == "a" and id_at.call(106.5, 20.0) == "b", "a direct touch beside a gap goes to the control under it")
	check(id_at.call(104.0, 20.0) == "b" and id_at.call(102.0, 20.0) == "a", "a touch in a gap goes to the nearer control")
	check(id_at.call(50.0, 43.0) == "a" and id_at.call(50.0, 47.0) == "c", "enlarged areas that overlap split at the halfway line")
	check(id_at.call(50.0, 39.0) == "a" and id_at.call(50.0, 51.0) == "c", "a direct touch is never taken by a neighbour's margin")
	check(id_at.call(50.0, 20.0 - 60.0) == "", "a touch far from everything reaches nothing")
	# A destructive control gives way in the gap beside a safe one.
	ui._buttons.clear()
	add.call("equip", Rect2(0, 0, 150, 62))
	ui._buttons.append({"id": "scrap", "rect": Rect2(0, 72, 150, 62), "careful": true})
	check(id_at.call(75.0, 61.0) == "equip" and id_at.call(75.0, 73.0) == "scrap", "a direct touch on either button still reaches it")
	check(id_at.call(75.0, 68.0) == "equip" and id_at.call(75.0, 70.0) == "equip", "a loose touch in the gap goes to the safe button, not the destructive one")
	check(id_at.call(75.0, 134.0 + 14.0) == "scrap", "away from the neighbour the destructive button keeps its margin")
	# Adjacent segments with no gap, like a segmented control.
	ui._buttons.clear()
	add.call("s0", Rect2(0, 0, 100, 54))
	add.call("s1", Rect2(100, 0, 100, 54))
	add.call("s2", Rect2(200, 0, 100, 54))
	check(id_at.call(99.0, 27.0) == "s0" and id_at.call(100.5, 27.0) == "s1" and id_at.call(199.0, 27.0) == "s1" and id_at.call(201.0, 27.0) == "s2", "adjacent segments keep their exact boundaries (no slop leaks across)")
	check(id_at.call(150.0, 54.0 + 18.0) == "s1" and id_at.call(150.0, -18.0) == "s1", "a touch above or below a segment reaches it")
	check(id_at.call(150.0, 54.0 + 60.0) == "", "but not from far away")
	# A card with a small button inside, and a control scrolled under a strip.
	ui._buttons.clear()
	add.call("card", Rect2(0, 100, 300, 120))
	add.call("btn", Rect2(200, 110, 80, 40))
	check(id_at.call(240.0, 130.0) == "btn" and id_at.call(100.0, 130.0) == "card", "a button on a card beats the card directly under it")
	check(id_at.call(240.0, 156.0) == "card", "below the button, in the card, the card is a direct touch and wins over the button's margin")
	ui._buttons.clear()
	ui._covers.clear()
	add.call("hidden", Rect2(0, 0, 300, 100))
	ui.cover(Rect2(0, 0, 300, 60))
	add.call("tab", Rect2(100, 10, 80, 40))
	check(id_at.call(20.0, 30.0) == "" and id_at.call(150.0, 30.0) == "tab", "a control that slid under an opaque strip stops answering inside the strip")
	check(id_at.call(20.0, 80.0) == "hidden", "and answers again below it")
	ui.free()

	# The real screens: segments, chips, tabs and the strips above scrolled content.
	var menu = load("res://title_screen.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	menu.go("settings")
	for i in range(5):
		await process_frame
	var seg: Rect2 = menu.ui.rect_of("set_nova_side:left")
	var seg2: Rect2 = menu.ui.rect_of("set_nova_side:right")
	var uip = menu.ui
	check(str(uip._find(Vector2(seg.end.x - 1.0, seg.get_center().y)).get("id", "")) == "set_nova_side:left" and str(uip._find(Vector2(seg2.position.x + 1.0, seg2.get_center().y)).get("id", "")) == "set_nova_side:right", "settings segments split exactly at their edge")
	check(str(uip._find(Vector2(seg.get_center().x, seg.end.y + 12.0)).get("id", "")) == "set_nova_side:left", "a touch 12 units below a segment reaches it")
	var next_row: Rect2 = menu.ui.rect_of("set_nova_double_tap:false")
	var mid_y := (seg.end.y + next_row.position.y) * 0.5
	check(str(uip._find(Vector2(seg.get_center().x, mid_y)).get("id", "")) == "", "halfway between two settings rows nothing is selected")
	var gear_rng := RandomNumberGenerator.new()
	gear_rng.seed = 5
	for i in range(3):
		save.add_gear(gear_db.roll_item(gear_rng, 10.0 + float(i), 0.5, 0, 0))
	menu.go("hangar")
	menu.pages.hangar.on_ui("tab_gear")
	for i in range(5):
		await process_frame
	# On a real gear card, the loose gap between EQUIP and SCRAP belongs to EQUIP.
	var equip_rect := Rect2()
	var scrap_rect := Rect2()
	for gb in menu.ui._buttons:
		var gid := str(gb.id)
		if gid.begins_with("g_equip_") and equip_rect.size.x == 0.0:
			equip_rect = gb.rect
			scrap_rect = menu.ui.rect_of("g_scrap_" + gid.substr(8))
	if equip_rect.size.x > 0.0 and scrap_rect.size.x > 0.0:
		var gap := scrap_rect.position.y - equip_rect.end.y
		var cx := equip_rect.get_center().x
		check(str(uip._find(Vector2(cx, equip_rect.end.y - 2.0)).get("id", "")).begins_with("g_equip_") and str(uip._find(Vector2(cx, scrap_rect.position.y + 2.0)).get("id", "")).begins_with("g_scrap_"), "EQUIP and SCRAP each answer a direct touch next to each other")
		check(str(uip._find(Vector2(cx, equip_rect.end.y + gap * 0.5)).get("id", "")).begins_with("g_equip_"), "a loose touch halfway in the gap goes to EQUIP, not SCRAP (gap %.0f units)" % gap)
	save.gear = []
	var tab_gear: Rect2 = menu.ui.rect_of("tab_gear")
	var tab_lab: Rect2 = menu.ui.rect_of("tab_lab")
	check(str(uip._find(Vector2(tab_gear.end.x - 1.0, tab_gear.get_center().y)).get("id", "")) == "tab_gear" and str(uip._find(Vector2(tab_lab.position.x + 1.0, tab_lab.get_center().y)).get("id", "")) == "tab_lab", "Hangar tabs split exactly at their edge")
	var gap_x := (tab_gear.end.x + tab_lab.position.x) * 0.5
	var gap_hit := str(uip._find(Vector2(gap_x - 1.0, tab_gear.get_center().y)).get("id", ""))
	check(gap_hit == "tab_gear" and str(uip._find(Vector2(gap_x + 1.0, tab_gear.get_center().y)).get("id", "")) == "tab_lab", "a touch in the gap between tabs goes to the nearer tab")
	var chips: Array = ["g_filter_all", "g_filter_weapon", "g_filter_reactor", "g_filter_plating"]
	var all_there := true
	for id in chips:
		if menu.ui.rect_of(id).size.x < 1.0:
			all_there = false
	menu.ui.scroll = 480.0
	for i in range(3):
		await process_frame
	for id in chips:
		var cr: Rect2 = menu.ui.rect_of(id)
		if cr.size.x > 0.0 and cr.position.y > 400.0 and cr.end.y < 1200.0:
			check(str(uip._find(cr.get_center()).get("id", "")) == id and str(uip._find(Vector2(cr.get_center().x, cr.end.y + 14.0)).get("id", "")) in [id, "g_equip_" + id], "Gear filter chip %s answers a touch on it and just under it" % id)
	# Content scrolled under the tab strip must not answer touches in the strip.
	menu.pages.hangar.on_ui("tab_ships")
	menu.ui.scroll = 0.0
	for i in range(4):
		await process_frame
	var strip_top: float = float(menu.top) + 178.0
	menu.ui.scroll = 300.0
	for i in range(4):
		await process_frame
	var ship: Rect2 = menu.ui.rect_of("ship_nova")
	if ship.size.x > 0.0 and ship.position.y < strip_top + 30.0 and ship.end.y > strip_top + 30.0:
		var under := Vector2(gap_x, strip_top + 36.0)
		var strip_hit := str(uip._find(under).get("id", ""))
		check(not strip_hit.begins_with("ship_"), "a ship card scrolled under the tab strip does not answer touches in the strip (%s)" % strip_hit)
	menu.queue_free()
	await process_frame
	print("touch targets ok")

## Combat, phase by phase: the glass pieces draw, and every control still does its job when touched.
func _test_glass_hud() -> void:
	var touch := func(game, id: String) -> void:
		var rect: Rect2 = game.ui.rect_of(id)
		var down := InputEventScreenTouch.new()
		down.index = 0
		down.position = rect.get_center()
		down.pressed = true
		game.ui._input(down)
		var up := InputEventScreenTouch.new()
		up.index = 0
		up.position = rect.get_center()
		up.pressed = false
		game.ui._input(up)
	var frames := func(n: int) -> void:
		for i in range(n):
			await process_frame
	var game = await _new_game(_level(3))
	var P = game.Phase
	_step(game, 2.4)
	await frames.call(3)
	check(game.phase == P.PLAYING, "the flight is under way")
	check(game.ui.rect_of("pause").size.x >= 70.0, "the pause button is drawn and pressable")
	game.energy = 100.0
	await frames.call(3)
	check(game.ui.rect_of("burst").size.x >= 120.0, "the Nova disc is pressable when full")
	game.energy = 40.0
	await frames.call(3)
	check(game.ui.rect_of("burst").size.x == 0.0, "the Nova disc cannot be pressed while charging")
	# Pause and resume through real touches.
	await touch.call(game, "pause")
	check(game.phase == P.PAUSED, "touching pause pauses")
	await frames.call(3)
	for id in ["resume", "retry", "music", "sound", "map"]:
		check(game.ui.rect_of(id).size.y >= 80.0, "pause menu button %s is drawn" % id)
	check(game.ui.rect_of("resume").end.y < float(game.H) - float(game.inset.y), "the pause menu fits the screen")
	var music_before: float = float(save.opt.music_volume)
	game.input_lock = 0.0 # controls ignore touches for a tenth of a second after pausing; wait that out
	await touch.call(game, "music")
	check(float(save.opt.music_volume) != music_before, "the music toggle works from the glass pause menu")
	await touch.call(game, "music")
	await touch.call(game, "resume")
	check(game.phase == P.RESUME, "touching resume starts the countdown")
	await frames.call(3)
	_step(game, 1.2)
	check(game.phase == P.PLAYING, "the flight carries on after the countdown")
	# Module selection.
	game._begin_upgrade()
	game.phase_t = 2.0
	game.input_lock = 0.0
	await frames.call(4)
	check(game.phase == P.UPGRADE and game.card_options.size() >= 2, "the upgrade screen opens")
	for i in range(game.card_options.size()):
		check(game.ui.rect_of("card%d" % i).size.y >= 150.0, "upgrade card %d is drawn and pressable" % i)
	var held_before: int = (game.held as Dictionary).size()
	await touch.call(game, "card0")
	check(game.card_picked == 0, "touching a card picks it")
	game.queue_free()
	await process_frame
	# Boss encounter.
	game = await _new_game(_level(10))
	game.level.waves[0] = []
	var guard := 0
	while game.boss == null and guard < 400:
		game._process(STEP)
		guard += 1
	check(game.boss != null, "the boss arrives")
	_step(game, 2.0)
	await frames.call(3)
	check(game.ui.rect_of("pause").size.x >= 70.0, "the pause button is there during the boss fight")
	game.queue_free()
	await process_frame
	# Victory.
	game = await _new_game(_level(3))
	_step(game, 2.4)
	game.phase = game.Phase.PLAYING
	game._level_complete()
	game.phase_t = 3.0
	await frames.call(4)
	for id in ["next", "retry", "hangar"]:
		var r: Rect2 = game.ui.rect_of(id)
		check(r.size.x >= 200.0 and r.end.y <= float(game.H) - float(game.inset.y), "results button %s is drawn inside the screen" % id)
	game.queue_free()
	await process_frame
	# Defeat.
	game = await _new_game(_level(3))
	_step(game, 2.4)
	game._show_defeat()
	game.phase_t = 3.0
	await frames.call(4)
	for id in ["retry", "hangar"]:
		var r2: Rect2 = game.ui.rect_of(id)
		check(r2.size.x >= 200.0 and r2.end.y <= float(game.H) - float(game.inset.y), "defeat button %s is drawn inside the screen" % id)
	game.queue_free()
	await process_frame
	# The same screens under each comfort setting.
	for combo in [[true, false, 1.0, false], [false, true, 1.0, false], [false, false, 1.12, false], [true, true, 1.12, true]]:
		save.opt.reduced_motion = combo[0]
		save.opt.reduced_flash = combo[1]
		save.opt.ui_scale = combo[2]
		save.opt.colorblind = combo[3]
		save.apply_display()
		for which in ["play", "cards", "pause", "results", "defeat"]:
			game = await _new_game(_level(3))
			_step(game, 2.4)
			match which:
				"cards":
					game._begin_upgrade()
					game.phase_t = 2.0
				"pause":
					game.set_paused(true)
				"results":
					game.phase = game.Phase.PLAYING
					game._level_complete()
					game.phase_t = 3.0
				"defeat":
					game._show_defeat()
					game.phase_t = 3.0
			await frames.call(3)
			var any := false
			for b in game.ui._buttons:
				any = true
			check(any, "%s screen has controls with motion=%s flashes=%s scale=%.2f" % [which, str(combo[0]), str(combo[1]), combo[2]])
			game.queue_free()
			await process_frame
	save.opt.reduced_motion = false
	save.opt.reduced_flash = false
	save.opt.ui_scale = 1.0
	save.opt.colorblind = false
	save.apply_display()
	print("glass hud ok")

## The Pilot Profile: the numbers behind it (Pilot is the single source), the page itself (read back from what it
## really painted), the chip that opens it, rewards that match what grant() pays, and the comfort settings.
func _test_pilot_profile() -> void:
	var P = load("res://src/data/pilot.gd")
	var U = load("res://src/ui.gd")
	var rarity_rare: int = gear_db.RARE
	var rarity_epic: int = gear_db.EPIC
	# --- The XP curve is untouched ---
	check(P.need(1) == 125 and P.need(12) == 400 and P.need(100) == 2600, "the XP curve is unchanged")
	check(P.xp_at_level_start(1) == 0 and P.xp_at_level_start(5) == 125 + 150 + 175 + 200, "XP at the start of a level adds up the curve")
	for lv in [1, 2, 5, 12, 40, 100, 150]:
		var start: int = P.xp_at_level_start(lv)
		check(int(P.level_of(start).level) == lv and int(P.level_of(start).into) == 0, "level %d starts at its XP total" % lv)
		check(int(P.level_of(start + P.need(lv) - 1).level) == lv and int(P.level_of(start + P.need(lv)).level) == lv + 1, "level %d ends one XP before the next" % lv)
	# --- What a level pays ---
	var r13: Dictionary = P.reward_for(13)
	check(int(r13.salvage) == 72 and int(r13.parts) == 11 and int(r13.gear) == -1, "level 13 pays 72 salvage, 11 parts and no gear")
	check(int(P.reward_for(12).parts) == 11 and int(P.reward_for(11).parts) == 10, "parts use the same whole-number halving as before")
	check(int(P.reward_for(5).gear) == rarity_rare and int(P.reward_for(10).gear) == rarity_epic and int(P.reward_for(15).gear) == rarity_rare and int(P.reward_for(20).gear) == rarity_epic, "gear comes every fifth level: Rare, and Epic on every tenth")
	check(int(P.reward_for(7).gear) == -1 and int(P.reward_for(101).gear) == -1 and int(P.reward_for(105).gear) == rarity_rare, "other levels, including past 100, follow the same rule")
	check(int(P.next_gear_level(12).level) == 15 and int(P.next_gear_level(12).rarity) == rarity_rare and int(P.next_gear_level(15).level) == 20 and int(P.next_gear_level(15).rarity) == rarity_epic, "the next gear levels after 12 and 15")
	# --- Permanent bonuses ---
	check(is_equal_approx(P.dmg_bonus_at(1), 1.003) and is_equal_approx(P.dmg_bonus_at(50), 1.15) and is_equal_approx(P.dmg_bonus_at(100), 1.3), "damage bonus is +0.3% a level")
	check(is_equal_approx(P.dmg_bonus_at(150), 1.3) and is_equal_approx(P.shield_bonus_at(100), 50.0) and is_equal_approx(P.shield_bonus_at(250), 50.0), "both bonuses stop at level 100")
	for lv in [1, 12, 99, 100, 101, 140]:
		save.pilot_xp = P.xp_at_level_start(lv)
		check(is_equal_approx(P.dmg_bonus(), P.dmg_bonus_at(lv)) and is_equal_approx(P.shield_bonus(), P.shield_bonus_at(lv)), "combat uses the same bonuses at level %d" % lv)
	var g99: Dictionary = P.bonus_gain(99)
	var g100: Dictionary = P.bonus_gain(100)
	var g101: Dictionary = P.bonus_gain(101)
	check(is_equal_approx(float(g99.dmg), 0.003) and is_equal_approx(float(g99.shield), 0.5) and not bool(g99.maxed), "reaching level 99 still adds bonus")
	check(is_equal_approx(float(g100.dmg), 0.003) and is_equal_approx(float(g100.shield), 0.5) and not bool(g100.maxed), "reaching level 100 adds the last of the bonus")
	check(is_zero_approx(float(g101.dmg)) and is_zero_approx(float(g101.shield)) and bool(g101.maxed), "reaching level 101 adds nothing: maxed")
	# --- Milestones are relative to the current level ---
	var ms: Array = load("res://src/menus/menu_profile.gd").new(null).milestones(12)
	var got: Array = []
	for item in ms:
		got.append([str(item.kind), int(item.level)])
	check(got == [["next", 13], ["gear", 15], ["gear", 20], ["gear", 25], ["cap", 100]], "milestones from level 12 (%s)" % str(got))
	check(int(ms[1].rarity) == rarity_rare and int(ms[2].rarity) == rarity_epic and int(ms[3].rarity) == rarity_rare, "and their rarities")
	for lv in [1, 4, 9, 12, 24, 98, 99, 100, 101, 250]:
		var list: Array = load("res://src/menus/menu_profile.gd").new(null).milestones(lv)
		var levels: Array = []
		var past := false
		for item in list:
			levels.append(int(item.level))
			if int(item.level) <= lv:
				past = true
		check(not past, "no milestone at or below level %d is offered as upcoming %s" % [lv, str(levels)])
		var dup := {}
		for lvl in levels:
			check(not dup.has(lvl), "milestone levels are not repeated from level %d" % lv)
			dup[lvl] = true
		var at_cap := 0
		for item in list:
			if int(item.level) == P.BONUS_CAP:
				at_cap += 1
		check(at_cap == (1 if lv < P.BONUS_CAP else 0), "level 100 is listed exactly once while it is ahead, and never after (level %d)" % lv)

	# --- grant() pays exactly what the preview promises, across several levels at once ---
	# (the pilot-level achievements pay salvage too, so they are marked as already earned)
	save.achievements = {"pilot_10": true, "pilot_50": true}
	for case in [[1, 600], [3, 1300], [4, 3000], [9, 200], [98, 9000], [100, 4000]]:
		save.pilot_xp = P.xp_at_level_start(int(case[0]))
		var salvage_before: int = save.salvage
		var parts_before: int = save.parts
		var gear_before: int = save.gear.size()
		var result: Dictionary = P.grant(int(case[1]))
		var after_level: int = int(P.level_of(save.pilot_xp).level)
		var want_salvage := 0
		var want_parts := 0
		var want_gear: Array = []
		for lv in range(int(case[0]) + 1, after_level + 1):
			var pay: Dictionary = P.reward_for(lv)
			want_salvage += int(pay.salvage)
			want_parts += int(pay.parts)
			if int(pay.gear) >= 0:
				want_gear.append(int(pay.gear))
		check(int(result.levels) == after_level - int(case[0]), "grant counts %d levels gained from level %d" % [int(result.levels), int(case[0])])
		check(save.salvage - salvage_before == want_salvage and save.parts - parts_before == want_parts, "grant paid the previewed salvage and parts from level %d (%d / %d)" % [int(case[0]), want_salvage, want_parts])
		check((result.items as Array).size() == want_gear.size() and save.gear.size() - gear_before == want_gear.size(), "grant paid the previewed gear drops from level %d" % int(case[0]))
		for k in range(want_gear.size()):
			check(int(result.items[k].rarity) >= want_gear[k], "gear drop %d is at least the previewed rarity" % k)
		if after_level > int(case[0]):
			check(str(result.rewards[0].detail) == "+%d salvage  +%d parts" % [want_salvage, want_parts], "the results line matches the preview")
	save.gear = []
	save.salvage = 0
	save.parts = 0
	save.achievements = {}

	# --- The title chip opens the profile, and Back returns ---
	save.pilot_xp = P.xp_at_level_start(12) + 260
	var menu = load("res://title_screen.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	menu.go("title")
	for i in range(4):
		await process_frame
	var chip: Rect2 = menu.ui.rect_of("profile")
	check(is_equal_approx(chip.size.x, 190.0) and is_equal_approx(chip.size.y, 56.0) and is_equal_approx(chip.position.x, 20.0), "the Pilot chip keeps its size and place (%s)" % str(chip))
	var settings_rect: Rect2 = menu.ui.rect_of("settings")
	check(not chip.intersects(settings_rect), "the chip does not run into the settings button")
	await _press_id(menu.ui, "profile")
	check(menu.screen == "profile", "touching the Pilot chip opens the profile")
	for i in range(5):
		await process_frame
	check(menu.ui.rect_of("back").size.x >= 80.0, "the profile has a Back button")
	await _press_id(menu.ui, "back")
	check(menu.screen == "title", "Back returns to the title screen")
	for i in range(4):
		await process_frame
	check(menu.ui.rect_of("play").size.x > 100.0, "the title screen is back")

	# --- The page shows the real numbers ---
	var profile = menu.pages.profile
	profile.capture_text = true
	var salvage0: int = save.salvage
	var parts0: int = save.parts
	var xp0: int = save.pilot_xp
	var gear0: int = save.gear.size()
	save.stats = {"kill": 1832, "boss": 9, "clear": 74, "best_combo": 67, "gear_found": 58, "legendary": 3}
	save.endless_best_wave = 17
	save.owned_ships = ["nova", "interceptor", "lancer"]
	save.ship = "interceptor"
	save.mastery = {"interceptor": 1600}
	save.achievements = {"first_kill": true, "kill_1k": true, "nova_50": true}
	for n in range(1, 31):
		save.star_mask[n] = 7
	var open_profile := func() -> void:
		menu.go("profile")
		for i in range(6):
			await process_frame
	await open_profile.call()
	var seen := func(text: String) -> bool:
		return text in profile.shown
	check(seen.call("PILOT LEVEL 12") and seen.call("260 / 400 XP") and seen.call("140 XP TO NEXT LEVEL") and seen.call("65%") and seen.call("LIFETIME XP: %s" % U.num(save.pilot_xp)), "the XP section shows level 12, 260 / 400, 140 to go and 65%%")
	check(seen.call("NEXT LEVEL — LEVEL 13") and seen.call("+72") and seen.call("+11") and seen.call("+0.3%") and seen.call("+0.5"), "the next-level rewards come from the real next level")
	check(not _shown_has(profile, "GEAR DROP"), "no gear card when the next level pays no gear")
	check(seen.call("+3.6%") and seen.call("+6.0") and seen.call("CAP +30.0% AT LEVEL 100") and seen.call("CAP +50.0 AT LEVEL 100"), "the combat attributes show the bonuses combat applies")
	check(seen.call("1,832") and seen.call("9") and seen.call("67") and seen.call("74") and seen.call("30 / 90".replace("30 / 90", "%d / %d" % [save.total_stars(), Levels.LEVEL_COUNT * 3])) and seen.call("17") and seen.call("58") and seen.call("3 / 5"), "the career statistics show the saved values")
	check(seen.call("%d / %d" % [save.achievements.size(), Goals.ACHIEVEMENTS.size()]), "the achievements count is real")
	check(seen.call("INTERCEPTOR") and seen.call("MASTERY 3") and seen.call("MASTERY 3 / 10"), "the current ship and its mastery are shown")
	var shown_levels: Array = []
	for line in profile.shown:
		if str(line).begins_with("LEVEL ") and "·" in str(line):
			shown_levels.append(str(line))
	check(seen.call("LEVEL 15  ·  RARE GEAR") and seen.call("LEVEL 20  ·  EPIC GEAR") and seen.call("LEVEL 25  ·  RARE GEAR") and seen.call("LEVEL 100  ·  BONUSES MAXED"), "the roadmap lists the next milestones (%s)" % str(shown_levels))
	check(seen.call("LEVEL 13  ·  NEXT LEVEL"), "and the next level first")
	# XP start, middle and end of a level.
	var xp_cases := [[0, "0 / 400 XP", "400 XP TO NEXT LEVEL", "0%"], [200, "200 / 400 XP", "200 XP TO NEXT LEVEL", "50%"], [399, "399 / 400 XP", "1 XP TO NEXT LEVEL", "99%"]]
	for case in xp_cases:
		save.pilot_xp = P.xp_at_level_start(12) + int(case[0])
		for i in range(3):
			await process_frame
		check(seen.call("PILOT LEVEL 12") and seen.call(str(case[1])) and seen.call(str(case[2])) and seen.call(str(case[3])), "XP %d of 400 shows %s, %s, %s" % [int(case[0]), str(case[1]), str(case[2]), str(case[3])])
	# Gear milestones: Rare at 5, Epic at 10.
	save.pilot_xp = P.xp_at_level_start(4) + 10
	for i in range(3):
		await process_frame
	check(seen.call("RARE GEAR DROP") and seen.call("Guaranteed on level 5.") and seen.call("+40") and seen.call("+7"), "level 5 previews a Rare gear drop with 40 salvage and 7 parts")
	save.pilot_xp = P.xp_at_level_start(9) + 10
	for i in range(3):
		await process_frame
	check(seen.call("EPIC GEAR DROP") and seen.call("Guaranteed on level 10.") and seen.call("+60") and seen.call("+10"), "level 10 previews an Epic gear drop with 60 salvage and 10 parts")
	# Level 99, 100 and past it.
	save.pilot_xp = P.xp_at_level_start(99) + 5
	for i in range(3):
		await process_frame
	check(seen.call("NEXT LEVEL — LEVEL 100") and seen.call("+0.3%") and not seen.call("MAXED") and seen.call("+29.7%") and seen.call("LEVEL 99 / 100") and seen.call("EPIC GEAR DROP"), "level 99 still previews the last bonus increase, and the level-100 Epic")
	save.pilot_xp = P.xp_at_level_start(100) + 5
	for i in range(3):
		await process_frame
	check(seen.call("NEXT LEVEL — LEVEL 101") and seen.call("MAXED") and not seen.call("+0.3%") and seen.call("+30.0%") and seen.call("+50.0") and seen.call("LEVEL 100  ·  BONUSES MAXED  ·  COMPLETE"), "level 100 shows the bonuses maxed and the milestone complete")
	check(not seen.call("LEVEL 100  ·  BONUSES MAXED"), "a reached milestone is not offered as upcoming")
	save.pilot_xp = P.xp_at_level_start(150) + 5
	for i in range(3):
		await process_frame
	check(seen.call("PILOT LEVEL 150") and seen.call("+30.0%") and seen.call("NEXT LEVEL — LEVEL 151") and seen.call("MAXED") and seen.call("NO LEVEL CAP"), "past level 100 the page keeps going with the bonuses capped")
	check(save.salvage == salvage0 and save.parts == parts0 and save.gear.size() == gear0, "opening and reading the profile pays nothing")

	# --- Levelling up in a real flight updates the page, and pays what the preview said ---
	menu.queue_free()
	await process_frame
	save.pilot_xp = P.xp_at_level_start(3)
	save.salvage = 0
	save.parts = 0
	save.gear = []
	var game = await _new_game(_level(3))
	game.phase = game.Phase.PLAYING
	game.kills = 1200
	game._level_complete()
	var before: int = int(game.pilot_before.level)
	var after: int = int(game.pilot_after.level)
	check(before == 3 and after >= before + 3, "one flight can gain several levels (%d to %d)" % [before, after])
	var pay_salvage := 0
	var pay_parts := 0
	var pay_gear := 0
	for lv in range(before + 1, after + 1):
		var pay2: Dictionary = P.reward_for(lv)
		pay_salvage += int(pay2.salvage)
		pay_parts += int(pay2.parts)
		if int(pay2.gear) >= 0:
			pay_gear += 1
	var line_ok := false
	for r in game.rewards:
		if str(r.detail) == "+%d salvage  +%d parts" % [pay_salvage, pay_parts]:
			line_ok = true
	check(line_ok, "the results line pays exactly the previewed salvage and parts for levels %d to %d" % [before + 1, after])
	var pilot_items := 0
	for it in game.loot:
		if int(it.get("power", 0)) >= 1 and bool(it.get("new", false)):
			pilot_items += 1
	check(pilot_items >= pay_gear and pay_gear >= 1, "and the previewed gear drop arrived (%d of %d)" % [pilot_items, pay_gear])
	var salvage_now: int = save.salvage
	var xp_now: int = save.pilot_xp
	game._bank()
	check(save.salvage == salvage_now and save.pilot_xp == xp_now, "a flight pays its levels only once")
	game.queue_free()
	await process_frame
	menu = load("res://title_screen.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	menu.pages.profile.capture_text = true
	menu.go("profile")
	for i in range(6):
		await process_frame
	var next_pay: Dictionary = P.reward_for(after + 1)
	check(("PILOT LEVEL %d" % after) in menu.pages.profile.shown and ("NEXT LEVEL — LEVEL %d" % (after + 1)) in menu.pages.profile.shown and ("+%s" % U.num(int(next_pay.salvage))) in menu.pages.profile.shown, "after the flight the profile shows the new level and the next one's rewards")
	check(int(menu.pages.profile.summary().level) == after, "the profile's level matches the save")

	# --- Hangar button, scrolling and touch targets ---
	check(menu.ui.scroll_max > 400.0, "the profile scrolls (%.0f)" % menu.ui.scroll_max)
	var back_at: Rect2 = menu.ui.rect_of("back")
	menu.ui.scroll = 700.0
	for i in range(4):
		await process_frame
	check(menu.ui.rect_of("back") == back_at, "the header stays put while the page scrolls")
	menu.ui.scroll = menu.ui.scroll_max
	for i in range(4):
		await process_frame
	var hangar_btn: Rect2 = menu.ui.rect_of("profile_hangar")
	check(hangar_btn.size.x >= 150.0 and hangar_btn.end.x <= float(menu.W) and hangar_btn.position.x >= 0.0, "the Hangar button is on screen at the bottom (%s)" % str(hangar_btn))
	check(hangar_btn.end.y <= float(menu.H) - float(menu.bottom) + 1.0, "and clear of the bottom safe area")
	await _press_id(menu.ui, "profile_hangar")
	check(menu.screen == "hangar", "OPEN HANGAR goes to the Hangar")
	menu.queue_free()
	await process_frame

	# --- The page under each comfort setting ---
	for combo in [[true, false, 1.0], [false, true, 1.0], [false, false, 1.12], [true, true, 1.12]]:
		save.opt.reduced_motion = combo[0]
		save.opt.reduced_flash = combo[1]
		save.opt.ui_scale = combo[2]
		save.apply_display()
		save.pilot_xp = P.xp_at_level_start(19) + 300
		menu = load("res://title_screen.tscn").instantiate()
		root.add_child(menu)
		await process_frame
		menu.pages.profile.capture_text = true
		menu.go("profile")
		for i in range(6):
			await process_frame
		var label := "motion=%s flashes=%s scale=%.2f" % [str(combo[0]), str(combo[1]), combo[2]]
		check(("PILOT LEVEL 19") in menu.pages.profile.shown and ("EPIC GEAR DROP") in menu.pages.profile.shown and ("LEVEL 25  ·  RARE GEAR") in menu.pages.profile.shown, "the profile shows its data with %s" % label)
		check(menu.ui.scroll_max > 300.0, "the profile scrolls with %s" % label)
		var width: float = float(menu.W)
		var off_screen := 0
		for step in [0.0, 600.0, 1200.0, 1800.0, 2400.0]:
			menu.ui.scroll = minf(step, menu.ui.scroll_max)
			for i in range(3):
				await process_frame
			for b in menu.ui._buttons:
				var br: Rect2 = b.rect
				if br.position.x < -1.0 or br.end.x > width + 1.0:
					off_screen += 1
		check(off_screen == 0, "no control runs off the side with %s" % label)
		menu.queue_free()
		await process_frame
	save.opt.reduced_motion = false
	save.opt.reduced_flash = false
	save.opt.ui_scale = 1.0
	save.apply_display()
	save.pilot_xp = 0
	save.stats = {}
	save.mastery = {}
	save.star_mask = {}
	save.achievements = {}
	save.endless_best_wave = 0
	save.owned_ships = ["nova"]
	save.ship = "nova"
	save.salvage = 0
	save.parts = 0
	save.gear = []
	print("pilot profile ok")

# ---------- Cloud save ----------

var _cloud_mock_script
var _cloud_script

## A complete late-game save: every progress key holds something other than a new player's value.
func _cloud_rich_save() -> void:
	save.reset_progress()
	save.salvage = 12345
	save.parts = 321
	save.pilot_xp = 98765
	save.unlocked = 40
	save.best_score = 777000
	save.endless_best_wave = 17
	for n in range(1, 41):
		save.star_mask[n] = 7 if n % 3 != 0 else 3
	save.level_best = {5: 12000, 9: 40500}
	save.upgrades = {"hull": 3, "damage": 2}
	save.owned_ships = ["nova", "interceptor", "lancer"]
	save.ship = "interceptor"
	save.blueprints = ["bp_aegis"]
	save.nova_mode = "singularity"
	save.loadout = ["a", "b"]
	save.mastery = {"interceptor": 1600, "nova": 400}
	save.paints = {"nova": "ember"}
	save.tutorial = {"move": true, "card": true}
	save.stats = {"kill": 1832, "boss": 9, "clear": 74, "best_combo": 67, "gear_found": 58, "legendary": 3}
	save.side_cleared = [101, 102]
	save.bosses_beaten = [1, 2]
	save.achievements = {"first_kill": true, "kill_1k": true}
	save.codex = {"fighter": 3}
	save.contracts = {"day": 20000, "done": [1]}
	save.expedition = {"depth": 2}
	save.weekly_best = {"w1": 900}
	save.daily_best = {"d1": 400}
	save.reroll_tokens = 3
	save.expedition_wins = 4
	save.seen_unlocks = ["u1"]
	save.rift_claimed = [5, 10]
	save.tier_unlocked = 2
	save.tier_data = {1: {"stars": {5: 3}}}
	save.danger = {"done": {"rush": 2}, "last": {}}
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for slot in ["weapon", "reactor", "plating", "weapon"]:
		var item: Dictionary = gear_db.generate(rng, 30.0, gear_db.EPIC, slot, 0)
		item.lvl = 3
		save.add_gear(item)
	for it in save.gear:
		if save.equipped_uid("interceptor", str(it.slot)) == 0:
			save.equip("interceptor", int(it.uid))
	save.save_data()

func _cloud_hash(d: Dictionary) -> String:
	return _cloud_script_class().progress_hash(d)

func _cloud_script_class():
	return load("res://src/meta/cloud_save.gd")

## A Cloud orchestrator of its own, wired to `mock`, with a short debounce so tests need not wait.
func _make_cloud(mock, signed_in := true):
	var cloud = _cloud_script.new()
	cloud.autostart = false
	cloud.debounce = 0.05
	cloud.timeout = 1.0
	cloud.auth_timeout = 0.4
	root.add_child(cloud)
	cloud.forget_state()
	if signed_in:
		mock.set_auth(_cloud_script_class().Auth.SIGNED_IN)
	cloud.use(mock)
	return cloud

## Waits until the orchestrator has nothing running and nothing scheduled.
func _cloud_settle(cloud, max_frames := 900) -> void:
	for i in range(max_frames):
		await process_frame
		if i > 3 and not cloud.busy and (cloud._timer.is_stopped() or cloud._fail_kind != ""):
			break
	for i in range(3):
		await process_frame

func _free_cloud(cloud) -> void:
	cloud.queue_free()
	await process_frame

func _fresh_install() -> void:
	save.reset_progress()
	save.remove_files(save.path)
	save.save_data()

func _cloud_no_progress_changes(before: Dictionary, what: String) -> void:
	check(_cloud_hash(save.to_dict()) == _cloud_hash(before), what)

func _test_cloud_save() -> void:
	var CS = _cloud_script_class()
	_cloud_mock_script = load("res://tools/mock_cloud.gd")
	_cloud_script = load("res://src/meta/cloud_sync.gd")
	var saved_opt: Dictionary = save.opt.duplicate()
	var saved_dict: Dictionary = save.to_dict()
	# --- The blob holds every progress key and no settings ---
	_cloud_rich_save()
	var rich: Dictionary = save.to_dict()
	for key in save.PROGRESS_KEYS:
		check(rich.has(key), "to_dict holds %s" % key)
	var blob: PackedByteArray = CS.encode(rich)
	var dec: Dictionary = CS.decode(blob)
	check(bool(dec.ok), "a full save encodes and decodes (%s)" % str(dec.get("error", "")))
	for key in save.PROGRESS_KEYS:
		check((dec.data as Dictionary).has(key), "the cloud copy holds %s" % key)
		check(str(dec.data.get(key)) == str(rich.get(key)), "the cloud copy of %s is unchanged" % key)
	check(not (dec.data as Dictionary).has("opt") and not (dec.data as Dictionary).has("settings"), "settings are not part of the cloud save")
	check(CS.progress_hash(dec.data) == CS.progress_hash(rich), "decoding gives back the same progress")
	check(CS.has_progress(rich) and not CS.has_progress(CS.migrate({"version": 2})), "has_progress tells a played save from an empty one")
	check(CS.SNAPSHOT_NAME == "starfall_salvage_main", "one primary snapshot name")
	var s: Dictionary = CS.summarize(rich)
	check(int(s.salvage) == 12345 and int(s.gear) == 4 and int(s.ships) == 3 and int(s.stars) > 80 and int(s.level) >= 1, "the conflict summary is real")
	# --- Restoring replaces everything, and leaves the settings alone ---
	save.opt.music_volume = 0.33
	save.reset_progress()
	save.save_data()
	check(save.salvage == 0 and save.gear.is_empty(), "the test save was wiped")
	save.restore_progress(dec.data)
	check(CS.progress_hash(save.to_dict()) == CS.progress_hash(rich), "a restore brings back every key")
	check(save.gear.size() == 4 and save.equipped.has("interceptor") and (save.equipped.interceptor as Dictionary).size() == 3, "gear and what is equipped come back")
	check(save.pilot_xp == 98765 and int(save.mastery.interceptor) == 1600 and save.ship == "interceptor" and save.owned_ships.size() == 3, "pilot XP, mastery and ships come back")
	check(is_equal_approx(float(save.opt.music_volume), 0.33), "a restore does not touch the settings")
	# --- A restore replaces, it never takes the larger number ---
	var spent: Dictionary = CS.decode(CS.encode(rich)).data.duplicate(true)
	spent.salvage = 40
	spent.parts = 1
	save.restore_progress(spent)
	check(save.salvage == 40 and save.parts == 1 and save.pilot_xp == 98765, "a lower balance from the cloud is restored as it is (a real purchase)")
	save.restore_progress(rich)
	# --- Damaged, hostile and foreign data is refused ---
	var bad_cases := {
		"empty": PackedByteArray(),
		"noise": PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
		"truncated": blob.slice(0, blob.size() / 2),
		"not a dictionary": var_to_bytes([1, 2, 3]),
		"not an envelope": var_to_bytes({"hello": "world"}),
		"too large": PackedByteArray(),
	}
	bad_cases["too large"].resize(CS.MAX_BYTES + 1)
	for name in bad_cases:
		var r: Dictionary = CS.decode(bad_cases[name])
		check(not bool(r.ok), "decode refuses %s" % name)
	var flipped := blob.duplicate()
	flipped[flipped.size() - 5] = flipped[flipped.size() - 5] ^ 0xFF
	check(not bool(CS.decode(flipped).ok), "decode refuses a blob with one changed byte")
	var env_of := func(mutate: Callable) -> PackedByteArray:
		var env: Dictionary = JSON.parse_string(blob.get_string_from_utf8())
		mutate.call(env)
		return JSON.stringify(env).to_utf8_buffer()
	check(str(CS.decode(env_of.call(func(e): e["game"] = "other_game")).code) == "game", "decode refuses another game's save")
	check(str(CS.decode(env_of.call(func(e): e["format"] = 99)).code) == "newer", "decode refuses a newer blob format")
	check(str(CS.decode(env_of.call(func(e): e["checksum"] = "00")).code) == "checksum", "decode refuses a wrong checksum")
	var rewrap := func(mutate: Callable) -> PackedByteArray:
		var data: Dictionary = rich.duplicate(true)
		mutate.call(data)
		return CS.encode(data)
	var invalid := {
		"a save from a newer game": rewrap.call(func(d): d["version"] = 99),
		"a negative balance": rewrap.call(func(d): d["salvage"] = -5),
		"a balance that is not a number": rewrap.call(func(d): d["salvage"] = "lots"),
		"an impossible level count": rewrap.call(func(d): d["unlocked"] = 9999),
		"an unknown ship": rewrap.call(func(d): d["ship"] = "death_star"),
		"a ship that is not owned": rewrap.call(func(d): d["ship"] = "warden"),
		"a repeated gear id": rewrap.call(func(d): d["gear"] = [d.gear[0], d.gear[0]]),
		"a gear item in an unknown slot": rewrap.call(func(d): d.gear[0]["slot"] = "cupholder"),
		"a gear item above its level cap": rewrap.call(func(d): d.gear[0]["lvl"] = 500),
		"a gear item with an unknown stat": rewrap.call(func(d): d.gear[0]["aff"] = [{"k": "godmode", "r": 1.0}]),
		"upgrades of the wrong type": rewrap.call(func(d): d["upgrades"] = {"hull": "max"}),
		"a missing key": rewrap.call(func(d): d.erase("star_mask")),
		"stars of the wrong type": rewrap.call(func(d): d["star_mask"] = [1, 2]),
	}
	for name in invalid:
		var r2: Dictionary = CS.decode(invalid[name])
		check(not bool(r2.ok) and str(r2.code) in ["invalid", "newer"], "decode refuses %s (%s)" % [name, str(r2.get("code"))])
	# --- An older save is accepted and filled in ---
	var v1 := {"version": 1, "unlocked": 5, "salvage": 70, "star_mask": {1: 7}, "upgrades": {}, "ship": "nova", "owned_ships": ["nova"]}
	var v1r: Dictionary = CS.decode(CS.encode(v1))
	check(bool(v1r.ok), "a version 1 cloud save is accepted (%s)" % str(v1r.get("errors")))
	if bool(v1r.ok):
		save.restore_progress(v1r.data)
		check(save.unlocked == 5 and save.salvage == 70 and save.pilot_xp == 0 and save.gear.is_empty() and save.nova_mode == "pulse", "missing keys come back as a new player's values")
	save.opt = saved_opt
	print("cloud data ok")
	_test_has_progress()
	await _test_cloud_sync(saved_dict)

func _read_blob(p: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(p)

func _test_cloud_sync(original: Dictionary) -> void:
	var CS = _cloud_script_class()
	var St = CS.Status
	var side_files := [save.path + ".cloud", save.path + ".before_cloud", save.path + ".cloudconflict"]
	# --- A new install restores the cloud save without asking ---
	_cloud_rich_save()
	var rich: Dictionary = save.to_dict()
	var rich_blob: PackedByteArray = CS.encode(rich)
	_fresh_install()
	var mock = _cloud_mock_script.new()
	mock.set_blob(rich_blob)
	var cloud = _make_cloud(mock)
	await _cloud_settle(cloud)
	check(CS.progress_hash(save.to_dict()) == CS.progress_hash(rich), "a fresh install restores the cloud save")
	check(cloud.status() == St.SYNCED and cloud.conflict.is_empty() and not cloud.pending, "and shows CLOUD SYNCED with no question asked")
	check(mock.saves == 0 and mock.loads >= 1 and mock.last_name == CS.SNAPSHOT_NAME, "restoring never writes to the cloud")
	check(cloud.last_sync > 0, "and records when it synced")
	# The state file holds fingerprints and a time. No account data, no tokens.
	var state := ConfigFile.new()
	check(state.load(save.path + ".cloud") == OK and state.get_sections() == PackedStringArray(["sync"]) and state.get_section_keys("sync").size() == 4 and str(state.get_value("sync", "account", "")) == CS.account_hash("acct-A") and not "acct-A" in FileAccess.get_file_as_string(save.path + ".cloud"), "the sync record holds fingerprints, a time and a one-way hash of the account, never the id")
	var save_text := FileAccess.get_file_as_string(save.path)
	for word in ["oauth", "access_token", "id_token", "bearer", "password"]:
		check(not word in save_text.to_lower(), "the save file holds no %s" % word)
	# --- Fast-forward: another device spent salvage, this one did not change ---
	var other: Dictionary = save.to_dict()
	other.salvage = 100
	other.parts = 2
	mock.set_blob(CS.encode(other))
	cloud.sync_now()
	await _cloud_settle(cloud)
	check(save.salvage == 100 and save.parts == 2 and save.pilot_xp == 98765, "a lower balance from another device is restored, not replaced by the larger number")
	check(FileAccess.file_exists(save.path + ".before_cloud") and cloud.status() == St.SYNCED, "the old save was kept in a backup file first")
	await _free_cloud(cloud)
	# --- Guest progress is uploaded ---
	_cloud_rich_save()
	rich = save.to_dict()
	for f in side_files:
		DirAccess.remove_absolute(f)
	mock = _cloud_mock_script.new()
	cloud = _make_cloud(mock)
	await _cloud_settle(cloud)
	check(mock.exists and mock.saves == 1, "local progress with an empty cloud is uploaded once")
	check(bool(CS.decode(mock.blob).ok) and CS.progress_hash(CS.decode(mock.blob).data) == CS.progress_hash(rich), "and what was uploaded is the complete save")
	check(mock.last_name == CS.SNAPSHOT_NAME and "Pilot level" in mock.last_description and mock.last_progress > 1000000000, "with one snapshot name, a description and the write time as progress")
	check(cloud.status() == St.SYNCED and not cloud.pending and FileAccess.file_exists(save.path), "the local save stays")
	var guest_hash: String = CS.progress_hash(save.to_dict())
	# --- Several saves close together make one upload ---
	save.salvage += 10
	save.save_data()
	save.salvage += 10
	save.save_data()
	save.salvage += 10
	save.save_data()
	check(cloud.pending and cloud.status() == St.PENDING, "unsynced changes show as pending")
	await _cloud_settle(cloud)
	check(mock.saves == 2 and CS.progress_hash(CS.decode(mock.blob).data) == CS.progress_hash(save.to_dict()), "three quick saves became one upload (%d uploads)" % mock.saves)
	check(cloud.status() == St.SYNCED and not cloud.pending, "and the page is synced again")
	# --- Nothing syncs during a flight ---
	cloud.hold(true)
	save.salvage += 5
	save.save_data()
	await create_timer(0.4).timeout
	check(mock.saves == 2 and cloud.pending, "a held sync waits")
	cloud.hold(false)
	check(not cloud._timer.is_stopped() and cloud._timer.time_left <= 2.01, "and is scheduled when the flight ends")
	cloud.sync_now()
	await _cloud_settle(cloud)
	check(mock.saves == 3 and not cloud.pending, "and then goes through")
	# --- Google reports two versions of the cloud save, while saving and while loading ---
	for origin in ["SAVE", "LOAD"]:
		var other_a: Dictionary = save.to_dict()
		other_a.salvage = 111
		var other_b: Dictionary = save.to_dict()
		other_b.salvage = 222
		mock.conflict_blobs = [CS.encode(other_a), CS.encode(other_b)]
		for f in [save.path + ".cloudconflict.1", save.path + ".cloudconflict.2"]:
			DirAccess.remove_absolute(f)
		save.salvage += 7
		save.save_data()
		var local_conflict: Dictionary = save.to_dict()
		var blob_before: PackedByteArray = mock.blob.duplicate()
		mock.conflict_next = origin
		var started := Time.get_ticks_msec()
		if origin == "LOAD":
			cloud.sync_now(true)
		await _cloud_settle(cloud)
		check(cloud.status() == St.ERROR and cloud._fail_kind == "conflict" and not cloud.busy, "a %s conflict ends the request as an error" % origin)
		check(Time.get_ticks_msec() - started < int(cloud.timeout * 1000.0), "and does not wait for the timeout (%s)" % origin)
		check("two different cloud versions" in cloud.last_error and "untouched" in cloud.last_error, "and says what happened")
		check(bool(CS.decode(_read_blob(save.path + ".cloudconflict.1")).ok) and int(CS.decode(_read_blob(save.path + ".cloudconflict.2")).data.salvage) == 222 and int(CS.decode(_read_blob(save.path + ".cloudconflict.1")).data.salvage) == 111, "both reported versions are kept as files (%s)" % origin)
		check(CS.progress_hash(save.to_dict()) == CS.progress_hash(local_conflict) and mock.blob == blob_before, "nothing local or in the cloud was overwritten (%s)" % origin)
		check(cloud._timer.is_stopped(), "a conflict is not retried on a timer (%s)" % origin)
		cloud.sync_now(true)
		await _cloud_settle(cloud)
		check(cloud.status() == St.SYNCED, "Sync Now tries again and succeeds once the conflict is gone (%s)" % origin)
	await _free_cloud(cloud)
	# --- Offline: nothing is lost, and the upload happens later ---
	_cloud_rich_save()
	rich = save.to_dict()
	for f in side_files:
		DirAccess.remove_absolute(f)
	mock = _cloud_mock_script.new()
	mock.offline = true
	cloud = _make_cloud(mock)
	await _cloud_settle(cloud)
	check(cloud.status() == St.OFFLINE and cloud.pending and not mock.exists, "offline shows OFFLINE, keeps the changes pending and writes nothing")
	check(CS.progress_hash(save.to_dict()) == CS.progress_hash(rich) and FileAccess.file_exists(save.path), "and the local save is untouched")
	check("safe on this device" in cloud.last_error, "the message says progress is safe")
	mock.offline = false
	cloud.sync_now()
	await _cloud_settle(cloud)
	check(mock.exists and cloud.status() == St.SYNCED and not cloud.pending, "back online it uploads and shows CLOUD SYNCED")
	await _free_cloud(cloud)
	# --- A failed upload keeps the changes pending ---
	mock = _cloud_mock_script.new()
	mock.fail_save = "error"
	for f in side_files:
		DirAccess.remove_absolute(f)
	cloud = _make_cloud(mock)
	await _cloud_settle(cloud)
	check(cloud.status() == St.ERROR and cloud.pending and not mock.exists, "a failed upload shows SYNC ERROR and stays pending")
	check(CS.progress_hash(save.to_dict()) == CS.progress_hash(rich), "the local progress is exactly as it was")
	cloud.sync_now()
	await _cloud_settle(cloud)
	check(cloud.status() == St.SYNCED and mock.exists, "a retry succeeds")
	# --- A request that never answers times out and does not block the next one ---
	cloud.timeout = 0.3
	mock.silent = true
	save.salvage += 1
	save.save_data()
	await _cloud_settle(cloud)
	check(cloud.status() == St.OFFLINE and not cloud.busy and cloud.pending, "a silent cloud times out as OFFLINE")
	cloud.sync_now()
	await _cloud_settle(cloud)
	check(cloud.status() == St.SYNCED, "and the next sync goes through")
	await _free_cloud(cloud)
	# --- Two devices changed: the player decides ---
	_cloud_rich_save()
	for f in side_files:
		DirAccess.remove_absolute(f)
	mock = _cloud_mock_script.new()
	cloud = _make_cloud(mock)
	await _cloud_settle(cloud)
	var cloud_side: Dictionary = save.to_dict()
	cloud_side.salvage = 999
	cloud_side.pilot_xp = 100000
	mock.set_blob(CS.encode(cloud_side))
	save.salvage = 5
	save.save_data()
	var saves_before: int = mock.saves
	await _cloud_settle(cloud)
	check(cloud.status() == St.CONFLICT and not cloud.conflict.is_empty(), "both sides changed: CHOOSE A SAVE")
	check(mock.saves == saves_before and save.salvage == 5, "nothing was overwritten while waiting")
	check(int(cloud.conflict.local.salvage) == 5 and int(cloud.conflict.cloud.salvage) == 999, "the choice shows both saves")
	cloud.sync_now()
	await _cloud_settle(cloud)
	check(cloud.status() == St.CONFLICT and mock.saves == saves_before, "syncing again does not decide for the player")
	var restored_flag := [false]
	cloud.restored.connect(func(): restored_flag[0] = true)
	cloud.keep_local()
	await _cloud_settle(cloud)
	check(cloud.status() == St.SYNCED and int(CS.decode(mock.blob).data.salvage) == 5, "KEEP THIS DEVICE'S SAVE uploads this device's save")
	check(bool(CS.decode(_read_blob(save.path + ".cloudconflict")).ok) and int(CS.decode(_read_blob(save.path + ".cloudconflict")).data.salvage) == 999, "and the replaced cloud save is kept in a file")
	# The other way round.
	cloud_side = save.to_dict()
	cloud_side.salvage = 777
	mock.set_blob(CS.encode(cloud_side))
	save.salvage = 6
	save.save_data()
	await _cloud_settle(cloud)
	check(cloud.status() == St.CONFLICT, "a second disagreement is a conflict again")
	cloud.restore_cloud()
	await _cloud_settle(cloud)
	check(save.salvage == 777 and cloud.status() == St.SYNCED and restored_flag[0], "RESTORE CLOUD SAVE brings back the cloud save")
	check(int(CS.decode(_read_blob(save.path + ".cloudconflict")).data.salvage) == 6 and FileAccess.file_exists(save.path + ".before_cloud"), "and this device's save is kept in files")
	await _free_cloud(cloud)
	# --- A save erased on this device is never pushed over the cloud, and never restored silently ---
	_cloud_rich_save()
	for f in side_files:
		DirAccess.remove_absolute(f)
	mock = _cloud_mock_script.new()
	cloud = _make_cloud(mock)
	await _cloud_settle(cloud)
	var cloud_hash_before: String = CS.progress_hash(CS.decode(mock.blob).data)
	save.reset_progress()
	save.save_data()
	saves_before = mock.saves
	await _cloud_settle(cloud)
	check(cloud.status() == St.CONFLICT and mock.saves == saves_before and not CS.has_progress(save.to_dict()), "an erased save asks first and uploads nothing")
	check(CS.progress_hash(CS.decode(mock.blob).data) == cloud_hash_before, "the cloud save is untouched")
	await _free_cloud(cloud)
	# --- A fresh install with an empty cloud uploads nothing ---
	_fresh_install()
	for f in side_files:
		DirAccess.remove_absolute(f)
	mock = _cloud_mock_script.new()
	cloud = _make_cloud(mock)
	await _cloud_settle(cloud)
	check(mock.saves == 0 and not mock.exists and cloud.status() == St.SYNCED, "an empty new game does not create a cloud save")
	await _free_cloud(cloud)
	# --- Unreadable or foreign cloud data never replaces a save ---
	for case in ["noise", "newer"]:
		var junk := PackedByteArray([9, 9, 9, 9, 9, 9, 9, 9])
		if case == "newer":
			var future: Dictionary = rich.duplicate(true)
			future["version"] = 99
			junk = CS.encode(future)
		_cloud_rich_save()
		for f in side_files:
			DirAccess.remove_absolute(f)
		var local_before: Dictionary = save.to_dict()
		mock = _cloud_mock_script.new()
		mock.set_blob(junk)
		cloud = _make_cloud(mock)
		await _cloud_settle(cloud)
		check(cloud.status() == St.CONFLICT and not str(cloud.conflict.bad).is_empty() and (cloud.conflict.cloud as Dictionary).is_empty(), "%s cloud data: the screen says it is unreadable" % case)
		cloud.restore_cloud()
		await _cloud_settle(cloud)
		check(CS.progress_hash(save.to_dict()) == CS.progress_hash(local_before) and mock.saves == 0, "%s cloud data: it cannot be restored and nothing was uploaded" % case)
		cloud.keep_local()
		await _cloud_settle(cloud)
		check(bool(CS.decode(mock.blob).ok) and cloud.status() == St.SYNCED, "%s cloud data: the player may replace it with this device's save" % case)
		await _free_cloud(cloud)
		_fresh_install()
		for f in side_files:
			DirAccess.remove_absolute(f)
		mock = _cloud_mock_script.new()
		mock.set_blob(junk)
		cloud = _make_cloud(mock)
		await _cloud_settle(cloud)
		check(cloud.status() == St.ERROR and mock.saves == 0 and not CS.has_progress(save.to_dict()), "%s cloud data on a new install is an error, not a restore" % case)
		await _free_cloud(cloud)
	# --- Sign-in comes and goes ---
	_cloud_rich_save()
	for f in side_files:
		DirAccess.remove_absolute(f)
	mock = _cloud_mock_script.new()
	mock.set_auth(CS.Auth.CHECKING)
	cloud = _make_cloud(mock, false)
	await process_frame
	check(cloud.status() == St.CONNECTING and mock.loads == 0, "checking sign-in shows CONNECTING and syncs nothing")
	mock.set_auth(CS.Auth.SIGNED_IN)
	await _cloud_settle(cloud)
	check(cloud.status() == St.SYNCED and mock.exists, "signing in syncs")
	mock.set_auth(CS.Auth.SIGNED_OUT)
	await process_frame
	check(cloud.status() == St.GUEST and cloud.status_label() == "LOCAL GUEST" and CS.progress_hash(save.to_dict()) == CS.progress_hash(rich), "signing out returns to LOCAL GUEST and keeps the local save")
	await _free_cloud(cloud)
	# --- Desktop and builds without the plugin play as a local guest ---
	var plain = CS.make_backend()
	check(not plain.available() and plain.auth == CS.Auth.UNAVAILABLE, "this build has no cloud service")
	var answered := [{}]
	plain.load_snapshot(CS.SNAPSHOT_NAME, func(r): answered[0] = r)
	await process_frame
	check(not bool(answered[0].get("ok", true)) and str(answered[0].get("kind")) == "unavailable", "a missing service answers 'unavailable', it does not pretend")
	var live = root.get_node("Cloud")
	check(live.status() == St.GUEST and live.status_label() == "LOCAL GUEST" and not live.signed_in(), "the game's own Cloud runs as a local guest here")
	check("Android" in live.account_text() and not "synced" in live.account_text().to_lower(), "and does not claim cloud saving on desktop")
	var before_live: Dictionary = save.to_dict()
	live.sync_now()
	await process_frame
	check(not live.busy and CS.progress_hash(save.to_dict()) == CS.progress_hash(before_live), "Sync Now does nothing without a service")
	await _test_cloud_accounts()
	await _test_cloud_cleanup()
	await _test_cloud_plugin()
	await _test_cloud_profile(rich)
	# --- Put the test save back ---
	for f in side_files:
		DirAccess.remove_absolute(f)
	save.restore_progress(original)
	print("cloud sync ok")

## The Pilot Profile's ACCOUNT & CLOUD SAVE section, in every state, driven by the game's own Cloud with a mock service.
func _test_cloud_profile(rich: Dictionary) -> void:
	var CS = _cloud_script_class()
	var St = CS.Status
	var C = root.get_node("Cloud")
	var plain_backend = C.backend
	var side_files := [save.path + ".cloud", save.path + ".before_cloud", save.path + ".cloudconflict"]
	C.forget_state()
	C.timeout = 1.0
	var menu = load("res://title_screen.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	var profile = menu.pages.profile
	profile.capture_text = true
	var open_profile := func() -> void:
		menu.go("profile")
		await create_timer(0.6).timeout
	var seen := func(text: String) -> bool:
		return text in profile.shown
	var rect_ok := func(id: String) -> bool:
		var r: Rect2 = menu.ui.rect_of(id)
		return r.size.y >= 60.0 and r.size.x >= 150.0 and r.position.x >= 0.0 and r.end.x <= float(menu.W)
	_fresh_install()
	# LOCAL GUEST
	await open_profile.call()
	check(seen.call("ACCOUNT & CLOUD SAVE") and seen.call("LOCAL GUEST"), "the profile has an ACCOUNT & CLOUD SAVE section, as a local guest here")
	check(seen.call("Cloud saves need the Android version with Google Play Games. Progress is saved on this device only.") or _shown_has(profile, "saved on this device only"), "the guest text is honest")
	check(menu.ui.rect_of("cloud_sync").size.x == 0.0 and menu.ui.rect_of("cloud_connect").size.x == 0.0, "no Sync Now button without a service")
	# CONNECTING
	var mock = _cloud_mock_script.new()
	mock.set_auth(CS.Auth.CHECKING)
	C.use(mock)
	await open_profile.call()
	check(seen.call("CONNECTING") and _shown_has(profile, "Checking your Google Play Games sign-in"), "CONNECTING while sign-in is checked")
	# GOOGLE PLAY GAMES CONNECTED (the first sync is still running)
	mock.delay_frames = 400
	mock.set_auth(CS.Auth.SIGNED_IN)
	await open_profile.call()
	check(seen.call("GOOGLE PLAY GAMES CONNECTED") and seen.call("SYNCING..."), "GOOGLE PLAY GAMES CONNECTED during the first sync, with the button busy")
	check(menu.ui.rect_of("cloud_sync").size.x > 0.0 and rect_ok.call("cloud_sync"), "the sync button is a full-size touch target (%s)" % str(menu.ui.rect_of("cloud_sync")))
	check(not _shown_has(profile, "Sign out") and not _shown_has(profile, "@") and not _shown_has(profile, "gmail"), "no invented account name, picture or sign-out")
	# CLOUD SYNCED
	mock.delay_frames = 1
	C.use(mock)
	for i in range(120):
		await process_frame
		if not C.busy and i > 3:
			break
	await open_profile.call()
	check(seen.call("CLOUD SYNCED") and seen.call("SYNC NOW") and _shown_has(profile, "Signed in with Google Play Games") and _shown_has(profile, "LAST SYNC"), "CLOUD SYNCED with Sync Now and the last sync time")
	check(not seen.call("UNSYNCED CHANGES") and rect_ok.call("cloud_sync"), "nothing is unsynced")
	# SYNC PENDING
	C.debounce = 30.0
	save.salvage += 3
	save.save_data()
	await open_profile.call()
	check(seen.call("SYNC PENDING") and seen.call("UNSYNCED CHANGES"), "SYNC PENDING with an unsynced indicator")
	# Pressing Sync Now syncs.
	var loads0: int = mock.loads
	await _press_id(menu.ui, "cloud_sync")
	for i in range(60):
		await process_frame
		if not C.busy and i > 3:
			break
	check(mock.loads > loads0 and C.status() == St.SYNCED, "pressing Sync Now syncs")
	# OFFLINE and Retry
	mock.offline = true
	save.salvage += 3
	save.save_data()
	C.sync_now()
	for i in range(60):
		await process_frame
		if not C.busy and i > 3:
			break
	await open_profile.call()
	check(seen.call("OFFLINE") and seen.call("RETRY") and _shown_has(profile, "safe on this device"), "OFFLINE with Retry and a message that progress is safe")
	mock.offline = false
	loads0 = mock.loads
	await _press_id(menu.ui, "cloud_sync")
	for i in range(60):
		await process_frame
		if not C.busy and i > 3:
			break
	check(mock.loads > loads0 and C.status() == St.SYNCED, "pressing Retry syncs again")
	# SYNC ERROR
	mock.fail_kind = "error"
	C.sync_now()
	for i in range(60):
		await process_frame
		if not C.busy and i > 3:
			break
	await open_profile.call()
	check(seen.call("SYNC ERROR") and seen.call("RETRY"), "SYNC ERROR with Retry")
	# CHOOSE A SAVE
	C.forget_state()
	_cloud_rich_save()
	var cloud_side: Dictionary = save.to_dict()
	cloud_side.salvage = 321
	cloud_side.pilot_xp = 5000
	mock.set_blob(_cloud_script_class().encode(cloud_side))
	C.use(mock)
	for i in range(120):
		await process_frame
		if not C.busy and i > 3:
			break
	await open_profile.call()
	check(C.status() == St.CONFLICT and seen.call("CHOOSE A SAVE") and seen.call("KEEP THIS DEVICE'S SAVE") and seen.call("RESTORE CLOUD SAVE"), "a disagreement shows CHOOSE A SAVE with both choices")
	check(seen.call("THIS DEVICE") and seen.call("CLOUD SAVE") and seen.call("12,345 SALVAGE") and seen.call("321 SALVAGE"), "both saves are described with real numbers")
	check(_shown_has(profile, "replaces the cloud save") and _shown_has(profile, "Replaces this device's progress"), "each choice says what it will do")
	check(rect_ok.call("cloud_keep") and rect_ok.call("cloud_restore"), "both choices are full-size touch targets (%s, %s)" % [str(menu.ui.rect_of("cloud_keep")), str(menu.ui.rect_of("cloud_restore"))])
	var guard: Dictionary = save.to_dict()
	var saves_guard: int = mock.saves
	await _press_id(menu.ui, "cloud_keep")
	for i in range(4):
		await process_frame
	check(seen.call("YES, REPLACE THE CLOUD SAVE") and seen.call("CANCEL") and C.status() == St.CONFLICT, "a choice needs a second tap")
	check(CS.progress_hash(save.to_dict()) == CS.progress_hash(guard) and mock.saves == saves_guard, "and nothing happens after the first")
	await _press_id(menu.ui, "cloud_cancel")
	for i in range(4):
		await process_frame
	check(seen.call("KEEP THIS DEVICE'S SAVE") and C.status() == St.CONFLICT, "Cancel goes back to the two choices")
	await _press_id(menu.ui, "cloud_restore")
	for i in range(4):
		await process_frame
	check(seen.call("YES, REPLACE THIS DEVICE'S SAVE"), "Restore also asks again")
	await _press_id(menu.ui, "cloud_confirm")
	for i in range(60):
		await process_frame
		if not C.busy and i > 3:
			break
	check(save.salvage == 321 and save.pilot_xp == 5000 and C.status() == St.SYNCED, "confirming Restore brings back the cloud save")
	# ACCOUNT CHANGED
	C.forget_state()
	_cloud_rich_save()
	_clear_cloud_files()
	var amock = _cloud_mock_script.new()
	amock.set_auth(CS.Auth.SIGNED_IN)
	C.use(amock)
	for i in range(120):
		await process_frame
		if not C.busy and i > 3:
			break
	var b_side: Dictionary = save.to_dict()
	b_side.salvage = 555
	b_side.pilot_xp = 7000
	_switch_account(amock, "acct-B")
	amock.set_blob(CS.encode(b_side))
	C.sync_now(true)
	for i in range(120):
		await process_frame
		if not C.busy and i > 3:
			break
	await open_profile.call()
	check(C.status() == St.ACCOUNT and seen.call("ACCOUNT CHANGED") and seen.call("USE THIS DEVICE'S SAVE") and seen.call("LOAD THIS ACCOUNT'S CLOUD SAVE") and seen.call("PAUSE CLOUD SYNC"), "a different account shows ACCOUNT CHANGED with its three choices")
	check(seen.call("THIS DEVICE") and seen.call("NEW ACCOUNT'S CLOUD") and seen.call("12,345 SALVAGE") and seen.call("555 SALVAGE"), "both saves are described with real numbers")
	check(_shown_has(profile, "Nothing was changed") and _shown_has(profile, "Uploads this device's progress to the new account") and _shown_has(profile, "Replaces this device's progress with the new account's"), "the screen says nothing changed and what each choice will do")
	check(rect_ok.call("cloud_acct_local") and rect_ok.call("cloud_acct_cloud") and rect_ok.call("cloud_acct_pause"), "all three choices are full-size touch targets")
	var guard2: Dictionary = save.to_dict()
	var saves_guard2: int = amock.saves
	await _press_id(menu.ui, "cloud_acct_cloud")
	for i in range(4):
		await process_frame
	check(seen.call("YES, REPLACE THIS DEVICE'S SAVE") and seen.call("CANCEL") and C.status() == St.ACCOUNT and CS.progress_hash(save.to_dict()) == CS.progress_hash(guard2), "a choice needs a second tap and changes nothing on the first")
	await _press_id(menu.ui, "cloud_acct_cancel")
	for i in range(4):
		await process_frame
	check(seen.call("PAUSE CLOUD SYNC") and C.status() == St.ACCOUNT, "Cancel goes back to the choices")
	await _press_id(menu.ui, "cloud_acct_pause")
	for i in range(4):
		await process_frame
	check(seen.call("SYNC PAUSED") and seen.call("CHOOSE WHAT TO DO") and CS.progress_hash(save.to_dict()) == CS.progress_hash(guard2) and amock.saves == saves_guard2, "pausing shows SYNC PAUSED and changes nothing")
	await _press_id(menu.ui, "cloud_acct_review")
	for i in range(4):
		await process_frame
	check(seen.call("LOAD THIS ACCOUNT'S CLOUD SAVE"), "Choose what to do brings the choices back")
	await _press_id(menu.ui, "cloud_acct_cloud")
	for i in range(4):
		await process_frame
	await _press_id(menu.ui, "cloud_acct_confirm")
	for i in range(60):
		await process_frame
		if not C.busy and i > 3:
			break
	check(save.salvage == 555 and C.status() == St.SYNCED, "confirming loads the new account's cloud save")
	# Leave the game's own Cloud as a local guest again.
	menu.queue_free()
	await process_frame
	C.use(plain_backend)
	C.forget_state()
	C.debounce = C.DEBOUNCE
	C.timeout = C.TIMEOUT
	for f in side_files:
		DirAccess.remove_absolute(f)
	print("cloud profile ok")

## Switches the mock to another Google account the way a phone does: signed out, a different player, signed in.
func _switch_account(mock, id: String) -> void:
	var CS = _cloud_script_class()
	mock.set_auth(CS.Auth.SIGNED_OUT)
	mock.set_account(id)
	mock.set_auth(CS.Auth.SIGNED_IN)

func _clear_cloud_files() -> void:
	for suffix in [".cloud", ".before_cloud", ".cloudconflict", ".cloudconflict.1", ".cloudconflict.2"]:
		DirAccess.remove_absolute(save.path + suffix)

func _blob_hash(bytes: PackedByteArray) -> String:
	var r: Dictionary = _cloud_script_class().decode(bytes)
	return _cloud_script_class().progress_hash(r.data) if bool(r.ok) else "unreadable"

func _test_cloud_accounts() -> void:
	var CS = _cloud_script_class()
	var St = CS.Status
	# --- Account A, then account B with no cloud save ---
	_cloud_rich_save()
	_clear_cloud_files()
	var rich: Dictionary = save.to_dict()
	var mock = _cloud_mock_script.new()
	var cloud = _make_cloud(mock)
	await _cloud_settle(cloud)
	check(cloud.status() == St.SYNCED and mock.saves == 1 and mock.checks >= 1, "account A syncs and uploads")
	var a_blob: PackedByteArray = mock.blob.duplicate()
	var rec := FileAccess.get_file_as_string(save.path + ".cloud")
	check(not "acct-A" in rec and CS.account_hash("acct-A") in rec, "only a hash of the player id is stored")
	_switch_account(mock, "acct-B")
	await _cloud_settle(cloud)
	check(cloud.status() == St.ACCOUNT and cloud.status_label() == "ACCOUNT CHANGED" and bool(cloud.account_change.probed) and bool(cloud.account_change.empty), "a different account with no cloud save asks first")
	check(mock.saves == 1 and CS.progress_hash(save.to_dict()) == CS.progress_hash(rich), "nothing was uploaded to the new account and the local save is unchanged")
	check(mock.blob_of("acct-A") == a_blob and not mock.has_blob_of("acct-B"), "account A's cloud save is untouched and B still has none")
	var checks_before: int = mock.checks
	cloud.sync_now()
	cloud._on_timer()
	await process_frame
	check(mock.checks == checks_before and cloud.status() == St.ACCOUNT, "scheduled syncs do not run while the decision waits")
	cloud.account_use_cloud()
	check(cloud.status() == St.ACCOUNT, "loading a cloud save that does not exist is not possible")
	cloud.account_use_local()
	await _cloud_settle(cloud)
	check(cloud.status() == St.SYNCED and cloud.account_change.is_empty() and _blob_hash(mock.blob_of("acct-B")) == CS.progress_hash(save.to_dict()), "choosing this device's save carries it to account B")
	check(mock.blob_of("acct-A") == a_blob, "and account A's cloud save is still untouched")
	await _free_cloud(cloud)

	# --- Account A, then account B that already has a cloud save ---
	_cloud_rich_save()
	_clear_cloud_files()
	rich = save.to_dict()
	mock = _cloud_mock_script.new()
	cloud = _make_cloud(mock)
	await _cloud_settle(cloud)
	a_blob = mock.blob.duplicate()
	var b_side: Dictionary = rich.duplicate(true)
	b_side.salvage = 777
	b_side.pilot_xp = 1234
	_switch_account(mock, "acct-B")
	mock.set_blob(CS.encode(b_side))
	cloud.sync_now(true)
	await _cloud_settle(cloud)
	check(cloud.status() == St.ACCOUNT and int(cloud.account_change.cloud.salvage) == 777, "account B's existing cloud save is shown")
	check(save.salvage == 12345 and _blob_hash(mock.blob) == CS.progress_hash(b_side) and mock.saves == 1, "neither save changed while waiting")
	cloud.account_use_cloud()
	await _cloud_settle(cloud)
	check(save.salvage == 777 and cloud.status() == St.SYNCED, "choosing the new account's save restores it")
	check(FileAccess.file_exists(save.path + ".before_cloud") and int(CS.decode(_read_blob(save.path + ".cloudconflict")).data.salvage) == 12345, "and this device's save is kept in files")
	check(mock.blob_of("acct-A") == a_blob, "account A's cloud save is untouched")
	# Back to A: the device now holds B's save, so it asks again and changes nothing.
	_switch_account(mock, "acct-A")
	await _cloud_settle(cloud)
	check(cloud.status() == St.ACCOUNT and int(cloud.account_change.cloud.salvage) == 12345, "switching back to A asks again, showing A's cloud save")
	cloud.account_pause()
	check(cloud.status_label() == "SYNC PAUSED" and save.salvage == 777 and mock.blob_of("acct-A") == a_blob and _blob_hash(mock.blob_of("acct-B")) == CS.progress_hash(b_side), "pausing leaves every save as it was")
	await _free_cloud(cloud)

	# --- B with a cloud save, and the player carries this device's save over it ---
	_cloud_rich_save()
	_clear_cloud_files()
	rich = save.to_dict()
	mock = _cloud_mock_script.new()
	cloud = _make_cloud(mock)
	await _cloud_settle(cloud)
	_switch_account(mock, "acct-B")
	mock.set_blob(CS.encode(b_side))
	cloud.sync_now(true)
	await _cloud_settle(cloud)
	cloud.account_use_local()
	await _cloud_settle(cloud)
	check(cloud.status() == St.SYNCED and _blob_hash(mock.blob) == CS.progress_hash(save.to_dict()), "this device's save replaced B's cloud save by choice")
	check(int(CS.decode(_read_blob(save.path + ".cloudconflict")).data.salvage) == 777, "and B's old cloud save was kept in a file")
	await _free_cloud(cloud)

	# --- Switching to B and straight back to A resumes normally ---
	_cloud_rich_save()
	_clear_cloud_files()
	rich = save.to_dict()
	mock = _cloud_mock_script.new()
	cloud = _make_cloud(mock)
	await _cloud_settle(cloud)
	_switch_account(mock, "acct-B")
	await _cloud_settle(cloud)
	cloud.account_pause()
	_switch_account(mock, "acct-A")
	await _cloud_settle(cloud)
	check(cloud.status() == St.SYNCED and cloud.account_change.is_empty() and mock.saves == 1 and CS.progress_hash(save.to_dict()) == CS.progress_hash(rich), "back on the original account, syncing resumes without a question")
	# --- Signing out and in again as the same account ---
	mock.set_auth(CS.Auth.SIGNED_OUT)
	await process_frame
	check(cloud.status() == St.GUEST and CS.progress_hash(save.to_dict()) == CS.progress_hash(rich), "signed out is LOCAL GUEST with the save intact")
	mock.set_auth(CS.Auth.SIGNED_IN)
	await _cloud_settle(cloud)
	check(cloud.status() == St.SYNCED and cloud.account_change.is_empty() and mock.saves == 1, "signing in again as the same account needs no decision")
	await _free_cloud(cloud)

	# --- The account changes while a request is pending ---
	_cloud_rich_save()
	_clear_cloud_files()
	mock = _cloud_mock_script.new()
	mock.late_after_abort = true
	cloud = _make_cloud(mock)
	await _cloud_settle(cloud)
	var saves_a: int = mock.saves
	a_blob = mock.blob.duplicate()
	save.salvage += 9
	save.save_data()
	var pending_local: Dictionary = save.to_dict()
	mock.hold = "check"
	cloud.sync_now(true)
	await process_frame
	await process_frame
	check(cloud.busy, "a request is pending")
	_switch_account(mock, "acct-B")
	mock.hold = ""
	mock.release()
	await _cloud_settle(cloud)
	check(cloud.status() == St.ACCOUNT and mock.saves == saves_a, "the late answer for account A decided nothing: the new account is asked about, nothing uploaded")
	check(mock.blob_of("acct-A") == a_blob and not mock.has_blob_of("acct-B") and CS.progress_hash(save.to_dict()) == CS.progress_hash(pending_local), "A's cloud save and the local changes are exactly as they were")
	await _free_cloud(cloud)
	# A change nobody announced is still caught, because the player is confirmed before every sync.
	_cloud_rich_save()
	_clear_cloud_files()
	mock = _cloud_mock_script.new()
	cloud = _make_cloud(mock)
	await _cloud_settle(cloud)
	mock.set_account("acct-B")
	save.salvage += 1
	save.save_data()
	await _cloud_settle(cloud)
	check(cloud.status() == St.ACCOUNT and mock.saves == 1, "a silent account change is caught at the next sync and nothing is uploaded")
	await _free_cloud(cloud)

	# --- The identity cannot be confirmed ---
	_cloud_rich_save()
	_clear_cloud_files()
	rich = save.to_dict()
	mock = _cloud_mock_script.new()
	mock.identity_empty = true
	cloud = _make_cloud(mock)
	await _cloud_settle(cloud)
	check(cloud.status() == St.ERROR and cloud._fail_kind == "identity" and "which Google Play Games account" in cloud.last_error, "an unknown player means no sync, with an explanation")
	check(mock.loads == 0 and mock.saves == 0 and CS.progress_hash(save.to_dict()) == CS.progress_hash(rich) and not FileAccess.file_exists(save.path + ".cloud"), "nothing was read, written or recorded")
	mock.identity_empty = false
	mock.identity_fail = true
	cloud.sync_now(true)
	await _cloud_settle(cloud)
	check(cloud._fail_kind == "identity" and mock.loads == 0, "a failed identity check also stops the sync")
	mock.identity_fail = false
	cloud.sync_now(true)
	await _cloud_settle(cloud)
	check(cloud.status() == St.SYNCED, "and it syncs once the player can be confirmed")
	await _free_cloud(cloud)

	# --- A sync record from before accounts were recorded is not trusted ---
	_cloud_rich_save()
	_clear_cloud_files()
	mock = _cloud_mock_script.new()
	cloud = _make_cloud(mock)
	await _cloud_settle(cloud)
	await _free_cloud(cloud)
	var legacy := ConfigFile.new()
	legacy.load(save.path + ".cloud")
	legacy.erase_section_key("sync", "account")
	legacy.save(save.path + ".cloud")
	save.salvage += 1
	save.save_data()
	cloud = _cloud_script.new()
	cloud.autostart = false
	cloud.debounce = 0.05
	root.add_child(cloud)
	cloud.use(mock)
	await _cloud_settle(cloud)
	check(cloud.status() == St.CONFLICT and mock.saves == 1, "a record that names no account is dropped: both saves have progress, so the player is asked")
	await _free_cloud(cloud)
	_clear_cloud_files()
	print("cloud accounts ok")

## Signing out, or switching account, with a request pending must leave nothing running.
func _test_cloud_cleanup() -> void:
	var CS = _cloud_script_class()
	var St = CS.Status
	# --- Sign out while a load is pending, then sign in again ---
	_cloud_rich_save()
	_clear_cloud_files()
	var rich: Dictionary = save.to_dict()
	var mock = _cloud_mock_script.new()
	mock.hold = "load"
	mock.late_after_abort = true
	var cloud = _make_cloud(mock)
	for i in range(8):
		await process_frame
	check(cloud.busy, "a load is pending")
	mock.set_auth(CS.Auth.SIGNED_OUT)
	check(not cloud.busy and cloud.status() == St.GUEST and mock.aborts >= 1 and cloud._timer.is_stopped(), "signing out stops the request, tells the backend to abort and cancels the timer")
	mock.release()
	await process_frame
	check(cloud.status() == St.GUEST and mock.saves == 0 and CS.progress_hash(save.to_dict()) == CS.progress_hash(rich), "the late load answer changed nothing")
	mock.hold = ""
	mock.set_auth(CS.Auth.SIGNED_IN)
	await _cloud_settle(cloud)
	check(cloud.status() == St.SYNCED and mock.saves == 1 and mock.exists, "signing in again starts a fresh operation that succeeds")
	await _free_cloud(cloud)
	# --- Sign out while a save is pending, then sign in again ---
	_cloud_rich_save()
	_clear_cloud_files()
	rich = save.to_dict()
	mock = _cloud_mock_script.new()
	mock.hold = "save"
	mock.late_after_abort = true
	cloud = _make_cloud(mock)
	for i in range(10):
		await process_frame
	check(cloud.busy and mock.saves == 1, "a save is pending")
	mock.set_auth(CS.Auth.SIGNED_OUT)
	check(not cloud.busy and cloud.status() == St.GUEST and mock.aborts >= 1, "signing out abandons the save")
	mock.release()
	await process_frame
	check(cloud.status() == St.GUEST, "the late save answer did not bring the session back")
	var rec := ConfigFile.new()
	var recorded := rec.load(save.path + ".cloud") == OK and str(rec.get_value("sync", "base_local", "")) != ""
	check(not recorded, "the abandoned save was not recorded as synced")
	mock.hold = ""
	mock.set_auth(CS.Auth.SIGNED_IN)
	await _cloud_settle(cloud)
	check(cloud.status() == St.SYNCED and mock.saves == 1 and CS.progress_hash(save.to_dict()) == CS.progress_hash(rich), "signing in again finds the cloud matches and finishes cleanly")
	await _free_cloud(cloud)
	# --- A scheduled retry does not survive a sign-out ---
	_cloud_rich_save()
	_clear_cloud_files()
	mock = _cloud_mock_script.new()
	mock.offline = true
	cloud = _make_cloud(mock)
	await _cloud_settle(cloud)
	check(cloud.status() == St.OFFLINE and not cloud._timer.is_stopped(), "an offline failure schedules a retry")
	mock.set_auth(CS.Auth.SIGNED_OUT)
	check(cloud._timer.is_stopped() and cloud.last_error == "", "signing out cancels the scheduled retry and clears the old error")
	await _free_cloud(cloud)
	# --- Sign-in that never answers ends in an error, not in waiting forever ---
	mock = _cloud_mock_script.new()
	mock.set_auth(CS.Auth.CHECKING)
	cloud = _make_cloud(mock, false)
	await create_timer(0.8).timeout
	check(mock.auth == CS.Auth.ERROR and cloud.status() == St.ERROR and cloud.account_text() != "", "a sign-in check that never answers becomes SYNC ERROR")
	await _free_cloud(cloud)
	_clear_cloud_files()
	print("cloud cleanup ok")

## Every field of Save.PROGRESS_KEYS is either meaningful progress or listed as generated. Anything meaningful, alone,
## stops a save being taken for a fresh install.
func _test_has_progress() -> void:
	var CS = _cloud_script_class()
	var fresh: Dictionary = save._defaults.duplicate(true)
	# What a brand new install holds after its first launch: today's contracts and the title screen's derived statistics.
	fresh["contracts"] = {"day": 20000, "list": [{"id": "c1", "text": "Do a thing", "stat": "kill", "goal": 50, "reward": 40, "progress": 0, "done": false, "claimed": false}], "reroll": 1}
	fresh["stats"] = {"ships_owned": 1, "best_mastery": 1, "pilot_level": 1}
	fresh["gear_uid"] = 17
	fresh["danger"] = {"done": {}, "last": {}}
	check(not CS.has_progress(fresh), "a new install with generated contracts, derived statistics and a gear counter is not progress")
	check(not CS.has_progress(save._defaults), "the bare defaults are not progress")
	var covered := {}
	var cases := {
		"salvage": 1, "parts": 1, "pilot_xp": 5, "best_score": 10, "endless_best_wave": 2, "expedition_wins": 1, "tier_unlocked": 1, "reroll_tokens": 1,
		"unlocked": 2, "ship": "lancer", "nova_mode": "singularity",
		"star_mask": {1: 1}, "level_best": {1: 500}, "upgrades": {"hull": 1}, "mastery": {"nova": 10}, "paints": {"nova": "ember"}, "tutorial": {"move": true},
		"achievements": {"first_kill": true}, "codex": {"fighter": true}, "expedition": {"active": true}, "weekly_best": {"w": 1}, "daily_best": {"d": 1},
		"equipped": {"nova": {"weapon": 3}}, "tier_data": {1: {"unlocked": 2, "stars": {}}},
		"gear": [{"uid": 1}], "blueprints": ["bp_aegis"], "loadout": ["spread"], "side_cleared": [101], "bosses_beaten": [1], "seen_unlocks": ["u"], "rift_claimed": [5],
		"owned_ships": ["nova", "lancer"],
		"stats": {"kill": 1}, "contracts": {"day": 20000, "list": [{"progress": 3, "done": false, "claimed": false}]},
		"danger": {"done": {"rush": 1}, "last": {}},
	}
	for key in cases:
		var d: Dictionary = fresh.duplicate(true)
		d[key] = cases[key]
		covered[key] = true
		check(CS.has_progress(d), "%s alone counts as progress" % key)
	# Variants of the two keys that are partly generated.
	for variant in [
		["stats", {"ships_owned": 1, "seen_enemy": ["fighter"]}], ["stats", {"best_combo": 12}], ["stats", {"ships_owned": 1, "kill": 0, "boss": 0}],
		["contracts", {"day": 1, "list": [{"progress": 0, "done": true, "claimed": false}]}], ["contracts", {"day": 1, "list": [{"progress": 0, "done": false, "claimed": true}]}],
		["danger", {"done": {}, "last": {"campaign": ["rush"]}}],
	]:
		var d2: Dictionary = fresh.duplicate(true)
		d2[variant[0]] = variant[1]
		var expect: bool = not (str(variant[0]) == "stats" and variant[1].get("kill", -1) == 0)
		check(CS.has_progress(d2) == expect, "%s variant %s %s progress" % [variant[0], str(variant[1]), "is" if expect else "is not"])
	# Nothing in PROGRESS_KEYS may be unclassified: a new key must be added to has_progress, or listed as generated.
	for key in save.PROGRESS_KEYS:
		check(covered.has(key) or key in CS.GENERATED_KEYS, "PROGRESS_KEYS entry %s is classified by has_progress" % key)
	for key in CS.GENERATED_KEYS:
		var d3: Dictionary = fresh.duplicate(true)
		d3[key] = 9999
		check(not CS.has_progress(d3), "generated key %s alone does not count" % key)
	print("has_progress ok")


## The Google Play Games adapter, run against a stand-in for the plugin (tools/fake_pgs) that copies the v3.4.0 wrappers.
## This proves the adapter's lifecycle and its handling of answers, silence, conflicts and late callbacks on desktop.
## It does not prove anything about the real plugin, Google's services or a phone.

const FAKE_SCRIPTS := {
	"sign_in": "res://tools/fake_pgs/fake_sign_in_client.gd",
	"snapshots": "res://tools/fake_pgs/fake_snapshots_client.gd",
	"players": "res://tools/fake_pgs/fake_players_client.gd",
}

func _pgs_rig(with_main := true, native := true) -> Dictionary:
	var rig := {"main": null}
	if with_main:
		var main = load("res://tools/fake_pgs/fake_play_games_services.gd").new()
		main.name = "GodotPlayGameServices"
		main.native_present = native
		root.add_child(main)
		rig.main = main
	var adapter = load("res://src/meta/cloud_play_games.gd").new()
	adapter.platform_name = "Android"
	adapter.verify_delay = 0.0
	adapter.scripts = FAKE_SCRIPTS.duplicate()
	var main_ref = rig.main
	adapter.native_present = func() -> bool: return main_ref != null and bool(main_ref.native_present)
	var cloud = _cloud_script.new()
	cloud.autostart = false
	cloud.debounce = 0.05
	cloud.timeout = 1.0
	cloud.auth_timeout = 0.4
	root.add_child(cloud)
	cloud.forget_state()
	rig.adapter = adapter
	rig.cloud = cloud
	return rig

func _pgs_free(rig: Dictionary) -> void:
	rig.cloud.queue_free()
	if rig.main != null:
		rig.main.queue_free()
	await process_frame

func _until(cond: Callable, frames := 150) -> bool:
	for i in range(frames):
		if cond.call():
			return true
		await process_frame
	return cond.call()

## Plays the sign-in and the player check, up to the point where the plugin is asked to open the snapshot.
func _pgs_to_load(rig: Dictionary, player := "player-1") -> void:
	var android = rig.main.android_plugin
	var loads: int = android.count("loadGame")
	var players: int = android.count("loadCurrentPlayer")
	android.emit_authenticated(true)
	await _until(func(): return android.count("loadCurrentPlayer") > players)
	android.emit_player(player)
	await _until(func(): return android.count("loadGame") > loads)

## ... and on to the point where it is asked to write the snapshot (the cloud holds nothing yet).
func _pgs_to_save(rig: Dictionary) -> void:
	var android = rig.main.android_plugin
	var saves: int = android.count("saveGame")
	await _pgs_to_load(rig)
	android.emit_loaded(PackedByteArray())
	await _until(func(): return android.count("saveGame") > saves)

func _test_cloud_plugin() -> void:
	var CS = _cloud_script_class()
	var St = CS.Status
	var files := [save.path + ".cloudconflict.1", save.path + ".cloudconflict.2"]
	# --- Availability is decided by what is really there ---
	var rig := _pgs_rig()
	check(rig.adapter.available(), "with the plugin's autoload, client scripts and native plugin present, the integration is available")
	rig.adapter.platform_name = "Windows"
	check(not rig.adapter.available(), "off Android it is not available")
	rig.adapter.platform_name = "Android"
	rig.main.native_present = false
	check(not rig.adapter.available(), "without the native plugin it is not available")
	rig.main.native_present = true
	rig.adapter.scripts = {"sign_in": "res://tools/fake_pgs/missing.gd", "snapshots": FAKE_SCRIPTS.snapshots, "players": FAKE_SCRIPTS.players}
	check(not rig.adapter.available(), "with a client script missing it is not available")
	await _pgs_free(rig)
	rig = _pgs_rig(false)
	check(not rig.adapter.available(), "without the plugin's autoload it is not available")
	rig.cloud.use(rig.adapter)
	check(rig.cloud.status() == St.GUEST and rig.adapter._clients == null, "started anyway, it fails safely to LOCAL GUEST and creates nothing")
	await _pgs_free(rig)
	rig = _pgs_rig(true, false)
	rig.cloud.use(rig.adapter)
	check(rig.cloud.status() == St.GUEST and rig.adapter._clients == null and "could not start" in rig.cloud.account_text(), "a failed plugin initialize also plays as LOCAL GUEST, with a reason")
	await _pgs_free(rig)

	# --- The lifecycle: initialize, then create the client Nodes, which then stay ---
	_cloud_rich_save()
	_clear_cloud_files()
	var rich: Dictionary = save.to_dict()
	rig = _pgs_rig()
	var cloud = rig.cloud
	var adapter = rig.adapter
	var main = rig.main
	cloud.use(adapter)
	var android = main.android_plugin
	check(android != null and android.initialized and main.initialize_calls == 1, "the plugin's autoload was initialized once")
	check(adapter._sign_in.wired and adapter._snapshots.wired and adapter._players.wired, "the client Nodes were created after initialization and connected to the plugin")
	check(adapter._clients.get_parent() == cloud and adapter._sign_in.is_inside_tree() and adapter._snapshots.get_parent() == adapter._clients, "and live under the Cloud autoload for the whole session")
	check(android.count("isAuthenticated") == 1 and cloud.status() == St.CONNECTING, "the sign-in check is asked for explicitly")
	cloud.use(adapter)
	check(main.initialize_calls == 1 and adapter._clients.get_child_count() == 3, "starting again does not initialize twice or duplicate the clients")
	await _pgs_to_save(rig)
	check(cloud.status() == St.CONNECTED or cloud.busy, "signed in, the account is confirmed before the save is touched")
	check(android.last("loadCurrentPlayer")[1] == true and android.last("loadGame")[2] == true, "the player is reloaded fresh, and the snapshot is opened with create-if-missing")
	var written: Array = android.last("saveGame")
	check(str(written[1]) == CS.SNAPSHOT_NAME and bool(CS.decode(written[3]).ok) and CS.progress_hash(CS.decode(written[3]).data) == CS.progress_hash(rich) and int(written[5]) > 1000000000, "the complete save is written under the one snapshot name")
	android.emit_saved(true)
	await _until(func(): return android.count("loadGame") == 2)
	check(cloud.busy, "'saved' is not believed until the snapshot has been read back")
	android.emit_loaded(written[3])
	await _cloud_settle(cloud)
	check(cloud.status() == St.SYNCED and not cloud.pending, "and then the sync is complete")
	await _pgs_free(rig)

	# --- A read-back that does not match is not a success ---
	_cloud_rich_save()
	_clear_cloud_files()
	rig = _pgs_rig()
	rig.cloud.use(rig.adapter)
	android = rig.main.android_plugin
	await _pgs_to_save(rig)
	android.emit_saved(true)
	await _until(func(): return android.count("loadGame") == 2)
	android.emit_loaded(PackedByteArray([1, 2, 3]))
	await _cloud_settle(rig.cloud)
	check(rig.cloud.status() == St.ERROR and rig.cloud.pending and rig.cloud._fail_kind == "unverified", "a snapshot that does not hold what was written is an error, not CLOUD SYNCED")
	await _pgs_free(rig)

	# --- A conflict while saving, and while loading ---
	for origin in ["SAVE", "LOAD"]:
		_cloud_rich_save()
		_clear_cloud_files()
		rich = save.to_dict()
		var mine: Dictionary = rich.duplicate(true)
		mine.salvage = 101
		var theirs: Dictionary = rich.duplicate(true)
		theirs.salvage = 202
		rig = _pgs_rig()
		rig.cloud.use(rig.adapter)
		android = rig.main.android_plugin
		var t0 := Time.get_ticks_msec()
		if origin == "SAVE":
			await _pgs_to_save(rig)
		else:
			await _pgs_to_load(rig)
		android.emit_conflict(origin, CS.encode(mine), CS.encode(theirs))
		await _cloud_settle(rig.cloud)
		check(rig.cloud._fail_kind == "conflict" and rig.cloud.status() == St.ERROR and not rig.cloud.busy, "a %s conflict completes the request at once as a failure" % origin)
		check(Time.get_ticks_msec() - t0 < 900, "without waiting for the timeout (%s)" % origin)
		check(int(CS.decode(_read_blob(files[0])).data.salvage) == 101 and int(CS.decode(_read_blob(files[1])).data.salvage) == 202, "both versions Google reported are kept as files (%s)" % origin)
		check(CS.progress_hash(save.to_dict()) == CS.progress_hash(rich), "the local save is untouched (%s)" % origin)
		var loads_now: int = android.count("loadGame")
		var saves_now: int = android.count("saveGame")
		android.emit_saved(true)
		android.emit_loaded(CS.encode(rich))
		await process_frame
		check(android.count("loadGame") == loads_now and android.count("saveGame") == saves_now and rig.cloud._fail_kind == "conflict", "answers that arrive after the conflict change nothing (%s)" % origin)
		await _pgs_free(rig)
	# A request is answered exactly once, whatever the plugin emits afterwards.
	rig = _pgs_rig()
	rig.adapter.start(rig.cloud)
	android = rig.main.android_plugin
	android.emit_authenticated(true)
	await process_frame
	var answers := []
	rig.adapter.save_snapshot(CS.SNAPSHOT_NAME, "d", PackedByteArray([1, 2, 3]), 1, func(r): answers.append(r))
	android.emit_conflict("SAVE", PackedByteArray([1]), PackedByteArray([2]))
	android.emit_saved(true)
	android.emit_loaded(PackedByteArray([1, 2, 3]))
	android.emit_conflict("SAVE", PackedByteArray([1]), PackedByteArray([2]))
	await process_frame
	check(answers.size() == 1 and str(answers[0].kind) == "conflict" and (answers[0].candidates as Array).size() == 2, "a request completes exactly once, with both versions attached")
	answers.clear()
	rig.adapter.save_snapshot(CS.SNAPSHOT_NAME, "d", PackedByteArray([1, 2, 3]), 1, func(r): answers.append(r))
	android.emit_saved(true)
	android.emit_loaded(PackedByteArray([1, 2, 3]))
	android.emit_saved(true)
	android.emit_loaded(PackedByteArray([1, 2, 3]))
	await process_frame
	check(answers.size() == 1 and bool(answers[0].ok), "a save answered, verified and then repeated still completes once")
	await _pgs_free(rig)

	# --- Silence times out, a late answer is ignored, and the next request works ---
	_cloud_rich_save()
	_clear_cloud_files()
	rich = save.to_dict()
	rig = _pgs_rig()
	rig.cloud.timeout = 0.3
	rig.cloud.use(rig.adapter)
	android = rig.main.android_plugin
	await _pgs_to_load(rig)
	await create_timer(0.7).timeout
	check(rig.cloud.status() == St.OFFLINE and not rig.adapter._done.is_valid(), "silence ends as OFFLINE and the adapter forgets the request")
	var saves_before: int = android.count("saveGame")
	android.emit_loaded(PackedByteArray())
	await process_frame
	check(android.count("saveGame") == saves_before and rig.cloud.status() == St.OFFLINE and CS.progress_hash(save.to_dict()) == CS.progress_hash(rich), "a late answer after the timeout changes nothing")
	var players_before: int = android.count("loadCurrentPlayer")
	rig.cloud.sync_now(true)
	await _until(func(): return android.count("loadCurrentPlayer") > players_before)
	check(android.count("loadCurrentPlayer") == players_before + 1 and rig.cloud.busy, "and the next sync starts normally")
	await _pgs_free(rig)

	# --- Sign out with a request pending, then sign in again ---
	for pending_step in ["load", "save"]:
		_cloud_rich_save()
		_clear_cloud_files()
		rich = save.to_dict()
		rig = _pgs_rig()
		rig.cloud.use(rig.adapter)
		android = rig.main.android_plugin
		if pending_step == "load":
			await _pgs_to_load(rig)
		else:
			await _pgs_to_save(rig)
		android.emit_authenticated(false)
		check(rig.cloud.status() == St.GUEST and not rig.cloud.busy and not rig.adapter._done.is_valid(), "signing out with a %s pending drops it" % pending_step)
		var s0: int = android.count("saveGame")
		var l0: int = android.count("loadGame")
		android.emit_saved(true)
		android.emit_loaded(CS.encode(rich))
		android.emit_player("player-1")
		await process_frame
		check(android.count("saveGame") == s0 and android.count("loadGame") == l0 and rig.cloud.status() == St.GUEST, "its late answers changed nothing (%s)" % pending_step)
		await _pgs_to_load(rig)
		check(rig.cloud.busy, "signing in again starts a fresh operation (%s)" % pending_step)
		await _pgs_free(rig)

	# --- An unknown player means no sync ---
	_cloud_rich_save()
	_clear_cloud_files()
	rig = _pgs_rig()
	rig.cloud.use(rig.adapter)
	android = rig.main.android_plugin
	android.emit_authenticated(true)
	await _until(func(): return android.count("loadCurrentPlayer") == 1)
	android.emit_player("")
	await _cloud_settle(rig.cloud)
	check(rig.cloud._fail_kind == "identity" and rig.cloud.status() == St.ERROR and android.count("loadGame") == 0 and android.count("saveGame") == 0, "a missing player id stops the sync before the save is touched")
	await _pgs_free(rig)

	# --- Sign-in answers ---
	rig = _pgs_rig()
	rig.cloud.use(rig.adapter)
	android = rig.main.android_plugin
	android.emit_authenticated(false)
	await process_frame
	check(rig.cloud.status() == St.GUEST and rig.cloud.can_connect(), "not signed in is LOCAL GUEST with a Connect button")
	rig.cloud.connect_account()
	check(android.count("signIn") == 1 and rig.adapter.auth == CS.Auth.CHECKING, "Connect asks the plugin to sign in")
	await _pgs_free(rig)
	for f in files:
		DirAccess.remove_absolute(f)
	_clear_cloud_files()
	print("cloud plugin ok")

func _sha(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()

func _shown_has(profile, fragment: String) -> bool:
	for line in profile.shown:
		if fragment in str(line):
			return true
	return false

## Presses a control with a real touch (down and up) on the layer that owns it.
func _press_id(ui, id: String) -> void:
	var rect: Rect2 = ui.rect_of(id)
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.position = rect.get_center()
	down.pressed = true
	ui._input(down)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.position = rect.get_center()
	up.pressed = false
	ui._input(up)
	await process_frame

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
