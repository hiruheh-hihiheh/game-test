extends "res://tools/test_game.gd"
## Measures how reachable each level's stars are, by playing every level several times with the test bot.
## Run: godot --headless --path . --script tools/star_audit.gd -- --test [--levels=1-60] [--runs=4] [--sides]
##
## Each level is played two ways, with the upgrades a player would roughly have by then (the same spending rule the
## campaign simulation uses):
##   immortal  the hull is refilled, so the run always finishes. Shows how much of the bonus objective is THERE to get.
##   mortal    a normal run. Shows wins, hulls lost and whether the shield ever broke.
## The bot is not a person: it does not chase crystals or plan combos. Treat "reached" as a floor, not a ceiling.

var runs := 4
var sides := false

func _run() -> void:
	_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--runs="):
			runs = int(arg.substr(7))
		elif arg == "--sides":
			sides = true
	save = root.get_node("Save")
	levels_db = load("res://src/data/levels.gd")
	gear_db = load("res://src/data/gear.gd")
	tiers_db = load("res://src/data/tiers.gd")
	pilot_db = load("res://src/data/pilot.gd")
	save.tutorial = {"move": true, "card": true, "nova": true, "gear": true, "crystal": true}
	var list: Array = []
	for n in range(first, last + 1):
		list.append(n)
	if sides:
		list = [101, 102, 103, 104, 105, 106]
	print("AUDIT level | name | objective | target | reached per immortal run | bonus rate | mortal: wins, flawless, shield kept | dropped crystals | [kills, grazes]")
	for n in list:
		var scale_n: int = n if n <= 60 else (levels_db.sector_of(n) - 1) * 10 + 6
		save.upgrades = {}
		save.salvage = int(pow(float(scale_n - 1), 1.7) * 10.0)
		_spend()
		save.salvage = 0
		save.unlocked = 60
		var def: Dictionary = levels_db.build(n)
		var obj: Array = def.obj
		var reached: Array = []
		var done := 0
		var dropped: Array = []
		var kills: Array = []
		for i in range(runs):
			var r: Dictionary = await _audit_play(n, true)
			reached.append(r.value)
			done += 1 if r.done else 0
			dropped.append(r.dropped)
			kills.append([r.kills, r.grazes])
		var wins := 0
		var flawless := 0
		var kept := 0
		for i in range(runs):
			var r: Dictionary = await _audit_play(n, false)
			wins += 1 if r.win else 0
			flawless += 1 if r.win and int(r.hull_lost) == 0 else 0
			kept += 1 if r.win and not r.shield_broke else 0
		print("AUDIT %3d | %-22s | %-8s | %4d | %-22s | %d/%d | %d/%d %d/%d %d/%d | %s | %s" % [n, str(def.name), str(obj[0]), int(obj[1]), str(reached), done, runs, wins, runs, flawless, runs, kept, runs, str(dropped), str(kills)])
	quit()

func _audit_play(n: int, immortal: bool) -> Dictionary:
	var game = await _new_game({"mode": "campaign" if n <= 60 else "side", "level": n, "mutators": [], "tier": 0})
	var P = game.Phase
	var elapsed := 0.0
	var think := 0.0
	var dropped := 0
	var prev := 0
	while elapsed < 300.0:
		think -= STEP
		if think <= 0.0:
			think = think_time
			_bot(game)
		if immortal:
			game.hull = game.max_hull
		game._process(STEP)
		elapsed += STEP
		var now: int = game.pickups.size() + int(game.tracker.crystals)
		if now > prev:
			dropped += now - prev
		prev = now
		if game.phase == P.CLEAR or game.phase == P.DEFEAT:
			break
		if int(elapsed / STEP) % 400 == 0:
			await process_frame
	var obj: Array = game.level.get("obj", ["", 0])
	var value := 0
	match str(obj[0]):
		"crystals":
			value = int(game.tracker.crystals)
		"kills":
			value = int(game.tracker.kills)
		"graze":
			value = int(game.tracker.grazes)
		"combo":
			value = game.best_combo
		"time":
			value = int(game.flight_time)
		"wrecks":
			value = int(game.tracker.wrecks)
		"ember":
			value = int(game.tracker.ember)
		"tanks":
			value = int(game.tracker.tanks)
		"nohatch":
			value = int(game.tracker.hatched)
		"husks":
			value = int(game.tracker.husks)
		"shield":
			value = 1 if game.tracker.shield_broke else 0
		"escort":
			value = 1 if (game.tracker.escort_ok and game.tracker.escort_seen) else 0
	var out := {"win": game.phase == P.CLEAR, "done": game.phase == P.CLEAR and game.objective_done(), "value": value, "hull_lost": game.hull_lost,
		"shield_broke": bool(game.tracker.shield_broke), "dropped": dropped, "kills": game.kills, "grazes": int(game.tracker.grazes)}
	await process_frame
	game.queue_free()
	await process_frame
	return out
