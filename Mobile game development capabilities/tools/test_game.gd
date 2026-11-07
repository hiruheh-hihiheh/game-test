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
	await _test_combat_polish()
	await _test_telegraphs()
	await _test_telegraph_bosses()
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
func _make_cloud(mock, signed_in := true, script = null):
	var cloud = (script if script != null else _cloud_script).new()
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
	check(_rec_exists("local_save_file") and cloud.status() == St.SYNCED, "the old save was kept in a backup file first")
	await _free_cloud(cloud)
	# --- Guest progress is uploaded ---
	_cloud_rich_save()
	rich = save.to_dict()
	_clear_cloud_files()
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
		check(bool(CS.decode(_rec("google_version_1")).ok) and int(CS.decode(_rec("google_version_2")).data.salvage) == 222 and int(CS.decode(_rec("google_version_1")).data.salvage) == 111, "both reported versions are kept as files (%s)" % origin)
		check(CS.progress_hash(save.to_dict()) == CS.progress_hash(local_conflict) and mock.blob == blob_before, "nothing local or in the cloud was overwritten (%s)" % origin)
		check(cloud._timer.is_stopped(), "a conflict is not retried on a timer (%s)" % origin)
		cloud.sync_now(true)
		await _cloud_settle(cloud)
		check(cloud.status() == St.SYNCED, "Sync Now tries again and succeeds once the conflict is gone (%s)" % origin)
	await _free_cloud(cloud)
	# --- Offline: nothing is lost, and the upload happens later ---
	_cloud_rich_save()
	rich = save.to_dict()
	_clear_cloud_files()
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
	_clear_cloud_files()
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
	_clear_cloud_files()
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
	check(bool(CS.decode(_rec("cloud_save")).ok) and int(CS.decode(_rec("cloud_save")).data.salvage) == 999, "and the replaced cloud save is kept in a file")
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
	check(int(CS.decode(_rec("local_progress")).data.salvage) == 6 and _rec_exists("local_save_file"), "and this device's save is kept in files")
	await _free_cloud(cloud)
	# --- A save erased on this device is never pushed over the cloud, and never restored silently ---
	_cloud_rich_save()
	_clear_cloud_files()
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
	_clear_cloud_files()
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
		_clear_cloud_files()
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
		_clear_cloud_files()
		mock = _cloud_mock_script.new()
		mock.set_blob(junk)
		cloud = _make_cloud(mock)
		await _cloud_settle(cloud)
		check(cloud.status() == St.ERROR and mock.saves == 0 and not CS.has_progress(save.to_dict()), "%s cloud data on a new install is an error, not a restore" % case)
		await _free_cloud(cloud)
	# --- Sign-in comes and goes ---
	_cloud_rich_save()
	_clear_cloud_files()
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
	await _test_cloud_preservation()
	await _test_cloud_plugin()
	await _test_cloud_profile(rich)
	# --- Put the test save back ---
	_clear_cloud_files()
	save.restore_progress(original)
	print("cloud sync ok")

## The Pilot Profile's ACCOUNT & CLOUD SAVE section, in every state, driven by the game's own Cloud with a mock service.
func _test_cloud_profile(rich: Dictionary) -> void:
	var CS = _cloud_script_class()
	var St = CS.Status
	var C = root.get_node("Cloud")
	var plain_backend = C.backend
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
	# If this device's save cannot be copied away first, nothing is replaced and the page says why.
	var blocked_by: String = save.path + ".recovery"
	save.remove_recovery(save.path)
	_write_text(blocked_by, "a file where the recovery folder should be")
	var guard_restore: Dictionary = save.to_dict()
	await _press_id(menu.ui, "cloud_confirm")
	for i in range(6):
		await process_frame
	check(C.status() == St.CONFLICT and CS.progress_hash(save.to_dict()) == CS.progress_hash(guard_restore) and _shown_has(profile, "Could not keep a copy") and _shown_has(profile, "Your saves are unchanged"), "a failed backup is explained on the page and nothing was replaced")
	check(rect_ok.call("cloud_keep") and rect_ok.call("cloud_restore"), "and the decision is still there")
	DirAccess.remove_absolute(blocked_by)
	await _press_id(menu.ui, "cloud_restore")
	for i in range(4):
		await process_frame
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
	_clear_cloud_files()
	print("cloud profile ok")

## Switches the mock to another Google account the way a phone does: signed out, a different player, signed in.
func _switch_account(mock, id: String) -> void:
	var CS = _cloud_script_class()
	mock.set_auth(CS.Auth.SIGNED_OUT)
	mock.set_account(id)
	mock.set_auth(CS.Auth.SIGNED_IN)

func _clear_cloud_files() -> void:
	DirAccess.remove_absolute(save.path + ".cloud")
	save.remove_recovery(save.path)

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
	check(_rec_exists("local_save_file") and int(CS.decode(_rec("local_progress")).data.salvage) == 12345, "and this device's save is kept in files")
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
	check(int(CS.decode(_rec("cloud_save")).data.salvage) == 777, "and B's old cloud save was kept in a file")
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
		check(int(CS.decode(_rec("google_version_1")).data.salvage) == 101 and int(CS.decode(_rec("google_version_2")).data.salvage) == 202, "both versions Google reported are kept as files (%s)" % origin)
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
	_clear_cloud_files()
	print("cloud plugin ok")

## One byte of the base64 payload changed: still plain ASCII, no longer matches its checksum.
func _corrupt_blob(bytes: PackedByteArray) -> PackedByteArray:
	var text := bytes.get_string_from_ascii()
	var at := text.find("\"payload\":\"") + 30
	var ch := text[at]
	text = text.substr(0, at) + ("B" if ch != "B" else "C") + text.substr(at + 1)
	return text.to_ascii_buffer()

func _faulty_cloud(mock, script):
	return _make_cloud(mock, true, script)

# ---- The recovery folder, as a player or a support person would read it ----

func _rec_dir() -> String:
	return save.path + ".recovery"

## Recovery files (not README, not temporary files), oldest first. `kind` filters by name, e.g. "cloud_save".
func _rec_files(kind := "") -> Array:
	var out: Array = []
	var d := DirAccess.open(_rec_dir())
	if d != null:
		for f in d.get_files():
			if f.length() > 7 and f.substr(0, 6).is_valid_int() and f[6] == "_" and not f.ends_with(".unverified") and not f.ends_with(".part") and (kind == "" or f.substr(7).begins_with(kind)):
				out.append(_rec_dir() + "/" + f)
	out.sort()
	return out

func _rec_temps() -> Array:
	var out: Array = []
	var d := DirAccess.open(_rec_dir())
	if d != null:
		for f in d.get_files():
			if f.ends_with(".part"):
				out.append(_rec_dir() + "/" + f)
	return out

## The bytes of the newest recovery file of a kind (`back` = 1 for the one before it), empty if there is none.
func _rec(kind: String, back := 0) -> PackedByteArray:
	var files := _rec_files(kind)
	var i := files.size() - 1 - back
	return _read_blob(files[i]) if i >= 0 else PackedByteArray()

func _rec_exists(kind: String) -> bool:
	return not _rec_files(kind).is_empty()

## Every recovery file with its bytes, to prove later operations leave earlier ones exactly as they were.
func _rec_snapshot() -> Dictionary:
	var out := {}
	for f in _rec_files():
		out[f] = _read_blob(f)
	return out

## A cloud that holds unreadable data, a local save with progress and a CHOOSE A SAVE question waiting.
func _unreadable_conflict(mock, cloud, bytes: PackedByteArray) -> void:
	save.salvage += 1
	save.save_data()
	mock.set_blob(bytes)
	cloud.sync_now(true)
	await _cloud_settle(cloud)

## Replacing a cloud save, restoring over local progress and deciding about an account only ever happen after the
## copy that makes them recoverable has been written and read back. Every failure leaves both sides as they were.
func _test_cloud_preservation() -> void:
	var CS = _cloud_script_class()
	var St = CS.Status
	var faulty = load("res://tools/faulty_cloud_sync.gd")

	# --- Unreadable cloud data, then KEEP THIS DEVICE'S SAVE: the exact bytes are kept ---
	for case in ["corrupted", "newer"]:
		_cloud_rich_save()
		_clear_cloud_files()
		var local: Dictionary = save.to_dict()
		var junk: PackedByteArray
		if case == "corrupted":
			var other: Dictionary = local.duplicate(true)
			other.salvage = 31
			junk = _corrupt_blob(CS.encode(other))
		else:
			var future: Dictionary = local.duplicate(true)
			future["version"] = 99
			future.salvage = 32
			junk = CS.encode(future)
		check(not bool(CS.decode(junk).ok), "the %s blob really is unreadable" % case)
		var mock = _cloud_mock_script.new()
		mock.set_blob(junk)
		var cloud = _make_cloud(mock)
		await _cloud_settle(cloud)
		check(cloud.status() == St.CONFLICT and (cloud.conflict.cloud as Dictionary).is_empty() and cloud.conflict.raw_bytes == junk, "%s cloud data: the conflict holds the original bytes" % case)
		cloud.keep_local()
		await _cloud_settle(cloud)
		check(cloud.status() == St.SYNCED and bool(CS.decode(mock.blob).ok) and CS.progress_hash(CS.decode(mock.blob).data) == CS.progress_hash(local), "%s cloud data: this device's save replaced it" % case)
		check(_rec("cloud_save") == junk, "%s cloud data: the old cloud bytes were kept exactly, not re-encoded" % case)
		await _free_cloud(cloud)

	# --- A readable cloud save is kept exactly as the cloud sent it too ---
	_cloud_rich_save()
	_clear_cloud_files()
	var mine: Dictionary = save.to_dict()
	var theirs: Dictionary = mine.duplicate(true)
	theirs.salvage = 4
	var theirs_blob: PackedByteArray = CS.encode(theirs)
	var mock2 = _cloud_mock_script.new()
	mock2.set_blob(theirs_blob)
	var cloud2 = _make_cloud(mock2)
	await _cloud_settle(cloud2)
	cloud2.keep_local()
	await _cloud_settle(cloud2)
	check(_rec("cloud_save") == theirs_blob and cloud2.status() == St.SYNCED, "a readable cloud save is kept byte for byte")
	await _free_cloud(cloud2)

	# --- Unreadable cloud data during an account switch ---
	_cloud_rich_save()
	_clear_cloud_files()
	mine = save.to_dict()
	var bad_b: PackedByteArray = _corrupt_blob(CS.encode(theirs))
	var mock3 = _cloud_mock_script.new()
	var cloud3 = _make_cloud(mock3)
	await _cloud_settle(cloud3)
	var a_blob: PackedByteArray = mock3.blob.duplicate()
	_switch_account(mock3, "acct-B")
	mock3.set_blob(bad_b)
	cloud3.sync_now(true)
	await _cloud_settle(cloud3)
	check(cloud3.status() == St.ACCOUNT and bool(cloud3.account_change.replaceable) and cloud3.account_change.raw_bytes == bad_b and (cloud3.account_change.cloud as Dictionary).is_empty(), "an unreadable cloud save on the new account is held exactly")
	cloud3.account_use_cloud()
	check(cloud3.status() == St.ACCOUNT and CS.progress_hash(save.to_dict()) == CS.progress_hash(mine), "it cannot be loaded")
	cloud3.account_use_local()
	await _cloud_settle(cloud3)
	check(cloud3.status() == St.SYNCED and _rec("cloud_save") == bad_b, "choosing this device's save kept the new account's unreadable bytes exactly")
	check(CS.progress_hash(CS.decode(mock3.blob).data) == CS.progress_hash(mine) and mock3.blob_of("acct-A") == a_blob, "and replaced only the new account's snapshot")
	await _free_cloud(cloud3)

	# --- Google reports two versions while the new account is being looked at ---
	_cloud_rich_save()
	_clear_cloud_files()
	mine = save.to_dict()
	var ver_a: PackedByteArray = CS.encode(theirs)
	var other_b: Dictionary = theirs.duplicate(true)
	other_b.salvage = 5
	var ver_b: PackedByteArray = CS.encode(other_b)
	var mock4 = _cloud_mock_script.new()
	var cloud4 = _make_cloud(mock4)
	await _cloud_settle(cloud4)
	var saves4: int = mock4.saves
	mock4.conflict_blobs = [ver_a, ver_b]
	mock4.conflict_next = "LOAD"
	_switch_account(mock4, "acct-B")
	await _cloud_settle(cloud4)
	check(cloud4.status() == St.ACCOUNT and bool(cloud4.account_change.conflict) and bool(cloud4.account_change.probed), "a Google conflict while looking at the new account is shown, not dropped")
	check(_rec("google_version_1") == ver_a and _rec("google_version_2") == ver_b, "both versions were kept exactly")
	check("Both versions were kept" in str(cloud4.account_change.bad), "and the screen says so")
	cloud4.account_use_local()
	cloud4.account_use_cloud()
	await process_frame
	check(cloud4.status() == St.ACCOUNT and mock4.saves == saves4 and CS.progress_hash(save.to_dict()) == CS.progress_hash(mine), "neither choice can replace anything while Google holds two versions")
	await _free_cloud(cloud4)
	# One version only.
	_cloud_rich_save()
	_clear_cloud_files()
	var mock5 = _cloud_mock_script.new()
	var cloud5 = _make_cloud(mock5)
	await _cloud_settle(cloud5)
	mock5.conflict_blobs = [ver_a]
	mock5.conflict_next = "LOAD"
	cloud5.sync_now(true)
	await _cloud_settle(cloud5)
	check(_rec("google_version_1") == ver_a and not _rec_exists("google_version_2") and "The version was kept" in cloud5.last_error, "one version: kept, and no second file exists")
	await _free_cloud(cloud5)

	# --- A backup that cannot be started: the recovery folder cannot be made ---
	_cloud_rich_save()
	_clear_cloud_files()
	mine = save.to_dict()
	var junk2: PackedByteArray = _corrupt_blob(CS.encode(theirs))
	var mock6 = _cloud_mock_script.new()
	mock6.set_blob(junk2)
	var cloud6 = _make_cloud(mock6)
	await _cloud_settle(cloud6)
	_write_text(_rec_dir(), "a file where the recovery folder should be")
	cloud6.keep_local()
	await process_frame
	check(cloud6.status() == St.CONFLICT and mock6.saves == 0 and mock6.blob == junk2 and CS.progress_hash(save.to_dict()) == CS.progress_hash(mine), "no recovery folder: the cloud save was not replaced and nothing changed")
	check("Could not keep a copy" in cloud6.choice_error and "the cloud save" in cloud6.choice_error, "and the player is told")
	DirAccess.remove_absolute(_rec_dir())
	cloud6.keep_local()
	await _cloud_settle(cloud6)
	check(cloud6.status() == St.SYNCED and _rec("cloud_save") == junk2 and cloud6.choice_error == "", "with the problem gone, the same decision goes through, and the old bytes are kept")
	await _free_cloud(cloud6)

	# --- Write faults on a first backup ---
	for fault in ["fail_open_for", "fail_store_for", "short_write_for", "fail_promote_for"]:
		_cloud_rich_save()
		_clear_cloud_files()
		mine = save.to_dict()
		var mock7 = _cloud_mock_script.new()
		mock7.set_blob(junk2)
		var cloud7 = _faulty_cloud(mock7, faulty)
		await _cloud_settle(cloud7)
		cloud7.set(fault, "cloud_save")
		cloud7.keep_local()
		await process_frame
		check(cloud7.status() == St.CONFLICT and mock7.saves == 0 and mock7.blob == junk2 and CS.progress_hash(save.to_dict()) == CS.progress_hash(mine) and cloud7.choice_error != "", "%s: KEEP THIS DEVICE'S SAVE does nothing and says why" % fault)
		check(_rec_files("cloud_save").is_empty() and _rec_temps().is_empty(), "%s: no half-written recovery file or temporary file is left" % fault)
		cloud7.set(fault, "")
		cloud7.keep_local()
		await _cloud_settle(cloud7)
		check(cloud7.status() == St.SYNCED and _rec("cloud_save") == junk2, "%s: and works once writes work" % fault)
		await _free_cloud(cloud7)

	# --- Restoring the cloud save when this device's save cannot be backed up ---
	for fault in ["fail_copy", "fail_open_for", "fail_store_for", "short_write_for", "fail_promote_for"]:
		_cloud_rich_save()
		_clear_cloud_files()
		var mock8 = _cloud_mock_script.new()
		var cloud8 = _faulty_cloud(mock8, faulty)
		await _cloud_settle(cloud8)
		var cloud_side: Dictionary = save.to_dict()
		cloud_side.salvage = 777
		mock8.set_blob(CS.encode(cloud_side))
		save.salvage = 5
		save.save_data()
		await _cloud_settle(cloud8)
		check(cloud8.status() == St.CONFLICT, "(%s) both changed: a conflict" % fault)
		mine = save.to_dict()
		var blob8: PackedByteArray = mock8.blob.duplicate()
		cloud8.set(fault, true if fault == "fail_copy" else "local_progress")
		cloud8.restore_cloud()
		await process_frame
		check(cloud8.status() == St.CONFLICT and save.salvage == 5 and CS.progress_hash(save.to_dict()) == CS.progress_hash(mine) and mock8.blob == blob8, "%s: RESTORE CLOUD SAVE does nothing when the backup fails" % fault)
		check("this device's save" in cloud8.choice_error and _rec_temps().is_empty(), "%s: and says which copy failed, leaving no temporary file" % fault)
		cloud8.set(fault, false if fault == "fail_copy" else "")
		cloud8.restore_cloud()
		await _cloud_settle(cloud8)
		check(save.salvage == 777 and cloud8.status() == St.SYNCED and int(CS.decode(_rec("local_progress")).data.salvage) == 5 and _rec_exists("local_save_file"), "%s: and goes through, keeping the old save, once the backup works" % fault)
		await _free_cloud(cloud8)

	# --- A silent restore (new install) is refused too when it cannot keep a copy ---
	_cloud_rich_save()
	var rich_blob: PackedByteArray = CS.encode(save.to_dict())
	_fresh_install()
	_clear_cloud_files()
	var fresh_before: Dictionary = save.to_dict()
	var mock9 = _cloud_mock_script.new()
	mock9.set_blob(rich_blob)
	var cloud9 = _make_cloud(mock9, false, faulty)
	cloud9.fail_copy = true
	mock9.set_auth(CS.Auth.SIGNED_IN)
	await _cloud_settle(cloud9)
	check(cloud9.status() == St.ERROR and cloud9._fail_kind == "backup" and CS.progress_hash(save.to_dict()) == CS.progress_hash(fresh_before) and mock9.blob == rich_blob, "a silent restore that cannot be backed up does not happen, and the cloud save is untouched")
	check("Could not keep a copy" in cloud9.last_error and cloud9.choice_error == "", "and the error is explained")
	cloud9.fail_copy = false
	cloud9.sync_now(true)
	await _cloud_settle(cloud9)
	check(cloud9.status() == St.SYNCED and save.salvage == 12345, "and it restores once the backup works")
	await _free_cloud(cloud9)

	# --- Account change: loading the new account's save with no backup possible ---
	_cloud_rich_save()
	_clear_cloud_files()
	mine = save.to_dict()
	var mock10 = _cloud_mock_script.new()
	var cloud10 = _faulty_cloud(mock10, faulty)
	await _cloud_settle(cloud10)
	_switch_account(mock10, "acct-B")
	mock10.set_blob(CS.encode(theirs))
	cloud10.sync_now(true)
	await _cloud_settle(cloud10)
	var bound: String = cloud10._account
	cloud10.fail_copy = true
	cloud10.account_use_cloud()
	await process_frame
	check(cloud10.status() == St.ACCOUNT and cloud10._account == bound and CS.progress_hash(save.to_dict()) == CS.progress_hash(mine) and cloud10.choice_error != "", "loading the new account's save without a backup: nothing changed, still bound to the old account, decision open")
	cloud10.fail_copy = false
	cloud10.account_use_cloud()
	await _cloud_settle(cloud10)
	check(save.salvage == int(theirs.salvage) and cloud10.status() == St.SYNCED and cloud10._account != bound, "and it works once the backup does")
	await _free_cloud(cloud10)

	# --- Account change: carrying this device's save over an unreadable cloud save, backup failing ---
	_cloud_rich_save()
	_clear_cloud_files()
	mine = save.to_dict()
	var mock11 = _cloud_mock_script.new()
	var cloud11 = _faulty_cloud(mock11, faulty)
	await _cloud_settle(cloud11)
	_switch_account(mock11, "acct-B")
	mock11.set_blob(bad_b)
	cloud11.sync_now(true)
	await _cloud_settle(cloud11)
	var saves11: int = mock11.saves
	var bound11: String = cloud11._account
	cloud11.fail_store_for = "cloud_save"
	cloud11.account_use_local()
	await process_frame
	check(cloud11.status() == St.ACCOUNT and mock11.saves == saves11 and mock11.blob == bad_b and cloud11._account == bound11 and cloud11.choice_error != "", "the new account's unreadable save was not replaced, because its bytes could not be kept")
	cloud11.fail_store_for = ""
	cloud11.account_use_local()
	await _cloud_settle(cloud11)
	check(cloud11.status() == St.SYNCED and _rec("cloud_save") == bad_b, "and it is kept, then replaced, once writes work")
	await _free_cloud(cloud11)

	# --- Google conflict where a version cannot be written: never claim both were kept ---
	for broken in ["google_version_2", "google_version_1"]:
		_cloud_rich_save()
		_clear_cloud_files()
		var mock12 = _cloud_mock_script.new()
		var cloud12 = _faulty_cloud(mock12, faulty)
		await _cloud_settle(cloud12)
		mock12.conflict_blobs = [ver_a, ver_b]
		mock12.conflict_next = "LOAD"
		cloud12.fail_open_for = broken
		cloud12.sync_now(true)
		await _cloud_settle(cloud12)
		var other_kind: String = "google_version_1" if broken == "google_version_2" else "google_version_2"
		var want: PackedByteArray = ver_a if other_kind == "google_version_1" else ver_b
		check(_rec(other_kind) == want and not _rec_exists(broken), "the version that could be written is exact, and the other has no file (%s failed)" % broken)
		var kept_n: int = 1 if other_kind == "google_version_1" else 2
		check(not "Both versions were" in cloud12.last_error and "Could not keep a copy of 1 of the 2" in cloud12.last_error and ("kept: version %d" % kept_n) in cloud12.last_error, "and the message says exactly which was kept (%s failed)" % broken)
		await _free_cloud(cloud12)
	_cloud_rich_save()
	_clear_cloud_files()
	var mock13 = _cloud_mock_script.new()
	var cloud13 = _faulty_cloud(mock13, faulty)
	await _cloud_settle(cloud13)
	mock13.conflict_blobs = [ver_a, ver_b]
	mock13.conflict_next = "LOAD"
	cloud13.fail_store_for = "google_version_1"
	cloud13.short_write_for = "google_version_2"
	cloud13.sync_now(true)
	await _cloud_settle(cloud13)
	check("Could not keep a copy of 2 of the 2" in cloud13.last_error and "kept: none" in cloud13.last_error and not "Both versions were" in cloud13.last_error, "when neither version could be written, it says so")
	await _free_cloud(cloud13)
	_clear_cloud_files()
	await _test_cloud_recovery_history()
	await _test_cloud_recovery_safety()
	print("cloud preservation ok")

## An earlier recovery file is never overwritten, truncated or removed by a later operation, successful or not.
func _test_cloud_recovery_history() -> void:
	var CS = _cloud_script_class()
	var St = CS.Status
	var faulty = load("res://tools/faulty_cloud_sync.gd")
	var base: Dictionary = {}

	# --- A. An existing cloud_save recovery file, then new backups that fail in every way ---
	_cloud_rich_save()
	_clear_cloud_files()
	base = save.to_dict()
	var older: Dictionary = base.duplicate(true)
	older.salvage = 41
	var important: PackedByteArray = _corrupt_blob(CS.encode(older))
	var newer: Dictionary = base.duplicate(true)
	newer.salvage = 42
	var junk_new: PackedByteArray = _corrupt_blob(CS.encode(newer))
	var mock = _cloud_mock_script.new()
	mock.set_blob(important)
	var cloud = _faulty_cloud(mock, faulty)
	await _cloud_settle(cloud)
	cloud.keep_local()
	await _cloud_settle(cloud)
	check(cloud.status() == St.SYNCED and _rec_files("cloud_save").size() == 1 and _rec("cloud_save") == important, "A: the first recovery copy exists")
	var before_a: Dictionary = _rec_snapshot()
	await _unreadable_conflict(mock, cloud, junk_new)
	check(cloud.status() == St.CONFLICT, "A: a second unreadable cloud save raises a new question")
	for fault in ["fail_open_for", "fail_store_for", "short_write_for", "fail_promote_for"]:
		cloud.set(fault, "cloud_save")
		cloud.keep_local()
		await process_frame
		check(cloud.status() == St.CONFLICT and mock.blob == junk_new and cloud.choice_error != "", "A (%s): the decision is blocked and the cloud save untouched" % fault)
		check(_rec_snapshot() == before_a and _rec_temps().is_empty(), "A (%s): the existing recovery file is byte-for-byte identical, with no temporary file left" % fault)
		cloud.set(fault, "")
	# --- D. A successful later backup adds a generation and keeps the first exactly ---
	cloud.keep_local()
	await _cloud_settle(cloud)
	var files_a := _rec_files("cloud_save")
	check(cloud.status() == St.SYNCED and files_a.size() == 2 and _read_blob(files_a[0]) == important and _read_blob(files_a[1]) == junk_new, "D: after a second successful backup both generations are there, exact and in order")
	check(int(files_a[0].get_file().substr(0, 6)) < int(files_a[1].get_file().substr(0, 6)), "D: the newer one has the higher generation number")
	check(recovery_newest_is(cloud, files_a[1]), "D: Cloud.recovery_files() ends with the newest file")
	await _free_cloud(cloud)

	# --- B. An existing local_save_file recovery copy, then a copy that fails ---
	_cloud_rich_save()
	_clear_cloud_files()
	mock = _cloud_mock_script.new()
	cloud = _faulty_cloud(mock, faulty)
	await _cloud_settle(cloud)
	var cloud_side: Dictionary = save.to_dict()
	cloud_side.salvage = 701
	mock.set_blob(CS.encode(cloud_side))
	save.salvage = 6
	save.save_data()
	await _cloud_settle(cloud)
	cloud.restore_cloud()
	await _cloud_settle(cloud)
	check(cloud.status() == St.SYNCED and save.salvage == 701 and _rec_files("local_save_file").size() == 1, "B: a first restore keeps this device's save file")
	var first_copy: PackedByteArray = _rec("local_save_file")
	check(not first_copy.is_empty(), "B: that copy has content")
	var before_b: Dictionary = _rec_snapshot()
	var cloud_side2: Dictionary = save.to_dict()
	cloud_side2.salvage = 702
	mock.set_blob(CS.encode(cloud_side2))
	save.salvage = 7
	save.save_data()
	await _cloud_settle(cloud)
	check(cloud.status() == St.CONFLICT, "B: a second disagreement")
	var local_b: Dictionary = save.to_dict()
	for fault in ["fail_copy", "fail_promote_for"]:
		cloud.set(fault, true if fault == "fail_copy" else "local_save_file")
		cloud.restore_cloud()
		await process_frame
		check(cloud.status() == St.CONFLICT and CS.progress_hash(save.to_dict()) == CS.progress_hash(local_b) and cloud.choice_error != "", "B (%s): nothing was restored" % fault)
		check(_rec_snapshot() == before_b and _rec("local_save_file") == first_copy and _rec_temps().is_empty(), "B (%s): the earlier local_save_file copy and every other recovery file are unchanged" % fault)
		cloud.set(fault, false if fault == "fail_copy" else "")
	# The second file of a set failing leaves the first of the new set as an extra file, never a damaged old one.
	cloud.fail_store_for = "local_progress"
	cloud.restore_cloud()
	await process_frame
	var after_b := _rec_snapshot()
	var intact := true
	for f in before_b:
		if not after_b.has(f) or after_b[f] != before_b[f]:
			intact = false
	check(cloud.status() == St.CONFLICT and intact and save.salvage == 7, "B: a failure on the second file of a set leaves every earlier file intact and replaces nothing")
	cloud.fail_store_for = ""
	cloud.restore_cloud()
	await _cloud_settle(cloud)
	check(save.salvage == 702 and _rec("local_progress") != PackedByteArray() and int(CS.decode(_rec("local_progress")).data.salvage) == 7, "B: and then it succeeds, keeping this device's save")
	var files_b := _rec_files("local_progress")
	check(files_b.size() == 2 and _read_blob(files_b[0]) == before_b[files_b[0]], "D: both restore generations are kept, the older one exactly")
	await _free_cloud(cloud)

	# --- C. Existing Google conflict candidates, then new conflicts whose writes fail ---
	_cloud_rich_save()
	_clear_cloud_files()
	var v1: Dictionary = save.to_dict()
	v1.salvage = 801
	var v2: Dictionary = save.to_dict()
	v2.salvage = 802
	var n1: Dictionary = save.to_dict()
	n1.salvage = 803
	var n2: Dictionary = save.to_dict()
	n2.salvage = 804
	var blobs_old: Array = [CS.encode(v1), CS.encode(v2)]
	var blobs_new: Array = [CS.encode(n1), CS.encode(n2)]
	mock = _cloud_mock_script.new()
	cloud = _faulty_cloud(mock, faulty)
	await _cloud_settle(cloud)
	mock.conflict_blobs = blobs_old
	mock.conflict_next = "LOAD"
	cloud.sync_now(true)
	await _cloud_settle(cloud)
	check(_rec_files("google_version_").size() == 2 and _rec("google_version_1") == blobs_old[0] and _rec("google_version_2") == blobs_old[1], "C: the first conflict's two versions are kept")
	var before_c: Dictionary = _rec_snapshot()
	var cases := [
		["fail_store_for", "google_version_1", [2], [1]],
		["fail_open_for", "google_version_2", [1], [2]],
		["fail_promote_for", "google_version_", [], [1, 2]],
	]
	for case in cases:
		mock.conflict_blobs = blobs_new
		mock.conflict_next = "LOAD"
		cloud.set(case[0], case[1])
		cloud.sync_now(true)
		await _cloud_settle(cloud)
		var now := _rec_snapshot()
		var old_ok := true
		for f in before_c:
			if not now.has(f) or now[f] != before_c[f]:
				old_ok = false
		check(old_ok, "C (%s): neither older candidate was destroyed" % case[0])
		var fresh_files: Array = []
		for f in now:
			if not before_c.has(f):
				fresh_files.append(f)
		check(fresh_files.size() == (case[2] as Array).size(), "C (%s): exactly the versions that could be written were added (%d)" % [case[0], fresh_files.size()])
		for i in (case[2] as Array):
			var found := false
			for f in fresh_files:
				if str(f).contains("google_version_%d" % int(i)) and now[f] == blobs_new[int(i) - 1]:
					found = true
			check(found, "C (%s): new version %d is kept exactly" % [case[0], int(i)])
		var lost_text := ", ".join((case[3] as Array).map(func(i): return "version %d" % int(i)))
		check(not "Both versions were" in cloud.last_error and ("not kept: " + lost_text) in cloud.last_error and _rec_temps().is_empty(), "C (%s): the message names exactly what was not kept" % case[0])
		cloud.set(case[0], "")
		# Remember the set for the next round, so each round proves it leaves the one before intact.
		before_c = _rec_snapshot()
	# --- D. A fully successful new conflict adds a third set and leaves the others ---
	mock.conflict_blobs = blobs_new
	mock.conflict_next = "LOAD"
	cloud.sync_now(true)
	await _cloud_settle(cloud)
	var latest: Dictionary = _rec_snapshot()
	var intact_c := true
	for f in before_c:
		if not latest.has(f) or latest[f] != before_c[f]:
			intact_c = false
	check(intact_c and "Both versions were kept" in cloud.last_error, "D: a successful new conflict adds its own set and keeps every earlier file exactly")
	await _free_cloud(cloud)

	# --- E. An interrupted backup: the temporary file is left, the old copy is safe, and cleanup touches only the temporary file ---
	_cloud_rich_save()
	_clear_cloud_files()
	base = save.to_dict()
	var keep_me: Dictionary = base.duplicate(true)
	keep_me.salvage = 91
	var precious: PackedByteArray = _corrupt_blob(CS.encode(keep_me))
	var later: Dictionary = base.duplicate(true)
	later.salvage = 92
	var junk_e: PackedByteArray = _corrupt_blob(CS.encode(later))
	mock = _cloud_mock_script.new()
	mock.set_blob(precious)
	cloud = _faulty_cloud(mock, faulty)
	await _cloud_settle(cloud)
	cloud.keep_local()
	await _cloud_settle(cloud)
	await _unreadable_conflict(mock, cloud, junk_e)
	var before_e: Dictionary = _rec_snapshot()
	var readme_before := _read_blob(_rec_dir() + "/README.txt")
	check(not readme_before.is_empty(), "E: the folder explains itself in a README.txt")
	cloud.fake_pid = 2147483000  # the interrupted writer is a process that is no longer running
	for mode in ["fail_store_for", "fail_promote_for"]:
		cloud.keep_temp_on_failure = true
		cloud.set(mode, "cloud_save")
		cloud.keep_local()
		await process_frame
		check(cloud.status() == St.CONFLICT and mock.blob == junk_e, "E (%s): the interrupted backup replaced nothing" % mode)
		check(_rec_snapshot() == before_e, "E (%s): the old recovery copy is byte-for-byte identical" % mode)
		check(not _rec_temps().is_empty(), "E (%s): the interrupted write left a temporary file, as a crash would" % mode)
		cloud.keep_temp_on_failure = false
		cloud.set(mode, "")
	cloud.fake_pid = 0
	var temps_before: int = _rec_temps().size()
	var removed: int = cloud.cleanup_recovery_temps()
	check(removed == temps_before and removed >= 2 and _rec_temps().is_empty(), "E: cleanup removes the unfinished temporary files (%d)" % removed)
	check(_rec_snapshot() == before_e and _read_blob(_rec_dir() + "/README.txt") == readme_before, "E: and touches no recovery file or the README")
	cloud.keep_local()
	await _cloud_settle(cloud)
	var files_e := _rec_files("cloud_save")
	check(cloud.status() == St.SYNCED and files_e.size() == 2 and _read_blob(files_e[0]) == precious and _read_blob(files_e[1]) == junk_e, "E: and the backup then succeeds beside the old one")
	await _free_cloud(cloud)
	_clear_cloud_files()
	print("cloud recovery history ok")

func recovery_newest_is(cloud, path: String) -> bool:
	var files: PackedStringArray = cloud.recovery_files()
	return not files.is_empty() and files[files.size() - 1] == path

func _rec_unverified() -> Array:
	var out: Array = []
	var d := DirAccess.open(_rec_dir())
	if d != null:
		for f in d.get_files():
			if f.ends_with(".unverified"):
				out.append(_rec_dir() + "/" + f)
	return out

func _rec_reservations() -> Array:
	var out: Array = []
	var d := DirAccess.open(_rec_dir())
	if d != null:
		for sub in d.get_directories():
			if sub.ends_with(".set"):
				out.append(sub)
	out.sort()
	return out

func _plain_faulty(faulty):
	return _make_cloud(_cloud_mock_script.new(), false, faulty)

## How recovery files are protected from being overwritten: a reservation made by creating a directory, a promotion that
## refuses an existing destination, a read-back after promotion, a README that is recreated, and temporary files that
## are only cleaned up when their process is gone.
func _test_cloud_recovery_safety() -> void:
	var CS = _cloud_script_class()
	var St = CS.Status
	var faulty = load("res://tools/faulty_cloud_sync.gd")
	var payload := PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9])

	# --- The reservation primitive: creating a taken directory reports that it exists ---
	_cloud_rich_save()
	_clear_cloud_files()
	var a = _plain_faulty(faulty)
	var rec_a: Dictionary = a._recovery_reserve()
	check(not rec_a.is_empty() and DirAccess.dir_exists_absolute(str(rec_a.path)), "a generation can be reserved")
	check(DirAccess.make_dir_absolute(str(rec_a.path)) == ERR_ALREADY_EXISTS, "creating the same reservation again is refused with 'already exists'")

	# --- Two writers after the same generation: only one can own it ---
	check(a._recovery_put(rec_a, "cloud_save", "blob", payload), "the owner writes its file")
	var before: Dictionary = _rec_snapshot()
	var b = _plain_faulty(faulty)
	b.force_generation = int(rec_a.gen)
	b.force_calls = 1
	var rec_b: Dictionary = b._recovery_reserve()
	check(not rec_b.is_empty() and int(rec_b.gen) != int(rec_a.gen), "a second writer that tries the same number is refused it and gets another")
	check(_rec_snapshot() == before, "and the first writer's recovery files are untouched by that")
	var other := PackedByteArray([9, 9, 9])
	check(b._recovery_put(rec_b, "cloud_save", "blob", other) and _rec_snapshot().size() == 2, "the second writer's file goes under its own number")
	check(a._recovery_put(rec_a, "local_progress", "blob", payload) and _read_blob("%s/%06d_cloud_save.blob" % [_rec_dir(), int(rec_a.gen)]) == payload, "the first writer can still finish its own set, and its first file is exact")
	# A writer that keeps losing gives up, safely.
	var c = _plain_faulty(faulty)
	c.force_generation = int(rec_a.gen)
	c.force_calls = 100
	c.reserve_attempts = 1
	var snap2: Dictionary = _rec_snapshot()
	var reservations_before: Array = _rec_reservations()
	check(c._recovery_reserve().is_empty(), "a writer that cannot get a number fails instead of writing")
	check(not c._keep_copy_of_cloud(payload) and _rec_snapshot() == snap2 and _rec_reservations() == reservations_before, "and its backup is reported as failed with nothing written, renamed or removed")
	a._recovery_finish(rec_a)
	b._recovery_finish(rec_b)
	check(_rec_reservations().size() == 2, "finished reservations with files stay, as the record of their generation")
	for cl in [a, b, c]:
		await _free_cloud(cl)

	# --- A reservation that wrote nothing is released; a finished one is never reclaimed by anyone ---
	_clear_cloud_files()
	var d = _plain_faulty(faulty)
	var rec_d: Dictionary = d._recovery_reserve()
	d._recovery_finish(rec_d)
	check(not DirAccess.dir_exists_absolute(str(rec_d.path)), "a reservation that wrote nothing releases itself")
	var rec_e: Dictionary = d._recovery_reserve()
	var rec_f: Dictionary = d._recovery_reserve()
	check(int(rec_e.gen) != int(rec_f.gen) and DirAccess.dir_exists_absolute(str(rec_e.path)) and DirAccess.dir_exists_absolute(str(rec_f.path)), "an unfinished reservation (a crashed writer's) stays, and later writers take other numbers")
	await _free_cloud(d)

	# --- The destination collision: a file appears at the exact destination after the checks, before promotion ---
	_cloud_rich_save()
	_clear_cloud_files()
	var s1 = _plain_faulty(faulty)
	s1.sentinel_for = "cloud_save"
	var rec_s: Dictionary = s1._recovery_reserve()
	var dest := "%s/%06d_cloud_save.blob" % [_rec_dir(), int(rec_s.gen)]
	check(not FileAccess.file_exists(dest), "the destination is free at first, so the early check passes")
	var wrote: bool = s1._recovery_put(rec_s, "cloud_save", "blob", payload)
	check(not wrote and _read_blob(dest) == s1.sentinel_bytes, "promotion refused to replace the sentinel: it reports failure and the sentinel's bytes are unchanged")
	check(_rec_temps().is_empty(), "and the staged temporary file was discarded")
	s1._recovery_finish(rec_s)
	check(_read_blob(dest) == s1.sentinel_bytes, "finishing the operation leaves the sentinel alone too")
	await _free_cloud(s1)
	# The same through a real decision.
	_cloud_rich_save()
	_clear_cloud_files()
	var local_before: Dictionary = save.to_dict()
	var junk: PackedByteArray = _corrupt_blob(CS.encode(local_before))
	var mock = _cloud_mock_script.new()
	mock.set_blob(junk)
	var s2 = _faulty_cloud(mock, faulty)
	await _cloud_settle(s2)
	s2.sentinel_for = "cloud_save"
	s2.keep_local()
	await process_frame
	var cs_files := _rec_files("cloud_save")
	check(s2.status() == St.CONFLICT and mock.blob == junk and mock.saves == 0 and CS.progress_hash(save.to_dict()) == CS.progress_hash(local_before) and s2.choice_error != "", "KEEP THIS DEVICE'S SAVE is blocked when its destination was taken, and nothing is replaced")
	check(cs_files.size() == 1 and _read_blob(cs_files[0]) == s2.sentinel_bytes, "the file that took the destination is exactly as it was")
	s2.sentinel_for = ""
	s2.keep_local()
	await _cloud_settle(s2)
	var after := _rec_files("cloud_save")
	check(s2.status() == St.SYNCED and after.size() == 2 and _read_blob(after[0]) == s2.sentinel_bytes and _read_blob(after[1]) == junk, "and the next attempt takes a new number and succeeds beside it")
	await _free_cloud(s2)

	# --- The promoted file fails its final read-back ---
	_cloud_rich_save()
	_clear_cloud_files()
	var older: Dictionary = save.to_dict()
	older.salvage = 61
	var important: PackedByteArray = _corrupt_blob(CS.encode(older))
	var newer: Dictionary = save.to_dict()
	newer.salvage = 62
	var junk_r: PackedByteArray = _corrupt_blob(CS.encode(newer))
	var mock3 = _cloud_mock_script.new()
	mock3.set_blob(important)
	var r1 = _faulty_cloud(mock3, faulty)
	await _cloud_settle(r1)
	r1.keep_local()
	await _cloud_settle(r1)
	await _unreadable_conflict(mock3, r1, junk_r)
	var existing: Dictionary = _rec_snapshot()
	check(r1.status() == St.CONFLICT and existing.size() == 1, "an earlier recovery file exists")
	r1.corrupt_after_promote_for = "cloud_save"
	r1.keep_local()
	await process_frame
	check(r1.status() == St.CONFLICT and mock3.blob == junk_r and mock3.saves == 1 and r1.choice_error != "", "a final read-back failure blocks the decision and replaces nothing")
	check(_rec_snapshot() == existing, "the earlier recovery file is identical, and no unverified file stands as a valid numbered copy")
	var bad := _rec_unverified()
	check(bad.size() == 1 and str(bad[0]).ends_with(".blob.unverified") and _rec_temps().is_empty(), "the failed copy is set aside as .unverified, and no temporary file is left")
	r1.corrupt_after_promote_for = ""
	r1.keep_local()
	await _cloud_settle(r1)
	var good := _rec_files("cloud_save")
	check(r1.status() == St.SYNCED and good.size() == 2 and _read_blob(good[0]) == important and _read_blob(good[1]) == junk_r and _rec_unverified().size() == 1, "and the retry succeeds, keeping the old copy, with the unverified one still set aside")
	await _free_cloud(r1)

	# --- README: recreated when missing, never overwritten, never claimed when it could not be written ---
	_cloud_rich_save()
	_clear_cloud_files()
	DirAccess.make_dir_recursive_absolute(_rec_dir())
	var h1 = _plain_faulty(faulty)
	check(not h1.recovery_folder_ready(), "a recovery folder without a README is not reported ready")
	var rec_h: Dictionary = h1._recovery_reserve()
	check(not rec_h.is_empty() and FileAccess.file_exists(_rec_dir() + "/README.txt") and h1.readme_ok and h1.recovery_folder_ready(), "an existing folder with no README gets one the next time it is used")
	h1._recovery_finish(rec_h)
	var custom := "my own notes".to_utf8_buffer()
	var f := FileAccess.open(_rec_dir() + "/README.txt", FileAccess.WRITE)
	f.store_buffer(custom)
	f.close()
	var rec_h2: Dictionary = h1._recovery_reserve()
	check(_read_blob(_rec_dir() + "/README.txt") == custom, "an existing README is never overwritten")
	h1._recovery_finish(rec_h2)
	await _free_cloud(h1)
	_clear_cloud_files()
	var h2 = _plain_faulty(faulty)
	h2.fail_open_for = "readme"
	var rec_h3: Dictionary = h2._recovery_reserve()
	check(not rec_h3.is_empty() and not h2.readme_ok and not h2.recovery_folder_ready() and not FileAccess.file_exists(_rec_dir() + "/README.txt"), "when the README cannot be written the folder is not reported fully ready")
	check(h2._recovery_put(rec_h3, "cloud_save", "blob", payload) and _rec_files("cloud_save").size() == 1, "but a recovery copy still goes ahead")
	h2._recovery_finish(rec_h3)
	h2.fail_open_for = ""
	var rec_h4: Dictionary = h2._recovery_reserve()
	check(h2.readme_ok and h2.recovery_folder_ready() and FileAccess.file_exists(_rec_dir() + "/README.txt"), "and the README is created on the next use")
	h2._recovery_finish(rec_h4)
	await _free_cloud(h2)

	# --- Temporary files: a running process's is never touched; a dead process's is cleaned up ---
	_clear_cloud_files()
	var t1 = _plain_faulty(faulty)
	var rec_t: Dictionary = t1._recovery_reserve()
	var valid := PackedByteArray([7, 7, 7])
	check(t1._recovery_put(rec_t, "cloud_save", "blob", valid), "a recovery copy to protect")
	var live := _rec_dir() + "/tmp_cloud_save_%d_1_1.part" % OS.get_process_id()
	var dead := _rec_dir() + "/tmp_cloud_save_2147483000_1_1.part"
	_write_text(live, "a write in progress in a running process")
	_write_text(dead, "left by a process that crashed")
	var snap_t: Dictionary = _rec_snapshot()
	var removed: int = t1.cleanup_recovery_temps()
	check(removed == 1 and FileAccess.file_exists(live) and not FileAccess.file_exists(dead), "cleanup removes a dead process's temporary file and leaves a running process's alone")
	check(_rec_snapshot() == snap_t and FileAccess.file_exists(_rec_dir() + "/README.txt") and _rec_reservations().size() == 1, "and touches no recovery file, README or reservation")
	DirAccess.remove_absolute(live)
	t1._recovery_finish(rec_t)
	await _free_cloud(t1)
	_clear_cloud_files()

	await _test_cloud_two_processes()
	print("cloud recovery safety ok")

## Two real game processes share one save path and race for recovery generations. This is the evidence for the
## reservation, on this machine only: it does not prove anything about another operating system or file system.
func _test_cloud_two_processes() -> void:
	var shared := "user://qa_contention_%d.cfg" % OS.get_process_id()
	var shared_abs := ProjectSettings.globalize_path(shared)
	var count := 25
	var start := Time.get_unix_time_from_system() + 8.0
	var pids: Array = []
	for tag in ["A", "B"]:
		var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tools/recovery_contention.gd", "--", "--test", "--path=" + shared, "--tag=" + tag, "--count=%d" % count, "--start=%f" % start]
		pids.append(OS.create_process(OS.get_executable_path(), args))
	check(int(pids[0]) > 0 and int(pids[1]) > 0, "two separate game processes were started")
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		if FileAccess.file_exists(shared + ".result_A") and FileAccess.file_exists(shared + ".result_B"):
			break
		await create_timer(0.5).timeout
	await create_timer(0.5).timeout
	var owners := {}
	var total_ok := 0
	var none := 0
	for tag in ["A", "B"]:
		var text := FileAccess.get_file_as_string(shared + ".result_" + tag)
		check(not text.is_empty(), "process %s reported" % tag)
		for line in text.split("\n", false):
			if line == "none":
				none += 1
				continue
			var bits := line.split(" ")
			var gen := int(bits[0])
			check(not owners.has(gen), "generation %d was reserved by one process only" % gen)
			owners[gen] = bits[3]
			if bits[1] == "true" and bits[2] == "true":
				total_ok += 1
	check(total_ok == owners.size() and total_ok + none == count * 2, "every reservation produced both files (%d sets, %d gave up)" % [total_ok, none])
	var files := DirAccess.get_files_at(shared + ".recovery")
	var recovery_count := 0
	var intact := true
	for gen in owners:
		var tag_i: String = owners[gen]
		var tagname := tag_i.split("-")[0]
		var idx := int(tag_i.split("-")[1])
		var expect := ("%s-%d-" % [tagname, idx]).repeat(300).to_utf8_buffer()
		for kind in ["cloud_save", "local_progress"]:
			var p := "%s.recovery/%06d_%s.blob" % [shared, int(gen), kind]
			recovery_count += 1
			if _read_blob(p) != expect:
				intact = false
	check(intact and recovery_count == total_ok * 2, "each generation's files hold exactly what its owner wrote, and no file was overwritten by the other process")
	var tmp_left := 0
	for f in files:
		if f.ends_with(".part"):
			tmp_left += 1
	check(tmp_left == 0, "no temporary file was left behind")
	save.remove_recovery(shared)
	DirAccess.remove_absolute(shared + ".result_A")
	DirAccess.remove_absolute(shared + ".result_B")

# ---------- Combat polish: explosions, impacts, shields, engines, audio ----------

func _fx_settle(fx, seconds := 6.0) -> void:
	for i in range(int(seconds / 0.05)):
		fx.update(0.05)

func _fx_lists(fx) -> Dictionary:
	return {"booms": fx.booms.size(), "rings": fx.rings.size(), "flashes": fx.flashes.size(), "debris": fx.debris.size(), "ripples": fx.ripples.size(), "bolts": fx.bolts.size()}

func _test_combat_polish() -> void:
	var FxS = load("res://src/combat/fx.gd")
	var ShieldS = load("res://src/combat/shield_fx.gd")
	var EngineS = load("res://src/combat/engine_fx.gd")
	var AudioS = load("res://src/combat/combat_audio.gd")
	var Enemies_ = load("res://src/data/enemies.gd")
	var Ships_ = load("res://src/data/ships.gd")
	var saved_opt: Dictionary = save.opt.duplicate()
	var saved_ships: Array = save.owned_ships.duplicate()
	var saved_ship: String = save.ship
	var saved_upgrades: Dictionary = save.upgrades.duplicate()
	save.upgrades = {}
	save.opt.particles = 2
	save.opt.reduced_flash = false
	save.opt.reduced_motion = false

	# --- The effect tables are complete ---
	for tier in FxS.TIERS:
		var t: Dictionary = FxS.TIERS[tier]
		check(t.has_all(["flash", "burst", "life", "ring", "sparks", "debris", "speed", "stages", "kick"]) and (t.ring as Array).size() == 5, "explosion tier %s is fully described" % tier)
	for w in Ships_.WEAPONS:
		check(FxS.IMPACTS.has(w), "weapon %s has its own impact look" % w)
	check(FxS.IMPACTS.has("arc"), "arcs have an impact look")
	for pal in FxS.PALETTES:
		check((FxS.PALETTES[pal] as Dictionary).has_all(["core", "hot", "mid", "debris"]), "palette %s is complete" % pal)
	for kind in Enemies_.DB:
		var info: Dictionary = Enemies_.DB[kind]
		var tier_name: String = FxS.tier_for(bool(info.get("heavy", false)), float(info.size))
		check(FxS.TIERS.has(tier_name), "enemy %s maps to an explosion tier (%s)" % [kind, tier_name])
		if bool(info.get("heavy", false)):
			check(tier_name == "heavy", "heavy enemy %s gets the heavy explosion" % kind)
	check(FxS.tier_for(false, 60.0) == "small" and FxS.tier_for(false, 130.0) == "medium", "small and medium enemies are told apart by size")

	# --- An explosion has all five layers, and bigger ones are bigger ---
	var fx = FxS.new()
	fx.density = 1.0
	var counts := {}
	for tier in ["small", "medium", "heavy"]:
		fx = FxS.new()
		fx.density = 1.0
		fx.explode(Vector2(300, 300), tier, 120.0, "fire")
		counts[tier] = {"sparks": fx.spark_count, "debris": fx.debris.size(), "booms": fx.booms.size()}
		check(fx.flashes.size() >= 1 and fx.booms.size() >= 1 and fx.rings.size() >= 1 and fx.spark_count > 0 and fx.debris.size() > 0, "a %s explosion has a flash, a burst, a ring, sparks and debris" % tier)
	check(int(counts.small.sparks) < int(counts.medium.sparks) and int(counts.medium.sparks) < int(counts.heavy.sparks), "bigger enemies throw more sparks (%s)" % str(counts))
	check(int(counts.small.debris) < int(counts.heavy.debris), "and more debris")
	fx = FxS.new()
	fx.density = 1.0
	fx.explode(Vector2(300, 300), "heavy", 200.0, "fire")
	var first_booms: int = fx.booms.size()
	check(fx._scheduled.size() >= 3, "a heavy explosion is staged: secondary bursts then a final blast")
	_fx_settle(fx, 0.12)
	check(fx.booms.size() > first_booms or fx.rings.size() > 1, "the secondary bursts arrive after the first")
	var sizes := {}
	for i in range(10):
		var f2 = FxS.new()
		f2.explode(Vector2.ZERO, "medium", 100.0, "fire")
		sizes[snappedf(float((f2.booms[0] as Dictionary).size), 0.1)] = true
	check(sizes.size() >= 4, "explosions vary: ten medium blasts had %d different sizes" % sizes.size())
	fx = FxS.new()
	fx.explode(Vector2(200, 200), "heavy", 200.0, "ice")
	_fx_settle(fx, 8.0)
	check(fx.live_count() == 0, "everything an explosion made has expired after a few seconds (%d left)" % fx.live_count())

	# --- Many explosions at once stay inside their caps and still clean up ---
	fx = FxS.new()
	fx.density = 1.0
	for i in range(300):
		fx.explode(Vector2(randf() * 720.0, randf() * 1280.0), ["small", "medium", "heavy"][i % 3], 150.0, "fire")
		fx.impact(Vector2(100, 100), "missile", 1.0)
		fx.shield_break(Vector2(100, 100), 80.0, Color.CYAN)
	var l := _fx_lists(fx)
	check(fx.spark_count <= FxS.MAX_SPARKS and l.booms <= FxS.MAX_BOOMS and l.rings <= FxS.MAX_RINGS and l.flashes <= FxS.MAX_FLASHES and l.debris <= FxS.MAX_DEBRIS and l.bolts <= FxS.MAX_BOLTS and l.ripples <= FxS.MAX_RIPPLES and fx._scheduled.size() <= FxS.MAX_SCHEDULED, "300 simultaneous explosions stay inside every cap (%s)" % str(l))
	_fx_settle(fx, 10.0)
	check(fx.live_count() == 0, "and every effect is gone afterwards (%d left)" % fx.live_count())
	# Bolts have their own cap, and the oldest is the one that goes.
	fx = FxS.new()
	for i in range(100):
		fx.bolt(Vector2(i, 0), Vector2(i, 100), Color(float(i) / 100.0, 0.0, 0.0))
	check(fx.bolts.size() == FxS.MAX_BOLTS and float(((fx.bolts[0] as Dictionary).color as Color).r) > 0.8, "100 lightning bolts keep only the newest %d" % FxS.MAX_BOLTS)
	_fx_settle(fx, 1.0)
	check(fx.bolts.is_empty(), "and bolts expire")

	# --- Boss destruction ---
	fx = FxS.new()
	fx.density = 1.0
	fx.boss_finale(Vector2(360, 300), 640.0)
	_fx_settle(fx, 0.3)
	check(fx.rings.size() >= 3 and fx.debris.size() >= 10 and fx.booms.size() >= 1, "a boss finale has a big burst, three shockwaves and thrown wreckage")
	_fx_settle(fx, 8.0)
	check(fx.live_count() == 0, "and it cleans up")

	# --- Weapon impacts: every weapon has its own look, and heavier ones are bigger ---
	for w in ["pulse", "twin", "beam", "missile", "scatter"]:
		fx = FxS.new()
		fx.density = 1.0
		fx.impact(Vector2(100, 100), w, 1.0)
		check(fx.flashes.size() == 1 and fx.spark_count >= 1, "%s impact: a flash and sparks" % w)
		var has_ring: bool = fx.rings.size() > 0
		check(has_ring == not (FxS.IMPACTS[w].ring as Array).is_empty(), "%s impact ring matches its look" % w)
		check((fx.booms.size() > 0) == (float(FxS.IMPACTS[w].boom) > 0.0), "%s impact burst matches its look" % w)
	var light = FxS.new()
	var heavy = FxS.new()
	light.impact(Vector2.ZERO, "pulse", 0.7)
	heavy.impact(Vector2.ZERO, "pulse", 2.0)
	check(float((heavy.flashes[0] as Dictionary).size) > float((light.flashes[0] as Dictionary).size) * 1.8, "a heavy hit's flash is clearly larger than a light one's")
	var shield_hit = FxS.new()
	shield_hit.impact(Vector2.ZERO, "pulse", 1.0, "shield")
	var hull_hit = FxS.new()
	hull_hit.impact(Vector2.ZERO, "pulse", 1.0, "hull")
	check(((shield_hit.flashes[0] as Dictionary).color as Color) != ((hull_hit.flashes[0] as Dictionary).color as Color), "a hit on a shield looks different from a hit on a hull")
	fx = FxS.new()
	for i in range(200):
		fx.impact(Vector2(i, i), "pulse", 1.0)
	check(fx.impacts_drawn <= int(FxS.IMPACT_BURST) and fx.impacts_skipped >= 150, "200 impacts in one frame are limited to a burst (%d drawn)" % fx.impacts_drawn)
	fx.update(0.5)
	fx.impact(Vector2.ZERO, "pulse", 1.0)
	check(fx.impacts_drawn > int(FxS.IMPACT_BURST), "and the budget refills with time")

	# --- Accessibility: Reduce Flash and Reduce Motion ---
	var normal = FxS.new()
	seed(4242)  # the same random variation for both, so only the setting differs
	normal.explode(Vector2.ZERO, "heavy", 200.0, "fire")
	normal.density = 1.0
	save.opt.reduced_flash = true
	var soft = FxS.new()
	seed(4242)
	soft.explode(Vector2.ZERO, "heavy", 200.0, "fire")
	check(float((soft.flashes[0] as Dictionary).size) < float((normal.flashes[0] as Dictionary).size) * 0.8 and float(((soft.flashes[0] as Dictionary).color as Color).a) < 0.7, "Reduce Flash makes the core flash smaller and dimmer")
	var normal_flashes := 0
	var soft_flashes := 0
	for pass_i in range(2):
		var test_fx = FxS.new()
		save.opt.reduced_flash = pass_i == 1
		test_fx.explode(Vector2.ZERO, "heavy", 200.0, "fire")
		_fx_settle(test_fx, 0.8)
		if pass_i == 0:
			normal_flashes = test_fx.flashes_made
		else:
			soft_flashes = test_fx.flashes_made
	check(soft_flashes < normal_flashes, "Reduce Flash turns the staged flashes of a heavy explosion into plain bursts (%d vs %d)" % [soft_flashes, normal_flashes])
	save.opt.reduced_flash = false
	save.opt.reduced_motion = true
	var calm_fx = FxS.new()
	calm_fx.density = 1.0
	calm_fx.explode(Vector2.ZERO, "heavy", 200.0, "fire")
	check(calm_fx._scheduled.is_empty() and calm_fx.debris.size() < FxS.TIERS.heavy.debris, "Reduce Motion removes the staged sequence and halves the flying pieces")
	var calm_break = FxS.new()
	calm_break.shield_break(Vector2.ZERO, 80.0, Color.CYAN)
	check(calm_break.bolts.size() <= 1 and calm_break.debris.size() <= 4, "Reduce Motion simplifies a shield break")
	var calm_boss = FxS.new()
	calm_boss.boss_finale(Vector2.ZERO, 600.0)
	_fx_settle(calm_boss, 0.4)
	check(calm_boss.rings.size() <= 1, "Reduce Motion gives a boss finale one shockwave")
	save.opt.reduced_motion = false

	# --- Shields: look, wear, break and recovery follow the real shield and never change it ---
	check(ShieldS.tier_of(1.0) == 0 and ShieldS.tier_of(0.6) == 1 and ShieldS.tier_of(0.3) == 2 and ShieldS.tier_of(0.1) == 3, "shield wear tiers: full, worn, low, critical")
	fx = FxS.new()
	var sfx_ = ShieldS.new(fx)
	check(sfx_.flicker(1.0) == 1.0, "a full shield does not flicker")
	var dimmed := false
	for i in range(60):
		sfx_.update(0.05, Vector2.ZERO, 5.0, 60.0, true, true)
		if sfx_.flicker(0.08) < 0.9:
			dimmed = true
	check(dimmed, "a nearly empty shield flickers")
	save.opt.reduced_flash = true
	var steady := true
	for i in range(60):
		sfx_.update(0.05, Vector2.ZERO, 5.0, 60.0, true, true)
		if sfx_.flicker(0.08) != 1.0:
			steady = false
	check(steady, "Reduce Flash keeps a worn shield steady, and the broken ring still shows the wear")
	save.opt.reduced_flash = false
	fx = FxS.new()
	sfx_ = ShieldS.new(fx)
	var power: float = sfx_.on_hit(Vector2(300, 600), Vector2(300, 300), 6.0, 60.0)
	var ripple_ang := float((fx.ripples[0] as Dictionary).ang)
	check(fx.ripples.size() == 1 and absf(angle_difference(ripple_ang, -PI * 0.5)) < 0.05, "a shield hit ripples on the side the shot came from")
	var heavy_power: float = sfx_.on_hit(Vector2(300, 600), Vector2(300, 900), 40.0, 60.0)
	check(heavy_power > power * 2.0 and absf(angle_difference(float((fx.ripples[1] as Dictionary).ang), PI * 0.5)) < 0.05, "a heavy hit is stronger, and from below ripples at the bottom")
	var arcs_seen := 0
	for i in range(80):
		var before_bolts: int = fx.bolts.size()
		sfx_.update(0.05, Vector2(300, 600), 4.0, 60.0, true, true)
		arcs_seen += maxi(0, fx.bolts.size() - before_bolts)
	check(arcs_seen > 0, "a low shield throws brief electrical arcs")
	save.opt.reduced_motion = true
	var calm_arcs := 0
	var fx_calm = FxS.new()
	var s_calm = ShieldS.new(fx_calm)
	for i in range(80):
		s_calm.update(0.05, Vector2(300, 600), 4.0, 60.0, true, true)
	calm_arcs = fx_calm.bolts.size()
	check(calm_arcs == 0, "Reduce Motion removes the arcs")
	save.opt.reduced_motion = false
	fx = FxS.new()
	sfx_ = ShieldS.new(fx)
	sfx_.update(0.016, Vector2(300, 600), 40.0, 60.0, true, true)
	sfx_.on_break(Vector2(300, 600))
	check(sfx_.collapse > 0.0 and fx.rings.size() >= 2 and fx.flashes.size() >= 1, "a shield break bursts, rings out and collapses")
	var shards := 0
	for p in fx.debris:
		if int((p as Dictionary).shape) == 2:
			shards += 1
	check(shards >= 6, "and fragments fly outwards (%d)" % shards)
	sfx_.update(0.1, Vector2(300, 600), 0.0, 60.0, true, true)
	check(sfx_.collapse_scale() > 1.0 and sfx_.collapse_alpha() > 0.0, "the bubble expands and fades rather than vanishing")
	var event: String = sfx_.update(0.016, Vector2(300, 600), 8.0, 60.0, true, true)
	check(event == "up" and sfx_.update(0.016, Vector2(300, 600), 9.0, 60.0, true, true) != "up", "a recovering shield announces itself once")
	var warned := 0
	for i in range(140):
		if sfx_.update(0.05, Vector2(300, 600), 3.0, 60.0, true, true) == "warn":
			warned += 1
	check(warned >= 1 and warned <= 3, "a nearly gone shield warns now and then, not constantly (%d in 7 s)" % warned)

	# --- In a real flight: damage is unchanged, and effects follow ---
	var game = await _new_game(_level(3))
	_step(game, 2.0)
	game.invuln = 0.0
	game.hull = game.max_hull
	var start_shield: float = game.shield
	game.hurt_player(10.0, game.player_pos + Vector2(0, -300))
	check(is_equal_approx(game.shield, start_shield - 10.0) and game.hull == game.max_hull, "a shield hit still removes exactly its damage")
	check(game.fx.ripples.size() >= 1, "and shows a ripple")
	game.invuln = 0.0
	game.hurt_player(game.shield + 5.0, game.player_pos + Vector2(100, -100))
	check(game.shield == 0.0 and game.hull == game.max_hull and game.tracker.shield_broke and game.shield_fx.collapse > 0.0, "breaking the shield still costs no hull, and it collapses visibly")
	game.invuln = 0.0
	game.hurt_player(5.0)
	check(game.hull == game.max_hull - 1, "the next hit still costs one hull")
	game.shield = game.max_shield * 0.1
	game.invuln = 0.0
	var ratio_before: float = game.shield / game.max_shield
	_step(game, 3.0)
	check(game.shield >= game.max_shield * 0.1 * 0.99 and ratio_before > 0.0, "wear effects never lower the shield")
	# Enemy shields.
	var shielded: Dictionary = game.spawn_enemy({"kind": "fighter", "mod": "shielded", "pos": Vector2(360, 300), "move": "straight", "vel": Vector2.ZERO})
	check(float(shielded.eshield_max) > 0.0 and is_equal_approx(float(shielded.eshield), float(shielded.eshield_max)), "a shielded enemy records its full shield")
	var hp_before: float = shielded.hp
	var sh_before: float = shielded.eshield
	game.fx.ripples.clear()
	game._hit_enemy(shielded, 0.4, shielded.pos + Vector2(0, 30), false, false, "pulse")
	check(is_equal_approx(float(shielded.eshield), sh_before - 0.4) and float(shielded.hp) == hp_before and game.fx.ripples.size() == 1, "a shot into an enemy shield removes exactly its damage and ripples")
	game._hit_enemy(shielded, 9.0, shielded.pos, false, false, "missile")
	check(float(shielded.eshield) <= 0.0 and game.fx.rings.size() >= 2, "an enemy shield breaks with a burst")
	var plain: Dictionary = game.spawn_enemy({"kind": "fighter", "pos": Vector2(200, 300), "move": "straight", "vel": Vector2.ZERO})
	check(float(plain.eshield) == 0.0 and float(plain.eshield_max) == 0.0, "enemies without a shield do not get one")
	var hp0: float = plain.hp
	game._hit_enemy(plain, 0.5, plain.pos, false, false, "twin")
	check(is_equal_approx(float(plain.hp), hp0 - 0.5), "a hull hit still removes exactly its damage")

	# --- Every kind of enemy dies with an explosion, and dying together stays bounded ---
	game.fx.update(20.0)
	for kind in Enemies_.DB:
		if kind == "ally":
			continue
		var e: Dictionary = game.spawn_enemy({"kind": kind, "pos": Vector2(360, 400), "move": "straight", "vel": Vector2.ZERO})
		game.fx.booms.clear()
		game.fx.flashes.clear()
		game._kill_enemy(e, true)
		check(game.fx.flashes.size() + game.fx.booms.size() > 0, "%s explodes" % kind)
	# A mine is heard once: its own blast, not the generic small explosion as well. Other small enemies still use the generic one.
	var audio_node = root.get_node("Audio")
	for kind in ["mine", "raider"]:
		for i in range(audio_node.POOL_SIZE):
			audio_node._pool[i].stop()
		audio_node._last.clear()
		var sound_target: Dictionary = game.spawn_enemy({"kind": kind, "pos": Vector2(360, 400), "move": "straight", "vel": Vector2.ZERO})
		game._kill_enemy(sound_target, true)
		var heard := {}
		for i in range(audio_node.POOL_SIZE):
			if audio_node._pool[i].playing and audio_node._pool_group[i] == "explosion":
				for sound_name in ["explode_s", "explode_m", "explode_heavy"]:
					if audio_node._pool[i].stream == audio_node._streams[sound_name]:
						heard[sound_name] = int(heard.get(sound_name, 0)) + 1
		if kind == "mine":
			check(heard == {"explode_m": 1}, "a mine dying makes one explosion sound, its own (%s)" % str(heard))
		else:
			check(heard == {"explode_s": 1}, "a small enemy dying makes one small explosion sound (%s)" % str(heard))
	for i in range(audio_node.POOL_SIZE):
		audio_node._pool[i].stop()
	game.fx.update(20.0)
	for i in range(30):
		game.spawn_enemy({"kind": ["gunship", "frigate", "fighter", "elite", "rock_l"][i % 5], "pos": Vector2(randf() * 600.0 + 60.0, randf() * 500.0 + 100.0), "move": "straight", "vel": Vector2.ZERO})
	for e2 in game.enemies.duplicate():
		if not e2.dead:
			game._kill_enemy(e2, true)
	var lists := _fx_lists(game.fx)
	check(game.fx.spark_count <= FxS.MAX_SPARKS and lists.booms <= FxS.MAX_BOOMS and lists.rings <= FxS.MAX_RINGS and lists.debris <= FxS.MAX_DEBRIS and game.fx.flashes.size() <= FxS.MAX_FLASHES, "thirty enemies dying at once stay inside the effect caps (%s)" % str(lists))
	_fx_settle(game.fx, 12.0)
	check(game.fx.live_count() == 0, "and nothing accumulates afterwards (%d left)" % game.fx.live_count())
	game.queue_free()
	await process_frame

	# --- Shots carry their weapon, and every ship's weapon hits with its own effect ---
	for id in Ships_.ORDER:
		save.ship = id
		save.owned_ships = Ships_.ORDER.duplicate()
		var g2 = await _new_game(_level(2))
		_step(g2, 2.5)
		check(g2.engine_fx.profile == EngineS.PROFILES[id], "%s flies with its own engine profile" % id)
		var wpn: String = str(Ships_.LIST[id].weapon)
		var carried := false
		for b in g2.shots:
			if str((b as Dictionary).get("wpn", "")) == wpn:
				carried = true
		check(carried or wpn == "beam", "%s shots carry their weapon (%s)" % [id, wpn])
		var target: Dictionary = g2.spawn_enemy({"kind": "gunship", "pos": Vector2(360, 300), "move": "straight", "vel": Vector2.ZERO})
		g2.fx.update(10.0)
		g2.fx.flashes.clear()
		g2.fx._impact_tokens = 14.0
		var hp_start: float = target.hp
		g2._hit_enemy(target, 0.9, target.pos, false, false, wpn)
		check(float(target.hp) == hp_start - 0.9, "%s hit removes exactly its damage" % id)
		if wpn != "missile":
			check(g2.fx.flashes.size() >= 1, "%s shows an impact flash" % id)
		g2.queue_free()
		await process_frame

	# --- Engines: reusable profiles, driven by real movement ---
	var glows := {}
	for id in Ships_.ORDER:
		check(EngineS.PROFILES.has(id), "%s has an engine profile" % id)
		glows[str((EngineS.PROFILES[id] as Dictionary).glow)] = true
	check(glows.size() == Ships_.ORDER.size(), "every ship's engine has its own colour")
	check(float(EngineS.PROFILES.warden.width) > float(EngineS.PROFILES.nova.width) and float(EngineS.PROFILES.nova.width) > float(EngineS.PROFILES.interceptor.width), "heavy ships have wider exhaust than agile ones")
	check(float(EngineS.PROFILES.interceptor.length) > float(EngineS.PROFILES.warden.length), "agile ships have longer, narrower exhaust")
	var engine = EngineS.new()
	var pos := Vector2(360, 900)
	for i in range(40):
		engine.update_motion(1.0 / 60.0, pos, true)
	var idle: float = engine.intensity()
	check(engine.speed_k < 0.05 and idle < 0.7, "a ship standing still has a short, calm exhaust (%.2f)" % idle)
	for i in range(40):
		pos.x += 5.0
		engine.update_motion(1.0 / 60.0, pos, true)
	var cruising: float = engine.intensity()
	check(cruising > idle + 0.3 and engine.speed_k > 0.3, "moving lengthens it (%.2f)" % cruising)
	for i in range(40):
		pos.x += 11.0
		engine.update_motion(1.0 / 60.0, pos, true)
	check(engine.intensity() > cruising and engine.speed_k > 0.8, "moving fast lengthens it further (%.2f)" % engine.intensity())
	check(engine.lateral > 0.3, "and it leans against sideways movement")
	check(engine._trail.size() > 0 and engine._trail.size() <= EngineS.TRAIL_SLOTS, "fast movement leaves a short trail of at most %d afterimages" % EngineS.TRAIL_SLOTS)
	for i in range(60):
		engine.update_motion(1.0 / 60.0, pos, true)
	check(engine._trail.is_empty() and engine.speed_k < 0.05, "and the trail fades away once the ship stops")
	var peak_ref: float = engine_peak_reference(EngineS)
	save.opt.reduced_motion = true
	var calm_engine = EngineS.new()
	var cpos := Vector2(360, 900)
	for i in range(80):
		cpos.x += 11.0
		calm_engine.update_motion(1.0 / 60.0, cpos, true)
	check(calm_engine._trail.is_empty() and calm_engine.intensity() < peak_ref, "Reduce Motion removes the trail and tones the exhaust down")
	save.opt.reduced_motion = false
	fx = FxS.new()
	fx.density = 1.0
	var slow_engine = EngineS.new()
	var fast_engine = EngineS.new()
	var sp := Vector2(360, 900)
	var fp := Vector2(360, 900)
	for i in range(30):
		fp.x += 11.0
		slow_engine.update_motion(1.0 / 60.0, sp, true)
		fast_engine.update_motion(1.0 / 60.0, fp, true)
	var slow_fx = FxS.new()
	var fast_fx = FxS.new()
	slow_fx.density = 1.0
	fast_fx.density = 1.0
	for i in range(60):
		slow_engine.emit(1.0 / 60.0, slow_fx, sp, true)
		fast_engine.emit(1.0 / 60.0, fast_fx, fp, true)
	check(fast_fx.spark_count > slow_fx.spark_count, "a fast ship streams more exhaust particles (%d vs %d)" % [fast_fx.spark_count, slow_fx.spark_count])
	var dead_fx = FxS.new()
	engine.emit(0.5, dead_fx, pos, false)
	check(dead_fx.spark_count == 0, "a destroyed ship stops emitting")

	# --- Audio: every sound exists, voices are limited and prioritised, music and the SFX volume are respected ---
	var audio = root.get_node("Audio")
	for n in audio.SFX_NAMES:
		check(audio._streams.get(n) != null, "sound %s is loaded" % n)
	for n in ["shoot", "shoot_twin", "shoot_scatter"]:
		check(not n in audio.SFX_NAMES and not FileAccess.file_exists("res://assets/audio/sfx/%s.wav" % n), "the retired %s sound is gone" % n)
	for group in audio.GROUPS:
		for n in audio.GROUPS[group]:
			check(n in audio.SFX_NAMES, "%s (voice group %s) is a real sound" % [n, group])
	for w in AudioS.FIRE:
		check(audio._streams.get(AudioS.FIRE[w].sound) != null, "%s fires with a real sound" % w)
	for n in ["fire_plasma", "fire_laser", "fire_scatter", "impact_plasma", "impact_laser", "impact_explosive", "impact_heavy", "shield_heavy", "shield_break", "shield_up", "shield_warn", "explode_heavy", "boss_chain", "boss_final"]:
		var stream: AudioStreamWAV = audio._streams.get(n)
		check(stream != null and stream.get_length() > 0.05, "new sound %s has content" % n)
	check(audio._streams.explode_s.get_length() < audio._streams.explode_m.get_length() and audio._streams.explode_m.get_length() < audio._streams.explode_heavy.get_length() and audio._streams.explode_heavy.get_length() < audio._streams.boss_final.get_length(), "explosions get longer from small to boss")
	check(audio._streams.shield_break.get_length() > audio._streams.shield_hit.get_length(), "the shield break is longer than a shield hit")
	check(int(audio.PRIORITY.boss_final) > int(audio.PRIORITY.explode_heavy) and int(audio.PRIORITY.explode_heavy) > int(audio.PRIORITY.explode_s) and int(audio.PRIORITY.shield_break) > int(audio.PRIORITY.shield_hit) and int(audio.PRIORITY.hull_hit) > int(audio.PRIORITY.impact_plasma), "important sounds outrank routine ones")
	var sfx_bus: int = AudioServer.get_bus_index("SFX")
	var limited := false
	for i in range(AudioServer.get_bus_effect_count(sfx_bus)):
		if "Limiter" in AudioServer.get_bus_effect(sfx_bus, i).get_class():
			limited = true
	check(limited, "the SFX bus ends in a limiter, so it cannot clip")
	# Voice limits: flood the impact group with sounds that are not throttled against each other.
	audio._last.clear()
	for i in range(40):
		audio._last.clear()
		audio.play(["hit", "clank", "impact_plasma", "impact_laser", "impact_explosive", "crit"][i % 6], -30.0)
	var impact_voices := 0
	for i in range(audio.POOL_SIZE):
		if audio._pool[i].playing and audio._pool_group[i] == "impact":
			impact_voices += 1
	check(impact_voices <= int(audio.GROUP_LIMIT.impact), "forty impact sounds in a row use at most %d voices (%d)" % [audio.GROUP_LIMIT.impact, impact_voices])
	audio._last.clear()
	audio.play("boss_final", -30.0)
	var boss_voice := false
	for i in range(audio.POOL_SIZE):
		if audio._pool[i].playing and audio._pool_group[i] == "explosion" and audio._pool[i].stream == audio._streams.boss_final:
			boss_voice = true
	check(boss_voice, "a boss explosion always gets a voice")
	for i in range(audio.POOL_SIZE):
		audio._pool[i].stop()
	# The player's volume settings still rule, and ducking comes back by itself.
	save.opt.music_volume = 0.8
	for i in range(300):
		audio._process(0.05)  # let any duck from the explosions above run out first
	audio.apply_volumes()
	var base_db: float = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
	audio.duck(6.0, 0.1)
	check(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) < base_db - 5.0, "a big blast lowers the music a little")
	for i in range(80):
		audio._process(0.05)
	check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) - base_db) < 0.01, "and the music comes back to the player's volume")
	save.opt.sfx_volume = 0.0
	audio.apply_volumes()
	check(AudioServer.get_bus_volume_db(sfx_bus) <= -79.0, "the SFX volume setting still silences every effect")
	save.opt.sfx_volume = 1.0
	audio.apply_volumes()

	# --- Boss destruction in a real fight: attacks stop, sub-explosions, a finale ---
	save.upgrades = {"cannon": 6, "rapid": 6}
	var bg = await _new_game(_level(10))
	bg.level.waves[0] = []
	_step(bg, 2.5)
	var guard := 0
	while bg.boss == null and guard < 400:
		bg.hull = bg.max_hull
		bg._process(STEP)
		guard += 1
	check(bg.boss != null, "a boss to destroy")
	var guard2 := 0
	while bg.boss != null and not bg.boss.can_be_hit() and guard2 < 600:
		bg._process(STEP)
		guard2 += 1
	bg.fx.update(20.0)
	var boss = bg.boss
	boss._apply(boss.max_hp * 5.0)
	check(boss.dying > 0.0 and bg.field.count == 0, "destroying a boss stops its attacks and clears its bullets")
	var blasts := 0
	var fired := false
	var guard3 := 0
	while not boss.dead and guard3 < 900:
		var b_before: int = bg.fx.booms.size()
		bg.hull = bg.max_hull
		bg._process(STEP)
		blasts += 1 if bg.fx.booms.size() > b_before else 0
		if bg.field.count != 0 and not boss.dead:
			fired = true
		guard3 += 1
	check(not fired, "a dying boss fires nothing")
	check(boss.dead and blasts >= 5, "a dying boss has several smaller explosions before the end (%d)" % blasts)
	_step(bg, 0.4)
	check(bg.fx.rings.size() >= 3 and bg.fx.debris.size() > 5, "and ends in a large blast with shockwaves and wreckage")
	_fx_settle(bg.fx, 12.0)
	check(bg.fx.live_count() == 0, "and it all cleans up")
	bg.queue_free()
	await process_frame

	save.opt = saved_opt
	save.owned_ships = saved_ships
	save.ship = saved_ship
	save.upgrades = saved_upgrades
	print("combat polish ok")

# ---------- Attack telegraphs ----------
var TgS
var TgPaintS
var BfS
var BossS
# Every check compares what the player is SHOWN (the descriptors from TgS.collect) with what the attack then
# really emitted: its bullets, beams, zones and spawns. Nothing here only asks whether a warning object exists.

const TG_SHOTS := {"aimed": "fighter", "twin": "weaver", "fan": "gunship", "lance": "sentinel", "bomb": "bomber", "broadside": "frigate", "spawn": "brood", "elite": "elite"}
## Attacks that are deliberately not warned, with the reason. Everything else a boss does must have a warning.
const TG_EXCLUDED := {"blink": "the Regent only moves; nothing is fired", "mirror": "teleports and places decoys; the burst is a reaction to a decoy being shot"}

func _tg_ang_eq(a: float, b: float) -> bool:
	return absf(wrapf(a - b, -PI, PI)) < 0.002

func _tg_bullets(game) -> Array:
	var out: Array = []
	for i in range(game.field.count):
		out.append({"at": game.field.pos[i], "ang": game.field.vel[i].angle(), "speed": game.field.vel[i].length(), "dmg": game.field.dmg[i], "kind": game.field.kind[i]})
	return out

## True when every ray has exactly one bullet at its origin and angle, and there are no other bullets.
func _tg_match(rays: Array, bullets: Array) -> bool:
	if rays.size() != bullets.size() or rays.is_empty():
		return false
	var used := {}
	for r in rays:
		var found := false
		for j in range(bullets.size()):
			if used.has(j):
				continue
			var b: Dictionary = bullets[j]
			if ((r.at as Vector2) - (b.at as Vector2)).length() < 0.05 and _tg_ang_eq(float(r.ang), float(b.ang)):
				used[j] = true
				found = true
				break
		if not found:
			return false
	return true

## Runs the game's timers (and the warning store) the way _update_world does.
func _tg_flush(game, seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		var dt := minf(0.02, left)
		game._update_timers(dt)
		game.tg.update(dt)
		left -= dt

func _tg_desc(game, owner) -> Dictionary:
	game.tg.collect(game)
	for d in game.tg.shown:
		if d.has("owner") and is_same(d.owner, owner):
			return d
	return {}

func _tg_reset(game) -> void:
	game.field.clear()
	game.timers.clear()
	game.pending.clear()
	game.tg.clear()
	game.hazards.beams.clear()
	game.hazards.zones.clear()
	game.hazards.wells.clear()
	game.hazards.spokes.clear()
	game.field.wells.clear()
	game.field.frost.clear()
	for i in range(game.enemies.size() - 1, -1, -1):
		game._release_enemy(i, game.enemies[i])

func _tg_enemy(game, shot: String, at: Vector2) -> Dictionary:
	var e: Dictionary = game.spawn_enemy({"kind": TG_SHOTS[shot], "pos": at, "vel": Vector2.ZERO, "move": "straight"})
	e.fire = 0.0
	return e

## The shots of each enemy attack written out from the original `_enemy_shoot`, independent of Telegraph.
func _tg_original_shots(shot: String, pos: Vector2, player: Vector2, phase: float) -> Array:
	var aim := (player - pos).angle()
	var out: Array = []
	match shot:
		"aimed":
			out.append({"at": pos + Vector2(0, 40), "ang": aim})
		"twin":
			out.append({"at": pos + Vector2(-26, 30), "ang": PI * 0.5})
			out.append({"at": pos + Vector2(26, 30), "ang": PI * 0.5})
		"fan":
			for i in range(5):
				out.append({"at": pos + Vector2(0, 80), "ang": aim + (float(i) - 2.0) * 0.2})
		"bomb":
			for side in [-0.32, 0.0, 0.32]:
				out.append({"at": pos + Vector2(0, 50), "ang": PI * 0.5 + float(side)})
		"broadside":
			for i in range(5):
				out.append({"at": pos + Vector2((float(i) - 2.0) * 44.0, 30), "ang": PI * 0.5})
		"elite":
			for i in range(14):
				out.append({"at": pos + Vector2(0, 40), "ang": float(i) * TAU / 14.0 + phase})
	return out

func _test_telegraphs() -> void:
	TgS = load("res://src/combat/telegraph.gd")
	TgPaintS = load("res://src/combat/telegraph_paint.gd")
	BfS = load("res://src/combat/bullet_field.gd")
	BossS = load("res://src/combat/boss_base.gd")
	var saved_opt = save.opt.duplicate()
	var game = await _new_game(_level(3))
	game.level.waves[0] = []
	game.elite_chance = 0.0
	game.phase = game.Phase.PLAYING
	game.player_pos = Vector2(420, 1100)
	game.player_target = game.player_pos
	var bm: float = float(game.scale_cfg.bullet) * float(game.bullet_mult)
	# What each shot should look like on the field, so the refactor to shared geometry provably changed nothing:
	# [speed, damage, bullet kind, count].
	var expect := {
		"aimed": [270.0, 24.0, BfS.ORB, 1], "twin": [270.0 * 1.08, 18.0, BfS.DART, 2], "fan": [270.0 * 0.95, 24.0, BfS.DART, 5],
		"bomb": [270.0 * 0.6, 30.0, BfS.HEAVY, 3], "broadside": [270.0 * 0.9, 24.0, BfS.DART, 5], "elite": [270.0 * 0.8, 24.0, BfS.ORB, 14],
	}

	# --- Enemy attacks: the warning is a function of the tell timer, and shows the shot that follows ---
	for shot in TG_SHOTS:
		_tg_reset(game)
		var e := _tg_enemy(game, shot, Vector2(300, 420))
		game._update_enemies(STEP)
		check(float(e.tell) > 0.0 and is_equal_approx(float(e.tell_max), TgS.tell_time(shot)), "%s: the existing tell still starts, for %.1fs" % [shot, TgS.tell_time(shot)])
		var d := _tg_desc(game, e)
		check(not d.is_empty() and str(d.kind) == shot, "%s: a warning is shown while the enemy prepares" % shot)
		var k0: float = float(d.get("k", -1.0))
		var rising := true
		var last_k := k0
		while float(e.tell) > 0.07:
			game._update_enemies(0.05)
			var dd := _tg_desc(game, e)
			rising = rising and not dd.is_empty() and float(dd.k) >= last_k - 1e-6 and absf(float(dd.k) - (1.0 - float(e.tell) / float(e.tell_max))) < 1e-5
			last_k = float(dd.get("k", -1.0))
		check(rising and last_k > 0.5, "%s: the warning follows the tell timer from %.2f to %.2f" % [shot, k0, last_k])
		# The ship moves just before the shot. Aimed attacks must follow it; lanes must not.
		var before_rays: Array = _tg_desc(game, e).get("rays", [])
		game.player_pos = Vector2(180, 1010)
		var pre := _tg_desc(game, e)
		var tracks: bool = shot in ["aimed", "fan", "lance"]
		if not before_rays.is_empty() and shot != "spawn" and shot != "elite":
			var moved := not _tg_ang_eq(float((before_rays[0] as Dictionary).ang), float((pre.rays as Array)[0].ang))
			check(moved == tracks, "%s: the warning %s the ship like the shot does" % [shot, "tracks" if tracks else "does not follow"])
		var first_new = game.field.count
		var enemies_before: int = game.enemies.size()
		game.t += 0.37  # time passes between the warning and the shot; nothing previewed may depend on it
		game._update_enemies(0.07)
		check(float(e.tell) <= 0.0, "%s: the shot fires when the tell ends" % shot)
		if shot == "lance":
			_tg_flush(game, 0.6)
		var bullets := _tg_bullets(game)
		if shot == "spawn":
			var born: Array = []
			for i in range(enemies_before, game.enemies.size()):
				born.append(game.enemies[i].pos)
			var marks: Array = []
			for m in pre.markers:
				marks.append(m.pos)
			check(born.size() == 2 and marks.size() == 2 and marks[0].is_equal_approx(born[0]) and marks[1].is_equal_approx(born[1]), "spawn: the two markers sit exactly where the swarmlets appear")
			check(game.field.count == 0, "spawn: no projectile warning for an attack that fires none")
		elif shot == "lance":
			var ok := bullets.size() == 5
			for b in bullets:
				ok = ok and _tg_ang_eq(float(b.ang), float((pre.rays as Array)[0].ang)) and absf(float(b.speed) - 400.0 * bm) < 0.05 and int(b.kind) == BfS.SHARD and absf(float(b.dmg) - 20.0) < 1e-4
			check(ok, "lance: all five delayed shots use the captured aim shown by the warning, at the same speed and damage")
		else:
			check(_tg_match(pre.rays, bullets), "%s: the warning's rays match the %d projectiles exactly (origin and angle)" % [shot, bullets.size()])
			check(_tg_match(_tg_original_shots(shot, e.pos, game.player_pos, float(e.tphase)), bullets), "%s: and those projectiles are the ones the original attack formulas give" % shot)
			var x: Array = expect[shot]
			var same := bullets.size() == int(x[3])
			for b in bullets:
				same = same and absf(float(b.speed) - float(x[0]) * bm) < 0.05 and int(b.kind) == int(x[2]) and absf(float(b.dmg) - float(x[1])) < 1e-4
			check(same, "%s: projectile count, speed, damage and type are exactly what they were" % shot)
		var after := _tg_desc(game, e)
		if shot == "elite":
			# The ring just fired. What is shown now is the follow-up volley, 0.45s later, aimed at the ship.
			check(str(after.get("kind", "")) == "elite_follow" and (after.rays as Array).size() == 3, "elite: after the ring, the follow-up shows as its own warning (not as part of the ring)")
			var fu_rays: Array = after.rays
			game.field.clear()
			_tg_flush(game, 0.3)
			check(not _tg_desc(game, e).is_empty() and game.field.count == 0, "elite: the follow-up is still only a warning 0.3s later")
			_tg_flush(game, 0.2)
			check(_tg_match(fu_rays, _tg_bullets(game)) and _tg_desc(game, e).is_empty(), "elite: the follow-up's three shots match its warning, which then disappears")
		else:
			check(after.is_empty(), "%s: no warning is left after the attack" % shot)
		game.player_pos = Vector2(420, 1100)
	_tg_reset(game)

	# --- The elite ring phase is chosen when the tell begins and reused at the shot ---
	var el := _tg_enemy(game, "elite", Vector2(300, 420))
	game._update_enemies(STEP)
	var phase0: float = float(el.tphase)
	var seen_a = (_tg_desc(game, el).rays as Array)[0].ang
	game.t += 0.4
	check(float(el.tphase) == phase0 and _tg_ang_eq(float((_tg_desc(game, el).rays as Array)[0].ang), float(seen_a)), "elite: time passing does not turn the previewed ring")
	_tg_reset(game)

	# --- Dead, frozen and out-of-range enemies leave nothing behind ---
	var dead := _tg_enemy(game, "aimed", Vector2(300, 420))
	game._update_enemies(STEP)
	check(not _tg_desc(game, dead).is_empty(), "a warning is shown for a preparing enemy")
	game._kill_enemy(dead, true)
	check(_tg_desc(game, dead).is_empty(), "killing the enemy removes its warning at once")
	game._update_enemies(STEP)
	check(_tg_desc(game, dead).is_empty() and game.tg.shown.is_empty(), "and none comes back after it is released")
	var cold := _tg_enemy(game, "fan", Vector2(300, 420))
	game._update_enemies(STEP)
	cold.frozen = 1.0
	check(_tg_desc(game, cold).is_empty(), "a frozen enemy shows no warning (its tell is paused too)")
	cold.frozen = 0.0
	cold.pos = Vector2(300, 1050)
	check(_tg_desc(game, cold).is_empty(), "an enemy that can no longer fire shows no warning")
	_tg_reset(game)
	var wake := _tg_enemy(game, "elite", Vector2(300, 420))
	game._update_enemies(STEP)
	game._update_enemies(1.0)
	check(not game.tg.timed.is_empty(), "the follow-up warning exists for the elite")
	game._kill_enemy(wake, true)
	check(_tg_desc(game, wake).is_empty(), "killing an elite between its volleys removes the follow-up warning")
	game.tg.update(0.0)
	check(game.tg.timed.is_empty(), "and the store drops it")
	_tg_reset(game)

	# --- Pause, hit-stop, slow motion and leaving the fight ---
	var clock := _tg_enemy(game, "aimed", Vector2(300, 420))
	game._update_enemies(STEP)
	game._update_enemies(0.1)
	var t_before: float = float(clock.tell)
	var k_before: float = float(_tg_desc(game, clock).k)
	game.hitstop = 0.2
	game._tick(STEP)
	check(is_equal_approx(float(clock.tell), t_before) and is_equal_approx(float(_tg_desc(game, clock).k), k_before), "hit-stop freezes the warning together with the tell")
	game.hitstop = 0.0
	game.time_scale = 0.3
	var expected_dt: float = STEP * move_toward(0.3, 1.0, STEP * 1.6)
	game._tick(STEP)
	check(absf((t_before - float(clock.tell)) - expected_dt) < 1e-4 and absf(float(_tg_desc(game, clock).k) - (1.0 - float(clock.tell) / float(clock.tell_max))) < 1e-5, "slow motion advances the warning by exactly the scaled time the tell used")
	game.time_scale = 1.0
	var paused_tell: float = float(clock.tell)
	game.set_paused(true)
	game._process(STEP)
	check(float(clock.tell) == paused_tell and not _tg_desc(game, clock).is_empty() and is_equal_approx(float(_tg_desc(game, clock).k), 1.0 - paused_tell / float(clock.tell_max)), "pausing holds the warning exactly where it was")
	game.phase = game.Phase.PLAYING
	game.phase = game.Phase.CLEAR
	game.tg.add("curtain_row", 0.0, 1.0, {"gap": 300.0, "hue": "warn", "list": [300.0]})
	check(_tg_desc(game, clock).is_empty() and game.tg.timed.is_empty(), "leaving the fight clears every warning")
	game.phase = game.Phase.PLAYING
	_tg_reset(game)

	# --- Several enemies at once stay readable, and the store has hard limits ---
	var kinds := ["aimed", "twin", "fan", "lance", "bomb", "broadside"]
	var crowd: Array = []
	for i in range(kinds.size()):
		crowd.append(_tg_enemy(game, kinds[i], Vector2(70.0 + float(i) * 118.0, 360.0 + float(i % 2) * 120.0)))
	game._update_enemies(STEP)
	for i in range(crowd.size()):
		crowd[i].tell = 0.2 + 0.04 * float(i)
	game.tg.collect(game)
	var owners := {}
	for d in game.tg.shown:
		owners[int(d.owner.id)] = str(d.kind)
	check(owners.size() == 6 and game.tg.shown.size() == 6, "six enemies preparing at once: six separate warnings")
	TgPaintS.build(game.tg.shown, 1.0, game.W, game.H)
	var busy = TgPaintS.stats()
	check(int(busy.lines) + int(busy.arcs) < 330 and int(busy.glows) <= TgPaintS.MAX_GLOWS, "and together they stay light (%d lines, %d arcs, %d glows)" % [busy.lines, busy.arcs, busy.glows])
	_tg_reset(game)
	var many: Array = []
	for i in range(16):
		many.append(_tg_enemy(game, "aimed", Vector2(40.0 + float(i) * 40.0, 300.0)))
	game._update_enemies(STEP)
	for i in range(many.size()):
		many[i].tell = 0.29 - 0.015 * float(i)
	game.tg.collect(game)
	var kept_min := 2.0
	var dropped_max := -1.0
	var kept_ids := {}
	for d in game.tg.shown:
		kept_min = minf(kept_min, float(d.k))
		kept_ids[int(d.owner.id)] = true
	for m in many:
		if not kept_ids.has(int(m.id)):
			dropped_max = maxf(dropped_max, 1.0 - float(m.tell) / float(m.tell_max))
	check(game.tg.shown.size() == TgS.MAX_ENEMY_SHOWN and kept_min >= dropped_max, "sixteen preparing: at most %d are drawn and they are the ones closest to firing" % TgS.MAX_ENEMY_SHOWN)
	_tg_reset(game)
	for i in range(100):
		game.tg.add("barrage", 0.0, 5.0, {"list": [float(i)]})
	check(game.tg.timed.size() == TgS.MAX_TIMED and is_equal_approx(float((game.tg.timed[0].data.list as Array)[0]), 100.0 - float(TgS.MAX_TIMED)), "the timed store is capped and drops the oldest first")
	var flood: Array = []
	for i in range(200):
		flood.append({"style": "radial", "hue": "danger", "k": 0.5, "origin": Vector2(300, 300), "centre": Vector2(300, 300), "rays": TgS.radial_rays(Vector2(300, 300), 28), "rl": 200.0})
		flood.append({"style": "fan", "hue": "warn", "k": 0.5, "origin": Vector2(300, 300), "rays": TgS.fan_rays(Vector2(300, 300), 13), "len": 560.0})
	TgPaintS.build(flood, 1.0, 720.0, 1280.0)
	var capped = TgPaintS.stats()
	check(int(capped.lines) <= TgPaintS.MAX_LINES and int(capped.arcs) <= TgPaintS.MAX_ARCS and int(capped.glows) <= TgPaintS.MAX_GLOWS and int(capped.polys) <= TgPaintS.MAX_POLYS and int(capped.plines) <= TgPaintS.MAX_PLINES and int(capped.segs) <= TgPaintS.MAX_SEGS, "four hundred warnings in one frame still draw within the hard caps (%s)" % str(capped))
	_tg_reset(game)

	# --- Audio: only the major attacks make a sound ---
	var audio_node = root.get_node("Audio")
	audio_node._last.clear()
	var quiet := _tg_enemy(game, "aimed", Vector2(300, 420))
	game._update_enemies(STEP)
	check(not audio_node._last.has("charge") and not audio_node._last.has("warning"), "an ordinary aimed shot has no warning sound")
	_tg_reset(game)
	audio_node._last.clear()
	var loud := _tg_enemy(game, "elite", Vector2(300, 420))
	game._update_enemies(STEP)
	check(audio_node._last.has("charge"), "the elite radial attack uses the existing charge sound")
	_tg_reset(game)

	# --- Accessibility ---
	var radial := {"style": "radial", "hue": "danger", "k": 0.6, "origin": Vector2(300, 400), "centre": Vector2(300, 400), "rays": TgS.radial_rays(Vector2(300, 400), 14, 0.3), "rl": 230.0}
	var spiral := {"style": "spiral", "hue": "arc", "k": 0.4, "origin": Vector2(300, 400), "arms": 3, "a0": 1.0, "kk": 0.015}
	var aimed := {"style": "aimed", "hue": "warn", "k": 0.7, "origin": Vector2(300, 300), "rays": [{"at": Vector2(300, 340), "ang": 1.4}], "len": 700.0}
	var sample := [radial, spiral, aimed]
	save.opt.reduced_motion = false
	save.opt.reduced_flash = false
	TgPaintS.build(sample, 1.0, game.W, game.H)
	var moving_a = TgPaintS.l_a.duplicate()
	var arcs_a = TgPaintS.a_0.duplicate()
	var lines_normal: int = TgPaintS.l_a.size()
	TgPaintS.build(sample, 1.37, game.W, game.H)
	check(moving_a != TgPaintS.l_a or arcs_a != TgPaintS.a_0, "by default the rings turn and the sweeps run")
	save.opt.reduced_motion = true
	TgPaintS.build(sample, 1.0, game.W, game.H)
	var still_a = TgPaintS.l_a.duplicate()
	var still_arcs = TgPaintS.a_0.duplicate()
	TgPaintS.build(sample, 1.37, game.W, game.H)
	check(still_a == TgPaintS.l_a and still_arcs == TgPaintS.a_0, "Reduce Motion: nothing spins or sweeps, the shapes hold still")
	check(TgPaintS.l_a.size() == lines_normal, "Reduce Motion keeps every line of the warning (%d)" % lines_normal)
	save.opt.reduced_motion = false
	TgPaintS.build(sample, 1.0, game.W, game.H)
	var glow_full := 0.0
	for c in TgPaintS.g_c:
		glow_full = maxf(glow_full, c.a)
	var pulse_moves := absf(TgPaintS._pulse(0.8) - 1.0) > 0.0
	save.opt.reduced_flash = true
	TgPaintS.build(sample, 1.0, game.W, game.H)
	var glow_soft := 0.0
	for c in TgPaintS.g_c:
		glow_soft = maxf(glow_soft, c.a)
	var steady := true
	for t in [0.1, 0.37, 0.9, 1.4]:
		TgPaintS.build(sample, t, game.W, game.H)
		steady = steady and TgPaintS._pulse(0.8) == 1.0
	check(pulse_moves and steady, "Reduce Flash: the warning pulse is steady instead of flickering")
	check(glow_soft <= glow_full * 0.5 + 1e-4 and TgPaintS.l_a.size() == lines_normal, "Reduce Flash: glows are at most half as bright and all the geometry is still there")
	save.opt.reduced_flash = false
	# Colour blind: a different palette, and every attack type still has its own shape.
	TgPaintS.build(sample, 1.0, game.W, game.H)
	var plain_col: Color = TgPaintS._hue("warn", 0.5)
	save.opt.colorblind = true
	TgPaintS.build(sample, 1.0, game.W, game.H)
	check(TgPaintS._hue("warn", 0.5) != plain_col and TgPaintS._hue("safe", 0.5).b > TgPaintS._hue("safe", 0.5).g, "Colour blind mode swaps to a blue and yellow palette")
	save.opt.colorblind = false
	var shapes := {}
	_tg_reset(game)
	for shot in TG_SHOTS:
		var s := _tg_enemy(game, shot, Vector2(300, 420))
		game._update_enemies(STEP)
		var dsc := _tg_desc(game, s)
		TgPaintS.build([dsc], 1.0, game.W, game.H)
		var sig := ""
		var origin: Vector2 = dsc.origin
		var sum := 0.0
		for i in range(TgPaintS.l_a.size()):
			sum += (TgPaintS.l_a[i] - TgPaintS.l_b[i]).length()
		sig = "%d/%d/%d/%d/%d" % [TgPaintS.l_a.size(), TgPaintS.a_at.size(), TgPaintS.polys.size(), TgPaintS.plines.size(), int(sum)]
		shapes[shot] = sig
		_tg_reset(game)
	var unique := {}
	for k in shapes:
		unique[shapes[k]] = true
	check(unique.size() == TG_SHOTS.size(), "every enemy attack type has its own shape, not just its own colour (%d distinct)" % unique.size())
	save.opt = saved_opt
	game.queue_free()
	await process_frame

## A game with a boss that has finished entering, the ship parked where the checks expect it.
func _tg_boss_game(sector: int):
	var game = await _new_game(_level(sector * 10))
	game.level.waves[0] = []
	game.elite_chance = 0.0
	_step(game, 2.5)
	var guard := 0
	while game.boss == null and guard < 400:
		game.hull = game.max_hull
		game._process(STEP)
		guard += 1
	guard = 0
	while game.boss != null and game.boss.entering and guard < 700:
		game.hull = game.max_hull
		game.invuln = 1.0
		game._process(STEP)
		guard += 1
	game.phase = game.Phase.BOSS
	game.player_pos = Vector2(300, 1100)
	game.player_target = game.player_pos
	_tg_reset(game)
	return game

## Prepares an attack the way the charge does, takes the warning, fires it, and returns both.
func _tg_attack(game, boss, name_: String) -> Dictionary:
	_tg_reset(game)
	boss.intent = boss.prepare(name_)
	boss.pending = name_
	boss.charge = BossS.CHARGE * 0.4
	game.tg.collect(game)
	var primary := {}
	for d in game.tg.shown:
		if str(d.get("src", "")) == "boss" and str(d.kind) == name_:
			primary = d
	var plan: Dictionary = boss.intent
	var enemies_before: int = game.enemies.size()
	boss.attack(name_)
	boss.charge = 0.0
	game._update_timers(0.001)
	return {"d": primary, "plan": plan, "bullets": _tg_bullets(game), "born": game.enemies.slice(enemies_before)}

func _tg_names(boss) -> Array:
	var names := {}
	var saved = boss.stage
	for s in range(3):
		boss.stage = s
		for n in boss.rotation():
			names[str(n)] = true
	if "heads" in boss:
		# The Hydra's rotation depends on how many heads are left.
		for alive in [2, 0]:
			for i in range(boss.heads.size()):
				boss.heads[i].head.alive = i < alive
			for n in boss.rotation():
				names[str(n)] = true
		for h in boss.heads:
			h.head.alive = true
	boss.stage = saved
	return names.keys()

func _tg_verify(game, boss, name_: String, r: Dictionary) -> void:
	var d: Dictionary = r.d
	var label := "%s s%d %s" % [str(boss.def.name), boss.stage, name_]
	if d.is_empty():
		check(false, label + ": has a warning")
		return
	var plan: Dictionary = r.plan
	var bullets: Array = r.bullets
	var W: float = float(game.W)
	match str(d.style):
		"fan", "aimed", "volley":
			if name_ == "fan":
				var n: int = 9 + boss.stage * 2
				var orig: Array = []
				for i in range(n):
					orig.append({"at": boss.muzzle(), "ang": PI * 0.5 + (float(i) - float(n - 1) * 0.5) * 0.17})
				check(_tg_match(orig, bullets), label + ": the fan is the original %d shots, 0.17 rad apart" % n)
			elif name_ == "aimed":
				var aim: float = (game.player_pos - boss.muzzle()).angle()
				var orig: Array = []
				for i in range(3):
					orig.append({"at": boss.muzzle(), "ang": aim + (float(i) - 1.0) * 0.12})
				check(_tg_match(orig, bullets), label + ": the aimed volley is the original three shots, 0.12 rad apart")
			if name_ == "throw":
				var rays: Array = d.rays
				var ok: bool = r.born.size() == rays.size() and not rays.is_empty()
				for i in range(mini(rays.size(), r.born.size())):
					var born: Dictionary = r.born[i]
					ok = ok and (born.pos as Vector2).is_equal_approx(rays[i].at) and _tg_ang_eq((born.vel as Vector2).angle(), float(rays[i].ang))
				check(ok, label + ": the boulders leave from, and along, the warned lines")
			else:
				check(_tg_match(d.rays, bullets), label + ": the %d warned rays are exactly the %d shots" % [(d.rays as Array).size(), bullets.size()])
				if name_ in ["fan", "aimed", "hurl", "shards"]:
					var base := {"fan": [245.0, BfS.DART, 24.0], "aimed": [305.0, BfS.ORB, 24.0], "hurl": [250.0, BfS.HEAVY, 30.0], "shards": [290.0, BfS.SHARD, 22.0]}[name_] as Array
					var same := true
					for b in bullets:
						same = same and absf(float(b.speed) - boss.speed(float(base[0]))) < 0.05 and int(b.kind) == int(base[1]) and absf(float(b.dmg) - float(base[2])) < 1e-4
					check(same, label + ": speed, damage and type are unchanged")
		"burst":
			var n := int(plan.n)
			var ok := _tg_match(d.rays, bullets) and int(d.n) == n and bullets.size() == 3
			check(ok, label + ": the first of %d aimed shots matches its warning" % n)
			var sequential = game.tg.timed.size() == 1 and (game.tg.timed[0].data.list as Array).size() == n - 1
			for i in range(1, n):
				_tg_flush(game, TgS.BURST_GAP)
				sequential = sequential and game.field.count == 3 * (i + 1) and (game.tg.timed.size() == 0 if i == n - 1 else (game.tg.timed[0].data.list as Array).size() == n - 1 - i)
			check(sequential, label + ": shots follow one by one, 0.26s apart, and the warning counts them down")
		"radial":
			if name_ == "collapse":
				var shown_kind := ""
				game.tg.collect(game)
				for s in game.tg.shown:
					if str(s.kind) == "collapse":
						shown_kind = str(s.style)
				check(shown_kind == "radial" and game.tg.timed.size() == 1, label + ": the rebound is warned for its whole 2s delay")
				_tg_flush(game, TgS.COLLAPSE_DELAY - 0.002)
				game.field.clear()
				_tg_flush(game, 0.01)
				check(_tg_match(d.rays, _tg_bullets(game)) and game.tg.timed.is_empty(), label + ": the 28 rebound shots match the warning, which then goes")
			else:
				check(_tg_match(d.rays, bullets), label + ": the %d radial rays are exactly the shots" % (d.rays as Array).size())
		"ring_gap":
			var count := int(plan.count)
			var step := TAU / float(count)
			var missing: Array = []
			for i in range(count):
				var present := false
				for b in bullets:
					present = present or _tg_ang_eq(float(b.ang), float(i) * step)
				if not present:
					missing.append(i)
			missing.sort()
			var want := [int(plan.gap), (int(plan.gap) + 1) % count]
			want.sort()
			var orig: Array = []
			for i in range(count):
				if i != int(plan.gap) and i != (int(plan.gap) + 1) % count:
					orig.append({"at": boss.muzzle(), "ang": float(i) * step})
			check(_tg_match(orig, bullets), label + ": the ring is the original evenly spaced shots minus the two at the gap")
			check(_tg_match(d.rays, bullets) and missing == want, label + ": the safe gap shown (shots %s) is the gap fired (%s)" % [str(want), str(missing)])
			check(_tg_ang_eq(float(d.gap_ang), (float(plan.gap) + 0.5) * step) and bullets.size() == count - 2, label + ": the gap centre and the %d-shot count are right" % (count - 2))
		"spiral":
			var kk: float = float(d.kk)
			check(boss.stream_t > 0.0 and is_equal_approx(boss.stream_angle, float(plan.angle)) and boss.stream_arms == int(d.arms), label + ": the stream starts at the previewed angle with the previewed arms")
			game.field.clear()
			boss.stream_gap = 0.0
			var ticks := 6
			for i in range(ticks):
				for j in range(game.field.count):
					game.field.pos[j] += game.field.vel[j] * 0.11
				boss._update_stream(0.11)
				if i == 0:
					var first_ok = game.field.count == boss.stream_arms
					for j in range(game.field.count):
						var matched := false
						for arm in range(boss.stream_arms):
							matched = matched or _tg_ang_eq(game.field.vel[j].angle(), float(d.a0) + float(arm) * TAU / float(boss.stream_arms))
						first_ok = first_ok and matched
					check(first_ok, label + ": the first shots leave exactly along the previewed arms")
			var head: float = boss.stream_angle
			var curve_ok := true
			var tested := 0
			for j in range(game.field.count):
				var off: Vector2 = game.field.pos[j] - boss.muzzle()
				if off.length() < 5.0:
					continue
				var best := 9.0
				for arm in range(boss.stream_arms):
					best = minf(best, absf(wrapf(off.angle() - (head + float(arm) * TAU / float(boss.stream_arms) - off.length() * kk), -PI, PI)))
				curve_ok = curve_ok and best < 0.02
				tested += 1
			check(curve_ok and tested > 6, label + ": %d shots in flight lie on the previewed spiral curve" % tested)
		"curtain":
			_tg_verify_curtain(game, boss, name_, label, d, plan, bullets)
		"columns", "rows":
			var axis := "col" if str(d.style) == "columns" else "row"
			var spots: Array = d.xs if axis == "col" else d.ys
			var beams: Array = []
			for b in game.hazards.beams:
				if str(b.axis) == axis:
					beams.append(b)
			var ok: bool = beams.size() == spots.size() and not spots.is_empty()
			for i in range(mini(beams.size(), spots.size())):
				ok = ok and absf(float(beams[i].at) - float(spots[i])) < 0.01 and absf(float(beams[i].w) - float(d.hw)) < 0.01
			check(ok, label + ": the %d warned %s are the beams that appear (position and width)" % [spots.size(), "columns" if axis == "col" else "rows"])
		"drops":
			var xs: Array = plan.xs
			var ok = game.field.count == 1 and absf(float(game.field.pos[0].x) - float(xs[0])) < 0.01 and (game.tg.timed[0].data.list as Array).size() == xs.size() - 1
			for i in range(1, xs.size()):
				_tg_flush(game, TgS.SHELL_GAP)
				ok = ok and game.field.count == i + 1 and absf(float(game.field.pos[i].x) - float(xs[i])) < 0.01
			check(ok and game.tg.timed.is_empty(), label + ": the 8 shell columns match the shells, in order, and clear as they fall")
		"spots":
			var spots: Array = d.spots
			var found: Array = game.hazards.wells if spots[0].shape == "well" else game.hazards.zones
			var ok: bool = found.size() == spots.size()
			for i in range(mini(found.size(), spots.size())):
				ok = ok and (found[i].pos as Vector2).is_equal_approx(spots[i].pos)
				if spots[0].shape != "well":
					ok = ok and absf(float(found[i].r) - float(spots[i].r)) < 0.01 and str(found[i].kind) == str(spots[i].shape)
			check(ok, label + ": the %d warned zones are where the zones appear" % spots.size())
		"hub":
			var sp: Dictionary = game.hazards.spokes[0] if not game.hazards.spokes.is_empty() else {}
			check(not sp.is_empty() and _tg_ang_eq(float(sp.angle), float(d.a0)) and signf(float(sp.speed)) == float(d.dir) and int(sp.arms) == int(d.arms), label + ": the spokes start at the warned angle and turn the warned way")
		"markers":
			_tg_verify_markers(game, boss, name_, label, d, plan)
		_:
			check(false, label + ": unknown warning style " + str(d.style))

func _tg_verify_curtain(game, boss, name_: String, label: String, d: Dictionary, plan: Dictionary, bullets: Array) -> void:
	var gaps: Array = plan.gaps
	var W: float = float(game.W)
	var row_xs := func(list: Array) -> Array:
		var out: Array = []
		for b in list:
			out.append(float(b.at.x))
		out.sort()
		return out
	var want0: Array = TgS.curtain_xs(float(gaps[0]), W)
	var got0: Array = row_xs.call(bullets)
	var orig_xs: Array = []
	var ox := 30.0
	while ox < W:
		if absf(ox - float(gaps[0])) > 118.0:
			orig_xs.append(ox)
		ox += 58.0
	check(got0 == want0 and (d.xs as Array) == want0 and got0 == orig_xs, label + ": row 1 has exactly the shots its warning shows, on the original 58px grid with a 118px opening")
	var open_ok := true
	for x in got0:
		open_ok = open_ok and not (float(x) > float(d.open_l) + 0.001 and float(x) < float(d.open_r) - 0.001)
	check(open_ok and (float(d.open_l) == 0.0 or got0.has(float(d.open_l))) and (float(d.open_r) == W or got0.has(float(d.open_r))), label + ": the opening shown is empty and bounded by real shots")
	var rows := gaps.size()
	check(game.tg.timed.size() == rows - 1, label + ": each later row has its own warning (%d)" % (rows - 1))
	var now := 0.001
	var rows_ok := true
	var progress_ok := true
	for i in range(1, rows):
		var due = float(i) * TgS.CURTAIN_GAP
		_tg_flush(game, due - 0.3 - now)
		now = due - 0.3
		game.tg.collect(game)
		var seen := {}
		for s in game.tg.shown:
			if str(s.style) == "curtain":
				seen = s
		var k_early: float = float(seen.get("k", -1.0))
		rows_ok = rows_ok and not seen.is_empty() and absf(float(seen.gap) - float(gaps[i])) < 0.001 and (seen.xs as Array) == TgS.curtain_xs(float(gaps[i]), W)
		game.field.clear()
		_tg_flush(game, 0.31)
		now = due + 0.01
		var fell: Array = row_xs.call(_tg_bullets(game))
		rows_ok = rows_ok and fell == TgS.curtain_xs(float(gaps[i]), W)
		game.tg.collect(game)
		var still := false
		for s in game.tg.shown:
			still = still or (str(s.style) == "curtain" and absf(float(s.gap) - float(gaps[i])) < 0.001)
		progress_ok = progress_ok and not still and k_early > 0.3
	check(rows_ok, label + ": every row is warned with its own opening, and it falls exactly as shown")
	check(progress_ok and game.tg.timed.is_empty(), label + ": each row's warning ends the moment its row falls, and none is left over")

func _tg_verify_markers(game, boss, name_: String, label: String, d: Dictionary, plan: Dictionary) -> void:
	var marks: Array = d.markers
	var pend: Array = game.pending
	var W: float = float(game.W)
	if name_ == "brood":
		var ok: bool = pend.size() == int(plan.n) and marks.size() == 1
		for p in pend:
			ok = ok and absf(float(p.pos.x) - float(plan.origin)) <= 110.001
		check(ok and absf(float(marks[0].pos.x) - float(plan.origin)) < 0.001, label + ": all %d swarm members enter within the warned area" % pend.size())
		_tg_flush(game, float(int(plan.n)) * 0.14 + 0.1)
		check(game.tg.timed.is_empty(), label + ": the marker is gone once the swarm has arrived")
		return
	var ok: bool = pend.size() == marks.size() and not marks.is_empty()
	var longest := 0.0
	var timed_expected := 0
	for i in range(mini(pend.size(), marks.size())):
		var p: Dictionary = pend[i]
		var m: Dictionary = marks[i]
		if name_ == "launch":
			ok = ok and absf(float(p.pos.y) - float(m.pos.y)) < 0.01 and ((float(p.pos.x) < 0.0) == (float(m.pos.x) < W * 0.5))
		else:
			ok = ok and absf(float(p.pos.x) - float(m.pos.x)) < 0.01
		ok = ok and absf(float(p.t) - float(m.delay)) < 0.001
		longest = maxf(longest, float(m.delay))
		if float(m.delay) > 0.0:
			timed_expected += 1
	check(ok, label + ": the %d arrival markers are where, and when, the group enters" % marks.size())
	check(game.tg.timed.size() == timed_expected, label + ": a marker stays for each member still to arrive (%d)" % timed_expected)
	_tg_flush(game, longest + 0.1)
	check(game.tg.timed.is_empty(), label + ": and each marker is gone once its member has arrived")

func _test_telegraph_bosses() -> void:
	TgS = load("res://src/combat/telegraph.gd")
	TgPaintS = load("res://src/combat/telegraph_paint.gd")
	BfS = load("res://src/combat/bullet_field.gd")
	BossS = load("res://src/combat/boss_base.gd")
	var saved_opt = save.opt.duplicate()
	var covered := 0
	var excluded: Array = []
	save.upgrades = {"cannon": 6, "rapid": 6}
	# Summons are queued in game.pending, which is only advanced in the PLAYING phase, so in a real boss fight they never
	# arrive and their markers are hidden. Everything else about them is checked here as if they did arrive.
	var probe = await _tg_boss_game(1)
	probe.spawn_group({"kind": "mine", "form": "scatter", "count": 2, "delay": 0.0})
	for i in range(100):
		probe.hull = probe.max_hull
		probe.invuln = 1.0
		probe._process(STEP)
	var arrive: bool = probe.pending.is_empty()
	check(arrive == TgS.summons_arrive, "Telegraph.summons_arrive (%s) matches the game: a summon queued in a boss fight %s" % [str(TgS.summons_arrive), "arrives" if arrive else "never arrives (pending is not advanced in the BOSS phase)"])
	var summon_hidden: bool = not TgS.summons_arrive
	var hidden_ok := true
	for name_ in ["rocks", "raiders", "mines"]:
		_tg_reset(probe)
		var d: Dictionary = probe.boss.describe(probe.boss.prepare(name_), 0.5)
		hidden_ok = hidden_ok and (d.is_empty() if summon_hidden else str(d.style) == "markers")
		probe.boss.attack(name_)
		hidden_ok = hidden_ok and (probe.tg.timed.is_empty() if summon_hidden else true)
	check(hidden_ok, "while summons do not arrive, no marker or queued marker announces them")
	probe.queue_free()
	await process_frame
	TgS.summons_arrive = true
	for sector in range(1, 7):
		var game = await _tg_boss_game(sector)
		var boss = game.boss
		check(boss != null and not boss.entering, "boss %d is out and ready for its attacks" % sector)
		if boss == null:
			game.queue_free()
			continue
		for s in range(3):
			boss.stage = s
			for name_ in _tg_names(boss):
				if name_ in TG_EXCLUDED:
					boss.intent = boss.prepare(name_)
					check(boss.describe(boss.intent, 0.5).is_empty(), "boss %d %s is excluded on purpose: %s" % [sector, name_, TG_EXCLUDED[name_]])
					if not excluded.has(name_):
						excluded.append(name_)
					continue
				var r := _tg_attack(game, boss, name_)
				_tg_verify(game, boss, name_, r)
				covered += 1 if s == 0 else 0
		boss.stage = 0
		if sector == 1:
			# Every shared attack has the right kind of warning.
			var styles := {"fan": "fan", "aimed": "aimed", "burst": "burst", "ring": "ring_gap", "spiral": "spiral", "curtain": "curtain", "strike": "columns", "rocks": "markers", "raiders": "markers", "mines": "markers"}
			for name_ in styles:
				var d: Dictionary = boss.describe(boss.prepare(name_), 0.5)
				check(str(d.get("style", "")) == styles[name_], "shared attack %s has a %s warning" % [name_, styles[name_]])
			# Rocks scale with the player count settings; the warning must too.
			game.count_mult = 1.5
			var scaled := _tg_attack(game, boss, "rocks")
			check(game.pending.size() == (scaled.d.markers as Array).size() and game.pending.size() == int(round(4.0 * 1.5)), "group markers follow the same count scaling as the group (%d)" % game.pending.size())
			game.count_mult = 1.0
			# The ring's gap is rolled once per charge, with the old odds and counts.
			var gaps := {}
			for i in range(60):
				var p: Dictionary = boss.prepare("ring")
				gaps[int(p.gap)] = true
				if int(p.count) != 20 or int(p.gap) < 0 or int(p.gap) >= 20:
					check(false, "ring plan out of range")
			check(gaps.size() > 8, "the ring gap is still random (%d distinct positions in 60 charges)" % gaps.size())
			# A stage change mid-charge re-prepares the plan so counts match the new stage.
			boss.stage = 0
			boss.pending = "ring"
			boss.charge = 0.3
			boss.intent = boss.prepare("ring")
			boss.stage = 1
			boss._stage_up()
			check(int(boss.intent.count) == 24 and int(boss.intent.stage) == 1, "a stage change mid-charge re-prepares the attack for the new stage")
			_tg_reset(game)
			boss.attack("ring")
			check(game.field.count == 22, "and the ring then fires 24 - 2 shots, as it always did")
			boss.stage = 0
			boss.charge = 0.0
			boss.intent = {}
		if sector == 6:
			# Audio: the second, lower tone is only for the most dangerous attacks. Boss order is ring, strike, wells, spiral.
			var audio_node = root.get_node("Audio")
			boss.stage = 0
			var tones := {}
			for want in [["ring", 0], ["strike", 1], ["wells", 2], ["spiral", 3]]:
				_tg_reset(game)
				audio_node._last.clear()
				boss.charge = 0.0
				boss.attack_t = 0.0
				boss.order = int(want[1])
				boss.update(STEP)
				tones[want[0]] = [boss.pending, audio_node._last.has("charge"), audio_node._last.has("warning")]
			check(tones.ring == ["ring", true, true] and tones.strike == ["strike", true, true], "Core: ring and strike play the charge sound and the lower warning tone")
			check(tones.wells == ["wells", true, false] and tones.spiral == ["spiral", true, false], "and ordinary attacks keep only the charge sound they always had")
			boss.charge = 0.0
			boss.intent = {}
		if sector == 5:
			# Turrets: warned for the last 0.45s of their wait, aimed where the shot will go.
			_tg_reset(game)
			boss.stage = 0
			boss.turret_fire = 0.3
			game.tg.collect(game)
			var turrets := 0
			var aim_ok := true
			for d in game.tg.shown:
				if str(d.kind) == "turret":
					turrets += 1
					aim_ok = aim_ok and _tg_ang_eq(float(d.rays[0].ang), (game.player_pos - (d.origin as Vector2)).angle())
			check(turrets == 4 and aim_ok, "Admiral: all four turrets warn, aimed at the ship")
			boss.turret_fire = 0.0001
			var alive_turrets := 0
			for p in boss.turrets:
				alive_turrets += 1 if p.alive else 0
			boss.tick(0.01)
			var shots := _tg_bullets(game)
			check(shots.size() == alive_turrets, "and they fire when the timer ends")
			boss.turret_fire = 3.0
			game.tg.collect(game)
			var calm_turret := true
			for d in game.tg.shown:
				calm_turret = calm_turret and str(d.kind) != "turret"
			check(calm_turret, "and show nothing while they wait")
		if sector == 3:
			_tg_reset(game)
			boss.stage = 0
			for h in boss.heads:
				h.fire = 0.2
			game.tg.collect(game)
			var heads := 0
			var rays_ok := true
			for d in game.tg.shown:
				if str(d.kind) == "spit":
					heads += 1
					var head_pos: Vector2 = (d.origin as Vector2)
					rays_ok = rays_ok and (d.rays as Array).size() == 3 and _tg_ang_eq(float(d.rays[1].ang), (game.player_pos - head_pos).angle())
			check(heads == 3 and rays_ok, "Hydra: each head warns before it spits, aimed at the ship")
			var seen: Array = []
			for d in game.tg.shown:
				if str(d.kind) == "spit":
					seen.append(d.rays)
			boss._spit(boss.heads[0].head)
			check(_tg_match(seen[0], _tg_bullets(game)), "and the spit follows its warning")
		game.queue_free()
		await process_frame
	check(covered >= 36, "%d boss attacks were each checked against what they fired" % covered)
	check(excluded.size() == TG_EXCLUDED.size(), "every excluded attack was audited (%s)" % str(excluded))

	# --- Charge timing, warning life cycle and boss death ---
	var game = await _tg_boss_game(2)
	var boss = game.boss
	boss.attack_t = 0.0
	boss.charge = 0.0
	boss.intent = {}
	boss.update(STEP)
	var started: bool = boss.charge > 0.0 and not boss.intent.is_empty()
	var frames := 1
	var kinds_ok := true
	var rising := true
	var last_k := -1.0
	while not boss.intent.is_empty() and frames < 60:
		game.tg.collect(game)
		var mine: Dictionary = {}
		for d in game.tg.shown:
			if str(d.get("src", "")) == "boss" and str(d.kind) == boss.pending:
				mine = d
		kinds_ok = kinds_ok and not mine.is_empty()
		rising = rising and float(mine.get("k", 0.0)) >= last_k
		last_k = float(mine.get("k", 0.0))
		boss.update(STEP)
		frames += 1
	check(started and kinds_ok and rising and last_k > 0.8, "the boss warning begins with the charge and rises to nearly 1 (%.2f)" % last_k)
	check(frames == int(ceil(BossS.CHARGE / STEP - 1e-9)), "the warning adds no delay: the attack still fires after %d frames (0.55s charge)" % frames)
	game.tg.collect(game)
	var leftover := false
	for d in game.tg.shown:
		leftover = leftover or (str(d.get("src", "")) == "boss" and str(d.kind) == boss.pending and str(d.get("style", "")) != "")
	# (a curtain's later rows legitimately outlive the charge; every other attack must be gone)
	check(not leftover or boss.pending in ["curtain", "burst"], "nothing from the charge lingers once the attack has fired")
	# Dying: nothing warns, nothing fires.
	_tg_reset(game)
	boss.attack_t = 0.0
	boss.charge = 0.0
	boss.update(STEP)
	boss.update(STEP)
	check(boss.charge > 0.0 and not boss.intent.is_empty(), "a charge is in progress")
	game.tg.add("barrage", 0.0, 3.0, {"list": [1.0, 2.0]})
	boss._begin_death()
	game.tg.collect(game)
	check(game.tg.shown.is_empty() and game.tg.timed.is_empty() and boss.intent.is_empty(), "a boss that starts dying drops its warning, its queued warnings and its intent at once")
	for i in range(40):
		boss.update(STEP)
		game.tg.collect(game)
	check(game.tg.shown.is_empty() and game.field.count == 0, "and a dying boss produces no further warnings or shots")
	game.queue_free()
	await process_frame
	TgS.summons_arrive = false
	save.upgrades = {}
	save.opt = saved_opt
	print("telegraphs ok")

func engine_peak_reference(EngineS) -> float:
	# What a ship flat out would show with Reduce Motion off: the calm one must be below it.
	var e = EngineS.new()
	var p := Vector2(360, 900)
	for i in range(80):
		p.x += 11.0
		e.update_motion(1.0 / 60.0, p, true)
	return e.intensity()

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
